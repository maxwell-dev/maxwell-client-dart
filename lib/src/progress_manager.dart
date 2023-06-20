class ProgressManager {
  Map<String, int> _progresses = Map();

  void operator []=(String topic, int offset) {
    this._progresses[topic] = offset;
  }

  void remove(String topic) {
    this._progresses.remove(topic);
  }

  void clear() {
    this._progresses.clear();
  }

  bool contains(String topic) {
    return this._progresses.containsKey(topic);
  }

  int? operator [](String topic) {
    return this._progresses[topic];
  }

  Map<String, int> get progresses {
    return this._progresses;
  }
}
