import 'dart:async';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/wm/river.dart';
import 'package:pangolin/services/wm/window.dart';
import 'package:pangolin/utils/wm/properties.dart';
import 'package:utopia_wm/wm.dart';

export 'package:pangolin/services/wm/window.dart';

/// Actions triggered by global key bindings that the shell UI carries out.
enum ShellCommand {
  toggleLauncher,
  toggleSearch,
  toggleOverview,
  showPowerMenu,
  lockSession,
  restartShell,
  openTerminal,
  openFiles,
  openSettings,
  openActivityMonitor,
  screenshot,
  screenshotScreen,
  volumeUp,
  volumeDown,
  volumeMute,
  brightnessUp,
  brightnessDown,

  // Touchpad gestures the shell maps to actions (see GestureAction).
  gestureSwipeUp,
  gestureSwipeDown,
  gesturePinchIn,
  gesturePinchOut,
}

/// A touchpad swipe up or down, reported while the fingers move so the shell
/// can follow them.
@immutable
class VerticalSwipe {
  const VerticalSwipe.begin(this.offset)
      : phase = VerticalSwipePhase.begin,
        velocity = 0,
        cancelled = false;
  const VerticalSwipe.update(this.offset)
      : phase = VerticalSwipePhase.update,
        velocity = 0,
        cancelled = false;
  const VerticalSwipe.end(this.offset, this.velocity, {required this.cancelled})
      : phase = VerticalSwipePhase.end;

  final VerticalSwipePhase phase;

  /// Distance travelled, positive upwards: 1 is a full overview swipe.
  final double offset;

  /// Distance per second when the fingers lifted.
  final double velocity;
  final bool cancelled;
}

enum VerticalSwipePhase { begin, update, end }

/// Where the overview shows a window, in shell surface coordinates.
@immutable
class OverviewSlot {
  const OverviewSlot(
    this.window,
    this.rect, {
    this.thumbnail = false,
    this.hiddenRect,
  });

  final ShellWindow window;
  final Rect rect;

  /// A small copy in a desktop thumbnail (a window may have both).
  final bool thumbnail;

  /// Where the copy comes from when the overview opens and goes back to when
  /// it closes. Windows default to their own place.
  final Rect? hiddenRect;
}

/// Virtual desktops ("desks") of the session.
@immutable
class DeskState {
  const DeskState({required this.count, required this.current});

  final int count;
  final int current;

  @override
  bool operator ==(Object other) =>
      other is DeskState && other.count == count && other.current == current;

  @override
  int get hashCode => Object.hash(count, current);
}

class WindowManagerServiceFactory extends ServiceFactory<WindowManagerService> {
  const WindowManagerServiceFactory();

  @override
  WindowManagerService build() {
    if (PangolinSession.isSession) return RiverWindowManagerService();
    return UtopiaWindowManagerService();
  }

  /// When river is not available (e.g. Pangolin was started on another
  /// layer-shell compositor) the shell keeps working, it just doesn't manage
  /// the session's windows.
  @override
  WindowManagerService? fallback() => UtopiaWindowManagerService();
}

/// Manages the windows of the session.
///
/// Every implementation hosts the shell's own surfaces in a Utopia
/// [WindowHierarchyController] ([controller]). Application windows are exposed
/// as [ShellWindow]s through [windows], regardless of whether they are real
/// Wayland clients (river) or Utopia windows rendered inside the shell.
abstract class WindowManagerService extends ListenableService {
  WindowManagerService();

  static WindowManagerService get current {
    return ServiceManager.getService<WindowManagerService>()!;
  }

  /// Hierarchy rendering the shell (and, in windowed mode, built-in apps).
  WindowHierarchyController get controller;

  void push(LiveWindowEntry entry);
  void pop(String id);

  /// Application windows from bottom to top of the stacking order.
  List<ShellWindow> get windows;

  /// Application windows from the most to the least recently focused.
  List<ShellWindow> get windowsByRecency;

  ShellWindow? get focusedWindow => windows.where((w) => w.focused).firstOrNull;

  /// Whether this service is the window manager of a real Wayland session.
  bool get managesSessionWindows => false;

  /// Logical area available to windows on the primary output.
  Rect get workArea => controller.wmBounds;

  void minimizeEverything();
  void unminimizeEverything();

  /// Ends the Wayland session (log out).
  Future<void> exitSession() async {}

  /// Commands from global key bindings (only emitted in session mode).
  Stream<ShellCommand> get shellCommands => const Stream.empty();

  /// Touchpad swipes up and down (only emitted in session mode).
  Stream<VerticalSwipe> get verticalSwipes => const Stream.empty();

  /// Area a window being dragged would snap to if released now.
  ValueListenable<Rect?> get snapPreview => _noRect;

  /// Index into [windowsByRecency] highlighted by the Alt+Tab switcher, or
  /// null when the switcher is closed.
  ValueListenable<int?> get switcherIndex => _noIndex;

  /// Windows the Alt+Tab switcher cycles through, most recent first.
  List<ShellWindow> get switcherWindows => windowsByRecency;

  /// Virtual desktops. Windowed mode has a single one.
  ValueListenable<DeskState> get desks => _singleDesk;

  /// Desktop [window] is on.
  int deskOf(ShellWindow window) => 0;

  void switchDesk(int index) {}

  /// Adds a desktop at the end; switches to it when [activate] is set.
  void addDesk({bool activate = false}) {}

  /// Removes desktop [index]; its windows move to a neighbouring desktop.
  void removeDesk(int index) {}

  void moveWindowToDesk(ShellWindow window, int desk) {}

  /// Window geometry in shell surface coordinates (session mode only).
  Rect? windowRect(ShellWindow window) => null;

  /// Whether [showOverview] can show the windows (session mode, with a
  /// compositor that draws window mirrors).
  bool get supportsOverview => false;

  /// Enters (or updates) the overview: the windows are replaced by copies
  /// animated to [slots] over [duration]. Copies of windows no longer in
  /// [slots] fade out. With [progress], the copies are put that far on their
  /// way right away instead (a gesture opening the overview, see
  /// [trackOverview]). With [fadeThumbnails], entering thumbnails fade in
  /// where they go rather than coming from their hidden places.
  void showOverview(
    List<OverviewSlot> slots, {
    required Duration duration,
    double? progress,
    bool fadeThumbnails = false,
  }) {}

  /// Puts the copies of the windows [progress] of the way between their
  /// windows (0) and their place in the overview (1), following a gesture.
  void trackOverview(double progress) {}

  /// Lifts the copy of [window] in the overview (pointer over it).
  void highlightOverview(ShellWindow? window) {}

  /// Leaves the overview: the copies go back to their windows over
  /// [duration], [activate] is raised and focused first.
  /// With [fadeThumbnails], thumbnails fade out where they are rather than
  /// going back to their hidden places.
  void hideOverview({
    ShellWindow? activate,
    required Duration duration,
    bool fadeThumbnails = false,
  }) {}

  static final ValueNotifier<Rect?> _noRect = ValueNotifier(null);
  static final ValueNotifier<int?> _noIndex = ValueNotifier(null);
  static final ValueNotifier<DeskState> _singleDesk =
      ValueNotifier(const DeskState(count: 1, current: 0));
}

/// Shared ownership of the Utopia hierarchy hosting the shell.
mixin ShellHierarchyHost on WindowManagerService {
  WindowHierarchyController? _controller;

  @override
  WindowHierarchyController get controller {
    if (_controller == null) {
      throw Exception(
        "The window manager service is not currently running, can't obtain the controller",
      );
    }
    return _controller!;
  }

  @protected
  void startHierarchy() => _controller = WindowHierarchyController();

  @protected
  void stopHierarchy() => _controller = null;

  @override
  void push(LiveWindowEntry entry) {
    unminimizeEverything();
    controller.addWindowEntry(entry);
  }

  @override
  void pop(String id) => controller.removeWindowEntry(id);
}

/// Window manager for windowed mode: application windows are Utopia windows
/// rendered inside the shell itself.
class UtopiaWindowManagerService extends WindowManagerService
    with ShellHierarchyHost {
  final Map<String, bool> _minimizedCache = {};
  final Map<String, _UtopiaShellWindow> _wrappers = {};

  @override
  void start() {
    startHierarchy();
    controller.addListener(_onHierarchyChanged);
  }

  @override
  void stop() {
    controller.removeListener(_onHierarchyChanged);
    stopHierarchy();
  }

  bool _isApp(LiveWindowEntry e) =>
      e.registry.maybeGet(WindowExtras.stableId) != "shell";

  void _onHierarchyChanged() {
    final Set<String> live = {};
    for (final LiveWindowEntry entry in controller.entries.where(_isApp)) {
      live.add(entry.registry.info.id);
      _wrappers.putIfAbsent(
        entry.registry.info.id,
        () => _UtopiaShellWindow(this, entry),
      );
    }
    _wrappers.removeWhere((id, _) => !live.contains(id));
    for (final _UtopiaShellWindow w in _wrappers.values) {
      w.refresh();
    }
    notifyListeners();
  }

  @override
  List<ShellWindow> get windows => [
        for (final LiveWindowEntry e in controller.entries.where(_isApp))
          if (_wrappers[e.registry.info.id] case final w?) w,
      ];

  @override
  List<ShellWindow> get windowsByRecency => [
        for (final String id in controller.focusHierarchy.reversed)
          if (_wrappers[id] case final w?) w,
      ];

  @override
  void minimizeEverything() {
    _minimizedCache.addEntries(
      controller.entries.map(
        (e) => MapEntry(e.registry.info.id, e.layoutState.minimized),
      ),
    );

    for (final LiveWindowEntry e in controller.entries.where(_isApp)) {
      e.layoutState.minimized = true;
    }
  }

  @override
  void unminimizeEverything() {
    for (final LiveWindowEntry entry in controller.entries) {
      final bool? cachedStatus = _minimizedCache[entry.registry.info.id];

      entry.layoutState.minimized = cachedStatus ?? false;
    }

    _minimizedCache.clear();
  }
}

class _UtopiaShellWindow extends ShellWindow {
  _UtopiaShellWindow(this._service, this._entry);

  final UtopiaWindowManagerService _service;
  final LiveWindowEntry _entry;

  WindowHierarchyController get _hierarchy => _service.controller;

  void refresh() => notifyListeners();

  @override
  String get id => _entry.registry.info.id;

  @override
  String? get appId => _entry.registry.maybeGet(WindowExtras.stableId);

  @override
  String get title => _entry.registry.info.title;

  @override
  ImageProvider? get icon => _entry.registry.info.icon;

  @override
  bool get minimized => _entry.layoutState.minimized;

  @override
  bool get maximized => _entry.layoutState.dock == WindowDock.maximized;

  @override
  bool get fullscreen => _entry.layoutState.fullscreen;

  @override
  bool get focused => _hierarchy.isFocused(id) && !minimized;

  @override
  void activate() {
    _entry.layoutState.minimized = false;
    _hierarchy.requestEntryFocus(id);
  }

  @override
  void minimize() {
    _entry.layoutState.minimized = true;
    final List<ShellWindow> others = _service.windowsByRecency
        .where((w) => w != this && !w.minimized)
        .toList();
    if (others.isNotEmpty) _hierarchy.requestEntryFocus(others.first.id);
  }

  @override
  void toggleMaximize() {
    _entry.layoutState.dock =
        maximized ? WindowDock.none : WindowDock.maximized;
  }

  @override
  void close() => unawaited(Future.microtask(() => _service.pop(id)));
}
