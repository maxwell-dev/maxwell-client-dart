import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:time/time.dart';
import 'package:maxwell_client/maxwell_client.dart';

void main() async {
  group("Connection", () {
    test("normal request", () async {
      var conn = Connection("localhost:10000", Options());
      await conn.waitOpen(1.seconds);
      try {
        var req = req_req_t()
          ..path = "/hello"
          ..payload = "";
        var rep = await conn.send(req, 1.seconds) as req_rep_t;
        expect(jsonDecode(rep.payload), equals("world"));
      } catch (error) {
        logger.e(error.toString());
        rethrow;
      } finally {
        conn.close();
      }
    });

    test("unknown msg", () async {
      var conn = Connection("localhost:8081", Options());
      await conn.waitOpen(1.seconds);
      try {
        await conn.send(auth_req_t()..token = "abc", 1.seconds);
      } catch (error) {
        expect(error, TypeMatcher<ServiceError>());
        var error2 = error as ServiceError;
        expect(error2.code, equals(1));
        expect(
            error2.desc,
            equals(
                'Received unknown msg: AuthReq { token: "abc", conn0_ref: 0, conn1_ref: 0, r#ref: 1 }'));
      } finally {
        conn.close();
      }
    });

    test("path not exist", () async {
      var conn = Connection("localhost:10000", Options());
      await conn.waitOpen(1.seconds);
      try {
        var req = req_req_t()
          ..path = "/hello2"
          ..payload = "";
        await conn.send(req, 1.seconds);
      } catch (error) {
        expect(error, TypeMatcher<ServiceError>());
        var error2 = error as ServiceError;
        expect(error2.code, equals(299));
        expect(
            error2.desc,
            equals(
                'Failed to get connetion: err: Failed to find endpoint: path: "/hello2"'));
      } finally {
        conn.close();
      }
    });

    test("failed to connect", () async {
      var conn;
      try {
        conn = Connection("localhost:1", Options());
      } catch (e) {
        throw new Exception("should not reach here");
      }

      try {
        await conn.waitOpen(1.seconds);
      } catch (error) {
        expect(error, TypeMatcher<SocketException>());
      } finally {
        conn.close();
      }
    });

    test("listen on connected event", () async {
      var conn = Connection("localhost:10000", Options());
      try {
        var completer = Completer();
        conn.addListener(Event.ON_CONNECTED, ([_]) {
          completer.complete("connected");
        });
        expect(await completer.future, "connected");
      } catch (error) {
        throw new Exception("should not reach here");
      } finally {
        conn.close();
      }
    });
  });

  group("MultiAltEndpointsConnection", () {
    test("normal request", () async {
      var conn = MultiAltEndpointsConnection(
          () => Future.value("localhost:10000"), Options());
      await conn.waitOpen(1.seconds);
      try {
        var req = req_req_t()
          ..path = "/hello"
          ..payload = "";
        var rep = await conn.send(req, 5.seconds) as req_rep_t;
        expect(jsonDecode(rep.payload), equals("world"));
      } catch (error) {
        logger.e(error.toString());
        rethrow;
      } finally {
        conn.close();
      }
    });

    test("unknown msg", () async {
      var conn = MultiAltEndpointsConnection(
          () => Future.value("localhost:8081"), Options());
      await conn.waitOpen(1.seconds);
      try {
        await conn.send(auth_req_t()..token = "abc", 1.seconds);
      } catch (error) {
        expect(error, TypeMatcher<ServiceError>());
        var error2 = error as ServiceError;
        expect(error2.code, equals(1));
        expect(
            error2.desc,
            equals(
                'Received unknown msg: AuthReq { token: "abc", conn0_ref: 0, conn1_ref: 0, r#ref: 1 }'));
      } finally {
        conn.close();
      }
    });

    test("path not exist", () async {
      var conn = MultiAltEndpointsConnection(
          () => Future.value("localhost:10000"), Options());
      await conn.waitOpen(1.seconds);
      try {
        var req = req_req_t()
          ..path = "/hello2"
          ..payload = "";
        await conn.send(req, 1.seconds);
      } catch (error) {
        expect(error, TypeMatcher<ServiceError>());
        var error2 = error as ServiceError;
        expect(error2.code, equals(299));
        expect(
            error2.desc,
            equals(
                'Failed to get connetion: err: Failed to find endpoint: path: "/hello2"'));
      } finally {
        conn.close();
      }
    });

    test("failed to connect", () async {
      var conn;
      try {
        conn = MultiAltEndpointsConnection(
            () => Future.value("localhost:1"), Options());
      } catch (e) {
        throw new Exception("should not reach here");
      }

      try {
        await conn.waitOpen(1.seconds);
      } catch (error) {
        logger.i("failed to connect: $error");
        expect(error, TypeMatcher<TimeoutException>());
      } finally {
        conn.close();
      }
    });

    test("listen on connected event", () async {
      var conn = MultiAltEndpointsConnection(
          () => Future.value("localhost:10000"), Options());
      try {
        var completer = Completer();
        conn.addListener(Event.ON_CONNECTED, ([_]) {
          completer.complete("connected");
        });
        expect(await completer.future, "connected");
      } catch (error) {
        throw new Exception("should not reach here");
      } finally {
        conn.close();
      }
    });
  });
}
