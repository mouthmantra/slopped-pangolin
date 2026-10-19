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

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/bluetooth.dart';
import 'package:pangolin/services/dbus/utils.dart';

/// Wi-Fi from NetworkManager, for Quick Settings: the radio, the networks
/// around, and connecting to them. Passwords are asked for by the secret
/// agent VpnService registers (NetworkSecretOverlay).
class WifiService extends ChangeNotifier {
  WifiService._() {
    unawaited(_start());
  }

  static final WifiService instance = WifiService._();
  static final Logger _logger = Logger("Wifi");

  static const String _nm = "org.freedesktop.NetworkManager";
  static const String _deviceInterface = "$_nm.Device";
  static const String _wirelessInterface = "$_nm.Device.Wireless";
  static const String _apInterface = "$_nm.AccessPoint";
  static const String _settingsInterface = "$_nm.Settings";
  static final DBusObjectPath _managerPath =
      DBusObjectPath("/org/freedesktop/NetworkManager");
  static final DBusObjectPath _settingsPath =
      DBusObjectPath("/org/freedesktop/NetworkManager/Settings");

  DBusClient? _bus;
  DBusObjectPath? _device;
  final List<StreamSubscription<Object>> _subscriptions = [];
  Timer? _refreshSoon;

  /// Whether NetworkManager and a Wi-Fi device could be reached.
  bool available = false;

  /// NetworkManager's WirelessEnabled.
  bool enabled = false;

  /// Networks around, one per name (the strongest access point), the
  /// connected one first, then by signal.
  List<WifiNetwork> networks = const [];

  /// The network being connected to, while NetworkManager works on it.
  String? connecting;

  /// The network that failed to connect last (wrong password, out of reach).
  String? failed;

  /// Saved connections by network name.
  Map<String, DBusObjectPath> _saved = {};
  int _deviceState = 0;

  WifiNetwork? get connected =>
      networks.where((n) => n.active).firstOrNull;

  Future<void> _start() async {
    if (!systemBusAvailable()) return;
    try {
      final DBusClient bus = DBusClient.system();
      _bus = bus;
      final DBusRemoteObject manager = _object(_managerPath);
      enabled =
          (await manager.getProperty(_nm, "WirelessEnabled")).asBoolean();
      _subscriptions.add(
        manager.propertiesChanged.listen((signal) {
          final DBusValue? value = signal.changedProperties["WirelessEnabled"];
          if (value == null) return;
          enabled = value.asBoolean();
          notifyListeners();
        }),
      );
      for (final DBusObjectPath path in (await manager.callMethod(_nm, "GetDevices", []))
          .returnValues
          .first
          .asObjectPathArray()) {
        final int type =
            (await _object(path).getProperty(_deviceInterface, "DeviceType"))
                .asUint32();
        if (type == 2) {
          _device = path;
          break;
        }
      }
      final DBusObjectPath? device = _device;
      if (device == null) return;
      available = true;
      // Access points come and go, their signal changes, the device
      // connects: refresh shortly after any of it.
      _subscriptions
        ..add(
          DBusSignalStream(bus, sender: _nm, pathNamespace: device)
              .listen((_) => _scheduleRefresh()),
        )
        ..add(
          DBusSignalStream(bus, sender: _nm, pathNamespace: _settingsPath)
              .listen((_) => _scheduleRefresh(saved: true)),
        );
      await _refreshSaved();
      await _refresh();
    } catch (e) {
      _logger.info("NetworkManager isn't available: $e");
    }
  }

  DBusRemoteObject _object(DBusObjectPath path) =>
      DBusRemoteObject(_bus!, name: _nm, path: path);

  bool _savedStale = false;

  void _scheduleRefresh({bool saved = false}) {
    _savedStale |= saved;
    _refreshSoon ??= Timer(const Duration(milliseconds: 300), () async {
      _refreshSoon = null;
      if (_savedStale) {
        _savedStale = false;
        await _refreshSaved();
      }
      await _refresh();
    });
  }

  Future<void> _refreshSaved() async {
    final Map<String, DBusObjectPath> saved = {};
    try {
      final List<DBusObjectPath> paths =
          (await _object(_settingsPath).callMethod(_settingsInterface, "ListConnections", []))
              .returnValues
              .first
              .asObjectPathArray()
              .toList();
      for (final DBusObjectPath path in paths) {
        final Map<String, Map<String, DBusValue>> settings =
            _decodeSettings((await _object(path)
                    .callMethod("$_settingsInterface.Connection", "GetSettings", []))
                .returnValues
                .first);
        final DBusValue? ssid = settings["802-11-wireless"]?["ssid"];
        if (ssid != null) saved[_ssid(ssid)] = path;
      }
    } catch (e) {
      _logger.info("Couldn't list saved connections: $e");
    }
    _saved = saved;
  }

  static Map<String, Map<String, DBusValue>> _decodeSettings(DBusValue value) =>
      value.asDict().map(
            (k, v) => MapEntry(k.asString(), v.asStringVariantDict()),
          );

  static String _ssid(DBusValue value) =>
      utf8.decode(value.asByteArray().toList(), allowMalformed: true);

  Future<void> _refresh() async {
    final DBusObjectPath? device = _device;
    if (device == null) return;
    try {
      final DBusRemoteObject dev = _object(device);
      _deviceState = (await dev.getProperty(_deviceInterface, "State")).asUint32();
      final DBusObjectPath active =
          (await dev.getProperty(_wirelessInterface, "ActiveAccessPoint")).asObjectPath();
      final List<DBusObjectPath> aps =
          (await dev.getProperty(_wirelessInterface, "AccessPoints"))
              .asObjectPathArray()
              .toList();
      final Map<String, WifiNetwork> byName = {};
      for (final DBusObjectPath ap in aps) {
        final Map<String, DBusValue> p;
        try {
          p = await _object(ap).getAllProperties(_apInterface);
        } on Object {
          continue; // Gone meanwhile.
        }
        final String ssid = _ssid(p["Ssid"]!);
        if (ssid.isEmpty) continue; // Hidden network.
        final int wpa = p["WpaFlags"]?.asUint32() ?? 0;
        final int rsn = p["RsnFlags"]?.asUint32() ?? 0;
        final WifiNetwork network = WifiNetwork._(
          ssid: ssid,
          accessPoint: ap,
          strength: p["Strength"]?.asByte() ?? 0,
          secured: (p["Flags"]?.asUint32() ?? 0) & 0x1 != 0 || wpa != 0 || rsn != 0,
          // NM_802_11_AP_SEC_KEY_MGMT_802_1X
          enterprise: (wpa | rsn) & 0x200 != 0,
          // NM_802_11_AP_SEC_KEY_MGMT_SAE (WPA3)
          sae: rsn & 0x400 != 0 && rsn & 0x100 == 0,
          saved: _saved.containsKey(ssid),
          active: ap == active,
        );
        final WifiNetwork? other = byName[ssid];
        if (other == null || network.active || (!other.active && network.strength > other.strength)) {
          byName[ssid] = network;
        }
      }
      networks = byName.values.toList()
        ..sort((a, b) {
          if (a.active != b.active) return a.active ? -1 : 1;
          return b.strength.compareTo(a.strength);
        });
      // NM_DEVICE_STATE: 40..90 working on it, 100 activated, below 40 not.
      if (connecting != null) {
        if (connected?.ssid == connecting && _deviceState == 100) {
          connecting = null;
        } else if (_deviceState < 40 && _sawActivation) {
          failed = connecting;
          connecting = null;
        }
        if (_deviceState >= 40) _sawActivation = true;
      }
      notifyListeners();
    } catch (e) {
      _logger.info("Couldn't read the Wi-Fi networks: $e");
    }
  }

  bool _sawActivation = false;

  Future<void> setEnabled(bool on) async {
    if (_bus == null) return;
    try {
      await _object(_managerPath).setProperty(_nm, "WirelessEnabled", DBusBoolean(on));
    } catch (e) {
      _logger.warning("Couldn't turn Wi-Fi ${on ? "on" : "off"}: $e");
    }
  }

  /// Asks the device to look for networks (NetworkManager may refuse when it
  /// scanned a moment ago).
  Future<void> scan() async {
    final DBusObjectPath? device = _device;
    if (device == null) return;
    try {
      await _object(device).callMethod(_wirelessInterface, "RequestScan", [DBusDict.stringVariant({})]);
    } on Object {
      // Scanned recently, or the radio is off.
    }
  }

  Future<void> connect(WifiNetwork network) async {
    final DBusObjectPath? device = _device;
    if (device == null) return;
    connecting = network.ssid;
    failed = null;
    _sawActivation = false;
    notifyListeners();
    try {
      final DBusObjectPath? saved = _saved[network.ssid];
      if (saved != null) {
        await _object(_managerPath).callMethod(_nm, "ActivateConnection", [
          saved,
          device,
          network.accessPoint,
        ]);
      } else {
        // NetworkManager fills in the rest, and asks the secret agent for the
        // password.
        await _object(_managerPath).callMethod(_nm, "AddAndActivateConnection", [
          DBusDict(
            DBusSignature("s"),
            DBusSignature("a{sv}"),
            {
              const DBusString("802-11-wireless"): DBusDict.stringVariant({
                "ssid": DBusArray.byte(utf8.encode(network.ssid)),
              }),
              if (network.secured)
                const DBusString("802-11-wireless-security"): DBusDict.stringVariant({
                  "key-mgmt": DBusString(network.sae ? "sae" : "wpa-psk"),
                }),
            },
          ),
          device,
          network.accessPoint,
        ]);
      }
      _scheduleRefresh(saved: saved == null);
    } catch (e) {
      _logger.info("Couldn't connect to ${network.ssid}: $e");
      connecting = null;
      failed = network.ssid;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final DBusObjectPath? device = _device;
    if (device == null) return;
    try {
      await _object(device).callMethod(_deviceInterface, "Disconnect", []);
    } on Object {
      // Already disconnected.
    }
  }
}

/// A Wi-Fi network around (its strongest access point).
class WifiNetwork {
  WifiNetwork._({
    required this.ssid,
    required this.accessPoint,
    required this.strength,
    required this.secured,
    required this.enterprise,
    required this.sae,
    required this.saved,
    required this.active,
  });

  final String ssid;
  final DBusObjectPath accessPoint;

  /// Signal, 0 to 100.
  final int strength;
  final bool secured;

  /// 802.1X (user name and certificates): set up in Settings.
  final bool enterprise;

  /// WPA3 only.
  final bool sae;
  final bool saved;
  final bool active;
}

/// Airplane mode: Wi-Fi and Bluetooth off, and back as they were after.
abstract final class AirplaneMode {
  static bool? _wifi;
  static bool? _bluetooth;

  static Future<void> set({required bool on}) async {
    final WifiService wifi = WifiService.instance;
    final BluetoothService bluetooth = BluetoothService.instance;
    if (on) {
      _wifi = wifi.enabled;
      _bluetooth = bluetooth.powered;
      await wifi.setEnabled(false);
      await bluetooth.setPowered(false);
    } else {
      // Turned on in an earlier session: both back on.
      await wifi.setEnabled(_wifi ?? true);
      await bluetooth.setPowered(_bluetooth ?? true);
      _wifi = _bluetooth = null;
    }
  }
}
