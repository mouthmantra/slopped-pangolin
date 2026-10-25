import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/tray/pixmap.dart';

DBusStruct _pixmap(int width, int height, List<int> argb) => DBusStruct([
      DBusInt32(width),
      DBusInt32(height),
      DBusArray.byte(argb),
    ]);

DBusArray _pixmaps(List<DBusStruct> pixmaps) =>
    DBusArray(DBusSignature("(iiay)"), pixmaps);

TrayPixmap _solid(int size) =>
    TrayPixmap.create(size, size, Uint8List(size * size * 4))!;

void main() {
  group("parseTrayPixmaps", () {
    test("reads every size", () {
      final List<TrayPixmap> result = parseTrayPixmaps(
        _pixmaps([
          _pixmap(1, 1, [255, 1, 2, 3]),
          _pixmap(2, 1, [255, 1, 2, 3, 0, 0, 0, 0]),
        ]),
      );
      expect(result.map((e) => (e.width, e.height)), [(1, 1), (2, 1)]);
      expect(result.first.argb, [255, 1, 2, 3]);
    });

    test("accepts the value still in its variant", () {
      expect(
        parseTrayPixmaps(DBusVariant(_pixmaps([_pixmap(1, 1, [1, 2, 3, 4])]))),
        hasLength(1),
      );
    });

    test("skips pixmaps with too little data or a silly size", () {
      final List<TrayPixmap> result = parseTrayPixmaps(
        _pixmaps([
          _pixmap(2, 2, [255, 1, 2, 3]), // 4 of 16 bytes
          _pixmap(0, 4, []),
          _pixmap(-1, 1, [1, 2, 3, 4]),
          _pixmap(4096, 1, List.filled(4096 * 4, 0)),
          _pixmap(1, 1, [9, 9, 9, 9]),
        ]),
      );
      expect(result, hasLength(1));
      expect(result.single.argb, [9, 9, 9, 9]);
    });

    test("anything else is no pixmaps", () {
      expect(parseTrayPixmaps(null), isEmpty);
      expect(parseTrayPixmaps(const DBusString("")), isEmpty);
      expect(parseTrayPixmaps(_pixmaps([])), isEmpty);
      expect(
        parseTrayPixmaps(
          DBusArray(DBusSignature("(ii)"), [
            DBusStruct([const DBusInt32(1), const DBusInt32(1)]),
          ]),
        ),
        isEmpty,
      );
    });
  });

  group("TrayPixmap.toRgba", () {
    test("turns network order ARGB into premultiplied RGBA", () {
      final TrayPixmap pixmap = TrayPixmap.create(
        3,
        1,
        Uint8List.fromList([
          255, 10, 20, 30, // opaque
          128, 255, 0, 100, // half transparent
          0, 200, 200, 200, // transparent
        ]),
      )!;
      expect(pixmap.toRgba(), [
        10, 20, 30, 255,
        128, 0, 50, 128,
        0, 0, 0, 0,
      ]);
    });

    test("ignores bytes past the image", () {
      final TrayPixmap pixmap = TrayPixmap.create(
        1,
        1,
        Uint8List.fromList([255, 1, 2, 3, 7, 7, 7, 7]),
      )!;
      expect(pixmap.toRgba(), [1, 2, 3, 255]);
    });
  });

  group("pickTrayPixmap", () {
    final List<TrayPixmap> sizes = [_solid(48), _solid(16), _solid(32), _solid(22)];

    test("takes the closest size", () {
      expect(pickTrayPixmap(sizes, 24)!.width, 22);
      expect(pickTrayPixmap(sizes, 30)!.width, 32);
      expect(pickTrayPixmap(sizes, 64)!.width, 48);
      expect(pickTrayPixmap(sizes, 10)!.width, 16);
    });

    test("prefers the larger one on a tie", () {
      expect(pickTrayPixmap(sizes, 27)!.width, 32);
      expect(pickTrayPixmap(sizes, 19)!.width, 22);
    });

    test("uses the larger side of non-square pixmaps", () {
      final TrayPixmap wide = TrayPixmap.create(40, 20, Uint8List(3200))!;
      expect(pickTrayPixmap([_solid(16), wide], 38), same(wide));
    });

    test("nothing to pick from", () {
      expect(pickTrayPixmap(const [], 24), isNull);
    });
  });

  test("pixmaps are equal by content", () {
    final TrayPixmap a = TrayPixmap.create(1, 1, Uint8List.fromList([1, 2, 3, 4]))!;
    final TrayPixmap b = TrayPixmap.create(1, 1, Uint8List.fromList([1, 2, 3, 4]))!;
    final TrayPixmap c = TrayPixmap.create(1, 1, Uint8List.fromList([1, 2, 3, 5]))!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
