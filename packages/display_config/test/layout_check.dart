// Self-check of the layout settling (no overlaps, no gaps):
//   dart run test/layout_check.dart

import 'package:display_config/display_config.dart';

void check(bool ok, String what) {
  if (!ok) throw StateError("failed: $what");
}

LayoutBox box(int x, int y, int w, int h) =>
    LayoutBox(x: x, y: y, width: w, height: h);

void valid(List<LayoutBox> boxes, String what) {
  for (int i = 0; i < boxes.length; i++) {
    for (int j = i + 1; j < boxes.length; j++) {
      check(!boxes[i].overlaps(boxes[j]), "$what: ${boxes[i]} overlaps ${boxes[j]}");
    }
    if (boxes.length > 1) {
      check(boxes.any((o) => o != boxes[i] && o.touches(boxes[i])),
          "$what: ${boxes[i]} touches nothing");
    }
  }
  check(boxes.map((b) => b.x).reduce((a, b) => a < b ? a : b) == 0, "$what: left at 0");
  check(boxes.map((b) => b.y).reduce((a, b) => a < b ? a : b) == 0, "$what: top at 0");
}

void main() {
  // wlroots truncates: 2560x1600 at 1.5 is 1706x1066.
  check(logicalSize(2560, 1600, 1.5, 0) == (1706, 1066), "logical size");
  check(logicalSize(3840, 2160, 1.5, 1) == (1440, 2560), "rotated size");

  // The report: a 4K monitor at 1.5 and the panel below it, overlapping it.
  final LayoutBox dp = box(0, 0, 2560, 1440);
  final LayoutBox edp = box(0, 1018, 2276, 1422);
  final List<LayoutBox> report = [dp, edp];
  settle(report);
  valid(report, "overlap");
  check(dp.x == 0 && dp.y == 0, "4K stays: $dp");
  check(edp.y == 1440 && edp.x == 0, "panel moves below, not aside: $edp");

  // A gap (a physical-pixel monitors.xml divided by the panel's own scale).
  final LayoutBox a = box(0, 0, 2560, 1440);
  final LayoutBox b = box(3072, 0, 1706, 1066);
  final List<LayoutBox> gap = [a, b];
  settle(gap);
  valid(gap, "gap");
  check(b.x == 2560 && b.y == 0, "gap closed: $b");

  // Mirrors stay on each other.
  final List<LayoutBox> mirror = [box(0, 0, 1920, 1080), box(0, 0, 1920, 1080)];
  settle(mirror);
  check(mirror[0].x == mirror[1].x && mirror[0].y == mirror[1].y, "mirror kept");

  // Same origin, different sizes: not a mirror.
  final List<LayoutBox> origin = [box(0, 0, 2560, 1440), box(0, 0, 1706, 1066)];
  settle(origin);
  valid(origin, "same origin");

  // Negative positions move to 0, 0.
  final List<LayoutBox> shifted = [box(-500, 200, 1920, 1080), box(1420, 200, 1920, 1080)];
  settle(shifted);
  valid(shifted, "shifted");
  check(shifted[0].x == 0 && shifted[1].x == 1920, "shifted kept apart: $shifted");

  // A display dropped left of the other, a little low: snaps beside it and
  // lines up with its top within the snap distance.
  final LayoutBox fixed = box(0, 0, 2560, 1440);
  final LayoutBox dragged = box(-1800, 90, 1706, 1066);
  final List<LayoutBox> drop = [fixed, dragged];
  settle(drop, moved: dragged, snap: 120);
  valid(drop, "drop");
  check(dragged.x == 0 && fixed.x == 1706, "dropped to the left: $drop");
  check(dragged.y == fixed.y, "tops lined up: $drop");

  // Dropped onto the other display: pushed out to the nearest edge.
  final LayoutBox onto = box(1000, 300, 1706, 1066);
  final List<LayoutBox> pile = [box(0, 0, 2560, 1440), onto];
  settle(pile, moved: onto, snap: 0);
  valid(pile, "dropped onto");

  // Three in a row, the middle one removed: the third closes up.
  final List<LayoutBox> row = [box(0, 0, 1920, 1080), box(3840, 0, 1920, 1080)];
  settle(row);
  valid(row, "row");
  check(row[1].x == 1920, "row closed up: $row");

  // A layout that's already fine is left alone.
  final List<LayoutBox> fine = [box(0, 0, 2560, 1440), box(2560, 374, 1706, 1066)];
  settle(fine);
  check(fine[1].x == 2560 && fine[1].y == 374, "fine layout kept: $fine");

  print("layout: all checks passed");
}
