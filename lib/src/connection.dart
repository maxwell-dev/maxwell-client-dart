import 'dart:async';
import 'dart:math';
import 'package:async/async.dart';
import 'package:web_socket_channel/io.dart';
import 'package:maxwell_protocol/maxwell_protocol.dart';
import './internal.dart';

class Event {
  final int _eventId;

  static const Event ON_CONNECTING = Event._(100);
  static const Event ON_CONNECTED = Event._(101);
  static const Event ON_DISCONNECTING = Event._(102);
  static const Event ON_DISCONNECTED = Event._(103);
  static const Event ON_ERROR = Event._(104);

  const Event._(this._eventId);

  bool operator ==(other) => other is Event && this._eventId == other._eventId;

  int get hashCode => this._eventId.hashCode;
}

enum ErrorCode {
  FAILED_TO_ENCODE,
  FAILED_TO_SEND,
  FAILED_TO_DECODE,
  FAILED_TO_RECEIVE,
  FAILED_TO_CONNECT,
  IDLE_TIMEOUT,
  OPAQUE_ERROR
}

class ServiceError implements Exception {
  int code;
  String desc;

  ServiceError(this.code, this.desc);

  String toString() {
    return 'ServiceError {code: $code, desc: $desc}';
  }
}

abstract class EventHandler {
  void onConnecting(List args);
  void onConnected(List args);
  void onDisconnecting(List args);
  void onDisconnected(List args);
  void onError(List args);
}

class DefaultEventHandler implements EventHandler {
  const DefaultEventHandler();
  void onConnecting(List args) {}
  void onConnected(List args) {}
  void onDisconnecting(List args) {}
  void onDisconnected(List args) {}
  void onError(List args) {}
}

typedef TryWithCallback = void Function();
void tryWith(TryWithCallback callback) {
  try {
    callback();
  } catch (e, s) {
    logger.e('Failed to execute: reason: $e, stack: $s');
  }
}

int ID_SEED = 0;

class Connection with Listenable {
  int _id = ID_SEED++;
  String _endpoint;
  Options _options;
  EventHandler _eventHandler;

  bool _shouldRun = true;
  Timer? _reconnectTimer = null;
  Timer? _heartbeatTimer = null;
  Timer? _checkStatusTimer = null;
  late DateTime _sendNonePingAt;
  late DateTime _receivedAt;
  bool _isHealthy = true;
  int _lastRef = 0;

  late IOWebSocketChannel _channel;
  bool _isOpen = false;
  Map<int, Completer> _completers = Map();

  //===========================================
  // apis
  //===========================================

  Connection(String endpoint, Options options,
      {EventHandler eventHandler = const DefaultEventHandler()})
      : _endpoint = endpoint,
        _options = options,
        _eventHandler = eventHandler {
    var now = DateTime.now();
    this._sendNonePingAt = now;
    this._receivedAt = now;
    this._connect();
  }

  void close() {
    this._shouldRun = false;
    this._stopRepeatHeartbeat();
    this._stopRepeatCheckStatus();
    this._stopReconnect();
    this._disconnect();
    this._completeCompleters();
  }

  int id() {
    return this._id;
  }

  String endpoint() {
    return this._endpoint;
  }

  bool isHealthy() {
    return this._isHealthy;
  }

  bool isOpen() {
    return this._isOpen;
  }

  Future<Connection> waitOpen([Duration? timeout = null]) {
    if (timeout == null) {
      timeout = this._options.waitOpenTimeout;
    }
    return this._channel.ready.then((value) => this).timeout(timeout);
  }

  Future<GeneratedMessage> waitOpenAndSend(GeneratedMessage msg,
      {Duration? waitOpenTimeout = null, Duration? roundTimeout = null}) async {
    if (!this._isOpen) {
      await this.waitOpen(waitOpenTimeout);
    }
    return await this.send(msg, roundTimeout);
  }

  Future<GeneratedMessage> send(GeneratedMessage msg, [Duration? timeout = null]) {
    var ref = this._newRef();
    msg.set_ref(ref);

    if (timeout == null) {
      timeout = this._options.roundTimeout;
    }

    var completer = Completer<GeneratedMessage>();
    this._completers[ref] = completer;

    var replyFuture = completer.future.whenComplete(() {
      this._completers.remove(ref);
    }).timeout(timeout, onTimeout: () {
      var e = TimeoutException('<${this._id}>msg: ${msg.toProto3Json()}', timeout);
      logger.d('<${this._id}>$e');
      completer.completeError(e);
      return completer.future;
    });

    try {
      this.doSend(msg);
    } catch (e) {
      completer.completeError(e);
    }

    return replyFuture;
  }

  void doSend(msg) {
    var now = DateTime.now();
    if (msg is! ping_req_t) {
      this._sendNonePingAt = now;
    }

    if (this._options.roundDebugEnabled) {
      logger.d('<${this._id}>Sending msg: ${msg.toProto3Json()}');
    }

    var encodedMsg = null;
    try {
      encodedMsg = encode_msg(msg);
    } catch (e, s) {
      logger.e('<${this._id}>Failed to encode msg: reason: $e, stack: $s');
      tryWith(() => this._eventHandler.onError([ErrorCode.FAILED_TO_ENCODE, e, this]));
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_ENCODE, e, this]);
      throw new Exception('<${this._id}>Failed to encode msg: reason: $e');
    }

    try {
      this._channel.sink.add(encodedMsg);
    } catch (e, s) {
      logger.e('<${this._id}>Failed to send msg: reason: $e, stack: $s');
      tryWith(() => this._eventHandler.onError([ErrorCode.FAILED_TO_SEND, e, this]));
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_SEND, e, this]);
      throw new Exception('<${this._id}>Failed to send msg: reason: $e');
    }
  }

  //===========================================
  // callback functions
  //===========================================

  void onData(data) {
    this._receivedAt = DateTime.now();

    GeneratedMessage msg;
    try {
      msg = decode_msg(data);
    } catch (e, s) {
      logger.e('<${this._id}>Failed to decode msg: reason: $e, stack: $s');
      tryWith(() => this._eventHandler.onError([ErrorCode.FAILED_TO_DECODE, e, this]));
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_DECODE, e, this]);
      return;
    }

    if (this._options.roundDebugEnabled) {
      logger.d('<${this._id}>Received msg: $msg');
    }

    if (msg is ping_rep_t) {
      return;
    }

    var ref = msg.get_ref();
    var completer = this._completers[ref];
    if (completer == null) {
      return;
    }
    try {
      if (msg is error_rep_t) {
        completer.completeError(ServiceError(msg.code, msg.desc));
      } else if (msg is error2_rep_t) {
        completer.completeError(ServiceError(msg.code, msg.desc));
      } else {
        completer.complete(msg);
      }
    } catch (e, s) {
      logger.e('<${this._id}>Failed to receive msg: reason: $e, stack: $s');
      tryWith(() => this._eventHandler.onError([ErrorCode.FAILED_TO_RECEIVE, e, this]));
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_RECEIVE, e, this]);
    } finally {
      this._completers.remove(ref);
    }
  }

  void onDone() {
    logger.i('<${this._id}>Disconnected: endpoint: ${this._endpoint}');
    try {
      this._isOpen = false;
      this._stopRepeatHeartbeat();
      this._stopRepeatCheckStatus();
      this._stopReconnect();
      this._closeChannel('Stream closed');
      tryWith(() => this._eventHandler.onDisconnected([this]));
      this.notify(Event.ON_DISCONNECTED, [this]);
    } finally {
      this._reconnect();
    }
  }

  void onError(error) {
    logger.e('<${this._id}>Error occured: ${error}');
    tryWith(() => this._eventHandler.onError([ErrorCode.OPAQUE_ERROR, error, this]));
    this.notify(Event.ON_ERROR, [ErrorCode.OPAQUE_ERROR, error, this]);
  }

  //===========================================
  // internal functions
  //===========================================

  void _connect() {
    logger.i('<${this._id}>Connecting: endpoint: ${this._endpoint}');
    tryWith(() => this._eventHandler.onConnecting([this]));
    this.notify(Event.ON_CONNECTING, [this]);
    var channel = IOWebSocketChannel.connect(this._buildUri());
    channel.stream.listen(this.onData, onError: this.onError, onDone: this.onDone);
    channel.ready.then((_) {
      logger.i('<${this._id}>Connected: endpoint: ${this._endpoint}');
      this._isOpen = true;
      this._repeatHeartbeat();
      this._repeatCheckStatus();
      tryWith(() => this._eventHandler.onConnected([this]));
      this.notify(Event.ON_CONNECTED, [this]);
    }, onError: (e) {
      logger.e('<${this._id}>Failed to connect: endpoint: ${this._endpoint}, error: $e');
      this._isOpen = false;
      tryWith(() => this._eventHandler.onError([ErrorCode.FAILED_TO_CONNECT, e, this]));
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_CONNECT, e, this]);
    });
    this._channel = channel;
  }

  void _disconnect() {
    if (this._isOpen) {
      logger.i('<${this._id}>Disconnecting: endpoint: ${this._endpoint}');
      tryWith(() => this._eventHandler.onDisconnecting([this]));
      this.notify(Event.ON_DISCONNECTING, [this]);
    } else {
      logger.i('<${this._id}>Disconnect again to close the channel: endpoint: ${this._endpoint}');
    }
    this._closeChannel('Disconnect connection');
  }

  void _reconnect() {
    if (!this._shouldRun) {
      return;
    }
    this._stopReconnect();
    this._reconnectTimer = Timer(this._options.reconnectDelay, this._connect);
  }

  void _stopReconnect() {
    if (this._reconnectTimer != null) {
      this._reconnectTimer!.cancel();
      this._reconnectTimer = null;
    }
  }

  void _repeatHeartbeat() {
    if (!this._shouldRun) {
      return;
    }
    this._stopRepeatHeartbeat();
    this._heartbeatTimer = Timer.periodic(this._options.heartbeatInterval, (timer) {
      this._sendHeartbeat();
    });
  }

  void _stopRepeatHeartbeat() {
    if (this._heartbeatTimer != null) {
      this._heartbeatTimer!.cancel();
      this._heartbeatTimer = null;
    }
  }

  void _sendHeartbeat() {
    try {
      this.doSend(ping_req_t());
    } catch (e, s) {
      logger.w('<${this._id}>Failed to send heartbeat: reason: $e, stack: $s');
    }
  }

  void _repeatCheckStatus() {
    if (!this._shouldRun) {
      return;
    }
    this._stopRepeatCheckStatus();
    this._checkStatusTimer = Timer.periodic(this._calcIntervalForCheckStatus(), (timer) {
      var now = DateTime.now();
      this._checkUnhealthyTimeout(now);
      this._checkIdleTimeout(now);
    });
  }

  void _stopRepeatCheckStatus() {
    if (this._checkStatusTimer != null) {
      this._checkStatusTimer!.cancel();
      this._checkStatusTimer = null;
    }
  }

  void _checkUnhealthyTimeout(DateTime now) {
    if (this._hasReceivedBeforeUnhealthyTimeout(now)) {
      this._isHealthy = true;
    } else {
      this._isHealthy = false;
      logger.w('<${this._id}>Connection is not healthy: endpoint: ${this._endpoint}');
    }
  }

  void _checkIdleTimeout(DateTime now) {
    if (!this._hasSentNonePingBeforeIdleTimeout(now)) {
      logger.i('<${this._id}>Idle timeout: endpoint: ${this._endpoint}');
      tryWith(() => this._eventHandler.onError([ErrorCode.IDLE_TIMEOUT, 'Idle timeout', this]));
      this.notify(Event.ON_ERROR, [ErrorCode.IDLE_TIMEOUT, 'Idle timeout', this]);
    }
  }

  bool _hasReceivedBeforeUnhealthyTimeout(DateTime now) {
    return now.difference(this._receivedAt) < this._options.unhealthyTimeout;
  }

  bool _hasSentNonePingBeforeIdleTimeout(DateTime now) {
    return now.difference(this._sendNonePingAt) < this._options.idleTimeout;
  }

  Duration _calcIntervalForCheckStatus() {
    var interval = (min(this._options.unhealthyTimeout.inMilliseconds,
            this._options.idleTimeout.inMilliseconds) ~/
        2);
    return Duration(milliseconds: interval);
  }

  void _closeChannel(String? reason) {
    this._channel.sink.close(10000, reason ?? '').whenComplete(() {
      logger.d('<${this._id}>Channel closed: reason: $reason, endpoint: ${this._endpoint}');
    });
  }

  void _completeCompleters() {
    for (var completer in this._completers.values) {
      completer.completeError('Disconnect connection');
    }
    this._completers.clear();
  }

  int _newRef() {
    if (this._lastRef > 100000000) {
      this._lastRef = 1;
    }
    return ++this._lastRef;
  }

  Uri _buildUri() {
    var parts = this._endpoint.split(':');
    var scheme = this._options.sslEnabled ? 'wss' : 'ws';
    return Uri(scheme: scheme, host: parts[0], port: int.parse(parts[1]), path: '\$ws');
  }
}

typedef PickEndpoint = Future<String> Function();

class MultiAltEndpointsConnection with Listenable implements EventHandler {
  PickEndpoint _pickEndpoint;
  Options _options;
  EventHandler _eventHandler;

  bool _shouldRun = true;
  late CancelableOperation _connectTask;
  Timer? _reconnectTimer = null;

  Connection? _connection = null;
  Completer _readyCompleter = Completer();
  Completer? _oldReadyCompleter = null;

  //===========================================
  // apis
  //===========================================

  MultiAltEndpointsConnection(PickEndpoint pickEndpoint, Options options,
      {EventHandler eventHandler = const DefaultEventHandler()})
      : _pickEndpoint = pickEndpoint,
        _options = options,
        _eventHandler = eventHandler {
    this._connect();
  }

  void close() {
    this._shouldRun = false;
    this._stopReconnect();
    this._disconnect();
  }

  int? id() {
    return this._connection?.id();
  }

  String? endpoint() {
    return this._connection?.endpoint();
  }

  bool isHealthy() {
    return this._connection == null || this._connection!.isHealthy();
  }

  bool isOpen() {
    return this._connection != null && this._connection!.isOpen();
  }

  Future<MultiAltEndpointsConnection> waitOpen([Duration? timeout = null]) {
    if (timeout == null) {
      timeout = this._options.waitOpenTimeout;
    }
    return this._readyCompleter.future.then((value) => this).timeout(timeout);
  }

  Future<GeneratedMessage> waitOpenAndSend(GeneratedMessage msg,
      {Duration? waitOpenTimeout, Duration? roundTimeout}) async {
    if (!this.isOpen()) {
      logger.d('Msg sent before connection is ready, waiting...');
      return await this.waitOpen(waitOpenTimeout).then((value) => value.send(msg, roundTimeout));
    } else {
      return await this._connection!.send(msg, roundTimeout);
    }
  }

  Future<GeneratedMessage> send(GeneratedMessage msg, [Duration? timeout]) {
    if (!this.isOpen()) {
      throw new Exception('Connection is not ready');
    }
    return this._connection!.send(msg, timeout);
  }

  //===========================================
  // EventHandler implementation
  //===========================================

  @override
  void onConnecting(args) {
    args.add(this);
    tryWith(() => this._eventHandler.onConnecting(args));
    this.notify(Event.ON_CONNECTING, args);
  }

  @override
  void onConnected(args) {
    args.add(this);
    if (this._oldReadyCompleter != null && !this._oldReadyCompleter!.isCompleted) {
      this._oldReadyCompleter!.complete(this);
    }
    if (!this._readyCompleter.isCompleted) {
      this._readyCompleter.complete(this);
    }
    tryWith(() => this._eventHandler.onConnected(args));
    this.notify(Event.ON_CONNECTED, args);
  }

  @override
  void onDisconnecting(args) {
    args.add(this);
    tryWith(() => this._eventHandler.onDisconnecting(args));
    this.notify(Event.ON_DISCONNECTING, args);
  }

  @override
  void onDisconnected(args) {
    args.add(this);
    this._oldReadyCompleter = this._readyCompleter;
    this._readyCompleter = Completer();
    tryWith(() => this._eventHandler.onDisconnected(args));
    this.notify(Event.ON_DISCONNECTED, args);
    this._disconnect();
    this._reconnect();
  }

  @override
  void onError(args) {
    args.add(this);
    logger.d('<${args[args.length - 2].id()}>Error occured: ${args}, propagating up...');
    tryWith(() => this._eventHandler.onError(args));
    this.notify(Event.ON_ERROR, args);
  }

  //===========================================
  // internal functions
  //===========================================

  void _connect() {
    this._connectTask = CancelableOperation.fromFuture(this._pickEndpoint().then((endpiont) {
      if (!this._shouldRun) {
        return;
      }
      this._connection = new Connection(endpiont, this._options, eventHandler: this);
    }).catchError((reason) {
      logger.e('Failed to pick endpoint: ${reason}');
      this._disconnect();
      this._reconnect();
    }));
  }

  void _disconnect() {
    this._connectTask.cancel();
    this._connection?.close();
  }

  void _reconnect() {
    if (!this._shouldRun) {
      return;
    }
    this._stopReconnect();
    this._reconnectTimer = Timer(this._options.reconnectDelay, this._connect);
  }

  void _stopReconnect() {
    if (this._reconnectTimer != null) {
      this._reconnectTimer!.cancel();
      this._reconnectTimer = null;
    }
  }
}

class ConnectionPool with Listenable implements EventHandler {
  PickEndpoint _pickEndpoint;
  Options _options;
  EventHandler _eventHandler;

  List<MultiAltEndpointsConnection> _connections = [];
  int _indexSeed = 0;

  //===========================================
  // apis
  //===========================================

  ConnectionPool(PickEndpoint pickEndpoint, Options options,
      {EventHandler eventHandler = const DefaultEventHandler()})
      : _pickEndpoint = pickEndpoint,
        _options = options,
        _eventHandler = eventHandler {
    for (var i = 0; i < this._options.pollMinSize; i++) {
      this._connections.add(this._createConnection());
    }
  }

  void close() {
    for (var connection in this._connections) {
      connection.close();
    }
  }

  MultiAltEndpointsConnection getConnection() {
    var index = this._nextIndex();
    var len = this._connections.length;
    for (var i = index; i < len; i++) {
      if (this._connections[i].isHealthy()) {
        return this._connections[i];
      }
    }
    for (var i = 0; i < index; i++) {
      if (this._connections[i].isHealthy()) {
        return this._connections[i];
      }
    }

    if (len < this._options.pollMaxSize) {
      var connection = this._createConnection();
      this._connections.add(connection);
      return connection;
    }

    return this._connections[index];
  }

  //===========================================
  // EventHandler implementation
  //===========================================

  @override
  void onConnecting(args) {
    tryWith(() => this._eventHandler.onConnecting(args));
    this.notify(Event.ON_CONNECTING, args);
  }

  @override
  void onConnected(args) {
    tryWith(() => this._eventHandler.onConnected(args));
    this.notify(Event.ON_CONNECTED, args);
  }

  @override
  void onDisconnecting(args) {
    tryWith(() => this._eventHandler.onDisconnecting(args));
    this.notify(Event.ON_DISCONNECTING, args);
  }

  @override
  void onDisconnected(args) {
    tryWith(() => this._eventHandler.onDisconnected(args));
    this.notify(Event.ON_DISCONNECTED, args);
  }

  @override
  void onError(args) {
    this._tryDropConnection(args[args.length - 1]);
    logger.d('<${args[args.length - 2].id()}>Error occured: ${args}, propagating up...');
    tryWith(() => this._eventHandler.onError(args));
    this.notify(Event.ON_ERROR, args);
  }

  //===========================================
  // internal functions
  //===========================================

  MultiAltEndpointsConnection _createConnection() {
    return new MultiAltEndpointsConnection(this._pickEndpoint, this._options, eventHandler: this);
  }

  void _tryDropConnection(MultiAltEndpointsConnection connection) {
    var oldLen = this._connections.length;
    var minSize = this._options.pollMinSize;
    if (oldLen <= minSize) {
      logger.i(
          '<${connection.id()}>No need to drop connection, since the pool size is already at min size: $minSize');
      return;
    }
    this._connections.remove(connection);
    var newLen = this._connections.length;
    logger.i(
        '<${connection.id()}>Dropping connection: endpoint: ${connection.endpoint()}, old pool size: $oldLen, new pool size: $newLen');
    connection.close();
  }

  int _nextIndex() {
    if (this._indexSeed >= this._connections.length - 1) {
      this._indexSeed = 0;
    } else {
      ++this._indexSeed;
    }
    return this._indexSeed;
  }
}
