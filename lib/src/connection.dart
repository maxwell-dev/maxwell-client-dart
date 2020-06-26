import 'dart:async';
import 'package:web_socket_channel2/io.dart';
import 'package:maxwell_protocol/maxwell_protocol.dart';
import 'package:maxwell_client/maxwell_client.dart';
import './logger.dart';

const int _MAX_REF = 1000000;

class Connection with Listenable {
  String _endpoint = null;
  Options _options = null;
  bool _shouldRun = true;
  Timer _reconnectTimer = null;
  Timer _heartbeatTimer = null;
  DateTime _lastSendingTime = DateTime.now();
  int _lastRef = 0;
  IOWebSocketChannel _channel = null;
  bool _isReady = false;
  Map<int, Completer> _completers = Map();

  Connection(String endpoint, Options options)
      : _endpoint = endpoint,
        _options = options {
    this._connect();
  }

  bool isReady() {
    return this._isReady;
  }

  Future<void> ready() {
    return this._channel.ready;
  }

  void close() {
    this._shouldRun = false;
    this._stopReconnect();
    this._disconnect();
  }

  Future<GeneratedMessage> send(GeneratedMessage msg,
      [Duration timeout = null]) async {
    var ref = this._newRef();

    msg.set_ref(ref);

    if (timeout == null) {
      timeout = this._options.defaultRoundTimeout;
    }

    var completer = Completer<GeneratedMessage>();
    this._completers[ref] = completer;

    this._send(msg);

    return completer.future.timeout(timeout, onTimeout: () {
      var desc = TimeoutException('msg: ${msg.toString()}');
      logger.i(desc);
      this._completers.remove(ref)?.completeError(desc);
      return Future.error(desc);
    });
  }

  void _connect() {
    logger.i('Connecting: endpoint: ${this._endpoint}');
    this.notify(Event.ON_CONNECTING);
    var channel = IOWebSocketChannel.connect(this._buildUri());
    channel.stream
        .listen(this.onData, onError: this.onError, onDone: this.onDone);
    this._channel = channel;
    this._channel.ready.then((_) {
      logger.i('Connected: endpoint: ${this._endpoint}');
      this._isReady = true;
      this._repeatSendHeartbeat();
      this.notify(Event.ON_CONNECTED);
    });
  }

  void onData(data) {
    GeneratedMessage msg = null;
    try {
      msg = decode_msg(data);
    } catch (e, s) {
      logger.e('Failed to decode msg: reason: $e, stack: $s');
      this.notify(Event.error(Code.FAILED_TO_DECODE), e);
      return;
    }

    if (msg is ping_req_t) {
      return;
    }

    var ref = msg.get_ref();

    var completer = this._completers[ref];
    if (completer == null) {
      return;
    }
    try {
      if (msg is error_rep_t) {
        completer.completeError('code: ${msg.code}, desc: ${msg.desc}');
      } else if (msg is error2_rep_t) {
        completer.completeError('code: ${msg.code}, desc: ${msg.desc}');
      } else {
        completer.complete(msg);
      }
    } catch (e, s) {
      logger.e('Failed to receive msg: reason: $e, stack: $s');
      this.notify(Event.error(Code.FAILED_TO_RECEIVE), e);
    } finally {
      this._completers.remove(ref);
    }
  }

  void onError(error) {
    logger.e('Error occured: ${error}');
    this.notify(Event.error(Code.FAILED_TO_CONNECT), error);
  }

  void onDone() {
    logger.i('Disconnected: endpoint: ${this._endpoint}');
    try {
      this._isReady = false;
      this._stopSendHeartbeat();
      this._closeChannel();
      this.notify(Event.ON_DISCONNECTED);
    } finally {
      if (this._shouldRun) {
        this._reconnect();
      }
    }
  }

  void _disconnect() {
    logger.i('Disconnecting: endpoint: ${this._endpoint}');
    this.notify(Event.ON_DISCONNECTING);
    this._closeChannel();
  }

  void _closeChannel() {
    if (this._channel != null) {
      this._channel.sink.close().then((_) {});
      this._channel = null;
    }
  }

  void _reconnect() {
    this._reconnectTimer = Timer(this._options.reconnectDelay, this._connect);
  }

  void _stopReconnect() {
    if (this._reconnectTimer != null) {
      this._reconnectTimer.cancel();
      this._reconnectTimer = null;
    }
  }

  void _repeatSendHeartbeat() {
    this._heartbeatTimer =
        Timer.periodic(this._options.heartbeatInterval, (Timer timer) {
      this._sendHeartbeat();
    });
  }

  void _stopSendHeartbeat() {
    if (this._heartbeatTimer != null) {
      this._heartbeatTimer.cancel();
      this._heartbeatTimer = null;
    }
  }

  void _sendHeartbeat() {
    if (this.isReady() && !this._hasSentHeartbeat()) {
      this._send(ping_req_t());
    }
  }

  void _send(msg) {
    var encodedMsg = null;
    try {
      encodedMsg = encode_msg(msg);
    } catch (e, s) {
      logger.e('Failed to encode msg: reason: $e, stack: $s');
      this.notify(Event.error(Code.FAILED_TO_ENCODE));
      return;
    }

    try {
      this._channel.sink.add(encodedMsg);
      this._lastSendingTime = DateTime.now();
    } catch (e, s) {
      logger.e('Failed to send msg: reason: $e, stack: $s');
      this.notify(Event.error(Code.FAILED_TO_SEND), e);
    }
  }

  bool _hasSentHeartbeat() {
    return DateTime.now()
        .subtract(this._options.heartbeatInterval)
        .isBefore(_lastSendingTime);
  }

  int _newRef() {
    if (this._lastRef > _MAX_REF) {
      this._lastRef = 1;
    }
    return ++this._lastRef;
  }

  Uri _buildUri() {
    var parts = this._endpoint.split(':');
    var scheme = this._options.sslEnabled ? 'wss' : 'ws';
    return Uri(scheme: scheme, host: parts[0], port: int.parse(parts[1]));
  }
}
