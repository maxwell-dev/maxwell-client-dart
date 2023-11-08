import 'dart:async';
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
  onConnecting(args);
  onConnected(args);
  onDisconnecting(args);
  onDisconnected(args);
  onError(args);
}

class DefaultEventHandler implements EventHandler {
  const DefaultEventHandler();
  onConnecting(args) {}
  onConnected(args) {}
  onDisconnecting(args) {}
  onDisconnected(args) {}
  onError(args) {}
}

class Connection with Listenable {
  String _endpoint;
  Options _options;
  EventHandler _eventHandler;

  bool _shouldRun = true;
  Timer? _reconnectTimer = null;
  Timer? _heartbeatTimer = null;
  DateTime _sentAt = DateTime.now();
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
    this._connect();
  }

  void close() {
    this._shouldRun = false;
    this._stopReconnect();
    this._disconnect();
    this._closeChannel();
  }

  String endpoint() {
    return this._endpoint;
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

  Future<GeneratedMessage> send(GeneratedMessage msg,
      [Duration? timeout = null]) {
    var ref = this._newRef();
    msg.set_ref(ref);

    if (timeout == null) {
      timeout = this._options.roundTimeout;
    }

    var completer = Completer<GeneratedMessage>();
    this._completers[ref] = completer;

    try {
      this._send(msg);
    } catch (e) {
      completer.completeError(e);
    }

    return completer.future.whenComplete(() {
      this._completers.remove(ref);
    }).timeout(timeout, onTimeout: () {
      var e = TimeoutException('msg: ${msg.toProto3Json()}', timeout);
      logger.d(e);
      completer.completeError(e);
      return completer.future;
    });
  }

  //===========================================
  // callback functions
  //===========================================

  void onData(data) {
    GeneratedMessage msg;
    try {
      msg = decode_msg(data);
    } catch (e, s) {
      logger.e('Failed to decode msg: reason: $e, stack: $s');
      this._eventHandler.onError([ErrorCode.FAILED_TO_DECODE, e, this]);
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_DECODE, e, this]);
      return;
    }

    if (msg is ping_req_t) {
      return;
    }

    if (this._options.roundDebugEnabled) {
      logger.d('Received msg: $msg');
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
      logger.e('Failed to receive msg: reason: $e, stack: $s');
      this._eventHandler.onError([ErrorCode.FAILED_TO_RECEIVE, e, this]);
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_RECEIVE, e, this]);
    } finally {
      this._completers.remove(ref);
    }
  }

  void onDone() {
    logger.i('Disconnected: endpoint: ${this._endpoint}');
    try {
      this._isOpen = false;
      this._stopRepeatSendHeartbeat();
      this._closeChannel();
      this._eventHandler.onDisconnected([this]);
      this.notify(Event.ON_DISCONNECTED, [this]);
    } finally {
      this._reconnect();
    }
  }

  void onError(error) {
    logger.e('Error occured: ${error}');
    this._eventHandler.onError([ErrorCode.OPAQUE_ERROR, error, this]);
    this.notify(Event.ON_ERROR, [ErrorCode.OPAQUE_ERROR, error, this]);
  }

  //===========================================
  // internal functions
  //===========================================

  void _connect() {
    logger.i('Connecting: endpoint: ${this._endpoint}');
    this._eventHandler.onConnecting([this]);
    this.notify(Event.ON_CONNECTING, [this]);
    var channel = IOWebSocketChannel.connect(this._buildUri());
    channel.stream
        .listen(this.onData, onError: this.onError, onDone: this.onDone);
    channel.ready.then((_) {
      logger.i('Connected: endpoint: ${this._endpoint}');
      this._isOpen = true;
      this._repeatSendHeartbeat();
      this._eventHandler.onConnected([this]);
      this.notify(Event.ON_CONNECTED, [this]);
    }, onError: (e) {
      logger.e('Failed to connect: endpoint: ${this._endpoint}, error: $e');
      this._isOpen = false;
      this._eventHandler.onError([ErrorCode.FAILED_TO_CONNECT, e, this]);
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_CONNECT, e, this]);
    });
    this._channel = channel;
  }

  void _disconnect() {
    logger.i('Disconnecting: endpoint: ${this._endpoint}');
    this._eventHandler.onDisconnecting([this]);
    this.notify(Event.ON_DISCONNECTING, [this]);
    this._closeChannel();
  }

  void _closeChannel() {
    this._channel.sink.close().then((_) {});
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

  void _repeatSendHeartbeat() {
    if (!this._shouldRun) {
      return;
    }
    this._heartbeatTimer =
        Timer.periodic(this._options.heartbeatInterval, (Timer timer) {
      this._sendHeartbeat();
    });
  }

  void _stopRepeatSendHeartbeat() {
    if (this._heartbeatTimer != null) {
      this._heartbeatTimer!.cancel();
      this._heartbeatTimer = null;
    }
  }

  void _sendHeartbeat() {
    if (this.isOpen() && !this._hasSentHeartbeat()) {
      this._send(ping_req_t());
    }
  }

  bool _hasSentHeartbeat() {
    return DateTime.now()
        .subtract(this._options.heartbeatInterval)
        .isBefore(_sentAt);
  }

  void _send(msg) {
    if (this._options.roundDebugEnabled) {
      logger.d('Sending msg: ${msg.toProto3Json()}');
    }

    var encodedMsg = null;
    try {
      encodedMsg = encode_msg(msg);
    } catch (e, s) {
      logger.e('Failed to encode msg: reason: $e, stack: $s');
      this._eventHandler.onError([ErrorCode.FAILED_TO_ENCODE, e, this]);
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_ENCODE, e, this]);
      throw new Exception('Failed to encode msg: reason: $e');
    }

    try {
      this._channel.sink.add(encodedMsg);
      this._sentAt = DateTime.now();
    } catch (e, s) {
      logger.e('Failed to send msg: reason: $e, stack: $s');
      this._eventHandler.onError([ErrorCode.FAILED_TO_SEND, e, this]);
      this.notify(Event.ON_ERROR, [ErrorCode.FAILED_TO_SEND, e, this]);
      throw new Exception('Failed to send msg: reason: $e');
    }
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
    return Uri(
        scheme: scheme,
        host: parts[0],
        port: int.parse(parts[1]),
        path: '\$ws');
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

  MultiAltEndpointsConnection(PickEndpoint pickEndpoint, Options options,
      {EventHandler eventHandler = const DefaultEventHandler()})
      : _pickEndpoint = pickEndpoint,
        _options = options,
        _eventHandler = eventHandler {
    this._connect();
  }

  close() {
    this._shouldRun = false;
    this._stopReconnect();
    this._connectTask.cancel();
    this._connection?.close();
  }

  String? endpoint() {
    return this._connection?.endpoint();
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

  Future<GeneratedMessage> send(GeneratedMessage msg,
      [Duration? timeout = null]) {
    return this._connection!.send(msg, timeout);
  }

  //===========================================
  // EventHandler implementation
  //===========================================

  @override
  onConnecting(args) {
    this._eventHandler.onConnecting(args);
    this.notify(Event.ON_CONNECTING, args);
  }

  @override
  onConnected(args) {
    if (this._oldReadyCompleter != null &&
        !this._oldReadyCompleter!.isCompleted) {
      this._oldReadyCompleter!.complete(this);
    }
    if (!this._readyCompleter.isCompleted) {
      this._readyCompleter.complete(this);
    }
    this._eventHandler.onConnected(args);
    this.notify(Event.ON_CONNECTED, args);
  }

  @override
  onDisconnecting(args) {
    this._eventHandler.onDisconnecting(args);
    this.notify(Event.ON_DISCONNECTING, args);
  }

  @override
  onDisconnected(args) {
    this._oldReadyCompleter = this._readyCompleter;
    this._readyCompleter = Completer();
    this._reconnect();
    this._eventHandler.onDisconnected(args);
    this.notify(Event.ON_DISCONNECTED, args);
  }

  @override
  onError(args) {
    logger.e('onError: endpoint: ${this._connection!.endpoint()}');
    this._eventHandler.onError(args);
    this.notify(Event.ON_ERROR, args);
  }

  //===========================================
  // internal functions
  //===========================================

  _connect() {
    this._connectTask =
        CancelableOperation.fromFuture(this._pickEndpoint().then((endpiont) {
      if (!this._shouldRun) {
        return;
      }
      this._connection =
          new Connection(endpiont, this._options, eventHandler: this);
    }).catchError((reason) {
      logger.e('Failed to pick endpoint: ${reason}');
      this._reconnect();
    }));
  }

  _reconnect() {
    if (!this._shouldRun) {
      return;
    }
    this._connection?.close();
    this._stopReconnect();
    this._reconnectTimer = Timer(this._options.reconnectDelay, this._connect);
  }

  _stopReconnect() {
    if (this._reconnectTimer != null) {
      this._reconnectTimer!.cancel();
      this._reconnectTimer = null;
    }
  }
}
