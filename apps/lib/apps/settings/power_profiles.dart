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

import 'package:dahlia_apps/kit/system.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// Client for the power profiles D-Bus API, as served by power-profiles-daemon
/// and by TuneD's tuned-ppd (Fedora's default). Uses the current
/// `org.freedesktop.UPower.PowerProfiles` name and falls back to the legacy
/// `net.hadess.PowerProfiles` one.
class PowerProfiles extends ChangeNotifier {
  static const List<(String, String)> _endpoints = [
    ("org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles"),
    ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles"),
  ];

  DBusClient? _bus;
  DBusRemoteObject? _object;
  String? _interface;
  StreamSubscription<DBusPropertiesChangedSignal>? _changes;

  bool _available = false;
  String? _active;
  List<String> _profiles = const [];
  String _degraded = "";

  /// Whether a power profiles service answered.
  bool get available => _available;

  /// The active profile: "power-saver", "balanced" or "performance".
  String? get active => _active;

  /// Profiles the hardware supports, in the service's order.
  List<String> get profiles => _profiles;

  /// Why performance mode is currently degraded ("lap-detected",
  /// "high-operating-temperature"), or empty.
  String get degradedReason => _degraded;

  Future<void> connect() async {
    if (!SystemUtils.systemBusAvailable) return;
    final DBusClient bus = DBusClient.system();
    for (final (String name, String path) in _endpoints) {
      final DBusRemoteObject object = DBusRemoteObject(bus, name: name, path: DBusObjectPath(path));
      try {
        final Map<String, DBusValue> props =
            await object.getAllProperties(name).timeout(const Duration(seconds: 3));
        _bus = bus;
        _object = object;
        _interface = name;
        _apply(props);
        _available = true;
        _changes = object.propertiesChanged.listen(
          (signal) {
            if (signal.propertiesInterface == name) _apply(signal.changedProperties);
          },
          onError: (_) {},
        );
        notifyListeners();
        return;
      } catch (_) {
        // Not provided by this name; try the next one.
      }
    }
    await bus.close();
  }

  void _apply(Map<String, DBusValue> props) {
    final DBusValue? active = props["ActiveProfile"];
    if (active is DBusString) _active = active.value;

    final DBusValue? profiles = props["Profiles"];
    if (profiles is DBusArray) {
      _profiles = [
        for (final DBusValue entry in profiles.children)
          if (entry is DBusDict)
            for (final MapEntry<DBusValue, DBusValue> field in entry.children.entries)
              if (field.key is DBusString &&
                  (field.key as DBusString).value == "Profile" &&
                  field.value is DBusVariant &&
                  (field.value as DBusVariant).value is DBusString)
                ((field.value as DBusVariant).value as DBusString).value,
      ];
    }

    final DBusValue? degraded = props["PerformanceDegraded"];
    if (degraded is DBusString) _degraded = degraded.value;
    notifyListeners();
  }

  /// Switches the active profile. Throws if the service refuses (e.g. polkit).
  Future<void> setActive(String profile) async {
    final DBusRemoteObject? object = _object;
    if (object == null) return;
    await object.setProperty(_interface!, "ActiveProfile", DBusString(profile));
    _active = profile;
    notifyListeners();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _bus?.close();
    super.dispose();
  }
}
