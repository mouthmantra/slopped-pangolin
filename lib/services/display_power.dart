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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/session_lock.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:wayland/wayland.dart';

/// Screens and their colors: turning the screens off (and locking) after
/// some time without input, and Night Shift, which warms their colors in
/// the evening (gamma tables).
class DisplayPower extends ChangeNotifier {
  DisplayPower._();

  static final DisplayPower instance = DisplayPower._();
  static final Logger _logger = Logger("DisplayPower");

  /// Color temperature of an untinted screen.
  static const int neutralTemperature = 6500;

  WaylandConnection? _connection;
  GlobalRegistry? _globals;
  WlSeat? _seat;
  ExtIdleNotifierV1? _idleNotifier;
  ZwlrOutputPowerManagerV1? _powerManager;
  ZwlrGammaControlManagerV1? _gammaManager;
  final Map<int, _Output> _outputs = {};

  ExtIdleNotificationV1? _idle;
  int? _idleMinutes;
  bool screensOff = false;

  /// Whether Night Shift tints the screens right now.
  bool get nightShiftActive => _targetTemperature < neutralTemperature;

  /// Whether the compositor lets Pangolin change the gamma tables.
  bool get nightShiftSupported => _gammaManager != null;

  double _temperature = neutralTemperature.toDouble();
  int _targetTemperature = neutralTemperature;
  Timer? _transition;
  Timer? _schedule;

  Future<void> start() async {
    try {
      final WaylandConnection connection = await WaylandConnection.connect();
      final GlobalRegistry globals = await GlobalRegistry.create(connection);
      _connection = connection;
      _globals = globals;
      _seat = globals.bind(WlSeat.interface, maxVersion: 7);
      _idleNotifier = globals.bind(ExtIdleNotifierV1.interface, maxVersion: 1);
      _powerManager = globals.bind(ZwlrOutputPowerManagerV1.interface);
      _gammaManager = globals.bind(ZwlrGammaControlManagerV1.interface);
      for (final WaylandGlobal global in globals.all(WlOutput.interface.name)) {
        _addOutput(global);
      }
      globals
        ..onAdded = (global) {
          if (global.interface == WlOutput.interface.name) _addOutput(global);
        }
        ..onRemoved = (global) => _outputs.remove(global.name)?.destroy();
      await connection.roundtrip();
    } on Object catch (e) {
      _logger.warning("Screen power and Night Shift are unavailable: $e");
      return;
    }
    PreferencesService.current.addListener(_followSettings);
    _followSettings();
    // Night Shift's schedule is checked every minute.
    _schedule = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateNightShift(),
    );
  }

  T _setting<T extends Object>(SessionSetting<T> setting) =>
      PreferencesService.current.get<T>(setting.key) ?? setting.defaultValue;

  void _followSettings() {
    _configureIdle(_setting(SessionSetting.screenOffMinutes));
    _updateNightShift();
  }

  // Inactivity.

  void _configureIdle(int minutes) {
    if (minutes == _idleMinutes) return;
    _idleMinutes = minutes;
    _idle?.destroy();
    _idle = null;
    final ExtIdleNotifierV1? notifier = _idleNotifier;
    final WlSeat? seat = _seat;
    if (notifier == null || seat == null || minutes <= 0) return;
    // Respects idle inhibitors (videos playing, presentations).
    _idle = notifier.getIdleNotification(minutes * 60 * 1000, seat)
      ..onIdled = _onIdle
      ..onResumed = _onResume;
    _connection?.flush();
  }

  Future<void> _onIdle() async {
    if (_setting(SessionSetting.lockOnScreenOff)) {
      await SessionLock.instance.lock();
    }
    _setPower(on: false);
  }

  void _onResume() => _setPower(on: true);

  void _setPower({required bool on}) {
    if (screensOff == !on) return;
    screensOff = !on;
    for (final _Output output in _outputs.values) {
      output.power?.setMode(on ? 1 : 0);
    }
    _connection?.flush();
    notifyListeners();
  }

  // Outputs.

  void _addOutput(WaylandGlobal global) {
    if (_outputs.containsKey(global.name)) return;
    final WlOutput? proxy = _globals?.bindGlobal(
      global,
      WlOutput.interface,
      maxVersion: 4,
    );
    if (proxy == null) return;
    final _Output output = _Output(proxy);
    _outputs[global.name] = output;
    output.power = _powerManager?.getOutputPower(proxy);
    final ZwlrGammaControlV1? gamma = _gammaManager?.getGammaControl(proxy);
    if (gamma != null) {
      output.gamma = gamma;
      gamma
        ..onGammaSize = (size) {
          output.gammaSize = size;
          _applyGamma(output, _temperature);
        }
        ..onFailed = () {
          // Another program (e.g. gammastep) owns the gamma tables.
          output.gamma = null;
          gamma.destroy();
        };
    }
    _connection?.flush();
  }

  // Night Shift.

  void _updateNightShift() {
    final bool enabled = _setting(SessionSetting.nightShift);
    final bool scheduled = _setting(SessionSetting.nightShiftScheduled);
    bool active = enabled;
    if (enabled && scheduled) {
      final DateTime now = DateTime.now();
      final int minute = now.hour * 60 + now.minute;
      final int from = _setting(SessionSetting.nightShiftFrom);
      final int to = _setting(SessionSetting.nightShiftTo);
      active = from <= to
          ? minute >= from && minute < to
          : minute >= from || minute < to;
    }
    final int target = active
        ? _setting(SessionSetting.nightShiftTemperature).clamp(1500, 6500)
        : neutralTemperature;
    if (target == _targetTemperature) return;
    _targetTemperature = target;
    notifyListeners();
    _animateTo(target.toDouble());
  }

  /// Eases the colors over a couple of seconds rather than switching.
  void _animateTo(double target) {
    _transition?.cancel();
    final double start = _temperature;
    const int steps = 40;
    int step = 0;
    _transition = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      step++;
      final double t = Curves.easeInOut.transform(step / steps);
      _temperature = start + (target - start) * t;
      for (final _Output output in _outputs.values) {
        _applyGamma(output, _temperature);
      }
      _connection?.flush();
      if (step >= steps) timer.cancel();
    });
  }

  void _applyGamma(_Output output, double temperature) {
    final ZwlrGammaControlV1? gamma = output.gamma;
    final int size = output.gammaSize;
    if (gamma == null || size < 2) return;
    final (double r, double g, double b) = whitePoint(temperature);
    final Uint16List table = Uint16List(size * 3);
    for (int i = 0; i < size; i++) {
      final double value = i / (size - 1) * 65535;
      table[i] = (value * r).round();
      table[size + i] = (value * g).round();
      table[2 * size + i] = (value * b).round();
    }
    try {
      // Handed over as a file descriptor, deleted right away.
      final String dir = Platform.environment["XDG_RUNTIME_DIR"] ??
          Directory.systemTemp.path;
      final File file = File("$dir/pangolin-gamma-${output.proxy.id}");
      file.writeAsBytesSync(table.buffer.asUint8List(), flush: true);
      final RandomAccessFile fd = file.openSync();
      file.deleteSync();
      gamma.setGamma(fd);
      _connection?.flush();
      fd.closeSync();
    } on FileSystemException catch (e) {
      _logger.warning("Couldn't write the gamma table: $e");
    }
  }

  /// Relative red, green and blue of a black body at [temperature] Kelvin,
  /// 1 at 6500 K (Tanner Helland's approximation).
  static (double, double, double) whitePoint(double temperature) {
    (double, double, double) raw(double kelvin) {
      final double t = kelvin / 100;
      final double r = t <= 66
          ? 255
          : 329.698727446 * math.pow(t - 60, -0.1332047592);
      final double g = t <= 66
          ? 99.4708025861 * math.log(t) - 161.1195681661
          : 288.1221695283 * math.pow(t - 60, -0.0755148492);
      final double b = t >= 66
          ? 255
          : t <= 19
              ? 0
              : 138.5177312231 * math.log(t - 10) - 305.0447927307;
      return (
        r.clamp(0, 255).toDouble(),
        g.clamp(0, 255).toDouble(),
        b.clamp(0, 255).toDouble(),
      );
    }

    final (double r, double g, double b) = raw(temperature);
    final (double nr, double ng, double nb) = raw(neutralTemperature.toDouble());
    return (
      (r / nr).clamp(0.0, 1.0),
      (g / ng).clamp(0.0, 1.0),
      (b / nb).clamp(0.0, 1.0),
    );
  }

  @override
  void dispose() {
    _transition?.cancel();
    _schedule?.cancel();
    super.dispose();
  }
}

class _Output {
  _Output(this.proxy);

  final WlOutput proxy;
  ZwlrOutputPowerV1? power;
  ZwlrGammaControlV1? gamma;
  int gammaSize = 0;

  void destroy() {
    power?.destroy();
    gamma?.destroy();
    if (proxy.version >= 3) proxy.release();
  }
}
