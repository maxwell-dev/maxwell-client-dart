import 'package:logger/logger.dart' show Level;

class Options {
  Duration reconnectDelay;
  Duration heartbeatInterval;
  Duration defaultRoundTimeout;
  Duration pullInterval;
  int defaultOffset;
  int getLimit;
  int queueCapacity;
  bool masterEnabled;
  bool sslEnabled;
  Level logLevel;

  Options(
      {this.reconnectDelay = const Duration(milliseconds: 3000),
      this.heartbeatInterval = const Duration(milliseconds: 10000),
      this.defaultRoundTimeout = const Duration(milliseconds: 15000),
      this.pullInterval = const Duration(milliseconds: 200),
      this.defaultOffset = -600,
      this.getLimit = 64,
      this.queueCapacity = 512,
      this.masterEnabled = true,
      this.sslEnabled = false,
      this.logLevel = Level.info});
}
