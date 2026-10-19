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
import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/components/overlays/notifications/queue.dart';
import 'package:pangolin/components/shell/osd.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/widgets/input_region.dart';

/// How much of the shell surface river draws.
///
/// The shell surface is transparent, above every window and as large as the
/// screen. Whenever river composites the screen again (a window moving, the
/// overview) it blends all of it, transparent or not: at 4K with fractional
/// scaling that's a 5120x2880 texture per frame. So river only draws the
/// strip along the bottom edge (the taskbar and room for its tooltips)
/// unless something else is on screen: overlays, menus, notifications, the
/// volume popup, the snap preview, the window switcher. The surface keeps its
/// size (river clips it, river-blur-v1 set_visible_area): no reallocation
/// and no relayout when that changes.
class ShellSurfaceArea with WidgetsBindingObserver {
  ShellSurfaceArea._();

  static final ShellSurfaceArea instance = ShellSurfaceArea._();
  static final Logger _logger = Logger("ShellSurfaceArea");

  /// Above the taskbar: tooltips of its buttons.
  static const double _tooltipRoom = 48;

  /// Back to the strip once nothing else was shown for this long (switching
  /// costs nothing, this only avoids flapping).
  static const Duration _idle = Duration(milliseconds: 250);

  bool _started = false;
  bool _full = true;
  Rect? _sent;
  bool _hasSent = false;
  Timer? _compactTimer;

  /// Set while the shell draws nothing but the taskbar although an overlay
  /// is open (the overview while river animates it).
  bool get quiet => _quiet;
  bool _quiet = false;
  set quiet(bool value) {
    if (value == _quiet) return;
    _quiet = value;
    if (_started) _update();
  }

  void start() {
    if (_started || !PangolinSession.isSession) return;
    _started = true;
    final WindowManagerService wm = WindowManagerService.current;
    for (final Listenable source in [
      ShellOverlayState.anyVisible,
      ShellInputRegion.instance.modal,
      NotificationQueue.active,
      Osd.instance,
      wm.snapPreview,
      wm.switcherIndex,
      PreferencesService.current,
      PangolinSession.tints,
    ]) {
      source.addListener(_update);
    }
    WidgetsBinding.instance.addObserver(this);
    _update();
  }

  // The screen changed size.
  @override
  void didChangeMetrics() => _update();

  bool get _needsFull {
    if (_quiet) return false;
    final WindowManagerService wm = WindowManagerService.current;
    return ShellOverlayState.anyVisible.value ||
        ShellInputRegion.instance.modal.value ||
        NotificationQueue.active.value ||
        Osd.instance.visible ||
        wm.snapPreview.value != null ||
        wm.switcherIndex.value != null;
  }

  void _update() {
    if (_needsFull) {
      _compactTimer?.cancel();
      _compactTimer = null;
      _apply(full: true);
    } else if (_full && !_quiet) {
      _compactTimer ??= Timer(_idle, () {
        _compactTimer = null;
        if (!_needsFull) _apply(full: false);
      });
    } else {
      _compactTimer?.cancel();
      _compactTimer = null;
      // Also when the taskbar or the screen changed size.
      _apply(full: false);
    }
  }

  /// The strip along the bottom edge, in shell surface coordinates.
  Rect? get _strip {
    final ui.FlutterView? shell = _view(PangolinSession.shellViewId);
    if (shell == null) return null;
    final Size size = shell.physicalSize / shell.devicePixelRatio;
    final double height =
        (PangolinSession.taskbarHeight + _tooltipRoom).ceilToDouble();
    return Rect.fromLTWH(0, size.height - height, size.width, height);
  }

  void _apply({required bool full}) {
    _full = full;
    final Rect? area = full ? null : _strip;
    if (_hasSent && area == _sent) return;
    // Nothing to undo before the first strip.
    if (!_hasSent && area == null) return;
    _hasSent = true;
    _sent = area;
    unawaited(_send(area));
  }

  Future<void> _send(Rect? area) async {
    try {
      await PangolinSession.setShellVisibleArea(area);
    } on PlatformException catch (e) {
      _logger.warning("Couldn't set the visible area of the shell: $e");
    }
  }

  /// Makes river draw the whole shell surface, right away (before what opens
  /// next draws its first frame).
  Future<void> ensureFull() async {
    if (!_started) return;
    _compactTimer?.cancel();
    _compactTimer = null;
    _apply(full: true);
  }

  static ui.FlutterView? _view(int? id) => id == null
      ? null
      : ui.PlatformDispatcher.instance.views
          .where((v) => v.viewId == id)
          .firstOrNull;
}
