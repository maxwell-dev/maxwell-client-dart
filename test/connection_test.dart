import 'dart:io';
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:time/time.dart';
import 'package:maxwell_protocol/maxwell_protocol.dart';
import 'package:maxwell_client/maxwell_client.dart';

final logger = Logger();

void main() {
  test("all", () async {
    var conn = Connection("localhost:8081", Options());
    await conn.ready();
    conn.send(auth_req_t()..token = "abc", 5.seconds).then((value) {
      logger.i('Sent successfully');
    }, onError: (error) {
      logger.e('Error occured: $error');
    });
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
