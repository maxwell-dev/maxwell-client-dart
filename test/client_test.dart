import 'package:test/test.dart';
import 'package:maxwell_client/maxwell_client.dart';
import 'package:time/time.dart';

void main() async {
  test("open and close", () async {
    var client = Client(["localhost:8081"], Options()..logLevel = Level.debug);
    client.close();
  });

  test("simple request", () async {
    var client = Client(["localhost:8081"], Options()..logLevel = Level.debug);
    try {
      var rep = await client.request("/hello",
          waitOpenTimeout: 1.seconds, roundTimeout: 1.seconds);
      expect(rep, "world");
    } catch (e) {
      logger.e('Failed to request: $e');
    } finally {
      client.close();
    }
  });

  test("suspend and resume", () async {
    var client = Client(["localhost:8081"], Options()..logLevel = Level.debug);
    client.suspend();
    client.resume();
    client.close();
  });
}
