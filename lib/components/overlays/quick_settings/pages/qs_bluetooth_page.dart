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

import 'package:flutter/material.dart';
import 'package:pangolin/components/overlays/quick_settings/widgets/qs_titlebar.dart';
import 'package:pangolin/services/bluetooth.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/widgets/quick_button.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// Bluetooth devices: connected and paired first, then the ones found while
/// the page is open. Tapping one connects or disconnects it.
class QsBluetoothPage extends StatefulWidget {
  const QsBluetoothPage({super.key});

  @override
  State<QsBluetoothPage> createState() => _QsBluetoothPageState();
}

class _QsBluetoothPageState extends State<QsBluetoothPage> {
  BluetoothService get _bt => BluetoothService.instance;

  /// Devices being connected or disconnected.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_bt.startScan());
  }

  @override
  void dispose() {
    unawaited(_bt.stopScan());
    super.dispose();
  }

  Future<void> _toggle(BluetoothDevice device) async {
    final String key = device.path.value;
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    if (device.connected) {
      await _bt.disconnect(device);
    } else {
      await _bt.connect(device);
    }
    if (mounted) setState(() => _busy.remove(key));
  }

  Future<void> _turnOn() async {
    await _bt.setPowered(true);
    await _bt.stopScan();
    await _bt.startScan();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: QsTitlebar(
        title: "Bluetooth",
        trailing: [
          QuickActionButton(
            leading: const Icon(Icons.settings_outlined, size: 20),
            title: "Settings",
            margin: EdgeInsets.zero,
            onPressed: () =>
                ActionManager.openSettings(context, page: "bluetooth"),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _bt,
        builder: (context, _) {
          final Color muted = theme.foregroundColor.withValues(alpha: 0.7);
          if (!_bt.available) {
            return Center(
              child: Text(
                "No Bluetooth adapter",
                style: TextStyle(color: muted),
              ),
            );
          }
          if (!_bt.powered) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Bluetooth is off", style: TextStyle(color: muted)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _turnOn,
                    child: const Text("Turn on"),
                  ),
                ],
              ),
            );
          }
          final List<BluetoothDevice> devices = _bt.devices;
          if (devices.isEmpty) {
            return Center(
              child: Text("Looking for devices…", style: TextStyle(color: muted)),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final BluetoothDevice d in devices)
                _DeviceRow(
                  device: d,
                  busy: _busy.contains(d.path.value),
                  onTap: () => _toggle(d),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.busy,
    required this.onTap,
  });

  final BluetoothDevice device;
  final bool busy;
  final VoidCallback onTap;

  static IconData _icon(String icon) => switch (icon) {
        "audio-headset" || "audio-headphones" => Icons.headphones_rounded,
        "audio-card" => Icons.speaker_rounded,
        "input-keyboard" => Icons.keyboard_rounded,
        "input-mouse" => Icons.mouse_rounded,
        "input-gaming" => Icons.sports_esports_rounded,
        "input-tablet" => Icons.draw_rounded,
        "phone" => Icons.smartphone_rounded,
        "computer" => Icons.computer_rounded,
        _ => Icons.bluetooth_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String state = device.connected
        ? "Connected"
        : device.paired
            ? "Paired"
            : "Not paired";
    final int? battery = device.battery;
    return ListTile(
      hoverColor: Colors.transparent,
      leading: Icon(
        _icon(device.icon),
        color: device.connected ? theme.colorScheme.primary : null,
      ),
      title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(battery != null ? "$state · $battery%" : state),
      trailing: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: onTap,
    );
  }
}
