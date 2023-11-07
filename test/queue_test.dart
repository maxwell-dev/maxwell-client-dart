import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';
import 'package:maxwell_client/maxwell_client.dart';

void main() {
  test("all", () {
    var q = Queue(3);
    q.put([
      msg_t()..offset = Int64(1),
      msg_t()..offset = Int64(2),
      msg_t()..offset = Int64(3),
      msg_t()..offset = Int64(4)
    ]);
    expect(q.size(), 3);
    q.removeFirst();
    expect(q.size(), 2);
    expect(q.firstOffset() == 2, true);
    q.removeTo(3);
    expect(q.size(), 0);
    q.put([
      msg_t()..offset = Int64(5),
      msg_t()..offset = Int64(7),
      msg_t()..offset = Int64(9),
      msg_t()..offset = Int64(11)
    ]);
    expect(q.size(), 3);
    q.removeTo(3);
    expect(q.size(), 3);
    q.removeTo(8);
    expect(q.size(), 1);
    expect(q.lastOffset() == 9, true);
    q.put([
      msg_t()..offset = Int64(5),
      msg_t()..offset = Int64(7),
      msg_t()..offset = Int64(9),
      msg_t()..offset = Int64(11)
    ]);
    expect(q.size(), 3);
    var result = q.getFrom(0, 5);
    expect(result.length, 3);
    expect(result[0].offset == 5, true);
    expect(result[1].offset == 7, true);
    expect(result[2].offset == 9, true);
    var result2 = q.getFrom(7, 5);
    expect(result2.length, 2);
    expect(result2[0].offset == 7, true);
    expect(result2[1].offset == 9, true);
    var result3 = q.getFrom(6, 1);
    expect(result3.length, 1);
    expect(result3[0].offset == 7, true);
    var result4 = q.getFrom(11, 1);
    expect(result4.length, 0);
  });
}
