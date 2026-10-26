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

import 'dart:math' as math;
import 'dart:ui';

/// Where windows go when outputs change: a new scale or position from
/// Settings > Displays, an output unplugged. Windows have positions in
/// river's layout, which outputs move around in; each window follows the
/// output it was on instead of staying at its old layout position, which
/// may now be on another output or on none.
abstract final class OutputFollow {
  /// Index of the output among [outputs] that [window] was on: the one it
  /// overlaps most, else the nearest; null without outputs.
  static int? homeOf(Rect window, List<Rect> outputs) {
    int? best;
    double bestArea = 0;
    for (int i = 0; i < outputs.length; i++) {
      final Rect overlap = window.intersect(outputs[i]);
      if (overlap.width <= 0 || overlap.height <= 0) continue;
      final double area = overlap.width * overlap.height;
      if (area > bestArea) {
        bestArea = area;
        best = i;
      }
    }
    return best ?? nearest(window.center, outputs);
  }

  /// Index of the output among [outputs] nearest to [point]; null without
  /// outputs.
  static int? nearest(Offset point, List<Rect> outputs) {
    int? best;
    double bestDistance = double.infinity;
    for (int i = 0; i < outputs.length; i++) {
      final Rect o = outputs[i];
      final double dx = point.dx.clamp(o.left, o.right) - point.dx;
      final double dy = point.dy.clamp(o.top, o.bottom) - point.dy;
      final double distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// [window] moved from its output as it was ([from]) to that output now
  /// or the one taking its windows ([to]): at the same place relative to it
  /// (scaled with it), its size kept, then inside [area] (that output's work
  /// area) with its top reachable, [topInset] being a title bar drawn above
  /// the content. A window larger than [area] goes to its top left corner.
  static Rect follow(
    Rect window,
    Rect from,
    Rect to,
    Rect area, {
    double topInset = 0,
  }) {
    double relative(double value, double start, double length) =>
        length > 0 ? (value - start) / length : 0;
    final double x =
        to.left + relative(window.left, from.left, from.width) * to.width;
    final double y =
        to.top + relative(window.top, from.top, from.height) * to.height;
    return fit(Rect.fromLTWH(x, y, window.width, window.height), area,
        topInset: topInset);
  }

  /// [window] moved the least to be inside [area], its top [topInset]
  /// below the top of [area].
  static Rect fit(Rect window, Rect area, {double topInset = 0}) {
    final double top = area.top + topInset;
    final double x = window.left
        .clamp(area.left, math.max(area.left, area.right - window.width));
    final double y =
        window.top.clamp(top, math.max(top, area.bottom - window.height));
    return Rect.fromLTWH(x, y, window.width, window.height);
  }
}
