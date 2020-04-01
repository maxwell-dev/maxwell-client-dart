import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:time/time.dart';
import 'package:maxwell_client/maxwell_client.dart';

final logger = Logger();

void main() {
  test("all", () async {
    var client = Client(["localhost:8081"], Options()..logLevel = Level.error);
    client.subscribe("topic_3", 0, (_) {
      var msgs = client.consume("topic_3");
      logger.i('received msgs: $msgs');
    });
    for (var i = 0; i < 10000; i++) {
      var reply = await client.request(Action(type: "get_candles"));
      logger.i('received reply: $reply');
      await Future.delayed(1.seconds);
    }
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9999);
    print("Serving at ${server.address}:${server.port}");

    await for (var request in server) {
      request.response
        ..headers.contentType =
            new ContentType("text", "plain", charset: "utf-8")
        ..write('Hello, world')
        ..close();
    }
  });
}
