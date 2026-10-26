import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/wm/output_follow.dart';

// Where windows go when outputs change (roadmap 2.8).
void main() {
  const Rect laptop = Rect.fromLTWH(0, 0, 1920, 1080);
  const Rect monitor = Rect.fromLTWH(1920, 0, 2560, 1440);
  // The monitor at 150%: smaller in logical pixels.
  const Rect monitorScaled = Rect.fromLTWH(1920, 0, 2560 / 1.5, 1440 / 1.5);

  test("a window stays on the output it overlaps most, else the nearest", () {
    expect(OutputFollow.homeOf(const Rect.fromLTWH(1800, 100, 400, 300), [laptop, monitor]), 1);
    expect(OutputFollow.homeOf(const Rect.fromLTWH(1700, 100, 400, 300), [laptop, monitor]), 0);
    // Off every output, below the monitor.
    expect(OutputFollow.homeOf(const Rect.fromLTWH(3000, 2000, 400, 300), [laptop, monitor]), 1);
    expect(OutputFollow.homeOf(const Rect.fromLTWH(0, 0, 10, 10), []), isNull);
  });

  test("a new scale keeps the window at the same place on its output", () {
    const Rect window = Rect.fromLTWH(2500, 200, 600, 400);
    final Rect moved = OutputFollow.follow(window, monitor, monitorScaled, monitorScaled);
    expect(moved.left, closeTo(1920 + 580 / 2560 * monitorScaled.width, 0.01));
    expect(moved.top, closeTo(200 / 1440 * monitorScaled.height, 0.01));
    expect(moved.size, window.size);
  });

  test("a window that would hang off its smaller output is pulled back", () {
    const Rect window = Rect.fromLTWH(4000, 900, 600, 400);
    final Rect moved = OutputFollow.follow(window, monitor, monitorScaled, monitorScaled);
    expect(moved.right, monitorScaled.right);
    expect(moved.bottom, monitorScaled.bottom);
  });

  test("windows of an unplugged output go to the one taking them", () {
    const Rect window = Rect.fromLTWH(2500, 200, 600, 400);
    // The laptop's work area keeps 48 px for the taskbar.
    final Rect area = laptop.copyWith(height: 1080 - 48);
    final Rect moved = OutputFollow.follow(window, monitor, laptop, area);
    expect(laptop.contains(moved.topLeft) && laptop.contains(moved.bottomRight - const Offset(1, 1)), isTrue);
    expect(moved.left, closeTo(580 / 2560 * 1920, 0.01));
    expect(moved.top, closeTo(200 / 1440 * 1080, 0.01));
  });

  test("the title bar stays reachable; a window too large goes to the corner", () {
    const Rect area = Rect.fromLTWH(0, 0, 1000, 800);
    expect(OutputFollow.fit(const Rect.fromLTWH(100, -50, 300, 200), area, topInset: 30).top, 30);
    final Rect large = OutputFollow.fit(const Rect.fromLTWH(300, 300, 1200, 900), area, topInset: 30);
    expect(large.topLeft, const Offset(0, 30));
  });
}

extension on Rect {
  Rect copyWith({double? height}) => Rect.fromLTWH(left, top, width, height ?? this.height);
}
