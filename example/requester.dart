import 'package:maxwell_client/maxwell_client.dart';

final client = Client(
    ["localhost:8081"],
    Options()
      ..logLevel = Level.error
      ..roundDebugEnabled = true);

run() async {
  try {
    var rep = await client.request("/hello");
    print("answer: $rep");
  } catch (e) {
    print("failed to request: error: $e");
  }
}

warm() async {
  final now = DateTime.now();
  for (var i = 0; i < 3; i++) {
    await run();
  }
  print("answer time@warm in: ${DateTime.now().difference(now).inMilliseconds}ms");
}

runOnce() async {
  final now = DateTime.now();
  await run();
  print("answer time@runOnce in: ${DateTime.now().difference(now).inMicroseconds / 1000}ms");
}

void main() async {
  await warm();
  for (var i = 0; i < 10000000; i++) {
    await runOnce();
  }
  client.close();
}
