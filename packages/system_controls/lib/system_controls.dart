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
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

// Shared by the Pangolin shell and the dahliaOS applications.

/// Volume of the default PipeWire sink (through wpctl), followed live with
/// `pactl subscribe` when available.
class VolumeControl extends ChangeNotifier {
  VolumeControl._() {
    unawaited(_start());
  }

  static final VolumeControl instance = VolumeControl._();
  static final Logger _logger = Logger("VolumeControl");
  static const String _sink = "@DEFAULT_AUDIO_SINK@";

  bool available = false;

  /// 0 to 1 (and up to 1.5 when amplified elsewhere).
  double volume = 0.5;
  bool muted = false;

  Timer? _poll;
  Timer? _debounce;
  Process? _subscription;

  Future<void> _start() async {
    await refresh();
    if (!available) return;
    try {
      final Process process = await Process.start("pactl", ["subscribe"]);
      _subscription = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.contains("sink") && !line.contains("server")) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 60), refresh);
      });
      unawaited(process.stderr.drain<void>());
    } on ProcessException {
      // Without pactl, catch up with changes made elsewhere now and then.
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    }
  }

  Future<void> refresh() async {
    try {
      final ProcessResult result =
          await Process.run("wpctl", ["get-volume", _sink]);
      if (result.exitCode != 0) return;
      final RegExpMatch? match =
          RegExp(r"Volume:\s*([0-9.]+)").firstMatch(result.stdout as String);
      if (match == null) return;
      final double value = double.parse(match.group(1)!);
      final bool mute = (result.stdout as String).contains("MUTED");
      if (!available || value != volume || mute != muted) {
        available = true;
        volume = value;
        muted = mute;
        notifyListeners();
      }
    } on ProcessException {
      if (available) {
        available = false;
        notifyListeners();
      }
    } catch (e) {
      _logger.fine("Couldn't read the volume: $e");
    }
  }

  double? _wanted;
  bool _setting = false;

  /// Sets the volume. Calls made while one is being applied (a slider being
  /// dragged) are coalesced: only the latest value is applied next.
  Future<void> setVolume(double value) async {
    final double clamped = value.clamp(0.0, 1.0);
    final bool unmute = muted && clamped > 0;
    volume = clamped;
    if (unmute) muted = false;
    notifyListeners();
    _wanted = clamped;
    if (unmute) await _run(["set-mute", _sink, "0"]);
    if (_setting) return;
    _setting = true;
    try {
      while (_wanted != null) {
        final double next = _wanted!;
        _wanted = null;
        await _run(["set-volume", _sink, next.toStringAsFixed(3)]);
      }
    } finally {
      _setting = false;
    }
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    notifyListeners();
    await _run(["set-mute", _sink, value ? "1" : "0"]);
  }

  /// One step of the volume keys.
  Future<void> step(int direction) =>
      setVolume(((volume * 20).round() + direction) / 20);

  Future<void> _run(List<String> args) async {
    try {
      await Process.run("wpctl", args);
    } on ProcessException catch (e) {
      _logger.warning("Couldn't change the volume: ${e.message}");
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _subscription?.kill();
    super.dispose();
  }
}

/// Display backlight: read from sysfs, changed through logind (no root or
/// extra tools needed), with brightnessctl as a fallback.
class BrightnessControl extends ChangeNotifier {
  BrightnessControl._() {
    _start();
  }

  static final BrightnessControl instance = BrightnessControl._();
  static final Logger _logger = Logger("BrightnessControl");

  String? _device;
  int _max = 1;
  Timer? _poll;

  bool get available => _device != null;

  /// 0 to 1.
  double brightness = 1;

  void _start() {
    final Directory root = Directory("/sys/class/backlight");
    if (!root.existsSync()) return;
    // Prefer firmware interfaces over raw ones, like other desktops.
    const List<String> order = ["firmware", "platform", "raw"];
    // Entries are links to the devices, followed by listSync.
    final List<Directory> devices =
        root.listSync().whereType<Directory>().toList();
    devices.sort((a, b) {
      int rank(Directory d) {
        final int i = order.indexOf(_read(p.join(d.path, "type")) ?? "");
        return i < 0 ? order.length : i;
      }

      return rank(a).compareTo(rank(b));
    });
    for (final Directory device in devices) {
      final int? max = int.tryParse(_read(p.join(device.path, "max_brightness")) ?? "");
      if (max == null || max <= 0) continue;
      _device = device.path;
      _max = max;
      break;
    }
    if (_device == null) return;
    _refresh();
    // The backlight can change underneath (other tools, firmware keys).
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  void _refresh() {
    final String? device = _device;
    if (device == null) return;
    final int? value = int.tryParse(
      _read(p.join(device, "actual_brightness")) ??
          _read(p.join(device, "brightness")) ??
          "",
    );
    if (value == null) return;
    final double fraction = (value / _max).clamp(0.0, 1.0);
    if ((fraction - brightness).abs() > 0.001) {
      brightness = fraction;
      notifyListeners();
    }
  }

  bool _setting = false;
  double? _pending;

  Future<void> setBrightness(double value) async {
    final String? device = _device;
    if (device == null) return;
    // Never fully dark from a slider or key.
    brightness = value.clamp(0.01, 1.0);
    notifyListeners();
    // Coalesce slider drags: only the latest value is applied.
    _pending = brightness;
    if (_setting) return;
    _setting = true;
    try {
      while (_pending != null) {
        final double target = _pending!;
        _pending = null;
        await _apply(p.basename(device), (target * _max).round());
      }
    } finally {
      _setting = false;
    }
  }

  Future<void> step(int direction) =>
      setBrightness(((brightness * 20).round() + direction) / 20);

  Future<void> _apply(String name, int value) async {
    try {
      final DBusClient bus = DBusClient.system();
      try {
        await DBusRemoteObject(
          bus,
          name: "org.freedesktop.login1",
          path: DBusObjectPath("/org/freedesktop/login1/session/auto"),
        ).callMethod(
          "org.freedesktop.login1.Session",
          "SetBrightness",
          [const DBusString("backlight"), DBusString(name), DBusUint32(value)],
          replySignature: DBusSignature(""),
        );
      } finally {
        await bus.close();
      }
    } catch (e) {
      try {
        await Process.run("brightnessctl", ["--device=$name", "set", "$value"]);
      } on ProcessException {
        _logger.warning("Couldn't change the brightness: $e");
      }
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
