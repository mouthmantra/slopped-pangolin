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
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:wayland/wayland.dart';

/// Timing curves of window effects. river runs them itself, so they must be
/// cubic beziers (CSS `cubic-bezier`), which Flutter's [Cubic] also is: the
/// shell can animate its own UI in sync with the same curve.
abstract final class MirrorCurves {
  /// Chromium OS "window open".
  static const Cubic open = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Cubic close = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Cubic minimize = Cubic(0.55, 0.055, 0.675, 0.19);
  static const Cubic unminimize = Cubic(0.215, 0.61, 0.355, 1.0);
  static const Cubic morph = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Cubic slide = Cubic(0.645, 0.045, 0.355, 1.0);
  static const Cubic slideRelease = Cubic(0.215, 0.61, 0.355, 1.0);
  static const Cubic overview = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// A scaled, translucent copy of a window drawn by river above all windows
/// (river-window-effects-v1). It shares the window's buffers, so creating
/// and animating one is cheap, and river animates it at the refresh rate of
/// the outputs.
///
/// Mirrors start out invisible. Geometry is in the compositor's logical
/// (layout) coordinates and maps the window's geometry, client side shadows
/// included.
class WindowMirror {
  WindowMirror(this._proxy) {
    _proxy.onDone = _onDone;
  }

  final RiverWindowMirrorV1 _proxy;
  Completer<bool>? _animation;
  Timer? _watchdog;
  bool _destroyed = false;

  /// Where the mirror is going (or is, when not animating).
  Rect rect = Rect.zero;
  double opacity = 0;

  bool get destroyed => _destroyed;

  /// Stops following the window: the mirror keeps its current content.
  void freeze() {
    if (!_destroyed) _proxy.freeze();
  }

  /// Draws the mirror above every other mirror.
  void placeTop() {
    if (!_destroyed) _proxy.placeTop();
  }

  void jumpTo(Rect rect, [double opacity = 1]) {
    animateTo(rect, opacity, duration: Duration.zero);
  }

  /// Animates from wherever the mirror is drawn now. Completes with true when
  /// the animation ran to the end, false when it was replaced or the mirror
  /// destroyed.
  Future<bool> animateTo(
    Rect rect,
    double opacity, {
    required Duration duration,
    Cubic curve = MirrorCurves.morph,
  }) {
    _settle(false);
    if (_destroyed) return Future.value(false);
    this.rect = rect;
    this.opacity = opacity;

    final int left = rect.left.round();
    final int top = rect.top.round();
    _proxy.animate(
      left,
      top,
      math.max(0, rect.right.round() - left),
      math.max(0, rect.bottom.round() - top),
      opacity.clamp(0.0, 1.0),
      duration.inMilliseconds,
      curve.a,
      curve.b,
      curve.c,
      curve.d,
    );
    if (duration.inMilliseconds <= 0) return Future.value(true);

    final Completer<bool> completer = Completer();
    _animation = completer;
    // river always reports the end of an animation; this only guards against
    // a compositor that went away.
    _watchdog = Timer(duration + const Duration(seconds: 1), () {
      if (_animation == completer) _settle(true);
    });
    return completer.future;
  }

  void _onDone() => _settle(true);

  void _settle(bool completed) {
    _watchdog?.cancel();
    _watchdog = null;
    final Completer<bool>? animation = _animation;
    _animation = null;
    if (animation != null && !animation.isCompleted) {
      animation.complete(completed);
    }
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _settle(false);
    _proxy.destroy();
  }
}

/// Rect [rect] scaled around its center.
Rect scaleRect(Rect rect, double scale) => Rect.fromCenter(
      center: rect.center,
      width: rect.width * scale,
      height: rect.height * scale,
    );
