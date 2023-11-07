import 'package:logger/logger.dart' show Level, Logger;
import './internal.dart';

class Options {
  Duration waitOpenTimeout;
  Duration reconnectDelay;
  Duration heartbeatInterval;
  Duration defaultRoundTimeout;
  Duration pullInterval;
  int defaultOffset;
  int getLimit;
  int queueCapacity;
  bool sslEnabled;
  Level logLevel;
  bool debugRoundEnabled;
  Store? store;

  Options(
      {this.waitOpenTimeout = const Duration(milliseconds: 5000),
      this.reconnectDelay = const Duration(milliseconds: 2000),
      this.heartbeatInterval = const Duration(milliseconds: 10000),
      this.defaultRoundTimeout = const Duration(milliseconds: 5000),
      this.pullInterval = const Duration(milliseconds: 200),
      this.defaultOffset = -60,
      this.getLimit = 128,
      this.queueCapacity = 512,
      this.sslEnabled = false,
      this.logLevel = Level.info,
      this.debugRoundEnabled = false,
      this.store}) {
    if (this.store == null) {
      this.store = new DefaultStore();
    }
    Logger.level = this.logLevel;
  }
}
