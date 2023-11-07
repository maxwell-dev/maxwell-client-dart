import 'package:test/test.dart';
import 'package:maxwell_client/maxwell_client.dart';

void main() async {
  test("pick frontend", () async {
    var master = Master(["localhost:8081"], Options());
    try {
      var endpoint = await master.pickFrontend();
      logger.i("picked endpoint: $endpoint");
      expect(endpoint, "127.0.0.1:10000");
    } catch (e, s) {
      logger.e("failed to pick endpoint: $e, $s");
    }
  });
}
