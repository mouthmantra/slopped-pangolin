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

/// Receives what [TouchpadGestureTracker] recognized.
abstract class GestureSink {
  /// A left/right swipe started moving between desktops.
  void deskSwipeBegin();

  /// Desktops travelled so far: positive towards the next desktop.
  void deskSwipeUpdate(double offset);

  /// The fingers lifted. [velocity] is in desktops per second.
  void deskSwipeEnd(double velocity, {required bool cancelled});

  /// An up/down swipe started; [offset] as in [verticalSwipeUpdate].
  void verticalSwipeBegin(double offset);

  /// Distance travelled so far, in [TouchpadGestureTracker.verticalDistance]
  /// units: positive upwards.
  void verticalSwipeUpdate(double offset);

  /// The fingers lifted. [velocity] is in distance units per second.
  void verticalSwipeEnd(double velocity, {required bool cancelled});

  void pinch({required bool inward});
}

/// User preferences for touchpad gestures.
class GestureConfig {
  const GestureConfig({
    this.horizontalSwitchesDesktops = true,
    this.invertHorizontal = false,
  });

  final bool horizontalSwitchesDesktops;
  final bool invertHorizontal;
}

enum _Axis { undecided, horizontal, vertical, ignored }

/// Turns touchpad swipe/pinch deltas into shell gestures, with GNOME's feel:
/// swipes are followed 1:1 (left/right move between desktops, one desktop
/// per [horizontalDistance] units; up/down open and close the overview over
/// [verticalDistance] units), pinches trigger once past a threshold.
class TouchpadGestureTracker {
  TouchpadGestureTracker(this.sink);

  final GestureSink sink;
  GestureConfig config = const GestureConfig();

  /// Touchpad units (as reported by libinput) for one desktop, as GNOME.
  static const double horizontalDistance = 400;
  static const double axisThreshold = 16;
  static const double verticalDistance = 300;
  static const double pinchInScale = 0.75;
  static const double pinchOutScale = 1.35;

  _Axis _axis = _Axis.ignored;
  double _dx = 0;
  double _dy = 0;
  final List<(int, double)> _samples = [];

  void swipeBegin(int time) {
    _axis = _Axis.undecided;
    _dx = 0;
    _dy = 0;
    _samples.clear();
  }

  void swipeUpdate(int time, double dx, double dy) {
    if (_axis == _Axis.ignored) return;
    _dx += dx;
    _dy += dy;

    if (_axis == _Axis.undecided) {
      if (_dx.abs() < axisThreshold && _dy.abs() < axisThreshold) return;
      if (_dx.abs() >= _dy.abs()) {
        if (!config.horizontalSwitchesDesktops) {
          _axis = _Axis.ignored;
          return;
        }
        _axis = _Axis.horizontal;
        sink.deskSwipeBegin();
      } else {
        _axis = _Axis.vertical;
        sink.verticalSwipeBegin(-_dy / verticalDistance);
      }
    }

    switch (_axis) {
      case _Axis.horizontal:
        final double offset = _offset(_dx);
        _samples.add((time, offset));
        if (_samples.length > 6) _samples.removeAt(0);
        sink.deskSwipeUpdate(offset);
      case _Axis.vertical:
        final double offset = -_dy / verticalDistance;
        _samples.add((time, offset));
        if (_samples.length > 6) _samples.removeAt(0);
        sink.verticalSwipeUpdate(offset);
      case _Axis.undecided || _Axis.ignored:
        break;
    }
  }

  void swipeEnd(int time, {required bool cancelled}) {
    switch (_axis) {
      case _Axis.horizontal:
        sink.deskSwipeEnd(_velocity(), cancelled: cancelled);
      case _Axis.vertical:
        sink.verticalSwipeEnd(_velocity(), cancelled: cancelled);
      case _Axis.undecided || _Axis.ignored:
        break;
    }
    _axis = _Axis.ignored;
  }

  double _offset(double dx) {
    // Fingers moving left reveal the next desktop, like natural scrolling.
    final double offset = -dx / horizontalDistance;
    return config.invertHorizontal ? -offset : offset;
  }

  double _velocity() {
    if (_samples.length < 2) return 0;
    final (int t0, double o0) = _samples.first;
    final (int t1, double o1) = _samples.last;
    final int dt = t1 - t0;
    if (dt <= 0) return 0;
    return (o1 - o0) / dt * 1000;
  }

  bool _pinchFired = false;

  void pinchBegin(int time) => _pinchFired = false;

  void pinchUpdate(int time, double scale) {
    if (_pinchFired) return;
    if (scale <= pinchInScale) {
      _pinchFired = true;
      sink.pinch(inward: true);
    } else if (scale >= pinchOutScale) {
      _pinchFired = true;
      sink.pinch(inward: false);
    }
  }

  void pinchEnd(int time) => _pinchFired = false;
}
