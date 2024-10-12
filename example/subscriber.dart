import 'package:maxwell_client/maxwell_client.dart';

final client = Client(
  ["localhost:8081"],
  Options()
    ..logLevel = Level.debug
    ..roundDebugEnabled = true,
);

void main() {
  const topic = "topic_1";
  client.subscribe(topic, -1, (offset) {
    print("------topic: $topic, offset: $offset------");
    var msgs;
    do {
      msgs = client.consume(topic);
      msgs.forEach((msg) {
        print(msg);
      });
    } while (msgs.length > 0);
  });
}
