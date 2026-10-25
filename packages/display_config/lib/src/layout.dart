// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

/// A monitor's place in the layout, in logical pixels.
class LayoutBox {
  LayoutBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  int x;
  int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;

  bool overlaps(LayoutBox o) =>
      x < o.right && o.x < right && y < o.bottom && o.y < bottom;

  /// Shares a stretch of edge with [o] (a corner alone doesn't count).
  bool touches(LayoutBox o) {
    if (overlaps(o)) return false;
    final bool side = (x == o.right || right == o.x) && y < o.bottom && o.y < bottom;
    final bool end = (y == o.bottom || bottom == o.y) && x < o.right && o.x < right;
    return side || end;
  }

  @override
  String toString() => "${width}x$height+$x+$y";
}

/// A monitor's size in the layout: its mode divided by its scale (truncated,
/// as wlroots does), turned when it's rotated a quarter turn.
(int, int) logicalSize(int width, int height, double scale, int transform) {
  final double s = scale > 0 ? scale : 1;
  final int w = (width / s).floor();
  final int h = (height / s).floor();
  return transform.isOdd ? (h, w) : (w, h);
}

/// Moves [boxes] so that none overlaps another and they hang together (each
/// shares an edge with another), keeping the arrangement as close to the
/// given one as it can; then moves the whole so its top left is at 0, 0, as
/// GNOME keeps it.
///
/// Boxes are placed one by one, the one nearest the layout's top left first
/// (or every other box before [moved], the one being dragged): a box that
/// overlaps or floats apart goes to the nearest place along an edge of one
/// placed before it. Within [snap] logical pixels of lining up with that
/// box's edge (or centre), it lines up.
///
/// Boxes exactly on an earlier one (same position and size) are mirrors of
/// it and stay there.
void settle(List<LayoutBox> boxes, {LayoutBox? moved, int snap = 0}) {
  if (boxes.isEmpty) return;
  final int minX = boxes.map((b) => b.x).reduce(math.min);
  final int minY = boxes.map((b) => b.y).reduce(math.min);
  int distance(LayoutBox b) => (b.x - minX) + (b.y - minY);
  final List<LayoutBox> order = [
    for (final LayoutBox b in boxes)
      if (b != moved) b,
  ]..sort((a, b) {
      final int d = distance(a) - distance(b);
      return d != 0 ? d : a.x - b.x;
    });
  if (moved != null && boxes.contains(moved)) order.add(moved);

  final List<LayoutBox> placed = [];
  for (final LayoutBox box in order) {
    if (placed.isEmpty) {
      placed.add(box);
      continue;
    }
    final bool mirrored = placed.any((p) =>
        p.x == box.x &&
        p.y == box.y &&
        p.width == box.width &&
        p.height == box.height);
    if (mirrored && box != moved) continue;
    final bool fits = placed.every((p) => !box.overlaps(p)) &&
        placed.any((p) => box.touches(p));
    if (!fits || (box == moved && snap > 0)) _place(box, placed, snap);
    placed.add(box);
  }

  final int left = boxes.map((b) => b.x).reduce(math.min);
  final int top = boxes.map((b) => b.y).reduce(math.min);
  for (final LayoutBox b in boxes) {
    b.x -= left;
    b.y -= top;
  }
}

/// Puts [box] at the free spot along the edge of a [placed] box nearest to
/// where it is.
void _place(LayoutBox box, List<LayoutBox> placed, int snap) {
  final int wantX = box.x;
  final int wantY = box.y;
  int? bestX;
  int? bestY;
  int bestDistance = 0;

  // Lines up with [p] along the edge's direction when close enough.
  int align(int want, int start, int end, int size) {
    if (snap <= 0) return want;
    for (final int target in [start, end - size, start + (end - start - size) ~/ 2]) {
      if ((want - target).abs() <= snap) return target;
    }
    return want;
  }

  void consider(int x, int y) {
    final LayoutBox at = LayoutBox(x: x, y: y, width: box.width, height: box.height);
    if (placed.any(at.overlaps)) return;
    final int dx = x - wantX;
    final int dy = y - wantY;
    final int d = dx * dx + dy * dy;
    if (bestX == null || d < bestDistance) {
      bestX = x;
      bestY = y;
      bestDistance = d;
    }
  }

  for (final LayoutBox p in placed) {
    // Beside p: overlapping it by at least one pixel along the edge.
    final int y = align(wantY, p.y, p.bottom, box.height)
        .clamp(p.y - box.height + 1, p.bottom - 1);
    consider(p.right, y);
    consider(p.x - box.width, y);
    // Above or below p.
    final int x = align(wantX, p.x, p.right, box.width)
        .clamp(p.x - box.width + 1, p.right - 1);
    consider(x, p.bottom);
    consider(x, p.y - box.height);
  }
  // Right of everything is always free.
  if (bestX == null) {
    final LayoutBox last = placed.reduce((a, b) => a.right >= b.right ? a : b);
    bestX = last.right;
    bestY = last.y;
  }
  box
    ..x = bestX!
    ..y = bestY!;
}
