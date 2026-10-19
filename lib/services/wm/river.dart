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
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/services/wm/gestures.dart';
import 'package:pangolin/services/wm/keysyms.dart';
import 'package:pangolin/services/wm/mirrors.dart';
import 'package:pangolin/services/wm/taskbar_geometry.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:wayland/wayland.dart';
import 'package:zenit_ui/zenit_ui.dart'
    show drawClose, drawMaximize, drawMinimize, drawRestore;

part 'river_decorations.dart';

/// Pangolin's window manager for the river compositor.
///
/// river implements the compositor side (rendering, input, protocols for
/// clients) and delegates every policy decision to a single window manager
/// client over river-window-management-v1. This service is that client,
/// written directly against the Wayland wire protocol so it can live inside
/// the shell and share state with the taskbar, overview and launcher.
///
/// The protocol is a loop of two sequences:
///
///  * manage: river reports new windows/outputs/seats, input bindings and
///    requests from windows, then waits for [_manage] to make window
///    management changes (sizes, focus, fullscreen, ...) and finish.
///  * render: river reports the dimensions windows actually took, then waits
///    for [_render] to position and stack them before it draws the frame.
///
/// Anything the shell wants to change (focus a window from the taskbar,
/// minimize, close, ...) is queued and applied in the next manage sequence,
/// which is requested with `manage_dirty`.
///
/// On top of that it provides:
///
///  * virtual desktops ("desks"): windows of other desks are hidden, and
///    switching slides the desks horizontally;
///  * Chromium OS style window animations and the overview, drawn by river
///    with mirrors of the windows (river-window-effects-v1) that river
///    animates itself, at the refresh rate of the outputs;
///  * touchpad gestures, when river offers river-touchpad-gestures-v1.
class RiverWindowManagerService extends WindowManagerService
    with ShellHierarchyHost
    implements GestureSink {
  late final WaylandConnection _connection;
  late final GlobalRegistry _globals;
  late final RiverWindowManagerV1 _wm;
  RiverLayerShellV1? _layerShell;
  RiverXkbBindingsV1? _xkbBindings;
  RiverTouchpadGesturesV1? _touchpadGestures;
  RiverWindowEffectsV1? _effects;

  /// Windows from bottom to top.
  final List<RiverWindow> _stack = [];

  /// Windows from the most to the least recently focused.
  final List<RiverWindow> _recency = [];

  final List<RiverWindow> _newWindows = [];
  final List<_Output> _outputs = [];
  final List<_Seat> _seats = [];

  final List<void Function()> _pendingActions = [];

  /// Run right after the next render sequence, once river applied it (e.g.
  /// dropping the mirror of a window that is shown again).
  final List<void Function()> _afterRender = [];

  RiverWindow? _focused;
  bool _stackingDirty = false;
  bool _changed = false;
  bool _manageRequested = false;
  bool _layerFocusExclusive = false;

  final StreamController<ShellCommand> _shellCommands =
      StreamController.broadcast();
  final StreamController<VerticalSwipe> _verticalSwipes =
      StreamController.broadcast();

  // Server side decorations (river_decorations.dart).
  WlCompositor? _compositor;
  WlShm? _shm;

  /// Shadows of server side decorated windows are drawn small and stretched.
  WpViewporter? _viewporter;

  /// Blur behind title bars, rounded corners of server side decorated
  /// windows (river_blur_v1 version 3).
  RiverBlurManagerV1? _blurManager;

  /// Shadow surfaces of server side decorated windows: where they are
  /// resized from.
  final Map<int, _Decoration> _shadowSurfaces = {};
  WlSeat? _wlSeat;
  WlPointer? _pointer;
  WpCursorShapeManagerV1? _cursorShapeManager;
  WpCursorShapeDeviceV1? _cursorShape;
  final Map<int, _Decoration> _decorationSurfaces = {};
  final ValueNotifier<Rect?> _snapPreview = ValueNotifier(null);
  final ValueNotifier<int?> _switcherIndex = ValueNotifier(null);

  /// Windows minimized by "show desktop", restored by the next toggle.
  List<RiverWindow>? _showDesktopMinimized;

  // Desks ---------------------------------------------------------------------

  static const int _maxDesks = 16;
  static const double _deskGap = 48;

  int _currentDesk = 0;
  int _deskCount = 1;
  final ValueNotifier<DeskState> _desks =
      ValueNotifier(const DeskState(count: 1, current: 0));

  /// Desks sliding, null otherwise.
  _Slide? _slide;

  // Preferences -----------------------------------------------------------------

  bool _animationsEnabled = true;
  final double _animationSpeed = 1;
  bool _dynamicDesks = false;
  bool _allDesksInSwitcher = false;
  bool _gesturesEnabled = true;
  int _gestureFingers = 3;
  bool _pinchClaimed = true;
  late final TouchpadGestureTracker _gestures = TouchpadGestureTracker(this);

  @override
  bool get managesSessionWindows => true;

  @override
  Stream<ShellCommand> get shellCommands => _shellCommands.stream;

  @override
  Stream<VerticalSwipe> get verticalSwipes => _verticalSwipes.stream;

  final StreamController<Alignment> _hotCorners = StreamController.broadcast();

  @override
  Stream<Alignment> get hotCorners => _hotCorners.stream;

  /// river starts a manage sequence when the pointer reaches or leaves a
  /// corner of an output, so its position arrives here wherever it is.
  void _checkHotCorner(_Seat seat) {
    final _Output? output = _primaryOutput;
    Alignment? corner;
    if (output != null && seat.op == null) {
      final int x = seat.pointerX - output.x;
      final int y = seat.pointerY - output.y;
      // Logical pixels, as river counts them.
      final bool left = x >= 0 && x < 2;
      final bool right = x >= output.width - 2 && x < output.width;
      final bool top = y >= 0 && y < 2;
      final bool bottom = y >= output.height - 2 && y < output.height;
      if ((left || right) && (top || bottom)) {
        corner = Alignment(left ? -1 : 1, top ? -1 : 1);
      }
    }
    if (corner == seat.corner) return;
    seat.corner = corner;
    if (corner != null) _hotCorners.add(corner);
  }

  @override
  ValueListenable<Rect?> get snapPreview => _snapPreview;

  @override
  ValueListenable<int?> get switcherIndex => _switcherIndex;

  @override
  List<ShellWindow> get windows => List.unmodifiable(_stack);

  @override
  List<ShellWindow> get windowsByRecency => List.unmodifiable(_recency);

  @override
  List<ShellWindow> get switcherWindows => List.unmodifiable(_switcherList);

  List<RiverWindow> get _switcherList => _allDesksInSwitcher
      ? _recency
      : _recency.where((w) => w._desk == _currentDesk).toList();

  @override
  ShellWindow? get focusedWindow => _focused;

  @override
  ValueListenable<DeskState> get desks => _desks;

  _Output? get _primaryOutput => _outputs.firstOrNull;

  @override
  Rect get workArea {
    final _Output? output = _primaryOutput;
    if (output == null) return Rect.zero;
    return Rect.fromLTWH(
      output.x.toDouble(),
      output.y.toDouble(),
      output.width.toDouble(),
      math.max(0.0, output.height - _taskbarReserved),
    );
  }

  /// Kept free for the taskbar at the bottom of the primary output.
  double _taskbarReserved = PangolinSession.taskbarReserved;

  /// Maximized and snapped windows take the new work area (in place: the
  /// stacking stays as it is).
  void _refitToWorkArea() {
    for (final RiverWindow w in _stack) {
      if (w._fullscreen || (!w._maximized && w._snap == _Snap.none)) continue;
      final Rect rect = _contentRect(
        w,
        w._maximized ? workArea : _snapRect(w._snap),
      );
      _proposeSize(w, rect.size);
      w._x = rect.left.toInt();
      w._y = rect.top.toInt();
      _position(w);
      w._notify();
      _changed = true;
    }
  }

  /// Layout coordinates to shell surface coordinates (the shell surface
  /// covers the primary output).
  Rect _local(Rect rect) {
    final _Output? output = _primaryOutput;
    if (output == null) return rect;
    return rect.shift(Offset(-output.x.toDouble(), -output.y.toDouble()));
  }

  /// Shell surface coordinates to layout coordinates.
  Rect _global(Rect rect) {
    final _Output? output = _primaryOutput;
    if (output == null) return rect;
    return rect.shift(Offset(output.x.toDouble(), output.y.toDouble()));
  }

  @override
  Future<void> start() async {
    startHierarchy();

    _connection = await WaylandConnection.connect();
    _connection.onListenerError = (e, s) {
      logger.severe("Error while handling a river event", e, s);
    };
    unawaited(
      _connection.done.then(
        (_) => logger.warning("Lost the connection to the compositor"),
        onError: (Object e) =>
            logger.severe("Connection to the compositor failed: $e"),
      ),
    );

    _globals = await GlobalRegistry.create(_connection);

    final RiverWindowManagerV1? wm =
        _globals.bind(RiverWindowManagerV1.interface);
    if (wm == null) {
      await _connection.close();
      throw StateError(
        "The compositor does not support river-window-management-v1",
      );
    }
    _wm = wm;

    // Binding river_layer_shell_v1 tells river that Pangolin supports layer
    // surfaces (its own taskbar included).
    _layerShell = _globals.bind(RiverLayerShellV1.interface);
    _xkbBindings = _globals.bind(RiverXkbBindingsV1.interface);
    _touchpadGestures = _globals.bind(RiverTouchpadGesturesV1.interface);
    _effects = _globals.bind(RiverWindowEffectsV1.interface);
    _compositor = _globals.bind(WlCompositor.interface, maxVersion: 4);
    _shm = _globals.bind(WlShm.interface);
    _viewporter = _globals.bind(WpViewporter.interface);
    _blurManager = _globals.bind(RiverBlurManagerV1.interface, maxVersion: 3);
    _wlSeat = _globals.bind(WlSeat.interface, maxVersion: 7);
    _cursorShapeManager = _globals.bind(WpCursorShapeManagerV1.interface);
    _bindDecorationInput();
    _effects
      ?..onClosingMirror = _onClosingMirror
      ..setClosingMirrors(1);

    bool unavailable = false;
    _wm
      ..onUnavailable = () {
        unavailable = true;
      }
      ..onFinished = () {
        logger.warning("river stopped window management");
      }
      ..onManageStart = _manage
      ..onRenderStart = _render
      ..onWindow = _onNewWindow
      ..onOutput = _onNewOutput
      ..onSeat = _onNewSeat
      ..onSessionLocked = () {
        logger.info("Session locked");
      }
      ..onSessionUnlocked = () {
        logger.info("Session unlocked");
      };

    await _connection.roundtrip();

    if (unavailable) {
      _wm.destroy();
      await _connection.close();
      throw StateError("Another window manager is already running");
    }

    logger.info(
      "Managing river session (window management v${_wm.version}, "
      "layer shell: ${_layerShell != null}, key bindings: ${_xkbBindings != null}, "
      "window effects: ${_effects != null}, "
      "touchpad gestures: ${_touchpadGestures != null})",
    );

    unawaited(_followPreferences());
  }

  @override
  Future<void> stop() async {
    _slide?.timer?.cancel();
    if ((_pointer?.version ?? 0) >= 3) _pointer?.release();
    _effects?.destroy();
    _wm.stop();
    await _connection.close();
    await _shellCommands.close();
    await _verticalSwipes.close();
    await _hotCorners.close();
    stopHierarchy();
  }

  Future<void> _followPreferences() async {
    await ServiceManager.waitForService<PreferencesService>();
    final PreferencesService prefs = PreferencesService.current;
    if (prefs.get<bool>(SessionSetting.gesturesSupported.key) !=
        (_touchpadGestures != null)) {
      prefs.set<bool>(
        SessionSetting.gesturesSupported.key,
        _touchpadGestures != null,
      );
    }

    T read<T extends Object>(SessionSetting<T> setting) {
      final Object? value = prefs.get<Object>(setting.key);
      return value is T ? value : setting.defaultValue;
    }

    void apply() {
      _animationsEnabled = read(SessionSetting.windowAnimations);
      _dynamicDesks = read(SessionSetting.dynamicDesktops);
      _allDesksInSwitcher = read(SessionSetting.taskbarAllDesktops);
      _gesturesEnabled = read(SessionSetting.gesturesEnabled);
      _gestureFingers = read(SessionSetting.gestureFingers).clamp(3, 4);
      _pinchClaimed =
          GestureAction.parse(read(SessionSetting.gesturePinchIn)) !=
                  GestureAction.none ||
              GestureAction.parse(read(SessionSetting.gesturePinchOut)) !=
                  GestureAction.none;
      _gestures.config = GestureConfig(
        horizontalSwitchesDesktops:
            GestureAction.parse(read(SessionSetting.gestureSwipeHorizontal)) ==
                GestureAction.switchDesktop,
        invertHorizontal: read(SessionSetting.gestureInvertHorizontal),
      );
      // The login screen uses the pointers it was started with (GNOME's).
      final String? greeterCursor =
          Platform.environment["PANGOLIN_GREETER"] == "1"
              ? Platform.environment["XCURSOR_THEME"]
              : null;
      _cursorTheme = greeterCursor ?? read(SessionSetting.cursorTheme);
      _cursorSize = greeterCursor != null
          ? int.tryParse(Platform.environment["XCURSOR_SIZE"] ?? "") ?? 24
          : read(SessionSetting.cursorSize).clamp(16, 128);
      for (final _Seat seat in _seats) {
        _applyGestureClaims(seat);
        _applyCursorTheme(seat);
      }
      _schedule(() => _normalizeDesks());
      final double reserved = PangolinSession.taskbarReserved;
      if (reserved != _taskbarReserved) {
        _taskbarReserved = reserved;
        _schedule(_refitToWorkArea);
      }
    }

    prefs.addListener(apply);
    apply();
  }

  // ===========================================================================
  // Public API used by the shell
  // ===========================================================================

  /// Runs [action] in the next manage sequence.
  void _schedule(void Function() action) {
    _pendingActions.add(action);
    _requestManage();
  }

  @override
  void minimizeEverything() => _schedule(() {
        final List<RiverWindow> visible = _deskWindows(_currentDesk)
            .where((w) => !w._minimized)
            .toList();
        _showDesktopMinimized = visible;
        for (final RiverWindow w in visible) {
          _minimize(w, refocus: false, animate: visible.length <= 8);
        }
        _setFocus(null);
      });

  @override
  void unminimizeEverything() => _schedule(() {
        final List<RiverWindow> windows = _showDesktopMinimized ??
            _deskWindows(_currentDesk).where((w) => w._minimized).toList();
        _showDesktopMinimized = null;
        for (final RiverWindow w in windows.where(_stack.contains)) {
          _unminimize(w, animate: windows.length <= 8);
        }
        final RiverWindow? top = _topOfDesk();
        if (top != null) _setFocus(top);
      });

  @override
  Future<void> exitSession() async {
    if (_wm.version >= 4) {
      _wm.exitSession();
      _connection.flush();
    }
  }

  @override
  int deskOf(ShellWindow window) =>
      window is RiverWindow ? window._desk : _currentDesk;

  @override
  void switchDesk(int index) => _schedule(() => _switchDesk(index));

  @override
  void addDesk({bool activate = false}) => _schedule(() {
        if (_deskCount >= _maxDesks) return;
        _deskCount++;
        if (activate) _switchDesk(_deskCount - 1);
        _publishDesks();
      });

  @override
  void removeDesk(int index) => _schedule(() => _removeDesk(index));

  @override
  void moveWindowToDesk(ShellWindow window, int desk) {
    if (window is! RiverWindow) return;
    _schedule(() => _moveToDesk(window, desk));
  }

  @override
  Rect? windowRect(ShellWindow window) =>
      window is RiverWindow && window._width > 0 ? _local(window.rect) : null;

  // ===========================================================================
  // Object lifecycle
  // ===========================================================================

  void _onNewWindow(RiverWindowV1 proxy) {
    final RiverWindow window = RiverWindow._(this, proxy);
    window._desk = _currentDesk;
    _newWindows.add(window);
    _stack.add(window);
    _recency.add(window);

    proxy
      ..onClosed = () {
        _onWindowClosed(window);
      }
      ..onAppId = (appId) {
        window._appId = appId;
        window._notify();
      }
      ..onTitle = (title) {
        window._title = title;
        window._notify();
      }
      ..onParent = (parent) {
        window._parent = parent?.userData as RiverWindow?;
        final RiverWindow? p = window._parent;
        if (p != null) window._desk = p._desk;
      }
      ..onIdentifier = (identifier) {
        window._identifier = identifier;
      }
      ..onUnreliablePid = (pid) {
        window.pid = pid;
      }
      ..onDecorationHint = (hint) {
        if (window._decorationHint != hint) window._decorationChanged = true;
        window._decorationHint = hint;
      }
      ..onDimensionsHint = (minW, minH, maxW, maxH) {
        window._minSize = Size(minW.toDouble(), minH.toDouble());
        window._maxSize = Size(maxW.toDouble(), maxH.toDouble());
      }
      ..onDimensions = (width, height) {
        window._width = width;
        window._height = height;
        window._pendingSize = null;
      }
      ..onMaximizeRequested = () {
        window._request = _WindowRequest.maximize;
      }
      ..onUnmaximizeRequested = () {
        window._request = _WindowRequest.unmaximize;
      }
      ..onMinimizeRequested = () {
        window._request = _WindowRequest.minimize;
      }
      ..onFullscreenRequested = (output) {
        window._request = _WindowRequest.fullscreen;
        window._fullscreenOutput = output;
      }
      ..onExitFullscreenRequested = () {
        window._request = _WindowRequest.exitFullscreen;
      }
      ..onPointerMoveRequested = (seat) {
        final _Seat? s = _seatFor(seat);
        if (s != null) s.pendingOp = _OpRequest.move(window);
      }
      ..onPointerResizeRequested = (seat, edges) {
        final _Seat? s = _seatFor(seat);
        if (s != null) s.pendingOp = _OpRequest.resize(window, edges);
      };
    proxy.userData = window;
  }

  void _onWindowClosed(RiverWindow window) {
    // The close animation runs on the mirror river sent before (see
    // [_onClosingMirror]); one still animating the window ends here.
    window._effectMirror?.destroy();
    window._effectMirror = null;
    final WindowMirror? slideMirror = _slide?.mirrors.remove(window);
    slideMirror?.destroy();

    _stack.remove(window);
    _recency.remove(window);
    _newWindows.remove(window);
    _showDesktopMinimized?.remove(window);
    for (final _Seat seat in _seats) {
      if (seat.op?.window == window) seat.op = null;
      if (seat.pendingOp?.window == window) seat.pendingOp = null;
      if (seat.hovered == window) seat.hovered = null;
    }

    _destroyDecoration(window);
    window.node.destroy();
    window.proxy.destroy();

    if (_focused == window) {
      _focused = null;
      _refocusRequested = true;
    }
    _changed = true;
    _desksDirty = true;
    window.dispose();
  }

  bool _refocusRequested = false;
  bool _desksDirty = false;

  void _onNewOutput(RiverOutputV1 proxy) {
    final _Output output = _Output(proxy);
    _outputs.add(output);

    proxy
      ..onPosition = (x, y) {
        output.x = x;
        output.y = y;
        _changed = true;
      }
      ..onDimensions = (w, h) {
        output.width = w;
        output.height = h;
        _changed = true;
      }
      ..onRemoved = () {
        _outputs.remove(output);
        output.layerShellOutput?.destroy();
        proxy.destroy();
        _changed = true;
      };

    output.layerShellOutput = _layerShell?.getOutput(proxy);
  }

  String _cursorTheme = SessionSetting.cursorTheme.defaultValue;
  int _cursorSize = SessionSetting.cursorSize.defaultValue;

  /// The pointer's theme (Settings > Appearance), river scales it per output.
  void _applyCursorTheme(_Seat seat) {
    if (seat.cursorTheme == (_cursorTheme, _cursorSize)) return;
    seat.cursorTheme = (_cursorTheme, _cursorSize);
    seat.proxy.setXcursorTheme(_cursorTheme, _cursorSize);
    _changed = true;
  }

  void _onNewSeat(RiverSeatV1 proxy) {
    final _Seat seat = _Seat(proxy);
    _seats.add(seat);
    _applyCursorTheme(seat);

    proxy
      ..onRemoved = () {
        _seats.remove(seat);
        seat.dispose();
        proxy.destroy();
      }
      ..onPointerEnter = (window) {
        seat.hovered = window.userData as RiverWindow?;
      }
      ..onPointerLeave = () {
        seat.hovered = null;
      }
      ..onPointerPosition = (x, y) {
        seat.pointerX = x;
        seat.pointerY = y;
        _checkHotCorner(seat);
      }
      ..onWindowInteraction = (window) {
        seat.interacted = window.userData as RiverWindow?;
      }
      ..onOpDelta = (dx, dy) {
        seat.opDx = dx;
        seat.opDy = dy;
      }
      ..onOpRelease = () {
        seat.opReleased = true;
      };

    final RiverLayerShellSeatV1? layerSeat = _layerShell?.getSeat(proxy);
    if (layerSeat != null) {
      seat.layerSeat = layerSeat;
      layerSeat
        ..onFocusExclusive = () {
          _layerFocusExclusive = true;
        }
        ..onFocusNonExclusive = () {
          _layerFocusExclusive = false;
        }
        ..onFocusNone = () {
          _layerFocusExclusive = false;
          _refocusRequested = true;
        };
    }

    final RiverTouchpadGesturesSeatV1? gestures =
        _touchpadGestures?.getSeat(proxy);
    if (gestures != null) {
      seat.gestures = gestures;
      gestures
        ..onSwipeBegin = ((time, fingers) => _gestures.swipeBegin(time))
        ..onSwipeUpdate = ((time, dx, dy) => _gestures.swipeUpdate(time, dx, dy))
        ..onSwipeEnd = ((time, cancelled) =>
            _gestures.swipeEnd(time, cancelled: cancelled != 0))
        ..onPinchBegin = ((time, fingers) => _gestures.pinchBegin(time))
        ..onPinchUpdate = ((time, dx, dy, scale, rotation) =>
            _gestures.pinchUpdate(time, scale))
        ..onPinchEnd = ((time, cancelled) => _gestures.pinchEnd(time));
      _applyGestureClaims(seat);
    }

    _createBindings(seat);
  }

  void _applyGestureClaims(_Seat seat) {
    final RiverTouchpadGesturesSeatV1? gestures = seat.gestures;
    if (gestures == null) return;
    final int mask = _gesturesEnabled ? 1 << _gestureFingers : 0;
    gestures
      ..setSwipeFingers(mask)
      ..setPinchFingers(_pinchClaimed ? mask : 0);
  }

  _Seat? _seatFor(RiverSeatV1 proxy) =>
      _seats.where((s) => s.proxy == proxy).firstOrNull;

  // ===========================================================================
  // Key and pointer bindings
  // ===========================================================================

  void _createBindings(_Seat seat) {
    final RiverXkbBindingsV1? xkb = _xkbBindings;
    if (xkb != null) {
      if (xkb.version >= 2) seat.xkbSeat = xkb.getSeat(seat.proxy);

      void bind(
        int keysym,
        int mods,
        void Function() onPress, {
        void Function()? onRelease,
        void Function()? onStopRepeat,
      }) {
        final RiverXkbBindingV1 binding =
            xkb.getXkbBinding(seat.proxy, keysym, mods);
        binding
          ..onPressed = () {
            _pendingActions.add(onPress);
          }
          ..onReleased = () {
            if (onRelease != null) _pendingActions.add(onRelease);
          }
          ..onStopRepeat = () {
            onStopRepeat?.call();
          };
        seat.keyBindings.add(binding);
      }

      // Tapping Super alone toggles the launcher. Pressing another key while
      // Super is held cancels the tap (river sends stop_repeat).
      for (final int sym in [Keysym.superL, Keysym.superR]) {
        for (final int mods in [Mod.none, Mod.logo]) {
          bind(
            sym,
            mods,
            () => seat.superTap = true,
            onRelease: () {
              if (seat.superTap) _emit(ShellCommand.toggleLauncher);
              seat.superTap = false;
            },
            onStopRepeat: () => seat.superTap = false,
          );
        }
      }

      bind(Keysym.letter('a'), Mod.logo,
          () => _emit(ShellCommand.toggleLauncher));
      bind(
          Keysym.letter('s'), Mod.logo, () => _emit(ShellCommand.toggleSearch));
      bind(Keysym.space, Mod.logo, () => _emit(ShellCommand.toggleSearch));
      bind(Keysym.tab, Mod.logo, () => _emit(ShellCommand.toggleOverview));
      bind(Keysym.letter('l'), Mod.logo, () => _emit(ShellCommand.lockSession));
      bind(
        Keysym.letter('r'),
        Mod.ctrl | Mod.shift | Mod.alt,
        () => _emit(ShellCommand.restartShell),
      );
      bind(Keysym.letter('d'), Mod.logo, _toggleShowDesktop);
      bind(Keysym.letter('e'), Mod.logo, () => _emit(ShellCommand.openFiles));
      bind(
          Keysym.letter('t'), Mod.logo, () => _emit(ShellCommand.openTerminal));
      bind(Keysym.returnKey, Mod.logo, () => _emit(ShellCommand.openTerminal));
      bind(
          Keysym.letter('i'), Mod.logo, () => _emit(ShellCommand.openSettings));
      bind(Keysym.escape, Mod.ctrl | Mod.shift,
          () => _emit(ShellCommand.openActivityMonitor));
      bind(Keysym.delete, Mod.ctrl | Mod.alt,
          () => _emit(ShellCommand.showPowerMenu));
      bind(Keysym.letter('e'), Mod.logo | Mod.shift,
          () => _emit(ShellCommand.showPowerMenu));
      bind(Keysym.print, Mod.none, () => _emit(ShellCommand.screenshot));
      bind(Keysym.print, Mod.shift, () => _emit(ShellCommand.screenshotScreen));
      bind(
        Keysym.letter('s'),
        Mod.logo | Mod.shift,
        () => _emit(ShellCommand.screenshot),
      );

      bind(Keysym.letter('q'), Mod.logo, () => _close(_focused));
      bind(Keysym.f4, Mod.alt, () => _close(_focused));
      bind(Keysym.up, Mod.logo, () {
        final RiverWindow? w = _focused;
        if (w != null && !w._maximized) _morph(w, () => _maximize(w));
      });
      bind(Keysym.down, Mod.logo, () {
        final RiverWindow? w = _focused;
        if (w == null) return;
        if (w._maximized || w._snap != _Snap.none) {
          _morph(w, () => _restoreFloating(w));
        } else {
          _minimize(w);
        }
      });
      bind(Keysym.left, Mod.logo, () => _snapFocused(_Snap.left));
      bind(Keysym.right, Mod.logo, () => _snapFocused(_Snap.right));
      bind(Keysym.letter('f'), Mod.logo | Mod.shift, () {
        final RiverWindow? w = _focused;
        if (w == null) return;
        w._fullscreen ? _exitFullscreen(w) : _enterFullscreen(w, null);
      });

      // Desktops: Super+Ctrl+arrows or Super+PageUp/PageDown switch, with
      // Shift the focused window comes along. Super+Ctrl+D adds a desktop,
      // Super+Ctrl+F4 removes the current one.
      for (final (int prev, int next, int mods) in [
        (Keysym.left, Keysym.right, Mod.logo | Mod.ctrl),
        (Keysym.pageUp, Keysym.pageDown, Mod.logo),
      ]) {
        bind(prev, mods, () => _switchDesk(_currentDesk - 1));
        bind(next, mods, () => _switchDesk(_currentDesk + 1));
        bind(prev, mods | Mod.shift, () => _moveFocusedAndFollow(-1));
        bind(next, mods | Mod.shift, () => _moveFocusedAndFollow(1));
      }
      bind(Keysym.letter('d'), Mod.logo | Mod.ctrl, () {
        if (_deskCount >= _maxDesks) return;
        _deskCount++;
        _switchDesk(_deskCount - 1);
        _publishDesks();
      });
      bind(Keysym.f4, Mod.logo | Mod.ctrl, () => _removeDesk(_currentDesk));

      // Alt+Tab cycles through windows in most-recently-used order. The
      // switcher stays open while Alt is held and commits on release.
      bind(Keysym.tab, Mod.alt, () => _cycleSwitcher(1));
      bind(Keysym.tab, Mod.alt | Mod.shift, () => _cycleSwitcher(-1));

      bind(Keysym.audioRaiseVolume, Mod.none,
          () => _emit(ShellCommand.volumeUp));
      bind(Keysym.audioLowerVolume, Mod.none,
          () => _emit(ShellCommand.volumeDown));
      bind(Keysym.audioMute, Mod.none, () => _emit(ShellCommand.volumeMute));
      bind(Keysym.monBrightnessUp, Mod.none,
          () => _emit(ShellCommand.brightnessUp));
      bind(Keysym.monBrightnessDown, Mod.none,
          () => _emit(ShellCommand.brightnessDown));

      seat.xkbSeat?.onModifiersUpdate = (oldMods, newMods) {
        if (_switcherIndex.value != null && newMods & Mod.alt == 0) {
          _pendingActions.add(_commitSwitcher);
        }
      };
    }

    // Super + drag moves, Super + right drag resizes.
    final RiverPointerBindingV1 move =
        seat.proxy.getPointerBinding(Button.left, Mod.logo);
    move.onPressed = () {
      final RiverWindow? w = seat.hovered;
      if (w != null) seat.pendingOp = _OpRequest.move(w);
    };
    final RiverPointerBindingV1 resize =
        seat.proxy.getPointerBinding(Button.right, Mod.logo);
    resize.onPressed = () {
      final RiverWindow? w = seat.hovered;
      if (w == null) return;
      // Resize from the corner closest to the pointer.
      final bool left = seat.pointerX < w._x + w._width / 2;
      final bool top = seat.pointerY < w._y + w._height / 2;
      seat.pendingOp = _OpRequest.resize(
        w,
        (left ? RiverWindowV1Edges.left : RiverWindowV1Edges.right) |
            (top ? RiverWindowV1Edges.top : RiverWindowV1Edges.bottom),
      );
    };
    seat.pointerBindings.addAll([move, resize]);
    seat.needsEnable = true;
  }

  void _emit(ShellCommand command) {
    // Delivered after the manage sequence so the shell never runs inside it.
    scheduleMicrotask(() => _shellCommands.add(command));
  }

  void _toggleShowDesktop() {
    final List<RiverWindow> desk = _deskWindows(_currentDesk);
    if (desk.any((w) => !w._minimized)) {
      final List<RiverWindow> visible =
          desk.where((w) => !w._minimized).toList();
      _showDesktopMinimized = visible;
      for (final RiverWindow w in visible) {
        _minimize(w, refocus: false, animate: visible.length <= 8);
      }
      _setFocus(null);
    } else {
      final List<RiverWindow> windows = _showDesktopMinimized ?? desk;
      _showDesktopMinimized = null;
      for (final RiverWindow w in windows.where(_stack.contains)) {
        _unminimize(w, animate: windows.length <= 8);
      }
      final RiverWindow? top = _topOfDesk();
      if (top != null) _setFocus(top);
    }
  }

  void _cycleSwitcher(int direction) {
    final int count = _switcherList.length;
    if (count == 0) return;
    final int current = _switcherIndex.value ?? 0;
    _switcherIndex.value = (current + direction) % count;
  }

  void _commitSwitcher() {
    final int? index = _switcherIndex.value;
    _switcherIndex.value = null;
    final List<RiverWindow> windows = _switcherList;
    if (index == null || index >= windows.length) return;
    _activate(windows[index]);
  }

  // ===========================================================================
  // Manage sequence
  // ===========================================================================

  static final bool _profile =
      Platform.environment["PANGOLIN_PROFILE"] != null;

  void _manage() {
    _manageRequested = false;
    final Stopwatch watch = Stopwatch()..start();
    try {
      _manageOutputs();
      _manageSeats();
      _manageNewWindows();
      for (final RiverWindow w in _stack) {
        if (w._decorationChanged) {
          w._decorationChanged = false;
          _manageDecorations(w);
        }
      }
      _manageWindowRequests();
      _manageOperations();

      final List<void Function()> actions = List.of(_pendingActions);
      _pendingActions.clear();
      for (final void Function() action in actions) {
        action();
      }

      if (_desksDirty) {
        _desksDirty = false;
        _normalizeDesks();
      }
      _manageVisibility();
      _manageFocus();
      _applyStacking();
    } catch (e, s) {
      logger.severe("Error in manage sequence", e, s);
    }

    if (_profile && watch.elapsedMicroseconds > 3000) {
      logger.info("slow manage: ${watch.elapsedMicroseconds / 1000}ms");
    }
    _wm.manageFinish();
    _publishChanges();
    if (_remapSurfaces) {
      _remapSurfaces = false;
      // Once river has the new default output (requests of this sequence
      // first): the shell's surfaces move there.
      Timer(const Duration(milliseconds: 150), () {
        unawaited(PangolinSession.remapSurfaces());
      });
    }
  }

  /// Whether a default output was set before (at startup the surfaces
  /// aren't shown yet).
  bool _defaultSet = false;
  bool _remapSurfaces = false;

  void _manageOutputs() {
    final _Output? primary = _primaryOutput;
    if (primary != null && !primary.isDefault) {
      for (final _Output o in _outputs) {
        o.isDefault = false;
      }
      primary.layerShellOutput?.setDefault();
      primary.isDefault = true;
      // The primary output changed (the one before was turned off or
      // unplugged): the shell's surfaces would stay where they were.
      if (_defaultSet) {
        logger.info("Moving the shell to the new primary output");
        _remapSurfaces = true;
      }
      _defaultSet = true;
    }
  }

  void _manageSeats() {
    for (final _Seat seat in _seats) {
      if (!seat.needsEnable) continue;
      seat.needsEnable = false;
      for (final RiverXkbBindingV1 b in seat.keyBindings) {
        b.enable();
      }
      for (final RiverPointerBindingV1 b in seat.pointerBindings) {
        b.enable();
      }
      if (seat.xkbSeat != null && seat.xkbSeat!.version >= 3) {
        seat.xkbSeat!.modifiersWatch(Mod.alt);
      }
    }
  }

  void _manageNewWindows() {
    final Rect area = workArea;
    for (final RiverWindow w in _newWindows) {
      w.proxy
        ..setCapabilities(
          RiverWindowV1Capabilities.maximize |
              RiverWindowV1Capabilities.fullscreen |
              RiverWindowV1Capabilities.minimize,
        )
        ..proposeDimensions(0, 0);
      _manageDecorations(w, initial: true);
      if (w.proxy.version >= 4 && !area.isEmpty) {
        w.proxy.setDimensionBounds(area.width.toInt(), area.height.toInt());
      }
      w._needsPlacement = true;
      // Stay hidden while a mirror animates the window in.
      if (_canAnimate(w)) {
        w._appearPending = true;
        w._effectHidden = true;
      }
      _syncVisibility(w);
      // The initial position of a node in river's render list is undefined:
      // always stack new windows explicitly.
      _raise(w, force: true);
      _setFocus(w);
    }
    if (_newWindows.isNotEmpty) {
      _changed = true;
      _desksDirty = true;
    }
    _newWindows.clear();
  }

  void _manageWindowRequests() {
    for (final RiverWindow w in List.of(_stack)) {
      final _WindowRequest? request = w._request;
      w._request = null;
      switch (request) {
        case _WindowRequest.maximize:
          _morph(w, () => _maximize(w));
        case _WindowRequest.unmaximize:
          _morph(w, () => _restoreFloating(w));
        case _WindowRequest.minimize:
          _minimize(w);
        case _WindowRequest.fullscreen:
          _enterFullscreen(w, w._fullscreenOutput);
        case _WindowRequest.exitFullscreen:
          _exitFullscreen(w);
        case null:
          break;
      }

      // Windows that came up larger than the work area are shrunk to fit.
      if (w._clampPending) {
        w._clampPending = false;
        final Rect area = workArea;
        w.proxy.proposeDimensions(
          math.min(w._width, area.width.toInt()),
          math.min(w._height, area.height.toInt()),
        );
      }
    }

    for (final _Seat seat in _seats) {
      final RiverWindow? interacted = seat.interacted;
      seat.interacted = null;
      if (interacted != null && _stack.contains(interacted)) {
        _raise(interacted);
        _setFocus(interacted);
      }
    }
  }

  void _manageOperations() {
    for (final _Seat seat in _seats) {
      final _OpRequest? request = seat.pendingOp;
      seat.pendingOp = null;
      if (request != null && seat.op == null && !request.window._fullscreen) {
        _startOperation(seat, request);
      }

      final _Operation? op = seat.op;
      if (op == null) continue;

      if (op.isMove) {
        if (seat.opDx.abs() + seat.opDy.abs() >= 4) op.moved = true;
        if (op.restorePending && op.moved) {
          op.restorePending = false;
          _restoreUnderPointer(seat, op);
        }
        if (!op.restorePending) {
          op.window._x = op.startRect.left.toInt() + seat.opDx;
          op.window._y = op.startRect.top.toInt() + seat.opDy;
          _position(op.window);
          _snapPreview.value =
              op.moved ? _snapTargetFor(seat)?.$2 : null;
        }
      } else {
        final Rect r = _resizedRect(op, seat.opDx, seat.opDy);
        op.window.proxy.proposeDimensions(r.width.toInt(), r.height.toInt());
      }

      if (seat.opReleased) {
        seat.opReleased = false;
        seat.proxy.opEnd();
        seat.op = null;
        _snapPreview.value = null;
        if (op.isMove && (op.restorePending || !op.moved)) {
          // A click: nothing moved.
        } else if (op.isMove) {
          final _Snap? snap = _snapTargetFor(seat)?.$1;
          if (snap == _Snap.maximized) {
            _morph(op.window, () => _maximize(op.window));
          } else if (snap != null) {
            _morph(op.window, () => _snap(op.window, snap));
          } else {
            op.window._floatingRect = op.window.rect;
          }
        } else {
          op.window.proxy.informResizeEnd();
          op.window._floatingRect = null; // recorded once dimensions arrive
          op.window._recordFloatingOnRender = true;
        }
      }
    }
  }

  void _startOperation(_Seat seat, _OpRequest request) {
    final RiverWindow w = request.window;
    _raise(w);
    _setFocus(w);

    final _Operation op = _Operation(w, w.rect, request.edges);
    if (request.edges == null && (w._maximized || w._snap != _Snap.none)) {
      op
        ..restorePending = true
        ..restoreRatio = w._width > 0
            ? ((seat.pointerX - w._x) / w._width).clamp(0.0, 1.0)
            : 0.5;
    }

    seat.opDx = 0;
    seat.opDy = 0;
    seat.opReleased = false;
    seat.op = op;
    seat.proxy.opStartPointer();
    if (request.edges != null) w.proxy.informResizeStart();
  }

  /// Dragging a maximized window: restores it under the pointer.
  void _restoreUnderPointer(_Seat seat, _Operation op) {
    final RiverWindow w = op.window;
    final Rect restore = w._floatingRect ?? _defaultFloatingRect(w);
    final int x = (seat.pointerX - restore.width * op.restoreRatio).round();
    // The pointer keeps holding the title bar, above the content when
    // river draws it.
    final int top = _decorationTop(w).toInt();
    final int y =
        math.max(workArea.top.toInt() + top, seat.pointerY - 16 + top);
    final Rect rect = Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      restore.width,
      restore.height,
    );
    _morph(w, () => _setFloating(w, rect));
    // The move goes on from here.
    op.startRect = rect.translate(-seat.opDx.toDouble(), -seat.opDy.toDouble());
  }

  Rect _resizedRect(_Operation op, int dx, int dy) {
    final int edges = op.edges!;
    final Rect start = op.startRect;
    final double minW = math.max(op.window._minSize.width, 120);
    final double minH = math.max(op.window._minSize.height, 80);
    double left = start.left,
        top = start.top,
        right = start.right,
        bottom = start.bottom;
    if (edges & RiverWindowV1Edges.left != 0)
      left = math.min(left + dx, right - minW);
    if (edges & RiverWindowV1Edges.right != 0)
      right = math.max(right + dx, left + minW);
    if (edges & RiverWindowV1Edges.top != 0)
      top = math.min(top + dy, bottom - minH);
    if (edges & RiverWindowV1Edges.bottom != 0)
      bottom = math.max(bottom + dy, top + minH);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  (_Snap, Rect)? _snapTargetFor(_Seat seat) {
    final _Output? output = _primaryOutput;
    if (output == null) return null;
    const int threshold = 4;
    final Rect area = workArea;
    if (seat.pointerY <= output.y + threshold) {
      return (_Snap.maximized, area);
    }
    if (seat.pointerX <= output.x + threshold) {
      return (_Snap.left, _snapRect(_Snap.left));
    }
    if (seat.pointerX >= output.x + output.width - threshold - 1) {
      return (_Snap.right, _snapRect(_Snap.right));
    }
    return null;
  }

  void _manageVisibility() {
    for (final RiverWindow w in _stack) {
      _syncVisibility(w);
    }
  }

  void _manageFocus() {
    if (_layerFocusExclusive) return;

    final RiverWindow? focused = _focused;
    if (focused == null ||
        focused._minimized ||
        focused._desk != _currentDesk ||
        !_stack.contains(focused)) {
      if (_refocusRequested || focused != null) {
        _setFocus(_topOfDesk());
      }
    } else if (_refocusRequested) {
      _setFocus(focused, force: true);
    }
    _refocusRequested = false;
  }

  // ===========================================================================
  // Render sequence
  // ===========================================================================

  void _render() {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Rect area = workArea;
      for (final RiverWindow w in _stack) {
        if (w._width <= 0) continue;

        if (w._needsPlacement) {
          w._needsPlacement = false;
          _place(w, area);
          _position(w);
          logger.fine("Placed $w at ${w.rect} (work area $area)");
          w._mapped = true;
          if (_profile) {
            // CLOCK_MONOTONIC, as the other profile logs: time to window.
            logger.info(
              "window mapped: ${w.appId} at ${Timeline.now ~/ 1000}ms",
            );
          }
          _changed = true;
          if (w._appearPending) {
            w._appearPending = false;
            if (_canAnimate(w)) {
              _animateOpen(w);
            } else {
              w._effectHidden = false;
              _requestManage();
            }
          }
        }

        if (w._recordFloatingOnRender) {
          w._recordFloatingOnRender = false;
          w._floatingRect = w.rect;
        }
      }

      // Interactive resizes anchored on the left/top edge keep the opposite
      // edge in place using the dimensions the window actually took.
      for (final _Seat seat in _seats) {
        final _Operation? op = seat.op;
        if (op == null || op.isMove) continue;
        final int edges = op.edges!;
        final RiverWindow w = op.window;
        if (edges & RiverWindowV1Edges.left != 0) {
          w._x = (op.startRect.right - w._width).round();
        }
        if (edges & RiverWindowV1Edges.top != 0) {
          w._y = (op.startRect.bottom - w._height).round();
        }
        _position(w);
      }

      _renderDecorations();
      _applyStacking();
    } catch (e, s) {
      logger.severe("Error in render sequence", e, s);
    } finally {
      _wm.renderFinish();
    }
    final List<void Function()> after = List.of(_afterRender);
    _afterRender.clear();
    for (final void Function() action in after) {
      action();
    }
    if (_profile && watch.elapsedMicroseconds > 3000) {
      logger.info("slow render: ${watch.elapsedMicroseconds / 1000}ms");
    }
    _publishChanges();
  }

  void _position(RiverWindow w) => w.node.setPosition(w._x, w._y);

  void _place(RiverWindow w, Rect area) {
    final RiverWindow? parent = w._parent;
    Rect rect;
    if (parent != null && _stack.contains(parent)) {
      rect = Rect.fromCenter(
        center: parent.rect.center,
        width: w._width.toDouble(),
        height: w._height.toDouble(),
      );
    } else {
      rect = Rect.fromCenter(
        center: area.center,
        width: w._width.toDouble(),
        height: w._height.toDouble(),
      );
      // Cascade windows that would open exactly on top of another one.
      int guard = 0;
      while (guard++ < 10 &&
          _stack.any(
            (o) =>
                o != w &&
                o._mapped &&
                !o._minimized &&
                o._desk == w._desk &&
                (o._x - rect.left).abs() < 8 &&
                (o._y - rect.top).abs() < 8,
          )) {
        rect = rect.shift(const Offset(32, 32));
      }
    }

    // Keep the titlebar reachable (a server side one sits above the window).
    final double top = area.top + _decorationTop(w);
    final double x = rect.left
        .clamp(area.left, math.max(area.left, area.right - rect.width));
    final double y =
        rect.top.clamp(top, math.max(top, area.bottom - rect.height));
    w._x = x.round();
    w._y = y.round();
    w._floatingRect = w.rect;

    if (w._width > area.width || w._height > area.height) {
      w._clampPending = true;
      _requestManage();
    }
  }

  void _requestManage() {
    if (_manageRequested) return;
    _manageRequested = true;
    _wm.manageDirty();
  }

  // ===========================================================================
  // Window state transitions (manage sequence only)
  // ===========================================================================

  /// Whether river should show [w] right now.
  bool _wantsShown(RiverWindow w) {
    // Mirrors stand in for the windows while the desks slide and in the
    // overview.
    if (_overviewActive || _slide != null) return false;
    if (w._effectHidden || w._minimized) return false;
    return w._desk == _currentDesk;
  }

  void _syncVisibility(RiverWindow w) {
    final bool shown = _wantsShown(w);
    if (shown == w._shown) return;
    w._shown = shown;
    if (shown) {
      w.proxy.show();
    } else {
      w.proxy.hide();
    }
  }

  List<RiverWindow> _deskWindows(int desk) =>
      _stack.where((w) => w._desk == desk).toList();

  RiverWindow? _topOfDesk() => _recency
      .where((w) => !w._minimized && w._desk == _currentDesk)
      .firstOrNull;

  void _raise(RiverWindow w, {bool force = false}) {
    if (!force && _stack.last == w) return;
    _stack
      ..remove(w)
      ..add(w);
    // Dialogs stay above their parent.
    for (final RiverWindow child
        in _stack.where((c) => c._parent == w).toList()) {
      _stack
        ..remove(child)
        ..add(child);
    }
    _stackingDirty = true;
    _changed = true;
  }

  void _applyStacking() {
    if (!_stackingDirty) return;
    _stackingDirty = false;
    for (final RiverWindow w in _stack) {
      w.node.placeTop();
    }
  }

  void _setFocus(RiverWindow? w, {bool force = false}) {
    if (_focused == w && !force) return;
    final RiverWindow? previous = _focused;
    _focused = w;
    if (w != null) {
      _recency
        ..remove(w)
        ..insert(0, w);
    }
    if (_layerFocusExclusive) return;
    for (final _Seat seat in _seats) {
      if (w != null) {
        seat.proxy.focusWindow(w.proxy);
      } else {
        seat.proxy.clearFocus();
      }
    }
    previous?._notify();
    w?._notify();
    _changed = true;
  }

  void _activate(RiverWindow w) {
    if (!_stack.contains(w)) return;
    if (w._desk != _currentDesk) _switchDesk(w._desk);
    _unminimize(w);
    _raise(w);
    _setFocus(w, force: true);
  }

  void _minimize(RiverWindow w, {bool refocus = true, bool animate = true}) {
    if (w._minimized) return;
    w._minimized = true;
    if (animate && _canAnimate(w) && w._shown && w._mapped) {
      _animateMinimize(w);
    }
    _syncVisibility(w);
    w._notify();
    if (refocus && _focused == w) _setFocus(_topOfDesk());
    _changed = true;
  }

  void _unminimize(RiverWindow w, {bool animate = true}) {
    if (!w._minimized) return;
    w._minimized = false;
    if (animate && _canAnimate(w) && w._mapped && w._width > 0) {
      _animateUnminimize(w);
    }
    _syncVisibility(w);
    _raise(w);
    w._notify();
    _changed = true;
  }

  /// Asks [w] to close; river reports it with a mirror to animate once it
  /// does (see [_onClosingMirror]).
  void _close(RiverWindow? w) {
    if (w == null || !_stack.contains(w)) return;
    w.proxy.close();
  }

  Rect _defaultFloatingRect(RiverWindow w) {
    final Rect area = workArea;
    final double width = math.min(area.width * 0.6, 1100);
    final double height = math.min(area.height * 0.7, 760);
    return Rect.fromCenter(center: area.center, width: width, height: height);
  }

  void _proposeSize(RiverWindow w, Size size) {
    w._pendingSize = size;
    w.proxy.proposeDimensions(size.width.toInt(), size.height.toInt());
  }

  void _setFloating(RiverWindow w, Rect rect) {
    if (w._maximized) w.proxy.informUnmaximized();
    w._maximized = false;
    w._snap = _Snap.none;
    w.proxy.setTiled(RiverWindowV1Edges.none);
    _proposeSize(w, rect.size);
    w._x = rect.left.toInt();
    w._y = rect.top.toInt();
    _position(w);
    w._notify();
  }

  void _maximize(RiverWindow w) {
    if (w._fullscreen) return;
    if (!w._maximized && w._snap == _Snap.none) w._floatingRect = w.rect;
    final Rect area = _contentRect(w, workArea);
    w._maximized = true;
    w._snap = _Snap.none;
    w.proxy
      ..informMaximized()
      ..setTiled(
        RiverWindowV1Edges.top |
            RiverWindowV1Edges.bottom |
            RiverWindowV1Edges.left |
            RiverWindowV1Edges.right,
      );
    _proposeSize(w, area.size);
    w._x = area.left.toInt();
    w._y = area.top.toInt();
    _position(w);
    _raise(w);
    w._notify();
    _changed = true;
  }

  void _restoreFloating(RiverWindow w) {
    if (w._fullscreen) _exitFullscreen(w);
    _setFloating(w, w._floatingRect ?? _defaultFloatingRect(w));
    _changed = true;
  }

  Rect _snapRect(_Snap snap) {
    final Rect area = workArea;
    final double half = (area.width / 2).floorToDouble();
    return switch (snap) {
      _Snap.left => Rect.fromLTWH(area.left, area.top, half, area.height),
      _Snap.right => Rect.fromLTWH(
          area.left + half, area.top, area.width - half, area.height),
      _ => area,
    };
  }

  void _snap(RiverWindow w, _Snap snap) {
    if (w._fullscreen) return;
    if (!w._maximized && w._snap == _Snap.none) w._floatingRect = w.rect;
    if (w._maximized) w.proxy.informUnmaximized();
    final Rect rect = _contentRect(w, _snapRect(snap));
    w._maximized = false;
    w._snap = snap;
    w.proxy.setTiled(
      RiverWindowV1Edges.top |
          RiverWindowV1Edges.bottom |
          (snap == _Snap.left
              ? RiverWindowV1Edges.left
              : RiverWindowV1Edges.right),
    );
    _proposeSize(w, rect.size);
    w._x = rect.left.toInt();
    w._y = rect.top.toInt();
    _position(w);
    _raise(w);
    w._notify();
    _changed = true;
  }

  void _snapFocused(_Snap snap) {
    final RiverWindow? w = _focused;
    if (w == null) return;
    if (w._snap == snap) {
      _morph(w, () => _restoreFloating(w));
    } else {
      _morph(w, () => _snap(w, snap));
    }
  }

  void _enterFullscreen(RiverWindow w, RiverOutputV1? requested) {
    final RiverOutputV1? output = requested ?? _primaryOutput?.proxy;
    if (output == null) return;
    w._fullscreen = true;
    w.proxy
      ..fullscreen(output)
      ..informFullscreen();
    _raise(w);
    _setFocus(w);
    w._notify();
    _changed = true;
  }

  void _exitFullscreen(RiverWindow w) {
    if (!w._fullscreen) return;
    w._fullscreen = false;
    w.proxy
      ..exitFullscreen()
      ..informNotFullscreen();
    // Restore the previous geometry in the same manage sequence.
    if (w._maximized) {
      w._maximized = false;
      _maximize(w);
    } else if (w._snap != _Snap.none) {
      final _Snap snap = w._snap;
      w._snap = _Snap.none;
      _snap(w, snap);
    } else {
      final Rect rect = w._floatingRect ?? _defaultFloatingRect(w);
      _proposeSize(w, rect.size);
      w._x = rect.left.toInt();
      w._y = rect.top.toInt();
      _position(w);
    }
    w._notify();
    _changed = true;
  }

  void _publishChanges() {
    if (!_changed) return;
    _changed = false;
    notifyListeners();
  }

  // ===========================================================================
  // Desks
  // ===========================================================================

  void _publishDesks() {
    _desks.value = DeskState(count: _deskCount, current: _currentDesk);
    _changed = true;
  }

  /// Horizontal distance between two desks while sliding.
  double get _deskStride => (_primaryOutput?.width ?? 0) + _deskGap;

  /// Where [w] is drawn while desk [view] (fractional) is shown.
  Rect _deskRect(RiverWindow w, double view) =>
      w.rect.shift(Offset((w._desk - view) * _deskStride, 0));

  /// Switches to [target] (clamped), sliding the desks when animations are
  /// on. Manage sequence only.
  void _switchDesk(int target) {
    final int desk = target.clamp(0, _deskCount - 1);
    if (desk == _currentDesk && _slide == null) return;
    if (_overviewActive ||
        !_animationsEnabled ||
        _effects == null ||
        _primaryOutput == null) {
      _cancelSlide();
      _setCurrentDesk(desk);
      return;
    }
    _slideTo(desk);
  }

  /// Manage sequence only.
  void _setCurrentDesk(int desk) {
    _currentDesk = desk.clamp(0, _deskCount - 1);
    _manageVisibility();
    _refocusRequested = true;
    _desksDirty = true;
    _publishDesks();
  }

  void _moveFocusedAndFollow(int direction) {
    final RiverWindow? w = _focused;
    final int target = _currentDesk + direction;
    if (target < 0) return;
    if (target >= _deskCount) {
      if (_deskCount >= _maxDesks) return;
      _deskCount++;
    }
    if (w != null) _moveToDesk(w, target);
    _switchDesk(target);
    if (w != null) _setFocus(w, force: true);
    _publishDesks();
  }

  void _moveToDesk(RiverWindow w, int desk) {
    if (desk < 0 || desk >= _deskCount || w._desk == desk) return;
    w._desk = desk;
    for (final RiverWindow child in _stack.where((c) => c._parent == w)) {
      child._desk = desk;
    }
    _desksDirty = true;
    _syncVisibility(w);
    if (_focused == w && desk != _currentDesk) _setFocus(_topOfDesk());
    w._notify();
    _changed = true;
  }

  void _removeDesk(int index) {
    if (_deskCount <= 1 || index < 0 || index >= _deskCount) return;
    _cancelSlide();
    final int target = index == 0 ? 1 : index - 1;
    for (final RiverWindow w in _stack) {
      if (w._desk == index) w._desk = target;
    }
    for (final RiverWindow w in _stack) {
      if (w._desk > index) w._desk--;
    }
    _deskCount--;
    if (_currentDesk > index || _currentDesk >= _deskCount) {
      _currentDesk = math.max(0, _currentDesk - 1);
    }
    _refocusRequested = true;
    _publishDesks();
  }

  /// With dynamic desktops (GNOME style) empty desktops other than the current
  /// one disappear and there is always exactly one empty desktop at the end.
  void _normalizeDesks() {
    if (!_dynamicDesks || _slide != null) return;
    bool changed = false;
    for (int d = _deskCount - 2; d >= 0; d--) {
      if (d == _currentDesk || _stack.any((w) => w._desk == d)) continue;
      for (final RiverWindow w in _stack) {
        if (w._desk > d) w._desk--;
      }
      if (_currentDesk > d) _currentDesk--;
      _deskCount--;
      changed = true;
    }
    while (_deskCount > 1 &&
        _currentDesk < _deskCount - 2 &&
        !_stack.any((w) => w._desk == _deskCount - 1) &&
        !_stack.any((w) => w._desk == _deskCount - 2)) {
      _deskCount--;
      changed = true;
    }
    if (_stack.any((w) => w._desk == _deskCount - 1) &&
        _deskCount < _maxDesks) {
      _deskCount++;
      changed = true;
    }
    if (changed) _publishDesks();
  }

  /// Makes sure the windows of desks [from]..[to] have a mirror in [slide],
  /// drawn where they are when desk [view] is shown. Mirrors are created
  /// bottom to top so they stack like the windows.
  void _addSlideMirrors(_Slide slide, int from, int to, double view) {
    for (final RiverWindow w in _stack) {
      if (slide.mirrors.containsKey(w)) continue;
      if (w._desk < from || w._desk > to) continue;
      if (w._minimized || !w._mapped || w._width <= 0) continue;
      final WindowMirror? mirror = _mirror(w);
      if (mirror == null) continue;
      mirror
        ..freeze()
        ..jumpTo(_deskRect(w, view));
      slide.mirrors[w] = mirror;
    }
  }

  /// Slides to desk [target]. The windows are hidden and their mirrors slide
  /// instead, animated by river at the refresh rate of the output. Manage
  /// sequence only.
  void _slideTo(int target, {Cubic curve = MirrorCurves.slide}) {
    final _Slide slide = _slide ??= _Slide(_currentDesk.toDouble());
    final double from = slide.current;
    final double distance = (target - from).abs();
    slide
      ..view = from
      ..target = target
      ..start = DateTime.now()
      ..duration = _scaled(
        Duration(
          milliseconds:
              (320 * math.min(math.max(distance, 0.4), 1.5)).round(),
        ),
      )
      ..curve = curve;

    _addSlideMirrors(
      slide,
      math.min(from.floor(), target),
      math.max(from.ceil(), target),
      from,
    );
    for (final MapEntry(key: w, value: mirror) in slide.mirrors.entries) {
      unawaited(
        mirror.animateTo(
          _deskRect(w, target.toDouble()),
          1,
          duration: slide.duration,
          curve: curve,
        ),
      );
    }
    slide.timer?.cancel();
    slide.timer = Timer(
      slide.duration + const Duration(milliseconds: 16),
      () => _schedule(() => _endSlide(slide)),
    );

    if (_currentDesk != target) {
      // The desk indicator and the taskbar follow right away.
      _currentDesk = target;
      _publishDesks();
    }
    _manageVisibility();
  }

  /// Shows the windows of the new desk in place of the mirrors. Manage
  /// sequence only.
  void _endSlide(_Slide slide) {
    if (_slide != slide) return;
    _cancelSlide();
    _refocusRequested = true;
    _desksDirty = true;
    _publishDesks();
  }

  /// Ends the slide where it is: windows are shown again and the mirrors go
  /// once river has drawn them. Manage sequence only.
  void _cancelSlide() {
    final _Slide? slide = _slide;
    if (slide == null) return;
    slide.timer?.cancel();
    _slide = null;
    _gestureBase = null;
    final List<WindowMirror> mirrors = slide.mirrors.values.toList();
    _afterRender.add(() {
      for (final WindowMirror mirror in mirrors) {
        mirror.destroy();
      }
    });
    _manageVisibility();
  }

  // GestureSink: left/right touchpad swipes move between desks following the
  // fingers, like GNOME. In the overview they switch desks once released.

  int? _gestureBase;
  double _overviewSwipe = 0;

  @override
  void deskSwipeBegin() {
    _overviewSwipe = 0;
    if (_overviewActive ||
        !_animationsEnabled ||
        _effects == null ||
        _primaryOutput == null) {
      return;
    }
    final _Slide slide = _slide ??= _Slide(_currentDesk.toDouble());
    final double view = slide.current;
    slide
      ..timer?.cancel()
      ..view = view
      ..target = null;
    final int base = view.round();
    _gestureBase = base;
    _addSlideMirrors(
      slide,
      math.max(0, base - 1),
      math.min(_deskCount - 1, base + 1),
      view,
    );
    for (final MapEntry(key: w, value: mirror) in slide.mirrors.entries) {
      mirror.jumpTo(_deskRect(w, view));
    }
    // Hide the windows behind the mirrors.
    _requestManage();
  }

  @override
  void deskSwipeUpdate(double offset) {
    _overviewSwipe = offset;
    final _Slide? slide = _slide;
    final int? base = _gestureBase;
    if (slide == null || base == null || slide.target != null) return;
    final double min = math.max(0, base - 1) - 0.08;
    final double max = math.min(_deskCount - 1, base + 1) + 0.08;
    slide.view = (base + offset).clamp(min, max);
    for (final MapEntry(key: w, value: mirror) in slide.mirrors.entries) {
      mirror.jumpTo(_deskRect(w, slide.view));
    }
  }

  @override
  void deskSwipeEnd(double velocity, {required bool cancelled}) {
    final int? base = _gestureBase;
    _gestureBase = null;
    if (base == null) {
      final double projected = _overviewSwipe + velocity * 0.15;
      if (_overviewActive && !cancelled && projected.abs() > 0.3) {
        switchDesk(_currentDesk + (projected > 0 ? 1 : -1));
      }
      return;
    }
    _schedule(() {
      final _Slide? slide = _slide;
      if (slide == null) return;
      int target = base;
      if (!cancelled) {
        final double projected = slide.view + velocity * 0.15;
        target = projected.round().clamp(
              math.max(0, base - 1),
              math.min(_deskCount - 1, base + 1),
            );
      }
      _slideTo(target, curve: MirrorCurves.slideRelease);
    });
  }

  // Up/down swipes go to the shell, which decides what follows them.

  @override
  void verticalSwipeBegin(double offset) =>
      _verticalSwipes.add(VerticalSwipe.begin(offset));

  @override
  void verticalSwipeUpdate(double offset) =>
      _verticalSwipes.add(VerticalSwipe.update(offset));

  @override
  void verticalSwipeEnd(double velocity, {required bool cancelled}) =>
      _verticalSwipes.add(VerticalSwipe.end(0, velocity, cancelled: cancelled));

  @override
  void pinch({required bool inward}) =>
      _emit(inward ? ShellCommand.gesturePinchIn : ShellCommand.gesturePinchOut);

  // ===========================================================================
  // Window animations
  // ===========================================================================
  //
  // Every animation draws a mirror of the window (river-window-effects-v1)
  // above the windows: no pixels are copied and river runs the animation
  // itself at the refresh rate of the outputs. A mirror covers its window as
  // soon as river receives the request, so the window can be hidden in the
  // same manage sequence without a gap; a window is shown again before its
  // mirror is dropped (see [_afterRender]).

  bool _canAnimate(RiverWindow w) =>
      _animationsEnabled &&
      _effects != null &&
      !w._fullscreen &&
      w._desk == _currentDesk &&
      _slide == null &&
      !_overviewActive;

  Duration _scaled(Duration duration) => duration * _animationSpeed;

  WindowMirror? _mirror(RiverWindow w) {
    final RiverWindowEffectsV1? effects = _effects;
    if (effects == null) return null;
    return WindowMirror(effects.getMirror(w.proxy));
  }

  /// A mirror for a new animation of [w], replacing the previous one.
  WindowMirror? _newEffectMirror(RiverWindow w) {
    final WindowMirror? previous = w._effectMirror;
    final WindowMirror? mirror = _mirror(w);
    w._effectMirror = mirror;
    // The new mirror is drawn above the old one once it is placed.
    if (previous != null) scheduleMicrotask(previous.destroy);
    return mirror;
  }

  void _dropEffectMirror(RiverWindow w, WindowMirror mirror) {
    if (w._effectMirror == mirror) w._effectMirror = null;
    mirror.destroy();
  }

  /// Shows [w] again in place of [mirror], then drops the mirror once river
  /// has applied the change.
  void _revealFrom(RiverWindow w, WindowMirror mirror) {
    _schedule(() {
      if (w._effectMirror != mirror) return;
      w._effectMirror = null;
      w._effectHidden = false;
      _syncVisibility(w);
      _afterRender.add(mirror.destroy);
    });
  }

  /// The taskbar button of [w] (layout coordinates), or the middle of the
  /// taskbar.
  Rect _taskbarRect(RiverWindow w) {
    final Rect? rect = TaskbarGeometry.rectFor(w.id);
    if (rect != null) return _global(rect);
    final _Output? output = _primaryOutput;
    final double x = output?.x.toDouble() ?? 0;
    final double y = output?.y.toDouble() ?? 0;
    final double width = output?.width.toDouble() ?? 1280;
    final double height = output?.height.toDouble() ?? 720;
    return Rect.fromCenter(
      center: Offset(x + width / 2, y + height - PangolinSession.taskbarHeight / 2),
      width: 40,
      height: 40,
    );
  }

  /// [w] shrunk into its taskbar button.
  Rect _minimizedRect(RiverWindow w) {
    final Rect button = _taskbarRect(w);
    return Rect.fromCenter(
      center: button.center,
      width: math.max(w._width * 0.1, 24),
      height: math.max(w._height * 0.1, 16),
    );
  }

  /// Fades and scales a new window in (Chromium OS "window open"). Render
  /// sequence, right after the window is placed.
  void _animateOpen(RiverWindow w) {
    final WindowMirror? mirror = _newEffectMirror(w);
    if (mirror == null) {
      _schedule(() {
        w._effectHidden = false;
        _syncVisibility(w);
      });
      return;
    }
    final Rect rect = w.rect;
    mirror.jumpTo(scaleRect(rect, 0.9), 0);
    unawaited(
      mirror
          .animateTo(
            rect,
            1,
            duration: _scaled(const Duration(milliseconds: 200)),
            curve: MirrorCurves.open,
          )
          .then((done) => done ? _revealFrom(w, mirror) : null),
    );
  }

  /// Shrinks the window into its taskbar button. Manage sequence only.
  void _animateMinimize(RiverWindow w) {
    final WindowMirror? mirror = _newEffectMirror(w);
    if (mirror == null) return;
    mirror
      ..freeze()
      ..jumpTo(w.rect);
    unawaited(
      mirror
          .animateTo(
            _minimizedRect(w),
            0,
            duration: _scaled(const Duration(milliseconds: 250)),
            curve: MirrorCurves.minimize,
          )
          .whenComplete(() => _dropEffectMirror(w, mirror)),
    );
  }

  /// Grows the window out of its taskbar button. Manage sequence only.
  void _animateUnminimize(RiverWindow w) {
    final WindowMirror? mirror = _newEffectMirror(w);
    if (mirror == null) return;
    w._effectHidden = true;
    mirror.jumpTo(_minimizedRect(w), 0);
    unawaited(
      mirror
          .animateTo(
            w.rect,
            1,
            duration: _scaled(const Duration(milliseconds: 240)),
            curve: MirrorCurves.unminimize,
          )
          .then((done) => done ? _revealFrom(w, mirror) : null),
    );
  }

  /// Applies a geometry [change] (maximize, snap, restore) with a cross-fade
  /// of the old content into the new bounds, like Chromium OS. Manage
  /// sequence only.
  void _morph(RiverWindow w, void Function() change) {
    if (!_canAnimate(w) || w._minimized || !w._mapped || !w._shown) {
      change();
      return;
    }
    final WindowMirror? mirror = _newEffectMirror(w);
    if (mirror == null) {
      change();
      return;
    }
    mirror
      ..freeze()
      ..jumpTo(w.rect);
    change();
    final Size size =
        w._pendingSize ?? Size(w._width.toDouble(), w._height.toDouble());
    unawaited(
      mirror
          .animateTo(
            Rect.fromLTWH(
              w._x.toDouble(),
              w._y.toDouble(),
              size.width,
              size.height,
            ),
            0,
            duration: _scaled(const Duration(milliseconds: 240)),
            curve: MirrorCurves.morph,
          )
          .whenComplete(() => _dropEffectMirror(w, mirror)),
    );
  }

  /// river reports every window that closes with a mirror of its last frame:
  /// fade it out where the window was (Chromium OS "window close").
  void _onClosingMirror(
    RiverWindowMirrorV1 proxy,
    RiverWindowV1 window,
    int x,
    int y,
    int width,
    int height,
  ) {
    final WindowMirror mirror = WindowMirror(proxy);
    final RiverWindow? w = window.userData as RiverWindow?;
    if (w == null ||
        !_canAnimate(w) ||
        !w._shown ||
        !w._mapped ||
        width <= 0 ||
        height <= 0 ||
        _coveredByOtherWindows(w)) {
      mirror.destroy();
      return;
    }
    final Rect rect = Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
    mirror.jumpTo(rect);
    unawaited(
      mirror
          .animateTo(
            scaleRect(rect, 0.9),
            0,
            duration: _scaled(const Duration(milliseconds: 160)),
            curve: MirrorCurves.close,
          )
          .whenComplete(mirror.destroy),
    );
  }

  /// Mirrors are drawn above every window: a closing window partly hidden by
  /// others is not animated.
  bool _coveredByOtherWindows(RiverWindow w) {
    final int index = _stack.indexOf(w);
    if (index < 0) return true;
    return _stack
        .skip(index + 1)
        .any((o) => o._shown && o._width > 0 && o.rect.overlaps(w.rect));
  }

  // ===========================================================================
  // Overview
  // ===========================================================================

  bool _overviewActive = false;
  int _overviewGeneration = 0;

  /// Mirrors shown by the overview, by window and whether they are the small
  /// copy in a desk thumbnail.
  final Map<(RiverWindow, bool), WindowMirror> _overviewMirrors = {};
  final Map<(RiverWindow, bool), Rect?> _overviewHiddenRects = {};

  /// Where each mirror is in the overview (layout coordinates).
  final Map<(RiverWindow, bool), Rect> _overviewTargets = {};
  RiverWindow? _overviewHighlight;

  @override
  bool get supportsOverview => _effects != null;

  /// Where the mirror of [w] is (and how opaque) when the overview is
  /// closed: on its window, in its taskbar button when minimized, faded out
  /// when on another desk.
  (Rect, double) _overviewRest(
    RiverWindow w, {
    required bool thumbnail,
    required Rect target,
    Rect? hidden,
  }) {
    if (thumbnail) return hidden != null ? (hidden, 1) : (target, 0);
    if (w._desk == _currentDesk && !w._minimized) return (w.rect, 1);
    if (w._desk == _currentDesk && w._minimized) return (_minimizedRect(w), 0);
    return (scaleRect(target, 0.9), 0);
  }

  @override
  void showOverview(
    List<OverviewSlot> slots, {
    required Duration duration,
    double? progress,
    bool fadeThumbnails = false,
  }) {
    if (_effects == null) return;
    final bool entering = !_overviewActive;
    _overviewActive = true;
    _overviewGeneration++;

    final Map<(RiverWindow, bool), OverviewSlot> wanted = {
      for (final OverviewSlot slot in slots)
        if (slot.window case final RiverWindow w when _stack.contains(w))
          (w, slot.thumbnail): slot,
    };

    for (final (RiverWindow, bool) key in _overviewMirrors.keys.toList()) {
      if (wanted.containsKey(key)) continue;
      final WindowMirror mirror = _overviewMirrors.remove(key)!;
      _overviewHiddenRects.remove(key);
      _overviewTargets.remove(key);
      unawaited(
        mirror
            .animateTo(
              scaleRect(mirror.rect, 0.9),
              0,
              duration: _scaled(const Duration(milliseconds: 180)),
              curve: MirrorCurves.close,
            )
            .whenComplete(mirror.destroy),
      );
    }

    final List<MapEntry<(RiverWindow, bool), OverviewSlot>> ordered =
        wanted.entries.toList()
          ..sort(
            (a, b) =>
                _stack.indexOf(a.key.$1).compareTo(_stack.indexOf(b.key.$1)),
          );
    for (final MapEntry(key: key, value: slot) in ordered) {
      final RiverWindow w = key.$1;
      final Rect target = _global(slot.rect);
      final Rect? hidden =
          slot.hiddenRect == null ? null : _global(slot.hiddenRect!);
      _overviewHiddenRects[key] = hidden;
      _overviewTargets[key] = target;
      final (Rect, double) rest = entering || progress != null
          ? _overviewRest(
              w,
              thumbnail: slot.thumbnail,
              target: target,
              hidden: fadeThumbnails && progress == null ? null : hidden,
            )
          : (scaleRect(target, 0.9), 0.0);
      WindowMirror? mirror = _overviewMirrors[key];
      if (mirror == null) {
        mirror = _mirror(w);
        if (mirror == null) continue;
        // Thumbnails don't need to follow the windows.
        if (slot.thumbnail) mirror.freeze();
        _overviewMirrors[key] = mirror;
        mirror.jumpTo(rest.$1, rest.$2);
      }
      if (progress != null) {
        mirror.jumpTo(
          Rect.lerp(rest.$1, target, progress)!,
          rest.$2 + (1 - rest.$2) * progress,
        );
      } else {
        unawaited(
          mirror.animateTo(
            _overviewHighlight == w && !slot.thumbnail
                ? _lifted(target)
                : target,
            1,
            duration: _scaled(duration),
            curve: MirrorCurves.overview,
          ),
        );
      }
    }

    if (entering) {
      // Window animations end where they are: the overview mirrors cover them.
      for (final RiverWindow w in _stack) {
        final WindowMirror? effect = w._effectMirror;
        w._effectMirror = null;
        w._effectHidden = false;
        if (effect != null) scheduleMicrotask(effect.destroy);
      }
      _schedule(_cancelSlide);
    }
  }

  @override
  void trackOverview(double progress) {
    if (!_overviewActive) return;
    // A gesture takes over from whatever animation was running.
    _overviewGeneration++;
    for (final MapEntry(key: key, value: mirror) in _overviewMirrors.entries) {
      final Rect? target = _overviewTargets[key];
      if (target == null) continue;
      final (Rect rect, double opacity) = _overviewRest(
        key.$1,
        thumbnail: key.$2,
        target: target,
        hidden: _overviewHiddenRects[key],
      );
      mirror.jumpTo(
        Rect.lerp(rect, target, progress)!,
        opacity + (1 - opacity) * progress,
      );
    }
  }

  /// [rect] grown a little, for the window under the pointer.
  Rect _lifted(Rect rect) => rect.inflate(
        math.min(10, math.max(rect.width, rect.height) * 0.025),
      );

  @override
  void highlightOverview(ShellWindow? window) {
    final RiverWindow? w = window is RiverWindow ? window : null;
    if (w == _overviewHighlight) return;
    final RiverWindow? previous = _overviewHighlight;
    _overviewHighlight = w;
    if (!_overviewActive) return;
    for (final RiverWindow? changed in [previous, w]) {
      if (changed == null) continue;
      final WindowMirror? mirror = _overviewMirrors[(changed, false)];
      final Rect? target = _overviewTargets[(changed, false)];
      if (mirror == null || target == null) continue;
      unawaited(
        mirror.animateTo(
          changed == w ? _lifted(target) : target,
          1,
          duration: _scaled(const Duration(milliseconds: 160)),
          curve: MirrorCurves.overview,
        ),
      );
    }
  }

  @override
  void hideOverview({
    ShellWindow? activate,
    required Duration duration,
    bool fadeThumbnails = false,
  }) {
    if (!_overviewActive) return;
    final int generation = ++_overviewGeneration;
    final RiverWindow? target = activate is RiverWindow ? activate : null;

    _schedule(() {
      if (generation != _overviewGeneration) return;
      if (target != null && _stack.contains(target)) {
        if (target._desk != _currentDesk) _setCurrentDesk(target._desk);
        if (target._minimized) {
          target._minimized = false;
          target._notify();
        }
        _raise(target);
        _setFocus(target, force: true);
      }

      // The windows' mirrors go back to their windows, stacked like them.
      for (final RiverWindow w in _stack) {
        _overviewMirrors[(w, false)]?.placeTop();
      }
      final Duration scaled = _scaled(duration);
      _overviewHighlight = null;
      for (final MapEntry(key: key, value: mirror)
          in _overviewMirrors.entries) {
        final (Rect, double) to = _overviewRest(
          key.$1,
          thumbnail: key.$2,
          target: _overviewTargets[key] ?? mirror.rect,
          hidden: fadeThumbnails ? null : _overviewHiddenRects[key],
        );
        unawaited(
          mirror.animateTo(
            to.$1,
            to.$2,
            duration: scaled,
            curve: MirrorCurves.overview,
          ),
        );
      }

      Timer(scaled + const Duration(milliseconds: 16), () {
        _schedule(() {
          if (generation != _overviewGeneration) return;
          _overviewActive = false;
          _manageVisibility();
          _refocusRequested = true;
          final List<WindowMirror> mirrors = _overviewMirrors.values.toList();
          _overviewMirrors.clear();
          _overviewHiddenRects.clear();
          _overviewTargets.clear();
          _afterRender.add(() {
            for (final WindowMirror mirror in mirrors) {
              mirror.destroy();
            }
          });
          _changed = true;
        });
      });
    });
  }
}

/// Desks sliding horizontally. The windows are hidden while mirrors of the
/// windows involved slide instead.
class _Slide {
  _Slide(this.view);

  /// Desk position (fractional) shown when the current animation started, or
  /// while following a gesture.
  double view;

  /// Desk the slide goes to; null while following a gesture.
  int? target;
  DateTime start = DateTime.now();
  Duration duration = Duration.zero;
  Cubic curve = MirrorCurves.slide;
  final Map<RiverWindow, WindowMirror> mirrors = {};
  Timer? timer;

  /// Desk position drawn right now (river runs the same curve).
  double get current {
    final int? to = target;
    if (to == null || duration <= Duration.zero) return view;
    final double t = (DateTime.now().difference(start).inMicroseconds /
            duration.inMicroseconds)
        .clamp(0.0, 1.0);
    return view + (to - view) * curve.transform(t);
  }
}

/// A Wayland window (xdg_toplevel or Xwayland) managed through river.
class RiverWindow extends ShellWindow {
  RiverWindow._(this._service, this.proxy) : node = proxy.getNode();

  final RiverWindowManagerService _service;
  final RiverWindowV1 proxy;
  final RiverNodeV1 node;

  String? _identifier;
  String? _appId;
  String? _title;
  RiverWindow? _parent;
  int? pid;

  int _x = 0;
  int _y = 0;
  int _width = 0;
  int _height = 0;
  Size _minSize = Size.zero;
  // ignore: unused_field
  Size _maxSize = Size.zero;
  // ignore: unused_field
  int? _decorationHint;
  bool _decorationChanged = false;
  _Decoration? _decoration;

  /// Size proposed to the window and not taken yet.
  Size? _pendingSize;

  bool _mapped = false;
  bool _needsPlacement = false;
  bool _clampPending = false;
  bool _recordFloatingOnRender = false;

  bool _minimized = false;
  bool _maximized = false;
  bool _fullscreen = false;
  _Snap _snap = _Snap.none;

  int _desk = 0;

  /// Whether river was last told to show the window.
  bool _shown = true;

  /// Hidden while a mirror animates in its place.
  bool _effectHidden = false;

  bool _appearPending = false;

  /// Mirror of the window animation running (open, minimize, ...).
  WindowMirror? _effectMirror;

  /// Geometry to return to when leaving maximized/snapped/fullscreen state.
  Rect? _floatingRect;

  _WindowRequest? _request;
  RiverOutputV1? _fullscreenOutput;

  @override
  String get id => _identifier ?? "river-${proxy.id}";

  @override
  String? get appId => _appId;

  @override
  String get title => _title ?? _appId ?? "";

  @override
  ShellWindow? get parent => _parent;

  @override
  bool get minimized => _minimized;

  @override
  bool get maximized => _maximized || _snap != _Snap.none;

  @override
  bool get fullscreen => _fullscreen;

  @override
  bool get focused => _service._focused == this && !_minimized;

  /// Content position and size in the compositor's logical coordinates.
  Rect get rect => Rect.fromLTWH(
        _x.toDouble(),
        _y.toDouble(),
        _width.toDouble(),
        _height.toDouble(),
      );

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void activate() => _service._schedule(() => _service._activate(this));

  @override
  void minimize() => _service._schedule(() => _service._minimize(this));

  @override
  void toggleMaximize() => _service._schedule(() {
        if (_maximized || _snap != _Snap.none) {
          _service._morph(this, () => _service._restoreFloating(this));
        } else {
          _service._morph(this, () => _service._maximize(this));
        }
      });

  @override
  void close() => _service._schedule(() => _service._close(this));

  @override
  String toString() => "RiverWindow($id, $_appId, \"$_title\")";
}

enum _Snap { none, left, right, maximized }

enum _WindowRequest {
  maximize,
  unmaximize,
  minimize,
  fullscreen,
  exitFullscreen
}

class _OpRequest {
  _OpRequest.move(this.window) : edges = null;
  _OpRequest.resize(this.window, int this.edges);

  final RiverWindow window;
  final int? edges;
}

class _Operation {
  _Operation(this.window, this.startRect, this.edges);

  final RiverWindow window;
  Rect startRect;
  final int? edges;

  /// A maximized or snapped window being moved: it's restored once the
  /// pointer actually moves (a click alone leaves it be), keeping the
  /// grabbed point ([restoreRatio] of its width) under the pointer.
  bool restorePending = false;
  double restoreRatio = 0.5;

  /// Whether the pointer moved at all.
  bool moved = false;

  bool get isMove => edges == null;
}

class _Output {
  _Output(this.proxy);

  final RiverOutputV1 proxy;
  RiverLayerShellOutputV1? layerShellOutput;
  bool isDefault = false;
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
}

class _Seat {
  _Seat(this.proxy);

  final RiverSeatV1 proxy;
  RiverXkbBindingsSeatV1? xkbSeat;
  RiverLayerShellSeatV1? layerSeat;
  RiverTouchpadGesturesSeatV1? gestures;
  final List<RiverXkbBindingV1> keyBindings = [];
  final List<RiverPointerBindingV1> pointerBindings = [];
  bool needsEnable = false;
  (String, int)? cursorTheme;

  RiverWindow? hovered;
  RiverWindow? interacted;
  int pointerX = 0;
  int pointerY = 0;

  /// The hot corner the pointer is in.
  Alignment? corner;

  bool superTap = false;

  _OpRequest? pendingOp;
  _Operation? op;
  int opDx = 0;
  int opDy = 0;
  bool opReleased = false;

  void dispose() {
    for (final RiverXkbBindingV1 b in keyBindings) {
      b.destroy();
    }
    for (final RiverPointerBindingV1 b in pointerBindings) {
      b.destroy();
    }
    xkbSeat?.destroy();
    layerSeat?.destroy();
    gestures?.destroy();
  }
}
