/*
Copyright 2021 The dahliaOS Authors

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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pangolin/components/overlays/overview/backdrop.dart';
import 'package:pangolin/components/overlays/overview/layout.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/shell_area.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/widgets/window_icon.dart';

/// The overview: the desks along the top next to a "New desktop" button, the
/// windows of the current desk spread out below.
///
/// In a river session the windows themselves are drawn by river (mirrors that
/// river animates from where the windows are), the bar, the window area and
/// the desk thumbnails by the desktop surface below them ([OverviewBackdrop]).
/// This overlay only draws what goes on top (labels, buttons) and handles
/// input. A touchpad swipe moves it with the fingers ([OverviewModel]).
class OverviewOverlay extends ShellOverlay {
  static const String overlayId = "overview";

  OverviewOverlay({super.key}) : super(id: overlayId);

  @override
  ShellOverlayState<OverviewOverlay> createState() => _OverviewOverlayState();
}

class _OverviewOverlayState extends ShellOverlayState<OverviewOverlay>
    implements OverviewGestureHandler {
  final FocusNode _focusNode = FocusNode(debugLabel: "overview");

  WindowManagerService get _wm => WindowManagerService.current;
  OverviewModel get _model => OverviewModel.instance;

  /// Progress when the current gesture started.
  double? _gestureStart;

  /// Labels, icons and buttons fade in once the overview has opened. Until
  /// then this surface stays as it is while the desktop surface below
  /// animates: two full screen surfaces changing in the same frames halve
  /// the frame rate.
  late final AnimationController _details = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  /// river animates the desktop surface's part of the overview (which then
  /// only draws where it's going) rather than the surface redrawing the
  /// whole screen on every frame.
  bool _riverBackdrop = false;
  int _backdropGeneration = 0;

  /// Fades the details in once river is done opening the overview (ends
  /// [ShellSurfaceArea.quiet] once it's done closing it).
  Timer? _detailsTimer;

  @override
  void initState() {
    super.initState();
    animationController.addListener(_onProgress);
    animationController.addStatusListener(_onStatus);
    _wm.addListener(_relayout);
    _wm.desks.addListener(_relayout);
    _model.gestureHandler = this;
  }

  @override
  void dispose() {
    if (_model.gestureHandler == this) _model.gestureHandler = null;
    _wm.removeListener(_relayout);
    _wm.desks.removeListener(_relayout);
    animationController.removeListener(_onProgress);
    _detailsTimer?.cancel();
    _details.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // The controller runs linearly between 0 and 1: animations apply the curve
  // themselves (animateTo), so a gesture can take over at any point and hand
  // back without a jump.
  void _onProgress() {
    _model.progress.value = animationController.value;
    // Tinted, the window area and the strip follow gestures as tints.
    if (!_riverBackdrop && !_tinted) {
      _model.backdrop.value = animationController.value;
    }
  }

  bool get _canAnimateBackdrop =>
      _wm.supportsOverview &&
      PangolinSession.partAnimations.value &&
      PangolinSession.desktopViewId != null;

  /// river tints the window area of the desktop surface and the desk bar
  /// fades in on it: the desktop surface doesn't draw the window area at all
  /// (river-blur-v1 version 4).
  bool get _tinted => _canAnimateBackdrop && PangolinSession.tints.value;

  /// The overview's window area (below the desk bar), on the desktop surface.
  Rect _windowArea(OverviewLayout layout) {
    final Size screen = MediaQuery.sizeOf(context);
    return Rect.fromLTRB(0, layout.stripHeight, screen.width, screen.height);
  }

  /// The desk bar, on the desktop surface.
  Rect _deskBar(OverviewLayout layout) => Rect.fromLTWH(
        0,
        0,
        MediaQuery.sizeOf(context).width,
        layout.stripHeight,
      );

  Color get _tintColor => Theme.of(context).colorScheme.surface.withValues(
        alpha: CustomizationService.current.enableEffects ? 0.82 : 1,
      );

  /// The desk bar's color, opaque.
  Color get _barColor => Theme.of(context).colorScheme.background;

  /// river tints the window area and the desk bar's strip in or out. The
  /// desktop surface draws the bar's desks only while the overview is open,
  /// under the strip's opaque tint while it changes (no copy of the surface
  /// to animate: a hidden surface still costs a full-screen pass at 4K).
  Future<void> _tintBackdrop({
    required bool open,
    required Duration duration,
  }) async {
    final int? view = PangolinSession.desktopViewId;
    final OverviewLayout? layout = _model.layout;
    if (view == null || layout == null) return;
    _riverBackdrop = true;
    final int generation = ++_backdropGeneration;
    Future<void> tint(Color color, Rect area, Duration duration) =>
        PangolinSession.setTint(
          view: view,
          color: color,
          area: area,
          duration: duration,
          curve: OverviewTiming.curve,
        );
    if (open) {
      unawaited(tint(_tintColor, _windowArea(layout), duration));
      unawaited(tint(_barColor, _deskBar(layout), duration));
      return;
    }
    unawaited(
        tint(_tintColor.withValues(alpha: 0), _windowArea(layout), duration));
    final Stopwatch elapsed = Stopwatch()..start();
    if (_model.backdrop.value > 0) {
      // The strip covers the desks again before they go.
      await tint(_barColor, _deskBar(layout), Duration.zero);
      if (!mounted || generation != _backdropGeneration) return;
      _model.backdrop.value = 0;
      await _presented();
    }
    final Duration left = duration - elapsed.elapsed;
    unawaited(
      tint(
        _barColor.withValues(alpha: 0),
        _deskBar(layout),
        left.isNegative ? Duration.zero : left,
      ),
    );
  }

  /// Once a frame drawn now is on screen (presented by the compositor).
  Future<void> _presented() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Open: the desktop surface draws the desks under the strip's opaque
  /// tint, which then goes.
  Future<void> _showDesks() async {
    final int? view = PangolinSession.desktopViewId;
    final OverviewLayout? layout = _model.layout;
    if (view == null || layout == null) return;
    final int generation = _backdropGeneration;
    _model.backdrop.value = 1;
    await _presented();
    if (!mounted || generation != _backdropGeneration || !controller.showing) {
      return;
    }
    unawaited(
      PangolinSession.setTint(
        view: view,
        color: _barColor.withValues(alpha: 0),
        area: _deskBar(layout),
      ),
    );
  }

  /// Cross-fades the desktop surface's part from how it looks now to [open]
  /// (river fades a copy out above the surface), then draws the end state.
  /// The bar of desks doesn't slide: the surface is the bottom one, moving
  /// a part of it would uncover nothing.
  Future<void> _animateBackdrop({
    required bool open,
    required Duration duration,
  }) async {
    final int? view = PangolinSession.desktopViewId;
    if (view == null) return;
    _riverBackdrop = true;
    final int generation = ++_backdropGeneration;
    await PangolinSession.animatePart(
      view: view,
      reveal: false,
      rect: Offset.zero & MediaQuery.sizeOf(context),
      duration: duration,
      curve: OverviewTiming.curve,
    );
    if (!mounted || generation != _backdropGeneration) return;
    _model.backdrop.value = open ? 1 : 0;
  }

  /// A swipe takes over: the desktop surface follows it frame by frame.
  void _followBackdrop() {
    if (!_riverBackdrop) return;
    _riverBackdrop = false;
    _backdropGeneration++;
    final OverviewLayout? layout = _model.layout;
    final int? view = PangolinSession.desktopViewId;
    if (layout != null && view != null) {
      // Ends river's animations of the surface.
      unawaited(
        PangolinSession.animatePart(
          view: view,
          reveal: true,
          rect: Offset.zero & MediaQuery.sizeOf(context),
          opacity: 1,
          duration: Duration.zero,
          curve: OverviewTiming.curve,
        ),
      );
    }
    if (_tinted) {
      // The strip covers the desks (drawn while open) during the swipe.
      _followTint(animationController.value);
      _model.backdrop.value = 0;
    } else {
      _model.backdrop.value = animationController.value;
    }
  }

  void _onStatus(AnimationStatus status) {
    // Leave the widget tree once closed.
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  OverviewLayout _computeLayout() {
    return OverviewLayout.compute(
      screen: MediaQuery.sizeOf(context),
      bottomInset: PangolinSession.taskbarHeight,
      wm: _wm,
      canAddDesk: _wm.managesSessionWindows && _wm.desks.value.count < 16,
    );
  }

  /// Follows windows opening/closing and desk changes while shown.
  void _relayout() {
    if (!controller.showing || !mounted) return;
    final OverviewLayout layout = _computeLayout();
    if (layout == _model.layout) return;
    _model.layout = layout;
    if (_gestureStart != null) {
      _wm.showOverview(
        layout.slots,
        duration: Duration.zero,
        progress: animationController.value,
      );
    } else {
      _wm.showOverview(layout.slots, duration: OverviewTiming.relayout);
    }
    setState(() {});
  }

  /// [full] scaled to the part of the way left to go.
  Duration _remaining(Duration full, double distance) {
    final int ms = (full.inMilliseconds * distance.clamp(0.0, 1.0)).round();
    return Duration(milliseconds: ms.clamp(120, full.inMilliseconds));
  }

  @override
  FutureOr<void> requestShow(Map<String, dynamic> args) {
    final bool entering = !controller.showing;
    final Duration duration =
        _remaining(OverviewTiming.open, 1 - animationController.value);
    final bool fade = _canAnimateBackdrop && _model.backdrop.value < 1;
    if (entering || _model.layout == null) {
      final OverviewLayout layout = _computeLayout();
      _model.layout = layout;
      _wm.showOverview(
        layout.slots,
        duration: duration,
        fadeThumbnails: fade,
      );
    } else {
      _wm.showOverview(
        _model.layout!.slots,
        duration: duration,
        fadeThumbnails: fade,
      );
    }
    controller.showing = true;
    _gestureStart = null;
    _detailsTimer?.cancel();
    void showDetails() {
      if (mounted && controller.showing && _gestureStart == null) {
        ShellSurfaceArea.instance.quiet = false;
        if (_tinted) unawaited(_showDesks());
        _details.forward();
      }
    }

    if (fade) {
      // river animates everything that moves: nothing here changes (and
      // no frames are drawn) until the details fade in, and river draws
      // only the taskbar of this surface meanwhile.
      if (_tinted) {
        ShellSurfaceArea.instance.quiet = true;
        unawaited(_tintBackdrop(open: true, duration: duration));
      } else {
        unawaited(_animateBackdrop(open: true, duration: duration));
      }
      animationController.value = 1;
      _detailsTimer = Timer(duration, showDetails);
    } else {
      animationController
          .animateTo(1, duration: duration, curve: OverviewTiming.curve)
          .then((_) => showDetails());
    }
    _focusNode.requestFocus();
  }

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) {
    if (!controller.showing) return null;
    controller.showing = false;
    _gestureStart = null;
    _model.hoveredDesk.value = null;
    _detailsTimer?.cancel();
    _details.value = 0;
    final Duration duration =
        _remaining(OverviewTiming.close, animationController.value);
    _wm.hideOverview(
      activate: args["activate"] as ShellWindow?,
      duration: duration,
      fadeThumbnails: _canAnimateBackdrop,
    );
    // An opening still on its way is dropped.
    _backdropGeneration++;
    if (_canAnimateBackdrop) {
      if (_tinted) {
        // The details are gone: river draws only the taskbar of this
        // surface while it animates the rest.
        ShellSurfaceArea.instance.quiet = true;
        unawaited(_tintBackdrop(open: false, duration: duration));
        // Until river is done: the overview's input region and overlay
        // state go a frame later and would make river draw the whole
        // surface for the rest of the animation.
        _detailsTimer = Timer(
          duration,
          () => ShellSurfaceArea.instance.quiet = false,
        );
      } else if (_model.backdrop.value > 0) {
        unawaited(
          _animateBackdrop(open: false, duration: duration),
        );
      }
      // river animates the rest.
      animationController.value = 0;
    } else {
      animationController.animateBack(
        0,
        duration: duration,
        curve: OverviewTiming.curve,
      );
    }
  }

  // Gestures (see OverviewGestureHandler).

  @override
  bool beginGesture() {
    if (!mounted || !_wm.supportsOverview) return false;
    animationController.stop();
    _detailsTimer?.cancel();
    _details.value = 0;
    _followBackdrop();
    if (_tinted) ShellSurfaceArea.instance.quiet = true;
    if (!controller.showing) {
      final OverviewLayout layout = _computeLayout();
      _model.layout = layout;
      controller.showing = true;
      _wm.showOverview(
        layout.slots,
        duration: Duration.zero,
        progress: animationController.value,
      );
      _focusNode.requestFocus();
    } else {
      _wm.trackOverview(animationController.value);
    }
    _followTint(animationController.value);
    _gestureStart = animationController.value;
    return true;
  }

  @override
  void updateGesture(double offset) {
    final double? start = _gestureStart;
    if (start == null) return;
    final double progress = (start + offset).clamp(0.0, 1.0);
    animationController.value = progress;
    _wm.trackOverview(progress);
    _followTint(progress);
  }

  /// A swipe: the tints follow it frame by frame.
  void _followTint(double progress) {
    final int? view = PangolinSession.desktopViewId;
    final OverviewLayout? layout = _model.layout;
    if (!_tinted || view == null || layout == null) return;
    unawaited(
      PangolinSession.setTint(
        view: view,
        color: _tintColor.withValues(alpha: _tintColor.a * progress),
        area: _windowArea(layout),
      ),
    );
    unawaited(
      PangolinSession.setTint(
        view: view,
        color: _barColor.withValues(alpha: progress),
        area: _deskBar(layout),
      ),
    );
  }

  @override
  void endGesture(double velocity, {required bool cancelled}) {
    final double? start = _gestureStart;
    if (start == null) return;
    final double progress = animationController.value;
    final bool open =
        cancelled ? start >= 0.5 : progress + velocity * 0.2 >= 0.5;
    _gestureStart = null;
    if (open) {
      requestShow(const {});
    } else {
      ShellService.current.dismissOverlay(OverviewOverlay.overlayId);
    }
  }

  void _dismiss({ShellWindow? activate}) {
    ShellService.current.dismissOverlay(
      OverviewOverlay.overlayId,
      args: {if (activate != null) "activate": activate},
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final OverviewLayout? layout = _model.layout;
    if (shouldHide || layout == null) return const SizedBox();
    final bool mirrored = _wm.supportsOverview;

    return Positioned.fill(
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: IgnorePointer(
          // Clicks go through while closing.
          ignoring: !controller.showing,
          child: AnimatedBuilder(
            animation: Listenable.merge([animationController, _details]),
            builder: (context, _) {
              final double t = animationController.value;
              // Mirrored: everything here waits for the overview to open
              // (see _details); windowed, it all moves along.
              final double details =
                  mirrored ? _details.value : ((t - 0.6) / 0.4).clamp(0.0, 1.0);
              final bool showStrip = !mirrored || details > 0;
              final Offset strip = layout.stripOffset(mirrored ? 1 : t);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _dismiss,
                      onSecondaryTap: _dismiss,
                      // Windowed mode has no backdrop surface: draw it here.
                      child: mirrored
                          ? null
                          : OverviewSurfaces(
                              layout: layout,
                              progress: t,
                              wallpaper: CustomizationService.current.wallpaper,
                            ),
                    ),
                  ),
                  // The bar takes clicks (they don't close the overview).
                  Positioned(
                    left: 0,
                    right: 0,
                    top: strip.dy,
                    height: layout.stripHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                    ),
                  ),
                  if (showStrip)
                    for (int d = 0; d < layout.desks.length; d++)
                      Positioned.fromRect(
                        rect: Rect.fromLTRB(
                          layout.desks[d].left,
                          layout.desks[d].top,
                          layout.desks[d].right,
                          layout.desks[d].bottom + layout.labelHeight,
                        ).shift(strip),
                        child: Opacity(
                          opacity: mirrored ? details : 1,
                          child: _DeskThumbnail(desk: d, layout: layout),
                        ),
                      ),
                  if (showStrip)
                    if (layout.addDesk case final Rect add)
                      Positioned.fromRect(
                        rect: add.shift(strip),
                        child: Opacity(
                          opacity: mirrored ? details : 1,
                          child: const _AddDeskButton(),
                        ),
                      ),
                  for (final (ShellWindow window, Rect rect) in layout.windows)
                    Positioned.fromRect(
                      key: ObjectKey(window),
                      rect: rect.inflate(_WindowSlot.reach),
                      child: _WindowSlot(
                        window: window,
                        details: details,
                        drawContent: !mirrored,
                        onActivate: () => _dismiss(activate: window),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Label, hover and drop target of a desk thumbnail (the thumbnail itself
/// is drawn by [OverviewSurfaces] on the desktop surface, below the copies of
/// the windows).
class _DeskThumbnail extends StatefulWidget {
  const _DeskThumbnail({required this.desk, required this.layout});

  final int desk;
  final OverviewLayout layout;

  @override
  State<_DeskThumbnail> createState() => _DeskThumbnailState();
}

class _DeskThumbnailState extends State<_DeskThumbnail> {
  bool _hovered = false;

  WindowManagerService get _wm => WindowManagerService.current;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
    final ValueNotifier<int?> shared = OverviewModel.instance.hoveredDesk;
    if (hovered) {
      shared.value = widget.desk;
    } else if (shared.value == widget.desk) {
      shared.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool current = widget.desk == widget.layout.currentDesk;
    final int count = widget.layout.desks.length;

    return DragTarget<ShellWindow>(
      onWillAcceptWithDetails: (details) =>
          _wm.deskOf(details.data) != widget.desk,
      onAcceptWithDetails: (details) {
        _setHovered(false);
        _wm.moveWindowToDesk(details.data, widget.desk);
      },
      onMove: (_) => _setHovered(true),
      onLeave: (_) => _setHovered(false),
      builder: (context, candidates, _) {
        final bool dropping = candidates.isNotEmpty;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            onTap: () => _wm.switchDesk(widget.desk),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Tints the thumbnail (and the windows in it).
                      Positioned.fill(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            borderRadius: OverviewLayout.deskRadius,
                            color: dropping
                                ? colors.secondary.withValues(alpha: 0.35)
                                : _hovered
                                    ? Colors.white.withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0),
                          ),
                        ),
                      ),
                      if (_hovered && count > 1)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _CircleButton(
                            icon: Icons.close_rounded,
                            tooltip: "Remove desktop",
                            onPressed: () => _wm.removeDesk(widget.desk),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: widget.layout.labelHeight,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: ShapeDecoration(
                        shape: const StadiumBorder(),
                        color: current
                            ? colors.secondary
                            : colors.secondary.withValues(alpha: 0),
                      ),
                      child: Text(
                        "Desktop ${widget.desk + 1}",
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color:
                              current ? colors.onSecondary : colors.onSurface,
                          fontWeight:
                              current ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "New desktop", an extended floating action button.
class _AddDeskButton extends StatefulWidget {
  const _AddDeskButton();

  @override
  State<_AddDeskButton> createState() => _AddDeskButtonState();
}

class _AddDeskButtonState extends State<_AddDeskButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: colors.secondary,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            WindowManagerService.current.addDesk();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: colors.onSecondary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.overviewOverlay.newDesktop,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Input and details of a window shown by the overview. It is laid out
/// [reach] larger than the window on every side, so the close button over
/// the window's corner is inside it: Flutter only hit-tests within a
/// widget's bounds (half the button didn't take clicks, and moving onto it
/// "left" the window and hid it).
class _WindowSlot extends StatefulWidget {
  const _WindowSlot({
    required this.window,
    required this.details,
    required this.drawContent,
    required this.onActivate,
  });

  final ShellWindow window;

  /// How far the slot reaches past the window on each side.
  static const double reach = 24;

  /// Opacity of the icon and the hover details.
  final double details;

  /// Draw a placeholder card (windowed mode, without window copies).
  final bool drawContent;
  final VoidCallback onActivate;

  @override
  State<_WindowSlot> createState() => _WindowSlotState();
}

class _WindowSlotState extends State<_WindowSlot> {
  bool _hovered = false;

  /// Hovered while the pointer is over the window, or over the close button
  /// shown for it: one region for the whole slot, so moving between the two
  /// doesn't leave one and enter the other.
  void _pointerAt(Offset position) {
    final Size? size = context.size;
    if (size == null) return;
    final Rect window = (Offset.zero & size).deflate(_WindowSlot.reach);
    final Rect close = Rect.fromCircle(
      center: window.topRight,
      radius: _CircleButton.size / 2,
    );
    _setHovered(
      window.contains(position) || (_hovered && close.contains(position)),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
    // river lifts the copy of the window under the pointer.
    final WindowManagerService wm = WindowManagerService.current;
    if (hovered) {
      wm.highlightOverview(widget.window);
    } else {
      wm.highlightOverview(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ShellWindow window = widget.window;
    final bool hovered = _hovered && widget.details > 0;

    final Widget slot = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        onTertiaryTapUp: (_) => window.close(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.drawContent)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: Constants.mediumShape,
                    color: theme.colorScheme.background,
                  ),
                  child: Center(child: WindowIcon(window: window, size: 64)),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -24,
              child: IgnorePointer(
                child: Opacity(
                  opacity: widget.details,
                  child: Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 10),
                        ],
                      ),
                      child: WindowIcon(window: window, size: 44),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: -42,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Center(child: _TitleChip(title: window.title)),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    const double reach = _WindowSlot.reach;
    // Not opaque: the margin may reach over a neighbour, which must still
    // see the pointer.
    return MouseRegion(
      opaque: false,
      onEnter: (e) => _pointerAt(e.localPosition),
      onHover: (e) => _pointerAt(e.localPosition),
      onExit: (_) => _setHovered(false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(reach),
              child: Draggable<ShellWindow>(
                data: window,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Transform.translate(
                  offset: const Offset(-28, -28),
                  child: Opacity(
                    opacity: 0.9,
                    child: WindowIcon(window: window, size: 56),
                  ),
                ),
                child: slot,
              ),
            ),
          ),
          // Centered on the window's corner.
          if (hovered)
            Positioned(
              top: reach - _CircleButton.size / 2,
              right: reach - _CircleButton.size / 2,
              child: _CircleButton(
                icon: Icons.close_rounded,
                tooltip: "Close",
                onPressed: window.close,
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleChip extends StatelessWidget {
  const _TitleChip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: theme.colorScheme.background,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  static const double size = 32;

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      // It may open over the button: it must not take the pointer from it.
      ignorePointer: true,
      child: Material(
        color: colors.background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: Icon(icon, size: 20, color: colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
