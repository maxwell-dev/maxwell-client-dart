import 'package:test/test.dart';
import 'package:maxwell_client/maxwell_client.dart';

void main() {
  test("leave all options default", () {
    var options = Options();
    expect(options.reconnectDelay, Duration(milliseconds: 2000));
    expect(options.heartbeatInterval, Duration(milliseconds: 10000));
    expect(options.roundTimeout, Duration(milliseconds: 5000));
    expect(options.pullLimit, 128);
    expect(options.queueCapacity, 512);
    expect(options.sslEnabled, false);
  });

  test("set some options", () {
    var options = Options(
        queueCapacity: 1024, roundTimeout: Duration(milliseconds: 30000));
    expect(options.reconnectDelay, Duration(milliseconds: 2000));
    expect(options.heartbeatInterval, Duration(milliseconds: 10000));
    expect(options.roundTimeout, Duration(milliseconds: 30000));
    expect(options.pullLimit, 128);
    expect(options.queueCapacity, 1024);
    expect(options.sslEnabled, false);
  });
}
