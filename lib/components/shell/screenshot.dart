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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/notifications.dart';
import 'package:pangolin/services/screencopy.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:path/path.dart' as p;
import 'package:zenit_ui/zenit_ui.dart';

/// Opens the screenshot tool.
abstract final class ScreenshotTool {
  static void open() {
    ShellService.current.dismissEverything();
    ShellService.current.showOverlay(ScreenshotOverlay.overlayId);
  }

  /// Captures the whole screen right away (Shift+Print).
  static Future<void> captureScreen() => _ScreenshotSaver.capture(null);
}

enum _Mode { area, window, screen }

/// The screenshot tool: pick an area, a window or the whole screen.
class ScreenshotOverlay extends ShellOverlay {
  static const String overlayId = "screenshot";

  ScreenshotOverlay({super.key}) : super(id: overlayId);

  @override
  ShellOverlayState<ScreenshotOverlay> createState() => _ScreenshotState();
}

class _ScreenshotState extends ShellOverlayState<ScreenshotOverlay> {
  final FocusNode _focus = FocusNode(debugLabel: "screenshot");
  _Mode _mode = _Mode.area;
  Offset? _dragStart;
  Rect? _selection;
  ShellWindow? _hovered;
  bool _capturing = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  FutureOr<void> requestShow(Map<String, dynamic> args) {
    _mode = _Mode.area;
    _selection = null;
    _hovered = null;
    _capturing = false;
    controller.showing = true;
    animationController.forward();
    _focus.requestFocus();
  }

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) {
    controller.showing = false;
    animationController.reverse();
  }

  void _close() =>
      ShellService.current.dismissOverlay(ScreenshotOverlay.overlayId);

  /// Windows of the current desk, topmost first, with their rects.
  List<(ShellWindow, Rect)> _windows() {
    final WindowManagerService wm = WindowManagerService.current;
    final int desk = wm.desks.value.current;
    return [
      for (final ShellWindow w in wm.windows.reversed)
        if (!w.minimized && wm.deskOf(w) == desk)
          if (wm.windowRect(w) case final Rect rect) (w, rect),
    ];
  }

  ShellWindow? _windowAt(Offset position) {
    for (final (ShellWindow w, Rect rect) in _windows()) {
      if (rect.contains(position)) return w;
    }
    return null;
  }

  Future<void> _capture() async {
    if (_capturing) return;
    final Size screen = MediaQuery.sizeOf(context);
    Rect? region;
    switch (_mode) {
      case _Mode.area:
        final Rect? selection = _selection;
        if (selection == null || selection.width < 2 || selection.height < 2) {
          return;
        }
        region = selection;
      case _Mode.window:
        final ShellWindow? window = _hovered;
        if (window == null) return;
        // On top of the others for the capture.
        window.activate();
        region = WindowManagerService.current.windowRect(window);
      case _Mode.screen:
        region = null;
    }
    region = region?.intersect(Offset.zero & screen);
    setState(() => _capturing = true);
    // The tool must be gone from the screen before capturing it.
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _close();
    await _ScreenshotSaver.capture(
      region,
      // Windows have rounded corners: keep what's around them out.
      cornerRadius: _mode == _Mode.window ? 12 : 0,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      unawaited(_capture());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (shouldHide || _capturing) return const SizedBox();
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.secondary;

    return Positioned.fill(
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: FadeTransition(
          opacity: animation,
          child: Stack(
            children: [
              Positioned.fill(
                child: MouseRegion(
                  cursor: _mode == _Mode.area
                      ? SystemMouseCursors.precise
                      : SystemMouseCursors.click,
                  onHover: (event) {
                    if (_mode != _Mode.window) return;
                    final ShellWindow? window = _windowAt(event.localPosition);
                    if (window != _hovered) setState(() => _hovered = window);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // From where the button went down, not from where the
                    // drag was recognized (past the touch slop).
                    onPanDown: _mode == _Mode.area
                        ? (d) => _dragStart = d.localPosition
                        : null,
                    onPanStart: _mode == _Mode.area
                        ? (d) => setState(() {
                              _selection = Rect.fromPoints(
                                _dragStart ?? d.localPosition,
                                d.localPosition,
                              );
                            })
                        : null,
                    onPanUpdate: _mode == _Mode.area
                        ? (d) => setState(() {
                              _selection = Rect.fromPoints(
                                _dragStart!,
                                d.localPosition,
                              );
                            })
                        : null,
                    onTapUp: (d) {
                      switch (_mode) {
                        case _Mode.area:
                          break;
                        case _Mode.window:
                          _hovered = _windowAt(d.localPosition);
                          unawaited(_capture());
                        case _Mode.screen:
                          unawaited(_capture());
                      }
                    },
                    child: CustomPaint(
                      painter: _ShadePainter(
                        hole: switch (_mode) {
                          _Mode.area => _selection,
                          _Mode.window => _hovered == null
                              ? null
                              : WindowManagerService.current
                                  .windowRect(_hovered!),
                          _Mode.screen => Offset.zero & MediaQuery.sizeOf(context),
                        },
                        accent: accent,
                      ),
                    ),
                  ),
                ),
              ),
              if (_mode == _Mode.area && _selection != null)
                Positioned.fromRect(
                  rect: _selection!,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _SizeChip(size: _selection!.size),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: WindowManagerService.current.controller.wmInsets.bottom +
                    24,
                child: Center(
                  child: _Toolbar(
                    mode: _mode,
                    canCapture: switch (_mode) {
                      _Mode.area => _selection != null &&
                          _selection!.width >= 2 &&
                          _selection!.height >= 2,
                      _Mode.window => _hovered != null,
                      _Mode.screen => true,
                    },
                    onMode: (mode) => setState(() {
                      _mode = mode;
                      _hovered = null;
                    }),
                    onCapture: () => unawaited(_capture()),
                    onClose: _close,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Darkens the screen except [hole], which takes a light accent tint.
class _ShadePainter extends CustomPainter {
  const _ShadePainter({required this.hole, required this.accent});

  final Rect? hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect? hole = this.hole;
    final Path shade = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      shade
        ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(6)))
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(shade, Paint()..color = const Color(0x66000000));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole, const Radius.circular(6)),
        Paint()..color = accent.withValues(alpha: 0.12),
      );
      // Corner handles.
      final Paint handle = Paint()..color = Colors.white;
      for (final Offset corner in [
        hole.topLeft,
        hole.topRight,
        hole.bottomLeft,
        hole.bottomRight,
      ]) {
        canvas.drawCircle(corner, 5, handle);
      }
    }
  }

  @override
  bool shouldRepaint(_ShadePainter old) =>
      old.hole != hole || old.accent != accent;
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    return DecoratedBox(
      decoration: const ShapeDecoration(
        shape: StadiumBorder(),
        color: Color(0xB3000000),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          "${(size.width * ratio).round()} × ${(size.height * ratio).round()}",
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.mode,
    required this.canCapture,
    required this.onMode,
    required this.onCapture,
    required this.onClose,
  });

  final _Mode mode;
  final bool canCapture;
  final ValueChanged<_Mode> onMode;
  final VoidCallback onCapture;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    Widget modeButton(_Mode value, IconData icon, String label) {
      final bool selected = value == mode;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? colors.secondary : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onMode(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.onSecondary : colors.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? colors.onSecondary : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SurfaceLayer(
      shape: const StadiumBorder(),
      dropShadow: true,
      padding: const EdgeInsets.all(6),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            modeButton(_Mode.area, Icons.crop_free_rounded, "Area"),
            modeButton(_Mode.window, Icons.web_asset_rounded, "Window"),
            modeButton(_Mode.screen, Icons.fullscreen_rounded, "Screen"),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 44,
              child: Material(
                color: canCapture
                    ? colors.secondary
                    : colors.secondary.withValues(alpha: 0.4),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: canCapture ? onCapture : null,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: colors.onSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: "Close",
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Captures, saves to ~/Pictures/Screenshots, copies to the clipboard and
/// tells the user.
abstract final class _ScreenshotSaver {
  static final Logger _logger = Logger("Screenshot");

  static Future<void> capture(Rect? region, {double cornerRadius = 0}) async {
    ui.Image? image = await Screencopy.capture(region: region);
    if (image == null) {
      _notify("Screenshot failed", "The screen couldn't be captured.");
      return;
    }
    if (cornerRadius > 0 && region != null && region.width > 0) {
      image = await _roundCorners(image, cornerRadius * image.width / region.width);
    }
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return;
    final Uint8List bytes = png.buffer.asUint8List();

    final Directory dir = Directory(p.join(_picturesDir(), "Screenshots"));
    await dir.create(recursive: true);
    final String stamp = DateTime.now()
        .toIso8601String()
        .split(".")
        .first
        .replaceAll(":", "-")
        .replaceAll("T", "_");
    final File file = File(p.join(dir.path, "Screenshot_$stamp.png"));
    await file.writeAsBytes(bytes);

    final bool copied = await _copyToClipboard(bytes);
    _notify(
      "Screenshot saved",
      copied ? "${file.path}\nAlso copied to the clipboard." : file.path,
    );
  }

  static Future<ui.Image> _roundCorners(ui.Image image, double radius) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Rect bounds =
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    Canvas(recorder)
      ..clipRRect(RRect.fromRectAndRadius(bounds, Radius.circular(radius)))
      ..drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    final ui.Image rounded =
        await recorder.endRecording().toImage(image.width, image.height);
    image.dispose();
    return rounded;
  }

  static String _picturesDir() {
    final String home = Platform.environment["HOME"] ?? Directory.current.path;
    try {
      final File dirs = File(p.join(home, ".config", "user-dirs.dirs"));
      for (final String line in dirs.readAsLinesSync()) {
        if (!line.startsWith("XDG_PICTURES_DIR=")) continue;
        final String value = line
            .substring("XDG_PICTURES_DIR=".length)
            .replaceAll('"', "")
            .replaceAll(r"$HOME", home);
        if (value.isNotEmpty) return value;
      }
    } on FileSystemException {
      // Default below.
    }
    return p.join(home, "Pictures");
  }

  /// Through wl-copy (wl-clipboard), when installed.
  static Future<bool> _copyToClipboard(Uint8List png) async {
    try {
      final Process process =
          await Process.start("wl-copy", ["--type", "image/png"]);
      process.stdin.add(png);
      await process.stdin.close();
      return await process.exitCode.timeout(
            const Duration(seconds: 3),
            onTimeout: () => 0,
          ) ==
          0;
    } on ProcessException {
      return false;
    }
  }

  static void _notify(String summary, String body) {
    try {
      NotificationService.current.pushNotification(
        ShellNotification(appName: "Screenshot", summary: summary, body: body),
      );
    } on Object catch (e) {
      _logger.info("$summary: $body ($e)");
    }
  }
}
