import 'package:maxwell_client/maxwell_client.dart';

class Master {
  List<String> _endpoints;
  Options _options;
  Connection? _connection = null;
  int _endpoint_index = -1;

  Master(endpoints, options)
      : _endpoints = endpoints,
        _options = options {
    this._connectToMaster();
  }

  void close() {
    this._disconnectFromMaster();
  }

  Future<String> assignFrontend([Duration? timeout = null]) async {
    if (timeout == null) {
      timeout = this._options.defaultRoundTimeout;
    }
    await this._connection!.ready().timeout(timeout);
    assign_frontend_rep_t rep = await this
        ._connection!
        .send(assign_frontend_req_t()) as assign_frontend_rep_t;
    return rep.endpoint;
  }

  void _connectToMaster() {
    this._connection = new Connection(this._nextEndpoint(), this._options);
  }

  void _disconnectFromMaster() {
    if (this._connection == null) {
      return;
    }
    this._connection!.close();
    this._connection = null;
  }

  String _nextEndpoint() {
    this._endpoint_index += 1;
    if (this._endpoint_index >= this._endpoints.length) {
      this._endpoint_index = 0;
    }
    return this._endpoints[this._endpoint_index];
  }
}
