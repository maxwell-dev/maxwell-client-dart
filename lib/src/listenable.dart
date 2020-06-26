import 'package:maxwell_client/maxwell_client.dart';
import 'package:tuple/tuple.dart';
import './logger.dart';

typedef OnEvent = void Function([dynamic result]);

mixin Listenable {
  Map<Event, List<OnEvent>> _listeners = Map();
  List<Tuple3> _pendingListeners = List();
  bool _isInIteration = false;

  void addListener(Event event, OnEvent callback) {
    if (this._isInIteration) {
      this._pendingListeners.add(Tuple3(1, event, callback));
      return;
    }
    var callbacks = this._listeners[event];
    if (callbacks == null) {
      callbacks = [];
      this._listeners[event] = callbacks;
    }
    if (callbacks.indexOf(callback) == -1) {
      callbacks.add(callback);
    }
  }

  void removeListener(Event event, OnEvent callback) {
    if (this._isInIteration) {
      this._pendingListeners.add(Tuple3(0, event, callback));
      return;
    }
    var callbacks = this._listeners[event];
    if (callbacks == null) {
      return;
    }
    callbacks.removeWhere((callback2) => callback2 == callback);
  }

  clear() {
    this._listeners.clear();
  }

  notify(Event event, [dynamic result = null]) {
    var callbacks = this._listeners[event];
    if (callbacks == null) {
      return;
    }
    try {
      this._isInIteration = true;
      callbacks.forEach((callback) {
        try {
          if (result != null) {
            callback(result);
          } else {
            callback();
          }
        } catch (e, s) {
          logger.e('Failed to notify: reason: $e, stack: $s');
        }
      });
    } finally {
      this._isInIteration = false;
      this._pendingListeners.forEach((tuple) {
        if (tuple.item1 == 1) {
          this.addListener(tuple.item2, tuple.item3);
        } else if (tuple.item1 == 0) {
          this.removeListener(tuple.item2, tuple.item3);
        } else {
          // Should never goes here.
        }
      });
    }
  }
}
