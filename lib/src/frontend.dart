import 'dart:async';
import 'dart:convert';
import 'package:async/async.dart';
import 'package:time/time.dart';
import 'package:fixnum/fixnum.dart';
import 'package:maxwell_protocol/maxwell_protocol.dart';
import './internal.dart';

typedef OnMsg = void Function(int lastOffset);

class Headers {
  String? token;
  bool sourceEnabled;
  Headers({this.sourceEnabled = false});
}

class Frontend with Listenable implements EventHandler {
  Master _master;
  Options _options;

  bool _closed = false;
  ProgressManager _progressManager = ProgressManager();
  Map<String, OnMsg> _callbacks = Map();
  Map<String, Queue> _queues = new Map();
  Map<String, CancelableOperation<void>> _pullTasks = Map();
  Map<String, Timer> _pullTimers = Map();

  late MultiAltEndpointsConnection _pullConnection;
  late ConnectionPool _requestConnections;
  bool _failedToConnect = false;

  Frontend(master, options)
      : _master = master,
        _options = options {
    this._pullConnection =
        MultiAltEndpointsConnection(this._pickEndpoint, options, eventHandler: this);
    this._requestConnections = ConnectionPool(this._pickEndpoint, options, eventHandler: this);
  }

  void suspend() {
    if (this._closed) {
      logger.w('Already closed, ignore suspending.');
      return;
    }
    this._cancelAllPullTasks();
  }

  void resume() {
    if (this._closed) {
      logger.w('Already closed, ignore resuming.');
      return;
    }
    this._renewAllPullTasks();
  }

  void close() {
    this._closed = true;
    this._cancelAllPullTasks();
    this._progressManager.clear();
    this._callbacks.clear();
    this._queues.clear();
    this._pullConnection.close();
  }

  void subscribe(String topic, int offset, OnMsg callback) {
    if (this._progressManager.contains(topic)) {
      logger.w('Already subscribed: topic: $topic');
      return;
    }
    this._progressManager[topic] = offset;
    this._queues[topic] = Queue(this._options.queueCapacity);
    this._callbacks[topic] = callback;
    if (this._pullConnection.isOpen()) {
      this._newPullTask(topic, offset);
    }
  }

  void unsubscribe(topic) {
    this._cancelPullTask(topic);
    this._callbacks.remove(topic);
    this._queues.remove(topic);
    this._progressManager.remove(topic);
  }

  List<msg_t> consume(topic, [offset = 0, limit = 128]) {
    var queue = this._queues[topic];
    if (queue == null) {
      return [];
    }
    var msgs = queue.getFrom(offset, limit);
    var count = msgs.length;
    if (count > 0) {
      queue.removeTo(msgs[count - 1].offset.toInt());
    }
    return msgs;
  }

  dynamic request(String path,
      {dynamic payload,
      Headers? headers,
      Duration? waitOpenTimeout,
      Duration? roundTimeout}) async {
    var msg = this._createReqReq(path, payload, headers);
    req_rep_t result = await this._requestConnections.waitOpenAndSend(msg,
        waitOpenTimeout: waitOpenTimeout, roundTimeout: roundTimeout) as req_rep_t;
    return jsonDecode(result.payload);
  }

  //===========================================
  // EventHandler implementation
  //===========================================

  @override
  void onConnecting(args) {
    this.notify(Event.ON_CONNECTING, args);
  }

  @override
  void onConnected(args) {
    this._failedToConnect = false;
    this._renewAllPullTasks();
    this.notify(Event.ON_CONNECTED, args);
  }

  @override
  void onDisconnecting(args) {
    this.notify(Event.ON_DISCONNECTING, args);
  }

  @override
  void onDisconnected(args) {
    this._cancelAllPullTasks();
    this.notify(Event.ON_DISCONNECTED, args);
  }

  @override
  void onError(args) {
    if (args[0] == ErrorCode.FAILED_TO_CONNECT) {
      this._failedToConnect = true;
    }
    this.notify(Event.ON_ERROR, args);
  }

  //===========================================
  // internal functions
  //===========================================

  Future<String> _pickEndpoint() async {
    return await this._master.pickFrontend(force: this._failedToConnect).timeout(5.seconds);
  }

  bool _isValidSubscription(topic) {
    if (this._progressManager.contains(topic) &&
        this._queues.containsKey(topic) &&
        this._callbacks.containsKey(topic)) {
      return true;
    } else {
      return false;
    }
  }

  void _renewAllPullTasks() {
    this._cancelAllPullTasks();
    for (var entry in this._progressManager.progresses.entries) {
      this._newPullTask(entry.key, entry.value);
    }
  }

  void _newPullTask(topic, offset) {
    this._cancelPullTask(topic);
    if (!this._isValidSubscription(topic)) {
      return;
    }
    var queue = this._queues[topic]!;
    if (queue.isFull()) {
      logger.w('Queue is full(${queue.size()}), waiting for consuming...');
      this._newPullTimer(1.seconds, topic, offset);
      this._callbacks[topic]!(offset - 1);
      return;
    }
    this._pullTasks[topic] = CancelableOperation.fromFuture(this
        ._pullConnection
        .send(this._createPullReq(topic, offset), roundTimeout: 5.seconds)
        .then((value) {
      if (!this._isValidSubscription(topic)) {
        return;
      }
      var msgs = (value as pull_rep_t).msgs;
      if (msgs.isEmpty) {
        logger.i('No msgs pulled: topic: ${topic}, offset: ${offset}');
        this._newPullTimer(this._options.pullInterval, topic, offset);
        return;
      }
      queue.put(msgs);
      var lastOffset = queue.lastOffset();
      var nextOffset = lastOffset + 1;
      this._progressManager[topic] = nextOffset;
      this._newPullTimer(this._options.pullInterval, topic, nextOffset);
      this._callbacks[topic]!(lastOffset);
    }).catchError((e, s) {
      if (e is TimeoutException) {
        logger.d('Timeout occured: reason: $e, stack: $s, will pull again...');
        this._newPullTimer(0.seconds, topic, offset);
      } else {
        logger.e('Error occured: reason: $e, stack: $s, will pull again...');
        this._newPullTimer(1.seconds, topic, offset);
      }
    }));
  }

  void _cancelAllPullTasks() {
    for (var task in this._pullTasks.values) {
      task.cancel();
    }
    this._pullTasks.clear();
    this._cancelAllPullTimers();
  }

  void _cancelPullTask(topic) {
    var task = this._pullTasks[topic];
    if (task != null) {
      task.cancel();
      this._pullTasks.remove(topic);
      this._cancelPullTimer(topic);
    }
  }

  void _newPullTimer(Duration duration, topic, offset) {
    this._cancelPullTimer(topic);
    this._pullTimers[topic] = Timer(duration, () {
      this._newPullTask(topic, offset);
    });
  }

  void _cancelAllPullTimers() {
    for (var timer in this._pullTimers.values) {
      timer.cancel();
    }
    this._pullTimers.clear();
  }

  void _cancelPullTimer(topic) {
    var timer = this._pullTimers[topic];
    if (timer != null) {
      timer.cancel();
      this._pullTimers.remove(topic);
    }
  }

  pull_req_t _createPullReq(topic, offset) {
    return pull_req_t()
      ..topic = topic
      ..offset = Int64(offset)
      ..limit = this._options.pullLimit;
  }

  req_req_t _createReqReq(String path, dynamic payload, [Headers? headers]) {
    if (headers == null) {
      headers = Headers();
    }

    var header = header_t();
    if (headers.token != null) {
      header.token = headers.token!;
    }
    return req_req_t()
      ..path = path
      ..payload = jsonEncode(payload != null ? payload : {})
      ..header = header;
  }
}
