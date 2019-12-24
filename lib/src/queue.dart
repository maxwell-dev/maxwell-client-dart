import 'package:maxwell_protocol/maxwell_protocol.dart';

class Queue {
  int _capacity;
  List<msg_t> _buffer;

  Queue(int capacity)
      : _capacity = capacity,
        _buffer = [];

  void put(List<msg_t> msgs) {
    if (msgs.length <= 0) {
      return;
    }
    var minIndex = this.minIndexFrom(msgs[0].offset.toInt());
    if (minIndex > -1) {
      this._buffer.removeRange(minIndex, this._buffer.length);
    }
    for (var i = 0; i < msgs.length; i++) {
      if (this._buffer.length >= this._capacity) {
        break;
      }
      this._buffer.add(msgs[i]);
    }
  }

  void removeFirst() {
    if (this._buffer.length > 0) {
      this._buffer.removeAt(0);
    }
  }

  void removeTo(int offset) {
    if (offset < 0) {
      return;
    }
    var maxIndex = this.maxIndexTo(offset);
    this._buffer.removeRange(0, maxIndex + 1);
  }

  void clear() {
    this._buffer.clear();
  }

  List<msg_t> getFrom(int offset, int limit) {
    List<msg_t> result = [];
    if (offset < 0) {
      offset = 0;
    }
    if (limit <= 0 || this._buffer.length <= 0) {
      return result;
    }
    var startIndex = this.minIndexFrom(offset);
    if (startIndex < 0) {
      return result;
    }
    var endIndex = startIndex + limit - 1;
    if (endIndex > this._buffer.length - 1) {
      endIndex = this._buffer.length - 1;
    }
    for (var i = startIndex; i <= endIndex; i++) {
      result.add(this._buffer[i]);
    }
    return result;
  }

  size() {
    return this._buffer.length;
  }

  isFull() {
    return this._buffer.length == this._capacity;
  }

  int firstOffset() {
    if (this._buffer.length <= 0) {
      return -1;
    }
    return this._buffer[0].offset.toInt();
  }

  int lastOffset() {
    if (this._buffer.length <= 0) {
      return -1;
    }
    return this._buffer[this._buffer.length - 1].offset.toInt();
  }

  minIndexFrom(int offset) {
    var index = -1;
    for (var i = 0; i < this._buffer.length; i++) {
      if (this._buffer[i].offset >= offset) {
        index = i;
        break;
      }
    }
    return index;
  }

  maxIndexTo(int offset) {
    var index = -1;
    for (var i = 0; i < this._buffer.length; i++) {
      if (this._buffer[i].offset > offset) {
        break;
      }
      index = i;
    }
    return index;
  }
}
