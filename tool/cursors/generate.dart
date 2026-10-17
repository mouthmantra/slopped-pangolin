// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

// Generates Pangolin's cursor theme (Chromium OS style: black shapes with a
// white outline and a soft shadow) as an Xcursor theme, from the vector
// shapes below, with Adwaita's hands (tool/cursors/adwaita). No
// dependencies:
//
//   dart run tool/cursors/generate.dart <output dir>
//
// writes <output dir>/Pangolin/{index.theme,cursors/*}.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Nominal sizes (River asks for 24 × the output scale).
const List<int> sizes = [24, 30, 32, 36, 48, 64, 72, 96];

/// Supersampling per axis.
const int ss = 4;

void main(List<String> args) {
  final String out = args.isNotEmpty ? args.first : "build/cursors";
  final Directory theme = Directory("$out/Pangolin/cursors")
    ..createSync(recursive: true);
  File("$out/Pangolin/index.theme").writeAsStringSync('''
[Icon Theme]
Name=Pangolin
Comment=Pangolin's cursors, in the style of Chromium OS, with Adwaita's hands
Inherits=Adwaita
''');

  for (final Cursor cursor in cursors) {
    final List<Uint8List> chunks = [];
    final List<(int, int)> toc = [];
    for (final int size in sizes) {
      final int frames = cursor.frames;
      for (int frame = 0; frame < frames; frame++) {
        final Image image = cursor.render(size, frame / frames);
        toc.add((size, chunks.length));
        chunks.add(image.encodeChunk(size, frames > 1 ? cursor.delay : 0));
      }
    }
    final File file = File("${theme.path}/${cursor.name}");
    file.writeAsBytesSync(_xcursor(chunks, toc));
    for (final String alias in cursor.aliases) {
      final Link link = Link("${theme.path}/$alias");
      if (link.existsSync() || File(link.path).existsSync()) link.deleteSync();
      link.createSync(cursor.name);
    }
  }
  final String adwaita =
      "${File(Platform.script.toFilePath()).parent.path}/adwaita";
  for (final MapEntry(key: name, value: aliases) in adwaitaCursors.entries) {
    File("$adwaita/$name").copySync("${theme.path}/$name");
    for (final String alias in aliases) {
      final Link link = Link("${theme.path}/$alias");
      if (link.existsSync() || File(link.path).existsSync()) link.deleteSync();
      link.createSync(name);
    }
  }
  stdout.writeln(
    "Wrote ${cursors.length + adwaitaCursors.length} cursors to $out/Pangolin",
  );
}

Uint8List _xcursor(List<Uint8List> chunks, List<(int, int)> toc) {
  const int headerSize = 16;
  final int tocSize = 12 * toc.length;
  final BytesBuilder out = BytesBuilder();
  final ByteData header = ByteData(headerSize)
    ..setUint32(0, 0x72756358, Endian.little) // "Xcur"
    ..setUint32(4, headerSize, Endian.little)
    ..setUint32(8, 0x10000, Endian.little)
    ..setUint32(12, toc.length, Endian.little);
  out.add(header.buffer.asUint8List());
  int position = headerSize + tocSize;
  final List<int> offsets = [];
  for (final Uint8List chunk in chunks) {
    offsets.add(position);
    position += chunk.length;
  }
  for (final (int size, int index) in toc) {
    final ByteData entry = ByteData(12)
      ..setUint32(0, 0xfffd0002, Endian.little)
      ..setUint32(4, size, Endian.little)
      ..setUint32(8, offsets[index], Endian.little);
    out.add(entry.buffer.asUint8List());
  }
  for (final Uint8List chunk in chunks) {
    out.add(chunk);
  }
  return out.toBytes();
}

/// Coverage mask at supersampled resolution, in a 24 unit design grid.
class Mask {
  Mask(this.size) : side = size * ss, data = Float32List(size * ss * size * ss);

  final int size;
  final int side;
  final Float32List data;

  double get scale => side / 24;

  void _set(int x, int y, double v) {
    if (x < 0 || y < 0 || x >= side || y >= side) return;
    final int i = y * side + x;
    if (v > data[i]) data[i] = v;
  }

  /// Fills a polygon (design units).
  void polygon(List<Point> points) {
    final List<Point> p = [for (final Point q in points) q * scale];
    final double minY = p.map((q) => q.y).reduce(math.min);
    final double maxY = p.map((q) => q.y).reduce(math.max);
    for (int y = math.max(0, minY.floor()); y <= math.min(side - 1, maxY.ceil()); y++) {
      final double cy = y + 0.5;
      final List<double> xs = [];
      for (int i = 0; i < p.length; i++) {
        final Point a = p[i];
        final Point b = p[(i + 1) % p.length];
        if ((a.y <= cy && b.y > cy) || (b.y <= cy && a.y > cy)) {
          xs.add(a.x + (cy - a.y) / (b.y - a.y) * (b.x - a.x));
        }
      }
      xs.sort();
      for (int i = 0; i + 1 < xs.length; i += 2) {
        for (int x = math.max(0, xs[i].round()); x < math.min(side, xs[i + 1].round()); x++) {
          _set(x, y, 1);
        }
      }
    }
  }

  void disc(Point center, double radius) {
    final Point c = center * scale;
    final double r = radius * scale;
    for (int y = (c.y - r).floor(); y <= (c.y + r).ceil(); y++) {
      for (int x = (c.x - r).floor(); x <= (c.x + r).ceil(); x++) {
        final double dx = x + 0.5 - c.x;
        final double dy = y + 0.5 - c.y;
        if (dx * dx + dy * dy <= r * r) _set(x, y, 1);
      }
    }
  }

  void roundRect(double l, double t, double r, double b, double radius) {
    polygon([Point(l + radius, t), Point(r - radius, t), Point(r - radius, b), Point(l + radius, b)]);
    polygon([Point(l, t + radius), Point(r, t + radius), Point(r, b - radius), Point(l, b - radius)]);
    for (final Point c in [
      Point(l + radius, t + radius),
      Point(r - radius, t + radius),
      Point(l + radius, b - radius),
      Point(r - radius, b - radius),
    ]) {
      disc(c, radius);
    }
  }

  /// A stroked path with round caps (discs stamped along it).
  void stroke(List<Point> path, double width) {
    final double step = 0.15;
    for (int i = 0; i + 1 < path.length; i++) {
      final Point a = path[i];
      final Point b = path[i + 1];
      final double length = (b - a).length;
      final int n = math.max(1, (length / step).ceil());
      for (int k = 0; k <= n; k++) {
        disc(a + (b - a) * (k / n), width / 2);
      }
    }
  }

  void arc(Point center, double radius, double from, double to, double width) {
    final int n = 64;
    stroke([
      for (int i = 0; i <= n; i++)
        center + Point(math.cos(from + (to - from) * i / n), math.sin(from + (to - from) * i / n)) * radius,
    ], width);
  }

  /// Every point within [radius] (design units) of the shape.
  Mask dilate(double radius) {
    final Mask result = Mask(size);
    final int r = (radius * scale).ceil();
    final List<(int, int)> offsets = [
      for (int dy = -r; dy <= r; dy++)
        for (int dx = -r; dx <= r; dx++)
          if (dx * dx + dy * dy <= r * r) (dx, dy),
    ];
    for (int y = 0; y < side; y++) {
      for (int x = 0; x < side; x++) {
        if (data[y * side + x] < 0.5) continue;
        for (final (int dx, int dy) in offsets) {
          result._set(x + dx, y + dy, 1);
        }
      }
    }
    return result;
  }

  /// Coverage per output pixel.
  Float32List downsample() {
    final Float32List out = Float32List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        double sum = 0;
        for (int sy = 0; sy < ss; sy++) {
          for (int sx = 0; sx < ss; sx++) {
            sum += data[(y * ss + sy) * side + x * ss + sx];
          }
        }
        out[y * size + x] = sum / (ss * ss);
      }
    }
    return out;
  }
}

class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;

  Point operator *(double k) => Point(x * k, y * k);
  Point operator +(Point o) => Point(x + o.x, y + o.y);
  Point operator -(Point o) => Point(x - o.x, y - o.y);
  double get length => math.sqrt(x * x + y * y);

  /// Rotated by [angle] around [center].
  Point rotate(double angle, Point center) {
    final double c = math.cos(angle);
    final double s = math.sin(angle);
    final Point d = this - center;
    return Point(center.x + d.x * c - d.y * s, center.y + d.x * s + d.y * c);
  }
}

class Image {
  Image(this.size, this.pixels, this.hotX, this.hotY);

  final int size;
  final Uint32List pixels;
  final int hotX;
  final int hotY;

  Uint8List encodeChunk(int nominal, int delay) {
    final ByteData data = ByteData(36 + size * size * 4)
      ..setUint32(0, 36, Endian.little)
      ..setUint32(4, 0xfffd0002, Endian.little)
      ..setUint32(8, nominal, Endian.little)
      ..setUint32(12, 1, Endian.little)
      ..setUint32(16, size, Endian.little)
      ..setUint32(20, size, Endian.little)
      ..setUint32(24, hotX, Endian.little)
      ..setUint32(28, hotY, Endian.little)
      ..setUint32(32, delay, Endian.little);
    for (int i = 0; i < pixels.length; i++) {
      data.setUint32(36 + i * 4, pixels[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }
}

/// A cursor: shapes drawn black over a white outline and a shadow.
class Cursor {
  const Cursor(
    this.name,
    this.hotspot,
    this.draw, {
    this.aliases = const [],
    this.frames = 1,
    this.delay = 0,
    this.outline = 1.15,
    this.accent,
    this.cut,
  });

  final String name;
  final List<String> aliases;
  final Point hotspot;

  /// Draws the black shape for animation progress t (0..1).
  final void Function(Mask mask, double t) draw;

  /// Draws parts in the accent color (the spinner), over the black.
  final void Function(Mask mask, double t)? accent;

  /// Draws white details over the black shape (a badge's plus sign).
  final void Function(Mask mask)? cut;
  final int frames;
  final int delay;
  final double outline;

  Image render(int size, double t) {
    final Mask fill = Mask(size);
    draw(fill, t);
    final Mask? accentMask = accent == null ? null : (Mask(size));
    if (accentMask != null) accent!(accentMask, t);

    // Outline around everything drawn.
    final Mask all = Mask(size);
    for (int i = 0; i < all.data.length; i++) {
      all.data[i] = math.max(fill.data[i], accentMask?.data[i] ?? 0);
    }
    final Mask outlined = all.dilate(outline);
    final Float32List f = fill.downsample();
    final Float32List a = accentMask?.downsample() ?? Float32List(size * size);
    final Float32List o = outlined.downsample();
    final Mask? cutMask = cut == null ? null : Mask(size);
    if (cutMask != null) cut!(cutMask);
    final Float32List w = cutMask?.downsample() ?? Float32List(size * size);

    // Soft shadow: the outline, blurred and moved down.
    final Float32List shadow = Float32List(size * size);
    final int blur = math.max(1, (size / 24).round());
    final int drop = math.max(1, (size / 24 * 0.8).round());
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        double sum = 0;
        int n = 0;
        for (int dy = -blur; dy <= blur; dy++) {
          for (int dx = -blur; dx <= blur; dx++) {
            final int sx = x + dx;
            final int sy = y + dy - drop;
            if (sx < 0 || sy < 0 || sx >= size || sy >= size) {
              n++;
              continue;
            }
            sum += o[sy * size + sx];
            n++;
          }
        }
        shadow[y * size + x] = sum / n;
      }
    }

    final Uint32List pixels = Uint32List(size * size);
    for (int i = 0; i < pixels.length; i++) {
      // Premultiplied over, back to front.
      double r = 0, g = 0, b = 0, alpha = 0;
      void over(double sr, double sg, double sb, double sa) {
        r = sr * sa + r * (1 - sa);
        g = sg * sa + g * (1 - sa);
        b = sb * sa + b * (1 - sa);
        alpha = sa + alpha * (1 - sa);
      }

      over(0, 0, 0, shadow[i] * 0.32);
      over(1, 1, 1, o[i]);
      over(0, 0, 0, f[i]);
      // Knuckle lines: soft gray, fainter where pixels are few.
      over(0.62, 0.62, 0.64, w[i] * (size < 32 ? 0.55 : 0.9));
      // Pangolin's orange for the spinner.
      over(1, 0.341, 0.133, a[i]);
      int c(double v) => (v.clamp(0, 1) * 255).round();
      pixels[i] = (c(alpha) << 24) | (c(r) << 16) | (c(g) << 8) | c(b);
    }
    final double k = size / 24;
    return Image(size, pixels, (hotspot.x * k).round(), (hotspot.y * k).round());
  }
}

// Shapes, in a 24 unit grid.

void _arrow(Mask m, [double dx = 0, double dy = 0, double k = 1]) {
  Point p(double x, double y) => Point(dx + (x - 4) * k + 4, dy + (y - 2) * k + 2);
  m.polygon([
    p(4, 2),
    p(4, 18.6),
    p(8.0, 14.9),
    p(10.6, 21.0),
    p(13.2, 19.9),
    p(10.6, 13.8),
    p(16.1, 13.8),
  ]);
}

/// A finger: a stroke with round ends.
void _doubleArrow(Mask m, double angle) {
  const Point c = Point(12, 12);
  List<Point> rot(List<Point> pts) => [for (final Point p in pts) p.rotate(angle, c)];
  m.polygon(rot([const Point(7.0, 11.0), const Point(17.0, 11.0), const Point(17.0, 13.0), const Point(7.0, 13.0)]));
  m.polygon(rot([const Point(3.2, 12), const Point(8.4, 6.8), const Point(8.4, 17.2)]));
  m.polygon(rot([const Point(20.8, 12), const Point(15.6, 6.8), const Point(15.6, 17.2)]));
}

void _move(Mask m) {
  m.polygon([const Point(11.1, 6.0), const Point(12.9, 6.0), const Point(12.9, 18.0), const Point(11.1, 18.0)]);
  m.polygon([const Point(6.0, 11.1), const Point(18.0, 11.1), const Point(18.0, 12.9), const Point(6.0, 12.9)]);
  for (int i = 0; i < 4; i++) {
    final double a = i * math.pi / 2;
    const Point c = Point(12, 12);
    m.polygon([
      const Point(12, 2.4).rotate(a, c),
      const Point(15.6, 6.4).rotate(a, c),
      const Point(8.4, 6.4).rotate(a, c),
    ]);
  }
}

void _ibeam(Mask m, {bool vertical = false}) {
  void rect(double l, double t, double r, double b) {
    if (vertical) {
      m.roundRect(t, l, b, r, 0.5);
    } else {
      m.roundRect(l, t, r, b, 0.5);
    }
  }

  rect(11.15, 4.5, 12.85, 19.5);
  rect(8.6, 3.2, 15.4, 4.9);
  rect(8.6, 19.1, 15.4, 20.8);
}

void _spinner(Mask m, Point center, double radius, double width, double t) {
  final double start = t * 2 * math.pi - math.pi / 2;
  m.arc(center, radius, start, start + 1.6 * math.pi, width);
}

void _badgePlus(Mask m) {
  m.disc(const Point(17.2, 17.6), 4.4);
}

/// The hands are Adwaita's, as they are (tool/cursors/adwaita, see the
/// README there for their license), with the names they go by.
const Map<String, List<String>> adwaitaCursors = {
  "pointer": [
    "hand2", "hand1", "hand", "pointing_hand",
    "e29285e634086352946a0e7090d73106", "9d800788f1b08800ae810202380a0822",
  ],
  "grab": [
    "openhand", "5aca4d189052212118709018842178c0",
  ],
  "grabbing": [
    "closedhand", "dnd-move", "dnd-none", "208530c400c041818281048008011002",
  ],
};

final List<Cursor> cursors = [
  Cursor("default", const Point(4, 2), (m, t) => _arrow(m), aliases: [
    "left_ptr", "arrow", "top_left_arrow", "left_arrow", "right_ptr",
    "center_ptr", "draft_large", "draft_small",
  ]),
  Cursor("text", const Point(12, 12), (m, t) => _ibeam(m), aliases: ["xterm", "ibeam"]),
  Cursor("vertical-text", const Point(12, 12), (m, t) => _ibeam(m, vertical: true)),
  Cursor("crosshair", const Point(12, 12), (m, t) {
    m.roundRect(3, 11.3, 21, 12.7, 0.4);
    m.roundRect(11.3, 3, 12.7, 21, 0.4);
  }, aliases: ["cross", "tcross", "cross_reverse", "diamond_cross"]),
  Cursor("cell", const Point(12, 12), (m, t) {
    m.roundRect(4, 10, 20, 14, 0.6);
    m.roundRect(10, 4, 14, 20, 0.6);
  }, aliases: ["plus"]),
  Cursor("move", const Point(12, 12), (m, t) => _move(m), aliases: [
    "fleur", "size_all", "all-scroll", "4498f0e0c1937ffe01fd06f973665830",
    "9081237383d90e509aa00f00170e968f",
  ]),
  Cursor("not-allowed", const Point(12, 12), (m, t) {
    m.arc(const Point(12, 12), 7.2, 0, 2 * math.pi, 2.6);
    m.stroke([const Point(7.0, 7.0), const Point(17.0, 17.0)], 2.6);
  }, aliases: [
    "crossed_circle", "forbidden", "no-drop", "dnd-no-drop", "circle",
    "03b6e0fcb3499374a867c041f52298f0",
  ]),
  Cursor("help", const Point(4, 2), (m, t) {
    _arrow(m, 0, 0, 0.82);
    m.arc(const Point(17.6, 13.0), 2.4, -math.pi * 0.95, math.pi * 0.35, 1.6);
    m.stroke([const Point(18.5, 15.1), const Point(17.6, 16.3), const Point(17.6, 17.2)], 1.6);
    m.disc(const Point(17.6, 20.0), 0.95);
  }, aliases: [
    "question_arrow", "whats_this", "left_ptr_help",
    "d9ce0ab605698f320427677b458ad60b", "5c6cd98b3f3ebcb1f9c7f1c204630408",
  ]),
  Cursor("wait", const Point(12, 12), (m, t) {}, accent: (m, t) {
    _spinner(m, const Point(12, 12), 6.6, 2.6, t);
  }, frames: 18, delay: 45, aliases: ["watch"]),
  Cursor("progress", const Point(4, 2), (m, t) => _arrow(m, 0, 0, 0.88), accent: (m, t) {
    _spinner(m, const Point(17.0, 17.2), 3.6, 1.8, t);
  }, frames: 18, delay: 45, aliases: [
    "left_ptr_watch", "half-busy", "08e8e1c95fe2fc01f976f1e063a24ccd",
    "3ecb610c1bf2410f44200f48c40d3599",
  ]),
  Cursor("copy", const Point(4, 2), (m, t) {
    _arrow(m, 0, 0, 0.82);
    _badgePlus(m);
  }, cut: (m) {
    m.roundRect(14.8, 16.9, 19.6, 18.3, 0.3);
    m.roundRect(16.5, 15.2, 17.9, 20.0, 0.3);
  }, aliases: [
    "dnd-copy", "1081e37283d90000800003c07f3ef6bf",
    "6407b0e94181790501fd1e167b474872",
  ]),
  Cursor("alias", const Point(4, 2), (m, t) {
    _arrow(m, 0, 0, 0.82);
    m.arc(const Point(18.5, 19.5), 3.4, math.pi, math.pi * 1.5, 1.5);
    m.polygon([const Point(18.2, 13.8), const Point(21.4, 16.1), const Point(18.2, 18.4)]);
  }, aliases: [
    "link", "dnd-link", "640fb0e74195791501fd1ed57b41487f",
    "3085a0e285430894940527032f8b26df",
  ]),
  Cursor("context-menu", const Point(4, 2), (m, t) {
    _arrow(m, 0, 0, 0.82);
    m.roundRect(14.2, 13.2, 21.4, 21.4, 1.2);
  }),
  Cursor("zoom-in", const Point(10, 10), (m, t) {
    m.arc(const Point(10, 10), 5.6, 0, 2 * math.pi, 2.0);
    m.stroke([const Point(14.2, 14.2), const Point(20.0, 20.0)], 2.8);
    m.stroke([const Point(7.4, 10), const Point(12.6, 10)], 1.6);
    m.stroke([const Point(10, 7.4), const Point(10, 12.6)], 1.6);
  }),
  Cursor("zoom-out", const Point(10, 10), (m, t) {
    m.arc(const Point(10, 10), 5.6, 0, 2 * math.pi, 2.0);
    m.stroke([const Point(14.2, 14.2), const Point(20.0, 20.0)], 2.8);
    m.stroke([const Point(7.4, 10), const Point(12.6, 10)], 1.6);
  }),
  Cursor("ew-resize", const Point(12, 12), (m, t) => _doubleArrow(m, 0), aliases: [
    "col-resize", "e-resize", "w-resize", "sb_h_double_arrow", "h_double_arrow",
    "size_hor", "right_side", "left_side", "split_h",
    "028006030e0e7ebffc7f7070c0600140", "14fef782d02440884392942c11205230",
  ]),
  Cursor("ns-resize", const Point(12, 12), (m, t) => _doubleArrow(m, math.pi / 2), aliases: [
    "row-resize", "n-resize", "s-resize", "sb_v_double_arrow", "v_double_arrow",
    "size_ver", "top_side", "bottom_side", "split_v",
    "00008160000006810000408080010102", "2870a09082c103050810ffdffffe0204",
  ]),
  Cursor("nwse-resize", const Point(12, 12), (m, t) => _doubleArrow(m, math.pi / 4), aliases: [
    "nw-resize", "se-resize", "size_fdiag", "top_left_corner",
    "bottom_right_corner", "fd_double_arrow", "c7088f0f3e6c8088236ef8e1e3e70000",
  ]),
  Cursor("nesw-resize", const Point(12, 12), (m, t) => _doubleArrow(m, -math.pi / 4), aliases: [
    "ne-resize", "sw-resize", "size_bdiag", "top_right_corner",
    "bottom_left_corner", "bd_double_arrow", "fcf1c3c7cd4491d801f1e1c78f100000",
  ]),
];
