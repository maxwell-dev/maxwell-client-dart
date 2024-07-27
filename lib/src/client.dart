import 'package:logger/logger.dart';
import 'package:maxwell_protocol/maxwell_protocol.dart';
import './internal.dart';

class Client {
  late Master _master;
  late Frontend _frontend;

  Client(endpoints, [options]) {
    var finalOptions = options == null ? Options() : options;
    Logger.level = finalOptions.logLevel;
    this._master = Master(endpoints, finalOptions);
    this._frontend = Frontend(this._master, finalOptions);
  }

  void suspend() {
    this._frontend.suspend();
  }

  void resume() {
    this._frontend.resume();
  }

  close() {
    this._frontend.close();
  }

  void subscribe(String topic, int offset, OnMsg callback) {
    this._frontend.subscribe(topic, offset, callback);
  }

  void unsubscribe(topic) {
    this._frontend.unsubscribe(topic);
  }

  List<msg_t> consume(topic, [offset = 0, limit = 64]) {
    return this._frontend.consume(topic, offset, limit);
  }

  Future<dynamic> request(String path,
      {dynamic payload,
      Headers? headers,
      Duration? waitOpenTimeout,
      Duration? roundTimeout}) async {
    return await this._frontend.request(path,
        payload: payload,
        headers: headers,
        waitOpenTimeout: waitOpenTimeout,
        roundTimeout: roundTimeout);
  }

  Future<void> waitOpen([Duration? timeout = null]) async {
    await this._frontend.waitOpen(timeout);
  }

  bool isOpen() {
    return this._frontend.isOpen();
  }
}
