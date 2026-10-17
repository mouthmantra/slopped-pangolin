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

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/services/wm/mirrors.dart';

/// Timing of the overview, shared by the shell surface (its own UI), the
/// desktop surface (backdrop) and river (the windows), so they move together.
abstract final class OverviewTiming {
  /// PANGOLIN_ANIMATION_SCALE slows the overview down (e.g. 10), like
  /// popups, to look at it closely.
  static final double _scale = (double.tryParse(
            Platform.environment["PANGOLIN_ANIMATION_SCALE"] ?? "",
          ) ??
          1)
      .clamp(0.1, 50.0);

  static final Duration open = const Duration(milliseconds: 320) * _scale;
  static final Duration close = const Duration(milliseconds: 260) * _scale;
  static final Duration relayout = const Duration(milliseconds: 260) * _scale;
  static const Cubic curve = MirrorCurves.overview;
}

/// Moves the overview with a touchpad swipe.
abstract interface class OverviewGestureHandler {
  /// Starts following a swipe from where the overview is (open or closed).
  /// False when the overview can't follow one.
  bool beginGesture();

  /// [offset] is the distance swiped since [beginGesture], 1 being the whole
  /// way from closed to open (negative: towards closed).
  void updateGesture(double offset);

  /// Opens or closes the overview, whichever the swipe went towards.
  void endGesture(double velocity, {required bool cancelled});
}

/// State shared by the overview on the shell surface and its backdrop on the
/// desktop surface: they are separate Flutter views of the same engine.
class OverviewModel extends ChangeNotifier {
  OverviewModel._();

  static final OverviewModel instance = OverviewModel._();

  /// 0 when closed, 1 when open (already curved).
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// How far open the desktop surface draws the overview: [progress] while
  /// following a swipe, the end state while river animates it there.
  final ValueNotifier<double> backdrop = ValueNotifier(0);

  /// Desk thumbnail hovered (or targeted while dragging a window).
  final ValueNotifier<int?> hoveredDesk = ValueNotifier(null);

  /// The overview overlay, which follows swipes.
  OverviewGestureHandler? gestureHandler;

  OverviewLayout? _layout;
  OverviewLayout? get layout => _layout;
  set layout(OverviewLayout? value) {
    if (value == _layout) return;
    _layout = value;
    notifyListeners();
  }
}

/// Where the overview shows desks and windows, in shell surface coordinates.
@immutable
class OverviewLayout {
  const OverviewLayout({
    required this.screen,
    required this.desks,
    required this.currentDesk,
    required this.addDesk,
    required this.labelHeight,
    required this.stripHeight,
    required this.windows,
    required this.thumbnails,
  });

  static const double _margin = 24;
  static const double _deskGap = 16;
  static const double _top = 16;
  static const double _bottom = 10;
  static const double _windowSpacing = 40;

  /// The "New desktop" button.
  static const Size addDeskSize = Size(172, 48);

  static const BorderRadius deskRadius = BorderRadius.all(Radius.circular(10));

  final Size screen;

  /// Desk thumbnails (without their label).
  final List<Rect> desks;
  final int currentDesk;

  /// "New desktop" button, null when no more desks can be added.
  final Rect? addDesk;
  final double labelHeight;

  /// Height of the bar along the top holding the desks, which slides down
  /// from above the screen as the overview opens.
  final double stripHeight;

  /// Windows of the current desk.
  final List<(ShellWindow, Rect)> windows;

  /// Small copies of the windows in the desk thumbnails.
  final List<(ShellWindow, Rect)> thumbnails;

  Offset stripOffset(double progress) =>
      Offset(0, -(1 - progress) * stripHeight);

  List<OverviewSlot> get slots => [
        for (final (ShellWindow w, Rect rect) in thumbnails)
          OverviewSlot(
            w,
            rect,
            thumbnail: true,
            hiddenRect: rect.shift(stripOffset(0)),
          ),
        for (final (ShellWindow w, Rect rect) in windows) OverviewSlot(w, rect),
      ];

  static OverviewLayout compute({
    required Size screen,
    required double bottomInset,
    required WindowManagerService wm,
    required bool canAddDesk,
  }) {
    final DeskState desks = wm.desks.value;
    final double aspect =
        screen.height > 0 ? screen.width / screen.height : 16 / 9;
    const double labelHeight = 30;

    // Desk strip: the desks from the left, as large as fits next to the
    // "New desktop" button on the right.
    final double addSpace = canAddDesk ? addDeskSize.width + _margin : 0;
    final double fixed = (desks.count - 1) * _deskGap + addSpace;
    final double maxWidth = math.max(0, screen.width - 2 * _margin);
    double thumbHeight = (screen.height * 0.11).clamp(56.0, 120.0);
    if (desks.count * thumbHeight * aspect + fixed > maxWidth) {
      thumbHeight = math.max(24, (maxWidth - fixed) / (desks.count * aspect));
    }
    final double thumbWidth = thumbHeight * aspect;
    final List<Rect> deskRects = [
      for (int d = 0; d < desks.count; d++)
        Rect.fromLTWH(
          _margin + d * (thumbWidth + _deskGap),
          _top,
          thumbWidth,
          thumbHeight,
        ),
    ];
    final double stripHeight = _top + thumbHeight + labelHeight + _bottom;
    final Rect? addRect = canAddDesk
        ? Rect.fromLTWH(
            screen.width - _margin - addDeskSize.width,
            ((stripHeight - addDeskSize.height) / 2).roundToDouble(),
            addDeskSize.width,
            addDeskSize.height,
          )
        : null;

    // Windows of the current desk, left to right as they are on screen.
    final List<(ShellWindow, Rect)> current = [
      for (final ShellWindow w in wm.windows)
        if (wm.deskOf(w) == desks.current)
          if (wm.windowRect(w) case final Rect rect) (w, rect),
    ]..sort((a, b) => a.$2.center.dx.compareTo(b.$2.center.dx));

    final Rect area = Rect.fromLTRB(
      _margin * 3,
      stripHeight + 48,
      screen.width - _margin * 3,
      // Room for the app icon below the last row.
      screen.height - bottomInset - _margin - 32,
    );
    final List<Rect> slots =
        _grid([for (final (_, r) in current) r.size], area);

    final double scale = screen.width > 0 ? thumbWidth / screen.width : 0;
    final List<(ShellWindow, Rect)> thumbnails = [
      for (final ShellWindow w in wm.windows)
        if (!w.minimized && wm.deskOf(w) < deskRects.length)
          if (wm.windowRect(w) case final Rect rect)
            (
              w,
              Rect.fromLTWH(
                deskRects[wm.deskOf(w)].left + rect.left * scale,
                deskRects[wm.deskOf(w)].top + rect.top * scale,
                rect.width * scale,
                rect.height * scale,
              ),
            ),
    ];

    return OverviewLayout(
      screen: screen,
      desks: deskRects,
      currentDesk: desks.current,
      addDesk: addRect,
      labelHeight: labelHeight,
      stripHeight: stripHeight,
      windows: [
        for (int i = 0; i < current.length; i++) (current[i].$1, slots[i]),
      ],
      thumbnails: thumbnails,
    );
  }

  /// Lays [sizes] out in rows inside [area], as large as possible without
  /// growing any window, each row centered.
  static List<Rect> _grid(List<Size> sizes, Rect area) {
    final int n = sizes.length;
    if (n == 0 || area.width <= 0 || area.height <= 0) return const [];

    double scaleFor(Size size, double cellWidth, double cellHeight) => math.min(
          1,
          math.min(cellWidth / size.width, cellHeight / size.height),
        );

    int bestRows = 1;
    double bestCoverage = -1;
    for (int rows = 1; rows <= n; rows++) {
      final int columns = (n / rows).ceil();
      if ((rows - 1) * columns >= n) continue;
      final double cellWidth =
          (area.width - (columns - 1) * _windowSpacing) / columns;
      final double cellHeight =
          (area.height - (rows - 1) * _windowSpacing) / rows;
      if (cellWidth <= 0 || cellHeight <= 0) continue;
      double coverage = 0;
      for (final Size size in sizes) {
        final double k = scaleFor(size, cellWidth, cellHeight);
        coverage += size.width * k * size.height * k;
      }
      if (coverage > bestCoverage * 1.0001) {
        bestCoverage = coverage;
        bestRows = rows;
      }
    }

    final int columns = (n / bestRows).ceil();
    final double cellWidth =
        (area.width - (columns - 1) * _windowSpacing) / columns;
    final double cellHeight =
        (area.height - (bestRows - 1) * _windowSpacing) / bestRows;

    final List<List<Size>> rows = [
      for (int r = 0; r < bestRows; r++)
        [
          for (int i = r * columns; i < math.min(n, (r + 1) * columns); i++)
            sizes[i] * scaleFor(sizes[i], cellWidth, cellHeight),
        ],
    ];
    final List<double> rowHeights = [
      for (final List<Size> row in rows)
        row.fold<double>(0, (h, s) => math.max(h, s.height)),
    ];
    final double totalHeight = rowHeights.fold<double>(0, (a, b) => a + b) +
        (bestRows - 1) * _windowSpacing;

    final List<Rect> result = [];
    double y = area.center.dy - totalHeight / 2;
    for (int r = 0; r < rows.length; r++) {
      final List<Size> row = rows[r];
      final double rowWidth = row.fold<double>(0, (w, s) => w + s.width) +
          (row.length - 1) * _windowSpacing;
      double x = area.center.dx - rowWidth / 2;
      for (final Size size in row) {
        result.add(
          Rect.fromLTWH(
            x.roundToDouble(),
            (y + (rowHeights[r] - size.height) / 2).roundToDouble(),
            size.width.roundToDouble(),
            size.height.roundToDouble(),
          ),
        );
        x += size.width + _windowSpacing;
      }
      y += rowHeights[r] + _windowSpacing;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is OverviewLayout &&
      other.screen == screen &&
      other.currentDesk == currentDesk &&
      other.addDesk == addDesk &&
      other.stripHeight == stripHeight &&
      listEquals(other.desks, desks) &&
      listEquals(other.windows, windows) &&
      listEquals(other.thumbnails, thumbnails);

  @override
  int get hashCode => Object.hash(
        screen,
        currentDesk,
        addDesk,
        Object.hashAll(desks),
        Object.hashAll(windows),
        Object.hashAll(thumbnails),
      );
}
