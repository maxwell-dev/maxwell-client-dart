import 'package:maxwell_client/maxwell_client.dart';

class Client {
  Frontend _frontend;

  Client(endpoints, [options]) {
    this._frontend = Frontend(endpoints, options == null ? Options() : options);
  }

  void subscribe(String topic, int offset, OnMsg callback) {
    this._frontend.subscribe(topic, offset, callback);
  }

  void unsubscribe(topic) {
    this._frontend.unsubscribe(topic);
  }

  List<msg_t> consume(topic, [offset = 0, limit = 32]) {
    return this._frontend.consume(topic, offset, limit);
  }

  dynamic request(Action action, [Params params]) async {
    return await this._frontend.request(action, params);
  }
}
