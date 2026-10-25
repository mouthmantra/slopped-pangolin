/*
Copyright 2026 The dahliaOS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:typed_data';

import 'package:dbus/dbus.dart';

/// One size of a StatusNotifierItem icon (`IconPixmap` and friends):
/// ARGB32 pixels in network byte order, not premultiplied.
class TrayPixmap {
  /// Larger icons are refused: nothing on a taskbar needs them and a broken
  /// item could otherwise make the shell allocate anything.
  static const int maxSize = 1024;

  final int width;
  final int height;
  final Uint8List argb;

  TrayPixmap._(this.width, this.height, this.argb);

  /// Null when the data doesn't describe [width] x [height] pixels.
  static TrayPixmap? create(int width, int height, Uint8List argb) {
    if (width <= 0 || height <= 0) return null;
    if (width > maxSize || height > maxSize) return null;
    if (argb.length < width * height * 4) return null;
    return TrayPixmap._(width, height, argb);
  }

  int get size => width > height ? width : height;

  /// The pixels as RGBA, premultiplied (what dart:ui expects of
  /// `decodeImageFromPixels` with `PixelFormat.rgba8888`).
  Uint8List toRgba() {
    final int count = width * height;
    final Uint8List out = Uint8List(count * 4);
    for (int i = 0; i < count * 4; i += 4) {
      final int a = argb[i];
      final int r = argb[i + 1];
      final int g = argb[i + 2];
      final int b = argb[i + 3];
      if (a == 255) {
        out[i] = r;
        out[i + 1] = g;
        out[i + 2] = b;
      } else if (a != 0) {
        out[i] = (r * a + 127) ~/ 255;
        out[i + 1] = (g * a + 127) ~/ 255;
        out[i + 2] = (b * a + 127) ~/ 255;
      }
      out[i + 3] = a;
    }
    return out;
  }

  late final int _hash = Object.hash(
    width,
    height,
    // Enough of the pixels to tell icons apart; == compares all of them.
    Object.hashAll(argb.length <= 64 ? argb : argb.sublist(0, 64)),
    argb.length,
  );

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TrayPixmap ||
        other.width != width ||
        other.height != height ||
        other.argb.length != argb.length ||
        other._hash != _hash) {
      return false;
    }
    for (int i = 0; i < argb.length; i++) {
      if (other.argb[i] != argb[i]) return false;
    }
    return true;
  }
}

/// Reads an `a(iiay)` property. Entries that don't make sense are skipped,
/// anything that isn't an array of pixmaps gives an empty list.
List<TrayPixmap> parseTrayPixmaps(DBusValue? raw) {
  final DBusValue? value = raw is DBusVariant ? raw.value : raw;
  if (value is! DBusArray) return const [];
  final List<TrayPixmap> result = [];
  for (final DBusValue child in value.children) {
    if (child is! DBusStruct || child.children.length < 3) continue;
    final List<DBusValue> fields = child.children;
    final int? width = _int(fields[0]);
    final int? height = _int(fields[1]);
    final Uint8List? bytes = _bytes(fields[2]);
    if (width == null || height == null || bytes == null) continue;
    final TrayPixmap? pixmap = TrayPixmap.create(width, height, bytes);
    if (pixmap != null) result.add(pixmap);
  }
  return result;
}

/// The pixmap closest to [size] pixels. Ties go to the larger one: scaled
/// down it stays sharp.
TrayPixmap? pickTrayPixmap(List<TrayPixmap> pixmaps, double size) {
  TrayPixmap? best;
  double bestDistance = double.infinity;
  for (final TrayPixmap pixmap in pixmaps) {
    final double distance = (pixmap.size - size).abs();
    if (distance < bestDistance ||
        (distance == bestDistance && best != null && pixmap.size > best.size)) {
      best = pixmap;
      bestDistance = distance;
    }
  }
  return best;
}

int? _int(DBusValue value) => switch (value) {
      DBusInt32(:final value) => value,
      DBusUint32(:final value) => value,
      DBusInt64(:final value) => value,
      DBusUint64(:final value) => value,
      DBusInt16(:final value) => value,
      DBusUint16(:final value) => value,
      _ => null,
    };

Uint8List? _bytes(DBusValue value) {
  if (value is! DBusArray || value.childSignature != DBusSignature.byte) {
    return null;
  }
  return Uint8List.fromList(value.asByteArray().toList());
}
