import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:time/time.dart';
import 'package:maxwell_client/maxwell_client.dart';

final logger = Logger();

var client = Client(["localhost:8081"], Options()..logLevel = Level.error);

Future<void> request(retry) async {
  try {
    var reply = await client.request("/hello");
    print('received reply: ${reply.length}');
    await Future.delayed(1.seconds);
  } catch (e) {
    print("=======>");
    print(e);
    if (retry < 5) {
      request(retry + 1);
    } else {
      rethrow;
    }
  }
}

void main() {
  test("all", () async {
    // client.subscribe("topic_3", 0, (_) {
    //   var msgs = client.consume("topic_3");
    //   logger.i('received msgs: $msgs');
    // });

    // for (var i = 0; i < 10000; i++) {
    await request(1);
    // }

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
