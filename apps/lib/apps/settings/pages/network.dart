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

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dbus/dbus.dart';

const String _nm = "org.freedesktop.NetworkManager";

class _AccessPoint {
  _AccessPoint(this.path, this.ssid, this.strength, this.secured, this.frequency);
  final DBusObjectPath path;
  final String ssid;
  final int strength;
  final bool secured;
  final int frequency;
}

class _Device {
  _Device(this.path, this.interface, this.type, this.state);
  final DBusObjectPath path;
  final String interface;
  final int type;
  final int state;
  String? connection;
  List<String> addresses = [];
  List<_AccessPoint> accessPoints = [];
  DBusObjectPath? activeAccessPoint;

  bool get wifi => type == 2;
  bool get ethernet => type == 1;
  bool get connected => state == 100;

  String get typeLabel => switch (type) {
        1 => "Ethernet",
        2 => "Wi-Fi",
        5 => "Bluetooth",
        13 => "Bridge",
        14 => "Generic",
        29 => "WireGuard",
        _ => "Network",
      };

  String get stateLabel => switch (state) {
        10 => "Unmanaged",
        20 => "Unavailable",
        30 => "Disconnected",
        40 || 50 || 60 || 70 || 80 || 90 => "Connecting…",
        100 => "Connected",
        110 => "Disconnecting…",
        120 => "Failed",
        _ => "Unknown",
      };
}

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  DBusClient? _bus;
  DBusRemoteObject? _manager;
  String? _error;
  bool _loading = true;
  bool _wirelessEnabled = false;
  int _connectivity = 0;
  List<_Device> _devices = [];
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _bus?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final DBusClient bus = DBusClient.system();
      _bus = bus;
      _manager = DBusRemoteObject(bus, name: _nm, path: DBusObjectPath("/org/freedesktop/NetworkManager"));
      await _load().timeout(const Duration(seconds: 3));
      _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "NetworkManager isn't running on this system.";
        });
      }
    }
  }

  Future<DBusValue> _prop(DBusRemoteObject o, String iface, String name) =>
      o.getProperty(iface, name);

  Future<void> _load() async {
    final DBusRemoteObject manager = _manager!;
    final bool wireless = (await _prop(manager, _nm, "WirelessEnabled")).asBoolean();
    final int connectivity = (await _prop(manager, _nm, "Connectivity")).asUint32();
    final DBusMethodSuccessResponse devicesResponse =
        await manager.callMethod(_nm, "GetDevices", [], replySignature: DBusSignature("ao"));

    final List<_Device> devices = [];
    for (final DBusObjectPath path in devicesResponse.values.first.asObjectPathArray()) {
      final DBusRemoteObject d = DBusRemoteObject(_bus!, name: _nm, path: path);
      const String di = "$_nm.Device";
      final int type = (await _prop(d, di, "DeviceType")).asUint32();
      if (type == 32 || type == 30) continue; // loopback, wifi-p2p
      final _Device device = _Device(
        path,
        (await _prop(d, di, "Interface")).asString(),
        type,
        (await _prop(d, di, "State")).asUint32(),
      );

      final DBusObjectPath active = (await _prop(d, di, "ActiveConnection")).asObjectPath();
      if (active.value != "/") {
        final DBusRemoteObject ac = DBusRemoteObject(_bus!, name: _nm, path: active);
        device.connection = (await _prop(ac, "$_nm.Connection.Active", "Id")).asString();
      }
      final DBusObjectPath ip4 = (await _prop(d, di, "Ip4Config")).asObjectPath();
      if (ip4.value != "/") {
        final DBusRemoteObject ipc = DBusRemoteObject(_bus!, name: _nm, path: ip4);
        final DBusValue data = await _prop(ipc, "$_nm.IP4Config", "AddressData");
        for (final DBusValue entry in data.asArray()) {
          final Map<String, DBusValue> m = entry.asStringVariantDict();
          device.addresses.add("${m["address"]?.asString()}/${m["prefix"]?.asUint32()}");
        }
      }

      if (device.wifi) {
        const String wi = "$_nm.Device.Wireless";
        device.activeAccessPoint = (await _prop(d, wi, "ActiveAccessPoint")).asObjectPath();
        final DBusMethodSuccessResponse aps =
            await d.callMethod(wi, "GetAllAccessPoints", [], replySignature: DBusSignature("ao"));
        final Map<String, _AccessPoint> bySsid = {};
        for (final DBusObjectPath apPath in aps.values.first.asObjectPathArray()) {
          final DBusRemoteObject ap = DBusRemoteObject(_bus!, name: _nm, path: apPath);
          const String ai = "$_nm.AccessPoint";
          final String ssid = utf8.decode(
            (await _prop(ap, ai, "Ssid")).asByteArray().toList(),
            allowMalformed: true,
          );
          if (ssid.isEmpty) continue;
          final int strength = (await _prop(ap, ai, "Strength")).asByte();
          final bool secured = (await _prop(ap, ai, "WpaFlags")).asUint32() != 0 ||
              (await _prop(ap, ai, "RsnFlags")).asUint32() != 0;
          final int freq = (await _prop(ap, ai, "Frequency")).asUint32();
          final _AccessPoint point = _AccessPoint(apPath, ssid, strength, secured, freq);
          if ((bySsid[ssid]?.strength ?? -1) < strength) bySsid[ssid] = point;
        }
        device.accessPoints = bySsid.values.toList()..sort((a, b) => b.strength.compareTo(a.strength));
      }
      devices.add(device);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _wirelessEnabled = wireless;
      _connectivity = connectivity;
      _devices = devices;
    });
  }

  Future<void> _setWireless(bool enabled) async {
    await _manager!.setProperty(_nm, "WirelessEnabled", DBusBoolean(enabled));
    await _load();
  }

  Future<void> _scan(_Device device) async {
    final DBusRemoteObject d = DBusRemoteObject(_bus!, name: _nm, path: device.path);
    try {
      await d.callMethod("$_nm.Device.Wireless", "RequestScan", [DBusDict.stringVariant({})]);
    } on DBusMethodResponseException {
      // Scans are rate limited by NetworkManager.
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await _load();
  }

  Future<void> _join(_Device device, _AccessPoint ap) async {
    String? password;
    if (ap.secured) {
      password = await showDialog<String>(
        context: context,
        builder: (context) {
          final TextEditingController controller = TextEditingController();
          return AlertDialog(
            title: Text("Connect to ${ap.ssid}"),
            content: TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Password"),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Connect")),
            ],
          );
        },
      );
      if (password == null) return;
    }

    final Map<String, Map<String, DBusValue>> settings = {
      "connection": {"type": const DBusString("802-11-wireless"), "id": DBusString(ap.ssid)},
      "802-11-wireless": {"ssid": DBusArray.byte(utf8.encode(ap.ssid))},
      if (password != null)
        "802-11-wireless-security": {
          "key-mgmt": const DBusString("wpa-psk"),
          "psk": DBusString(password),
        },
    };
    try {
      await _manager!.callMethod(
        _nm,
        "AddAndActivateConnection",
        [
          DBusDict(
            DBusSignature("s"),
            DBusSignature("a{sv}"),
            settings.map((k, v) => MapEntry(DBusString(k), DBusDict.stringVariant(v))),
          ),
          device.path,
          ap.path,
        ],
        replySignature: DBusSignature("oo"),
      );
    } on DBusMethodResponseException catch (e) {
      _toast("Couldn't connect: ${e.errorName}");
    }
    await _load();
  }

  Future<void> _disconnect(_Device device) async {
    final DBusRemoteObject d = DBusRemoteObject(_bus!, name: _nm, path: device.path);
    try {
      await d.callMethod("$_nm.Device", "Disconnect", []);
    } on DBusMethodResponseException catch (e) {
      _toast("Couldn't disconnect: ${e.errorName}");
    }
    await _load();
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _signalIcon(int strength) => switch (strength) {
        > 75 => Icons.signal_wifi_4_bar_rounded,
        > 50 => Icons.network_wifi_3_bar_rounded,
        > 25 => Icons.network_wifi_2_bar_rounded,
        _ => Icons.network_wifi_1_bar_rounded,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(icon: Icons.wifi_off_rounded, title: "Networking unavailable", subtitle: _error);
    }

    final String connectivity = switch (_connectivity) {
      4 => "Connected to the internet",
      3 => "Limited connectivity",
      2 => "Behind a captive portal",
      1 => "No connection",
      _ => "Unknown",
    };

    return SettingsPageBody(
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: _connectivity == 4 ? Icons.public_rounded : Icons.public_off_rounded,
              title: "Status",
              subtitle: connectivity,
            ),
            SettingsRow(
              icon: Icons.wifi_rounded,
              title: "Wi-Fi",
              trailing: ZenitSwitch(value: _wirelessEnabled, onChanged: _setWireless),
            ),
          ],
        ),
        for (final _Device device in _devices) ...[
          SettingsGroup(
            title: "${device.typeLabel} (${device.interface})",
            children: [
              SettingsRow(
                icon: device.wifi ? Icons.wifi_rounded : Icons.settings_ethernet_rounded,
                title: device.connection ?? device.stateLabel,
                subtitle: [
                  if (device.connection != null) device.stateLabel,
                  ...device.addresses,
                ].join(" · "),
                trailing: device.connected
                    ? TextButton(onPressed: () => _disconnect(device), child: const Text("Disconnect"))
                    : null,
              ),
              if (device.wifi && _wirelessEnabled) ...[
                for (final _AccessPoint ap in device.accessPoints.take(12))
                  SettingsRow(
                    icon: _signalIcon(ap.strength),
                    title: ap.ssid,
                    subtitle: "${ap.frequency > 4000 ? "5" : "2.4"} GHz${ap.secured ? " · Secured" : ""}",
                    trailing: device.activeAccessPoint == ap.path
                        ? const Icon(Icons.check_rounded)
                        : Icon(ap.secured ? Icons.lock_outline_rounded : Icons.lock_open_rounded, size: 18),
                    onTap: device.activeAccessPoint == ap.path ? null : () => _join(device, ap),
                  ),
                SettingsRow(
                  icon: Icons.refresh_rounded,
                  title: "Scan for networks",
                  onTap: () => _scan(device),
                ),
              ],
            ],
          ),
        ],
        if (_devices.isEmpty)
          const EmptyState(icon: Icons.device_unknown_outlined, title: "No network devices"),
      ],
    );
  }
}
