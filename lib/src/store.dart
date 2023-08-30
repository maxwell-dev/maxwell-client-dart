abstract class Store {
  dynamic get(String key);
  void set(String key, dynamic value);
  void remove(String key);
}

class DefaultStore implements Store {
  Map<String, dynamic> _map = new Map();

  DefaultStore() {}

  @override
  dynamic get(String key) {
    return this._map[key];
  }

  @override
  void remove(String key) {
    this._map.remove(key);
  }

  @override
  void set(String key, dynamic value) {
    this._map[key] = value;
  }
}
