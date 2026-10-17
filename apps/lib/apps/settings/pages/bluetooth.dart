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

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dbus/dbus.dart';

class _BtDevice {
  _BtDevice(this.path, this.props);
  final DBusObjectPath path;
  final Map<String, DBusValue> props;

  String get name =>
      props["Alias"]?.asString() ?? props["Name"]?.asString() ?? props["Address"]?.asString() ?? "Device";
  bool get paired => props["Paired"]?.asBoolean() ?? false;
  bool get connected => props["Connected"]?.asBoolean() ?? false;
  String get icon => props["Icon"]?.asString() ?? "";

  IconData get iconData => switch (icon) {
        "audio-headset" || "audio-headphones" => Icons.headphones_rounded,
        "audio-card" => Icons.speaker_rounded,
        "input-keyboard" => Icons.keyboard_rounded,
        "input-mouse" => Icons.mouse_rounded,
        "input-gaming" => Icons.sports_esports_rounded,
        "phone" => Icons.smartphone_rounded,
        "computer" => Icons.computer_rounded,
        _ => Icons.bluetooth_rounded,
      };
}

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  DBusClient? _bus;
  DBusObjectPath? _adapter;
  Map<String, DBusValue> _adapterProps = {};
  List<_BtDevice> _devices = [];
  String? _error;
  bool _loading = true;
  Timer? _timer;
  final Set<DBusObjectPath> _busy = {};

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bus?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _bus = DBusClient.system();
      await _load().timeout(const Duration(seconds: 3));
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "The Bluetooth service (BlueZ) isn't running on this system.";
        });
      }
    }
  }

  Future<void> _load() async {
    final DBusRemoteObjectManager manager =
        DBusRemoteObjectManager(_bus!, name: "org.bluez", path: DBusObjectPath("/"));
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await manager.getManagedObjects();

    DBusObjectPath? adapter;
    Map<String, DBusValue> adapterProps = {};
    final List<_BtDevice> devices = [];
    objects.forEach((path, interfaces) {
      if (interfaces.containsKey("org.bluez.Adapter1") && adapter == null) {
        adapter = path;
        adapterProps = interfaces["org.bluez.Adapter1"]!;
      }
      final Map<String, DBusValue>? device = interfaces["org.bluez.Device1"];
      if (device != null) devices.add(_BtDevice(path, device));
    });
    devices.sort((a, b) {
      if (a.paired != b.paired) return a.paired ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    if (!mounted) return;
    setState(() {
      _loading = false;
      _adapter = adapter;
      _adapterProps = adapterProps;
      _devices = devices;
    });
  }

  DBusRemoteObject _object(DBusObjectPath path) =>
      DBusRemoteObject(_bus!, name: "org.bluez", path: path);

  Future<void> _call(DBusObjectPath path, String iface, String method, [List<DBusValue> args = const []]) async {
    setState(() => _busy.add(path));
    try {
      await _object(path).callMethod(iface, method, args).timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is DBusMethodResponseException ? e.errorName : "$e")),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(path));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _adapter == null) {
      return EmptyState(
        icon: Icons.bluetooth_disabled_rounded,
        title: "Bluetooth unavailable",
        subtitle: _error ?? "No Bluetooth adapter found.",
      );
    }

    final bool powered = _adapterProps["Powered"]?.asBoolean() ?? false;
    final bool discovering = _adapterProps["Discovering"]?.asBoolean() ?? false;
    final List<_BtDevice> paired = _devices.where((d) => d.paired).toList();
    final List<_BtDevice> nearby = _devices.where((d) => !d.paired).toList();

    Widget deviceRow(_BtDevice d) => SettingsRow(
          icon: d.iconData,
          title: d.name,
          subtitle: d.connected ? "Connected" : (d.paired ? "Paired" : null),
          trailing: _busy.contains(d.path)
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!d.paired)
                      TextButton(onPressed: () => _call(d.path, "org.bluez.Device1", "Pair"), child: const Text("Pair"))
                    else
                      TextButton(
                        onPressed: () => _call(d.path, "org.bluez.Device1", d.connected ? "Disconnect" : "Connect"),
                        child: Text(d.connected ? "Disconnect" : "Connect"),
                      ),
                    if (d.paired)
                      IconButton(
                        tooltip: "Forget",
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _call(_adapter!, "org.bluez.Adapter1", "RemoveDevice", [d.path]),
                      ),
                  ],
                ),
        );

    return SettingsPageBody(
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.bluetooth_rounded,
              title: _adapterProps["Alias"]?.asString() ?? "Bluetooth",
              subtitle: _adapterProps["Address"]?.asString(),
              trailing: ZenitSwitch(
                value: powered,
                onChanged: (v) async {
                  await _object(_adapter!).setProperty("org.bluez.Adapter1", "Powered", DBusBoolean(v));
                  await _load();
                },
              ),
            ),
          ],
        ),
        if (powered) ...[
          if (paired.isNotEmpty) SettingsGroup(title: "My devices", children: [for (final d in paired) deviceRow(d)]),
          SettingsGroup(
            title: "Nearby devices",
            children: [
              for (final _BtDevice d in nearby) deviceRow(d),
              SettingsRow(
                icon: discovering ? Icons.stop_circle_outlined : Icons.radar_rounded,
                title: discovering ? "Stop searching" : "Search for devices",
                onTap: () => _call(_adapter!, "org.bluez.Adapter1", discovering ? "StopDiscovery" : "StartDiscovery"),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
