import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:async/async.dart';
import 'package:time/time.dart';
import 'package:fixnum/fixnum.dart';
import 'package:maxwell_protocol/maxwell_protocol.dart';
import 'package:maxwell_client/maxwell_client.dart';
import './logger.dart';

typedef OnMsg = void Function(int lastOffset);
final int _QUEUE_CAPACITY = 128;

class Action {
  String type;
  dynamic value;
  Action({@required this.type, this.value = ''});
}

class Params {
  bool sourceEnabled;
  Params({this.sourceEnabled = false});
}

class Frontend {
  List<String> _endpoints = null;
  Options _options = null;

  ProgressManager _progressManager = ProgressManager();
  Map<String, Queue> _queues = new Map();
  Map<String, OnMsg> _callbacks = Map();
  Map<String, CancelableOperation<void>> _pullTasks = Map();

  bool _shouldRun = true;

  Connection _connection = null;
  int _endpoint_index = -1;
  bool _isConnectionReady = false;
  Completer<void> _completer = Completer(); // check if connection is ready

  Frontend(endpoints, options)
      : _endpoints = endpoints,
        _options = options {
    this._connectToFrontend();
  }

  void suspend() {
    if (!this._shouldRun) {
      return;
    }
    this._shouldRun = false;
    this._disconnectFromFrontend();
    this._cancelAllPullTasks();
  }

  void resume() {
    if (this._shouldRun) {
      return;
    }
    this._shouldRun = true;
    this._connectToFrontend();
  }

  void close() {
    this._shouldRun = false;
    this._disconnectFromFrontend();
    this._cancelAllPullTasks();
    this._queues.clear();
    this._progressManager.clear();
  }

  void subscribe(String topic, int offset, OnMsg callback) {
    if (this._progressManager.contains(topic)) {
      throw 'Already subscribed: topic: $topic';
    }
    this._progressManager[topic] = offset;
    this._queues[topic] = Queue(_QUEUE_CAPACITY);
    this._callbacks[topic] = callback;
    if (this._isConnectionReady) {
      this._newPullTask(topic, offset);
    }
  }

  void unsubscribe(topic) {
    this._cancelPullTask(topic);
    this._callbacks.remove(topic);
    this._queues.remove(topic);
    this._progressManager.remove(topic);
  }

  List<msg_t> consume(topic, [offset = 0, limit = 32]) {
    var msgs = this._queues[topic].getFrom(offset, limit);
    var count = msgs.length;
    if (count > 0) {
      this._queues[topic].removeTo(msgs[count - 1].offset.toInt());
    }
    return msgs;
  }

  dynamic request(Action action, [Params params]) async {
    var msg = this._createDoReq(action, params);
    await this._getConnectionReady();
    if (this._connection == null) {
      throw 'Frontend already closed';
    }
    do_rep_t result = await this._connection.send(msg);
    return jsonDecode(result.value);
  }

  void _connectToFrontend() {
    this._resolveEndpoint().then((endpoint) {
      this._connection = new Connection(endpoint, this._options)
        ..addListener(Event.ON_CONNECTED, this._onConnectedToFrontend)
        ..addListener(Event.ON_DISCONNECTED, this._onDisconnectedFromFrontend);
    }).catchError((e, s) {
      logger.e('Failed to resolve endpoint: reason: $e, statck: $s');
      Timer(Duration(seconds: 1), () => this._connectToFrontend());
    });
  }

  void _disconnectFromFrontend() {
    this._isConnectionReady = false;
    if (!this._completer.isCompleted) {
      this._completer.completeError('Lost connection');
    } else {
      logger.w('Was completed already');
    }
    this._completer = Completer();
    if (this._connection == null) {
      return;
    }
    this._connection
      ..removeListener(Event.ON_CONNECTED, this._onConnectedToFrontend)
      ..removeListener(Event.ON_DISCONNECTED, this._onDisconnectedFromFrontend);
    this._connection.close();
    this._connection = null;
  }

  void _onConnectedToFrontend([_]) {
    this._isConnectionReady = true;
    if (!this._completer.isCompleted) {
      this._completer.complete();
    } else {
      logger.w('Was completed already');
    }
    this._renewAllPullTasks();
  }

  void _onDisconnectedFromFrontend([_]) {
    this._disconnectFromFrontend();
    this._cancelAllPullTasks();
    if (this._shouldRun) {
      Timer(Duration(seconds: 1), () => this._connectToFrontend());
    }
  }

  Future<void> _getConnectionReady() {
    return this._completer.future.timeout(5.seconds);
  }

  Future<String> _resolveEndpoint() async {
    if (!this._options.masterEnabled) {
      return Future.value(this._nextEndpoint());
    }
    var master;
    try {
      master = new Master(this._endpoints, this._options);
      return await master.resolveFrontend(5.seconds);
    } finally {
      master.close();
    }
  }

  String _nextEndpoint() {
    this._endpoint_index += 1;
    if (this._endpoint_index >= this._endpoints.length) {
      this._endpoint_index = 0;
    }
    return this._endpoints[this._endpoint_index];
  }

  void _renewAllPullTasks() {
    for (var entry in this._progressManager.progresses.entries) {
      this._newPullTask(entry.key, entry.value);
    }
  }

  void _newPullTask(topic, offset) {
    this._cancelPullTask(topic);
    if (!this._isValidSubscription(topic)) {
      return;
    }
    var queue = this._queues[topic];
    if (queue.isFull()) {
      logger.w('Queue is full(${queue.size()}), waiting for consuming...');
      Timer(1.seconds, () => this._newPullTask(topic, offset));
      this._callbacks[topic](offset - 1);
      return;
    }
    if (this._connection == null) {
      logger.d('Lost connection, waiting for reconnecting...');
      Timer(1.seconds, () => this._newPullTask(topic, offset));
      return;
    }
    this._pullTasks[topic] = CancelableOperation.fromFuture(this
        ._connection
        .send(this._createPullReq(topic, offset), 5.seconds)
        .then((value) {
      if (!this._isValidSubscription(topic)) {
        return;
      }
      queue.put((value as pull_rep_t).msgs);
      var lastOffset = queue.lastOffset();
      var nextOffset = lastOffset + 1;
      this._progressManager[topic] = nextOffset;
      Timer(this._options.pullInterval,
          () => this._newPullTask(topic, nextOffset));
      this._callbacks[topic](lastOffset);
    }).catchError((e, s) {
      if (e is TimeoutException) {
        logger.d('Timeout occured: reason: $e, stack: $s, will pull again...');
        Timer(10.milliseconds, () => this._newPullTask(topic, offset));
      } else {
        logger.e('Error occured: reason: $e, stack: $s, will pull again...');
        Timer(1.seconds, () => this._newPullTask(topic, offset));
      }
    }));
  }

  void _cancelAllPullTasks() {
    for (var task in this._pullTasks.values) {
      task.cancel();
    }
    this._pullTasks.clear();
  }

  void _cancelPullTask(topic) {
    var task = this._pullTasks[topic];
    if (task != null) {
      task.cancel();
      this._pullTasks.remove(topic);
    }
  }

  pull_req_t _createPullReq(topic, offset) {
    return pull_req_t()
      ..topic = topic
      ..offset = Int64(offset)
      ..limit = this._options.getLimit;
  }

  do_req_t _createDoReq(Action action, [Params params]) {
    if (params == null) {
      params = Params();
    }
    return do_req_t()
      ..type = action.type
      ..value = jsonEncode(action.value != null ? action.value : {})
      ..traces.add(trace_t())
      ..sourceEnabled = params.sourceEnabled;
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
}
