import 'package:maxwell_client/maxwell_client.dart';
import './logger.dart';

typedef OnEvent = void Function([dynamic result]);

mixin Listenable {
  Map<Event, List<OnEvent>> _listeners = Map();

  void addListener(Event event, OnEvent callback) {
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
  }
}
