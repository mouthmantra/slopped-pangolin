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
import 'dart:ui';

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:zenit_ui/zenit_ui.dart' show ZenitBlur;

enum SessionMode {
  /// Pangolin is the desktop shell of a Wayland session: the desktop and the
  /// shell are rendered to separate layer-shell surfaces and app windows are
  /// real Wayland clients managed by Pangolin's window manager.
  session,

  /// The whole shell is rendered inside a single window (web, development on
  /// another desktop, compositors without layer-shell).
  windowed,
}

enum KeyboardMode { none, exclusive, onDemand }

/// Bridge to the native runner that owns the session surfaces.
///
/// See linux/my_application.cc for the other side of the channel.
class PangolinSession {
  PangolinSession._();

  static const MethodChannel _channel =
      MethodChannel("io.dahliaos.pangolin/session");

  static SessionMode _mode = SessionMode.windowed;
  static int? _desktopViewId;
  static int? _shellViewId;

  static SessionMode get mode => _mode;
  static bool get isSession => _mode == SessionMode.session;

  /// Flutter view rendering the wallpaper on the BACKGROUND layer.
  static int? get desktopViewId => _desktopViewId;

  /// Flutter view rendering the taskbar and overlays on the TOP layer.
  static int? get shellViewId => _shellViewId;

  /// Height of the taskbar, which the window manager keeps free of windows.
  static const double taskbarHeight = 48;

  /// Exit status that asks the session's init script to start the shell
  /// again (Ctrl+Shift+Alt+R), as opposed to a sign out (0) or a crash.
  static const int restartExitCode = 75;

  /// Whether the session's init script restarted the shell after a crash
  /// (first-run UI such as the welcome screen is skipped then).
  static bool get isRestart =>
      Platform.environment["PANGOLIN_SHELL_RESTART"] == "1";

  static Future<void> init() async {
    if (kIsWeb) return;

    try {
      final Map<Object?, Object?>? info =
          await _channel.invokeMapMethod<Object?, Object?>("getSessionInfo");
      if (info == null || info["mode"] != "session") return;
      _channel.setMethodCallHandler((call) async {
        _nativeHandlers[call.method]?.call(call.arguments);
        return null;
      });

      _desktopViewId = info["desktopView"] as int?;
      _shellViewId = info["shellView"] as int?;
      _mode = SessionMode.session;

      // Frosted glass from river (river-blur-v1).
      ZenitBlur.sink = (view, regions) => _channel.invokeMethod(
            "setBlurRegions",
            {"view": view, "regions": regions.map((r) => r.encode()).toList()},
          );
      ZenitBlur.available.value =
          await _channel.invokeMethod<bool>("blurSupported") ?? false;
      partAnimations.value =
          await _channel.invokeMethod<bool>("animationsSupported") ?? false;
    } on MissingPluginException {
      // Running on a platform without the Pangolin runner.
    }
  }

  static final Map<String, void Function(Object? arguments)> _nativeHandlers =
      {};

  /// Handles [method] calls made by the runner (e.g. lock state changes).
  static void onNativeCall(
    String method,
    void Function(Object? arguments) handler,
  ) {
    _nativeHandlers[method] = handler;
  }

  /// Whether the compositor supports ext-session-lock-v1.
  static Future<bool> lockSupported() async {
    if (!isSession) return false;
    return await _channel.invokeMethod<bool>("lockSupported") ?? false;
  }

  /// Locks the session; returns whether locking started and the lock
  /// screen views.
  static Future<(bool, List<int>)> lock() async {
    final Map<Object?, Object?>? result =
        await _channel.invokeMapMethod<Object?, Object?>("lock");
    return (
      result?["started"] == true,
      [for (final Object? id in (result?["views"] as List?) ?? const []) id! as int],
    );
  }

  static Future<void> unlock() => _channel.invokeMethod("unlock");

  /// Whether river animates parts of the session surfaces (popups opening
  /// and closing) at the refresh rate of the outputs.
  static final ValueNotifier<bool> partAnimations = ValueNotifier(false);

  /// Animates [rect] (logical coordinates of [view]) into view from, or out
  /// of view to, the given state: scaled by [scale] around its center, moved
  /// by [offset], faded to [opacity]. Completes once river has the request:
  /// only frames drawn after that are animated.
  static Future<void> animatePart({
    required int view,
    required bool reveal,
    required Rect rect,
    Offset offset = Offset.zero,
    double scale = 1,
    double opacity = 0,
    required Duration duration,
    required Cubic curve,
  }) async {
    if (!partAnimations.value) return;
    int fixed(double value) => (value * 10000).round();
    try {
      await _channel.invokeMethod("animatePart", {
        "view": view,
        "values": [
          if (reveal) 1 else 0,
          rect.left.floor(),
          rect.top.floor(),
          rect.width.ceil(),
          rect.height.ceil(),
          offset.dx.round(),
          offset.dy.round(),
          fixed(scale),
          fixed(opacity.clamp(0.0, 1.0)),
          duration.inMilliseconds,
          fixed(curve.a),
          fixed(curve.b),
          fixed(curve.c),
          fixed(curve.d),
        ],
      }).timeout(const Duration(milliseconds: 200));
    } on TimeoutException {
      // Drawn without the animation.
    } on PlatformException {
      // Same.
    }
  }

  /// Maps the session surfaces. Must only be called once the window manager
  /// is bound, as river closes layer surfaces created before that.
  /// Maps the session surfaces; without [desktop], only the shell's.
  static Future<void> showSurfaces({bool desktop = true}) async {
    if (!isSession) return;
    await _channel.invokeMethod("showSurfaces", {"desktop": desktop});
  }

  /// Shows the desktop and shell surfaces again, which puts them on the
  /// window manager's default output: after the output they were on was
  /// turned off or another one became the primary output.
  static Future<void> remapSurfaces() async {
    if (!isSession) return;
    await _channel.invokeMethod("remapSurfaces");
  }

  /// Restricts pointer input on the shell surface to [rects], in logical
  /// pixels. Pass null to make the whole surface interactive.
  static Future<void> setShellInputRegion(List<Rect>? rects) async {
    if (!isSession) return;
    await _channel.invokeMethod("setInputRegion", {
      "view": _shellViewId,
      "rects": rects
          ?.map(
            (r) => [
              r.left.floor(),
              r.top.floor(),
              r.width.ceil(),
              r.height.ceil(),
            ],
          )
          .toList(),
    });
  }

  static Future<void> setShellKeyboardMode(KeyboardMode mode) async {
    if (!isSession) return;
    await _channel.invokeMethod("setKeyboardMode", {
      "view": _shellViewId,
      "mode": switch (mode) {
        KeyboardMode.none => "none",
        KeyboardMode.exclusive => "exclusive",
        KeyboardMode.onDemand => "on_demand",
      },
    });
  }
}
