import 'dart:io';
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:time/time.dart';
import 'package:maxwell_client/maxwell_client.dart';

final logger = Logger();

void main() {
  test("all", () async {
    var master = Master(["localhost:8081"], Options());
    try {
      var endpoint = await master.assignFrontend(10.seconds);
      logger.i("resolved endpoint: $endpoint");
    } catch (e, s) {
      logger.e("failed to resolve endpoint: $e, $s");
    }
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9997);
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
