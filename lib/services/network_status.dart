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

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// What the taskbar shows about the network, from NetworkManager.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._() {
    unawaited(_start());
  }

  static final NetworkStatus instance = NetworkStatus._();
  static final Logger _logger = Logger("NetworkStatus");

  static const String _nm = "org.freedesktop.NetworkManager";
  static const String _deviceInterface = "$_nm.Device";
  static const int _typeEthernet = 1;
  static const int _typeWifi = 2;
  static const int _stateActivated = 100;

  DBusClient? _bus;
  Timer? _poll;
  StreamSubscription<DBusPropertiesChangedSignal>? _changes;

  /// Whether NetworkManager could be reached.
  bool available = false;
  bool wiredConnected = false;
  bool wifiConnected = false;
  bool wifiEnabled = true;

  /// Signal strength of the connected access point, 0 to 100.
  int wifiStrength = 0;

  Future<void> _start() async {
    if (!File("/run/dbus/system_bus_socket").existsSync()) return;
    try {
      final DBusClient bus = DBusClient.system();
      _bus = bus;
      final DBusRemoteObject manager = DBusRemoteObject(
        bus,
        name: _nm,
        path: DBusObjectPath("/org/freedesktop/NetworkManager"),
      );
      _changes = manager.propertiesChanged.listen((_) => _refresh());
      await _refresh();
      // Signal strength and device states change without the manager's
      // properties changing.
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } catch (e) {
      _logger.info("NetworkManager isn't available: $e");
    }
  }

  bool _refreshing = false;

  Future<void> _refresh() async {
    final DBusClient? bus = _bus;
    if (bus == null || _refreshing) return;
    _refreshing = true;
    try {
      final DBusRemoteObject manager = DBusRemoteObject(
        bus,
        name: _nm,
        path: DBusObjectPath("/org/freedesktop/NetworkManager"),
      );
      final bool enabled =
          (await manager.getProperty(_nm, "WirelessEnabled")).asBoolean();
      final List<DBusObjectPath> devices =
          (await manager.callMethod(_nm, "GetDevices", []))
              .returnValues
              .first
              .asObjectPathArray()
              .toList();

      bool wired = false;
      bool wifi = false;
      int strength = 0;
      for (final DBusObjectPath path in devices) {
        final DBusRemoteObject device =
            DBusRemoteObject(bus, name: _nm, path: path);
        final int type =
            (await device.getProperty(_deviceInterface, "DeviceType"))
                .asUint32();
        if (type != _typeEthernet && type != _typeWifi) continue;
        final int state =
            (await device.getProperty(_deviceInterface, "State")).asUint32();
        if (state != _stateActivated) continue;
        if (type == _typeEthernet) {
          wired = true;
        } else {
          wifi = true;
          strength = await _strength(bus, device);
        }
      }

      if (!available ||
          wired != wiredConnected ||
          wifi != wifiConnected ||
          enabled != wifiEnabled ||
          (strength - wifiStrength).abs() >= 10) {
        available = true;
        wiredConnected = wired;
        wifiConnected = wifi;
        wifiEnabled = enabled;
        wifiStrength = strength;
        notifyListeners();
      }
    } catch (e) {
      _logger.fine("Couldn't read the network state: $e");
    } finally {
      _refreshing = false;
    }
  }

  Future<int> _strength(DBusClient bus, DBusRemoteObject device) async {
    try {
      final DBusObjectPath ap = (await device.getProperty(
        "$_nm.Device.Wireless",
        "ActiveAccessPoint",
      ))
          .asObjectPath();
      if (ap.value == "/") return 0;
      return (await DBusRemoteObject(bus, name: _nm, path: ap)
              .getProperty("$_nm.AccessPoint", "Strength"))
          .asByte();
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_bus?.close());
    super.dispose();
  }
}
