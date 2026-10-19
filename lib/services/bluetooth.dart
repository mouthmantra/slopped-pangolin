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

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/dbus/utils.dart';

/// Bluetooth from BlueZ: the adapter's power and its devices, for Quick
/// Settings and the taskbar.
class BluetoothService extends ChangeNotifier {
  BluetoothService._() {
    unawaited(_start());
  }

  static final BluetoothService instance = BluetoothService._();
  static final Logger _logger = Logger("Bluetooth");

  static const String _bluez = "org.bluez";
  static const String _adapterInterface = "org.bluez.Adapter1";
  static const String _deviceInterface = "org.bluez.Device1";
  static const String _batteryInterface = "org.bluez.Battery1";

  DBusClient? _bus;
  StreamSubscription<DBusSignal>? _signals;

  /// BlueZ's objects: path → interface → property → value.
  final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> _objects = {};
  int _scanners = 0;

  DBusObjectPath? get _adapter => _objects.entries
      .where((e) => e.value.containsKey(_adapterInterface))
      .map((e) => e.key)
      .firstOrNull;

  /// Whether there is an adapter to use.
  bool get available => _adapter != null;

  bool get powered =>
      _objects[_adapter]?[_adapterInterface]?["Powered"]?.toNative() == true;

  /// Devices with a name: connected first, then paired, then the others.
  List<BluetoothDevice> get devices {
    final List<BluetoothDevice> list = [
      for (final MapEntry<DBusObjectPath, Map<String, Map<String, DBusValue>>> e
          in _objects.entries)
        if (e.value[_deviceInterface] case final Map<String, DBusValue> props)
          if (BluetoothDevice._(e.key, props, e.value[_batteryInterface])
              case final BluetoothDevice device
              when device.name.isNotEmpty)
            device,
    ];
    int rank(BluetoothDevice d) => d.connected ? 0 : (d.paired ? 1 : 2);
    return list
      ..sort((a, b) {
        final int byRank = rank(a).compareTo(rank(b));
        return byRank != 0
            ? byRank
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  List<BluetoothDevice> get connected =>
      devices.where((d) => d.connected).toList();

  Future<void> _start() async {
    if (!systemBusAvailable()) return;
    try {
      final DBusClient bus = DBusClient.system();
      _bus = bus;
      final DBusRemoteObjectManager manager = DBusRemoteObjectManager(
        bus,
        name: _bluez,
        path: DBusObjectPath("/"),
      );
      _signals = manager.signals.listen(_onSignal);
      _objects.addAll(await manager.getManagedObjects());
      notifyListeners();
    } catch (e) {
      _logger.info("BlueZ isn't available: $e");
    }
  }

  void _onSignal(DBusSignal signal) {
    switch (signal) {
      case final DBusObjectManagerInterfacesAddedSignal added:
        _objects
            .putIfAbsent(added.changedPath, () => {})
            .addAll(added.interfacesAndProperties);
      case final DBusObjectManagerInterfacesRemovedSignal removed:
        final Map<String, Map<String, DBusValue>>? object =
            _objects[removed.changedPath];
        if (object == null) return;
        removed.interfaces.forEach(object.remove);
        if (object.isEmpty) _objects.remove(removed.changedPath);
      case final DBusPropertiesChangedSignal changed:
        final Map<String, DBusValue>? props =
            _objects[changed.path]?[changed.propertiesInterface];
        if (props == null) return;
        props.addAll(changed.changedProperties);
        changed.invalidatedProperties.forEach(props.remove);
      default:
        return;
    }
    notifyListeners();
  }

  DBusRemoteObject _object(DBusObjectPath path) =>
      DBusRemoteObject(_bus!, name: _bluez, path: path);

  Future<void> setPowered(bool on) async {
    final DBusObjectPath? adapter = _adapter;
    if (adapter == null) return;
    try {
      await _object(adapter)
          .setProperty(_adapterInterface, "Powered", DBusBoolean(on));
    } catch (e) {
      _logger.warning("Couldn't turn Bluetooth ${on ? "on" : "off"}: $e");
    }
  }

  /// Looks for devices while something shows them (pair with [stopScan]).
  Future<void> startScan() async {
    final DBusObjectPath? adapter = _adapter;
    if (++_scanners > 1 || adapter == null || !powered) return;
    await _call(adapter, _adapterInterface, "StartDiscovery");
  }

  Future<void> stopScan() async {
    final DBusObjectPath? adapter = _adapter;
    if (_scanners == 0 || --_scanners > 0 || adapter == null) return;
    await _call(adapter, _adapterInterface, "StopDiscovery");
  }

  /// Connects [device], pairing and trusting it first if it's new.
  Future<void> connect(BluetoothDevice device) async {
    if (!device.paired) {
      if (!await _call(device.path, _deviceInterface, "Pair")) return;
      await _object(device.path)
          .setProperty(_deviceInterface, "Trusted", const DBusBoolean(true))
          .catchError((Object _) {});
    }
    await _call(device.path, _deviceInterface, "Connect");
  }

  Future<void> disconnect(BluetoothDevice device) =>
      _call(device.path, _deviceInterface, "Disconnect");

  Future<bool> _call(
    DBusObjectPath path,
    String interface,
    String method,
  ) async {
    if (_bus == null) return false;
    try {
      await _object(path).callMethod(interface, method, []);
      return true;
    } catch (e) {
      _logger.info("Bluetooth $method on $path failed: $e");
      return false;
    }
  }
}

/// A device BlueZ knows (paired, or seen while scanning).
class BluetoothDevice {
  BluetoothDevice._(
    this.path,
    Map<String, DBusValue> props,
    Map<String, DBusValue>? battery,
  )   : name = (props["Alias"] ?? props["Name"])?.toNative() as String? ?? "",
        icon = props["Icon"]?.toNative() as String? ?? "",
        paired = props["Paired"]?.toNative() == true,
        connected = props["Connected"]?.toNative() == true,
        battery = battery?["Percentage"]?.toNative() as int?;

  final DBusObjectPath path;
  final String name;

  /// BlueZ's icon name: audio-headset, input-keyboard, phone, ...
  final String icon;
  final bool paired;
  final bool connected;

  /// Battery level in percent, when the device reports it.
  final int? battery;
}
