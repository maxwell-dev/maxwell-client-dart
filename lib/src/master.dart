import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import './internal.dart';

const CACHE_KEY = 'maxwell-client.frontend-endpoints';
const CACHE_TTL = 60 * 60 * 24;

class Master {
  bool _sslEnabled = false;
  List<String> _endpoints;
  int _endpoint_index = -1;
  late Store _store;

  Master(endpoints, options) : _endpoints = endpoints {
    this._sslEnabled = options.sslEnabled;
    this._initEndpointIndex();
    this._store = options.store!;
  }

  Future<String> pickFrontend({force = false}) async {
    var frontends = await this.pickFrontends(force: force);
    return frontends[Random().nextInt(frontends.length)];
  }

  Future<List> pickFrontends({force = false}) async {
    if (!force) {
      Map? endpointsInfo = this._store.get(CACHE_KEY);
      if (endpointsInfo != null) {
        if (this._now() - endpointsInfo['ts'] >= CACHE_TTL) {
          this._store.remove(CACHE_KEY);
        } else {
          return endpointsInfo['endpoints'];
        }
      }
    }
    var rep = await this._request('/\$pick-frontends');
    if (rep['code'] != 0) {
      throw new Exception('Failed to pick frontends: ${rep.code}');
    }
    var endpoints = rep['endpoints']!;
    if (endpoints.length == 0) {
      throw new Exception('Failed to pick available frontends!');
    }
    this._store.set(CACHE_KEY, {'ts': this._now(), 'endpoints': endpoints});
    return endpoints;
  }

  Future<dynamic> _request(String path) async {
    var url = this._sslEnabled
        ? Uri.https(this._nextEndpoint(), path)
        : Uri.http(this._nextEndpoint(), path);
    logger.i('Requesting master: $url');
    var response = await http.get(url);
    if (response.statusCode != 200) {
      throw new Exception('Failed to request master: url: $url, status: ${response.statusCode}');
    }
    var rep = jsonDecode(response.body);
    logger.i('Successfully to request master: rep: $rep');
    return rep;
  }

  void _initEndpointIndex() {
    if (this._endpoints.length == 0) {
      throw new Exception('No endpoint provided');
    }
    this._endpoint_index = Random().nextInt(this._endpoints.length);
  }

  String _nextEndpoint() {
    this._endpoint_index += 1;
    if (this._endpoint_index >= this._endpoints.length) {
      this._endpoint_index = 0;
    }
    return this._endpoints[this._endpoint_index];
  }

  int _now() {
    return (DateTime.now().millisecondsSinceEpoch / 1000).round();
  }
}
