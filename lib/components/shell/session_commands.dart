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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/overlays/launcher/compact_launcher_overlay.dart';
import 'package:pangolin/components/overlays/notifications/overlay.dart';
import 'package:pangolin/components/overlays/overview/layout.dart';
import 'package:pangolin/components/overlays/overview_overlay.dart';
import 'package:pangolin/components/overlays/power_overlay.dart';
import 'package:pangolin/components/overlays/quick_settings/quick_settings_overlay.dart';
import 'package:pangolin/components/overlays/search/search_overlay.dart';
import 'package:pangolin/components/shell/osd.dart';
import 'package:pangolin/components/shell/screenshot.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/services/hardware_controls.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/data/app_ids.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:pangolin/widgets/window_icon.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

/// Carries out [ShellCommand]s coming from the window manager's global key
/// bindings, and draws the window manager feedback that lives on the shell
/// surface (Alt+Tab switcher, snap preview).
class SessionCommands extends StatefulWidget {
  const SessionCommands({required this.child, super.key});

  final Widget child;

  @override
  State<SessionCommands> createState() => _SessionCommandsState();
}

class _SessionCommandsState extends State<SessionCommands> {
  StreamSubscription<ShellCommand>? _subscription;
  StreamSubscription<VerticalSwipe>? _swipes;

  WindowManagerService get _wm => WindowManagerService.current;

  @override
  void initState() {
    super.initState();
    _subscription = _wm.shellCommands.listen(_handle);
    _swipes = _wm.verticalSwipes.listen(_onVerticalSwipe);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _swipes?.cancel();
    super.dispose();
  }

  void _handle(ShellCommand command) {
    final ShellService shell = ShellService.current;
    switch (command) {
      case ShellCommand.toggleLauncher:
        shell.toggleOverlay(CompactLauncherOverlay.overlayId);
      case ShellCommand.toggleSearch:
        shell.toggleOverlay(SearchOverlay.overlayId);
      case ShellCommand.toggleOverview:
        shell.toggleOverlay(OverviewOverlay.overlayId);
      case ShellCommand.showPowerMenu:
        shell.showOverlay(PowerOverlay.overlayId);
      case ShellCommand.lockSession:
        ActionManager.lock();
      case ShellCommand.restartShell:
        // The session's init script starts the shell again right away.
        exit(PangolinSession.restartExitCode);
      case ShellCommand.openTerminal:
        _launch(DahliaApps.terminal);
      case ShellCommand.openFiles:
        _launch(DahliaApps.files);
      case ShellCommand.openSettings:
        _launch(DahliaApps.settings);
      case ShellCommand.openActivityMonitor:
        _launch(DahliaApps.activityMonitor);
      case ShellCommand.screenshot:
        unawaited(ScreenshotTool.open());
      case ShellCommand.screenshotScreen:
        unawaited(ScreenshotTool.captureScreen());
      case ShellCommand.volumeUp:
        VolumeControl.instance.step(1);
        Osd.instance.show(OsdKind.volume);
      case ShellCommand.volumeDown:
        VolumeControl.instance.step(-1);
        Osd.instance.show(OsdKind.volume);
      case ShellCommand.volumeMute:
        VolumeControl.instance.setMuted(!VolumeControl.instance.muted);
        Osd.instance.show(OsdKind.volume);
      case ShellCommand.brightnessUp:
        BrightnessControl.instance.step(1);
        Osd.instance.show(OsdKind.brightness);
      case ShellCommand.brightnessDown:
        BrightnessControl.instance.step(-1);
        Osd.instance.show(OsdKind.brightness);
      case ShellCommand.gestureSwipeUp ||
            ShellCommand.gestureSwipeDown ||
            ShellCommand.gesturePinchIn ||
            ShellCommand.gesturePinchOut:
        _onGesture(command);
    }
  }

  /// Swipe distance (see [VerticalSwipe.offset]) at which a swipe that
  /// doesn't move the overview runs its action.
  static const double _swipeThreshold = 0.3;

  /// The overview follows the current swipe.
  OverviewGestureHandler? _swipeOverview;
  double _swipeStart = 0;
  bool _swipeFired = false;

  /// Up/down touchpad swipes. Opening the overview (and closing it) follows
  /// the fingers; other actions run once the swipe went far enough.
  void _onVerticalSwipe(VerticalSwipe swipe) {
    switch (swipe.phase) {
      case VerticalSwipePhase.begin:
        _swipeFired = false;
        _swipeStart = swipe.offset;
        _swipeOverview = null;
        final ShellService shell = ShellService.current;
        final bool overview = shell.currentlyShown(OverviewOverlay.overlayId);
        final bool up = swipe.offset > 0;
        final bool follow = up
            ? !overview &&
                shell.currentlyShownOverlays.isEmpty &&
                _setting(SessionSetting.gestureSwipeUp) ==
                    GestureAction.overview
            : overview &&
                shell.currentlyShownOverlays
                    .every((id) => id == OverviewOverlay.overlayId);
        final OverviewGestureHandler? handler =
            OverviewModel.instance.gestureHandler;
        if (follow && handler != null && handler.beginGesture()) {
          _swipeOverview = handler;
          handler.updateGesture(swipe.offset - _swipeStart);
        }
      case VerticalSwipePhase.update:
        final OverviewGestureHandler? handler = _swipeOverview;
        if (handler != null) {
          handler.updateGesture(swipe.offset - _swipeStart);
        } else if (!_swipeFired && swipe.offset.abs() >= _swipeThreshold) {
          _swipeFired = true;
          _onGesture(
            swipe.offset > 0
                ? ShellCommand.gestureSwipeUp
                : ShellCommand.gestureSwipeDown,
          );
        }
      case VerticalSwipePhase.end:
        _swipeOverview?.endGesture(swipe.velocity, cancelled: swipe.cancelled);
        _swipeOverview = null;
    }
  }

  GestureAction _setting(SessionSetting<String> setting) => GestureAction.parse(
        PreferencesService.current.get<String>(setting.key) ??
            setting.defaultValue,
      );

  /// Touchpad gestures, GNOME style: swiping up opens the overview and then
  /// the launcher, swiping down goes back. Otherwise the configured action.
  void _onGesture(ShellCommand gesture) {
    final ShellService shell = ShellService.current;
    final bool overview = shell.currentlyShown(OverviewOverlay.overlayId);
    final bool launcher =
        shell.currentlyShown(CompactLauncherOverlay.overlayId);

    switch (gesture) {
      case ShellCommand.gestureSwipeUp:
        if (overview) {
          shell.dismissOverlay(OverviewOverlay.overlayId);
          shell.showOverlay(CompactLauncherOverlay.overlayId);
          return;
        }
        if (launcher) return;
        _runGestureAction(_setting(SessionSetting.gestureSwipeUp));
      case ShellCommand.gestureSwipeDown:
        if (shell.currentlyShownOverlays.isNotEmpty) {
          shell.dismissEverything();
          return;
        }
        _runGestureAction(_setting(SessionSetting.gestureSwipeDown));
      case ShellCommand.gesturePinchIn:
        _runGestureAction(_setting(SessionSetting.gesturePinchIn));
      case ShellCommand.gesturePinchOut:
        _runGestureAction(_setting(SessionSetting.gesturePinchOut));
      default:
        break;
    }
  }

  void _runGestureAction(GestureAction action) {
    final ShellService shell = ShellService.current;
    switch (action) {
      case GestureAction.none || GestureAction.switchDesktop:
        break;
      case GestureAction.overview:
        shell.toggleOverlay(OverviewOverlay.overlayId);
      case GestureAction.launcher:
        shell.toggleOverlay(CompactLauncherOverlay.overlayId);
      case GestureAction.search:
        shell.toggleOverlay(SearchOverlay.overlayId);
      case GestureAction.quickSettings:
        shell.toggleOverlay(QuickSettingsOverlay.overlayId);
      case GestureAction.notifications:
        shell.toggleOverlay(NotificationsOverlay.overlayId);
      case GestureAction.lockScreen:
        shell.dismissEverything();
        ActionManager.lock();
      case GestureAction.showDesktop:
        shell.dismissEverything();
        final int desk = _wm.desks.value.current;
        final bool anyVisible = _wm.windows
            .any((w) => _wm.deskOf(w) == desk && !w.minimized);
        anyVisible ? _wm.minimizeEverything() : _wm.unminimizeEverything();
    }
  }

  void _launch(String appId) {
    ShellService.current.dismissEverything();
    ApplicationService.current.startApp(appId);
  }



  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<Rect?>(
          valueListenable: _wm.snapPreview,
          builder: (context, rect, _) => _SnapPreview(rect: rect),
        ),
        widget.child,
        const OsdLayer(),
        _HotCorners(onAction: _runGestureAction),
        ValueListenableBuilder<int?>(
          valueListenable: _wm.switcherIndex,
          builder: (context, index, _) => index == null
              ? const SizedBox.shrink()
              : _WindowSwitcher(
                  windows: _wm.switcherWindows,
                  selected: index,
                ),
        ),
      ],
    );
  }
}

class _SnapPreview extends StatelessWidget {
  const _SnapPreview({required this.rect});

  final Rect? rect;

  @override
  Widget build(BuildContext context) {
    final Rect? rect = this.rect;
    if (rect == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);

    return Stack(
      children: [
        AnimatedPositioned.fromRect(
          duration: Constants.animationDuration,
          curve: Constants.animationCurve,
          rect: rect.deflate(8),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: Constants.bigShape,
                color: theme.colorScheme.secondary.withValues(alpha: 0.22),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WindowSwitcher extends StatelessWidget {
  const _WindowSwitcher({required this.windows, required this.selected});

  final List<ShellWindow> windows;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ShellWindow? current =
        selected < windows.length ? windows[selected] : null;

    return IgnorePointer(
      child: Center(
        child: SurfaceLayer(
          shape: Constants.bigShape,
          outline: true,
          dropShadow: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (int i = 0; i < windows.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 88,
                      height: 88,
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        shape: Constants.mediumShape,
                        color: i == selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.25)
                            : Colors.transparent,
                      ),
                      child: WindowIcon(window: windows[i], size: 56),
                    ),
                ],
              ),
              if (current != null) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hot corners: pushing the pointer into a corner of the screen runs the
/// action chosen for it in Settings (the overview for the top left one, as
/// in GNOME). river reports the corners (the shell surface doesn't cover
/// the screen when nothing is open), so the same corner also closes what it
/// opened.
class _HotCorners extends StatefulWidget {
  const _HotCorners({required this.onAction});

  final void Function(GestureAction action) onAction;

  @override
  State<_HotCorners> createState() => _HotCornersState();
}

class _HotCornersState extends State<_HotCorners> {
  static final Map<Alignment, SessionSetting<String>> _corners = {
    Alignment.topLeft: SessionSetting.hotCornerTopLeft,
    Alignment.topRight: SessionSetting.hotCornerTopRight,
    Alignment.bottomLeft: SessionSetting.hotCornerBottomLeft,
    Alignment.bottomRight: SessionSetting.hotCornerBottomRight,
  };

  StreamSubscription<Alignment>? _subscription;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _subscription = WindowManagerService.current.hotCorners.listen(_reached);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _reached(Alignment corner) {
    final SessionSetting<String>? setting = _corners[corner];
    if (setting == null) return;
    final GestureAction action = GestureAction.parse(
      PreferencesService.current.get<String>(setting.key) ??
          setting.defaultValue,
    );
    if (action == GestureAction.none || action == GestureAction.switchDesktop) {
      return;
    }
    // Not over a fullscreen app (games, videos), as in GNOME.
    final ShellWindow? focused = WindowManagerService.current.focusedWindow;
    if (focused != null && focused.fullscreen && !focused.minimized) return;
    // Once per visit, even when what it opens rebuilds the corner.
    final DateTime now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 600)) return;
    _last = now;
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
