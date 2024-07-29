import 'package:logger/logger.dart' show Level, Logger;
import './internal.dart';

class Options {
  Duration waitOpenTimeout;
  Duration reconnectDelay;
  Duration heartbeatInterval;
  Duration roundTimeout;
  Duration idleTimeout;
  int pollMinSize;
  int pollMaxSize;
  Duration pullInterval;
  int pullLimit;
  int queueCapacity;
  bool sslEnabled;
  Level logLevel;
  bool roundDebugEnabled;
  Store? store;

  Options(
      {this.waitOpenTimeout = const Duration(milliseconds: 5000),
      this.reconnectDelay = const Duration(milliseconds: 2000),
      this.heartbeatInterval = const Duration(milliseconds: 5000),
      this.roundTimeout = const Duration(milliseconds: 5000),
      this.idleTimeout = const Duration(milliseconds: 30000),
      this.pollMinSize = 1,
      this.pollMaxSize = 3,
      this.pullInterval = const Duration(milliseconds: 200),
      this.pullLimit = 128,
      this.queueCapacity = 512,
      this.sslEnabled = false,
      this.logLevel = Level.info,
      this.roundDebugEnabled = false,
      this.store}) {
    if (this.store == null) {
      this.store = new DefaultStore();
    }
    Logger.level = this.logLevel;
  }
}
