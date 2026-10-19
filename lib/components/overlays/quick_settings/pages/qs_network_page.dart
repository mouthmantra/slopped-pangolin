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
import 'package:pangolin/services/wifi.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/widgets/quick_button.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// Wi-Fi networks around: the connected one first. Tapping one connects to
/// it (the password is asked for when needed) or disconnects it.
class QsNetworkPage extends StatefulWidget {
  const QsNetworkPage({super.key});

  @override
  State<QsNetworkPage> createState() => _QsNetworkPageState();
}

class _QsNetworkPageState extends State<QsNetworkPage> {
  WifiService get _wifi => WifiService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_wifi.scan());
  }

  void _openSettings() => ActionManager.openSettings(context, page: "network");

  void _tap(WifiNetwork network) {
    if (network.active) {
      unawaited(_wifi.disconnect());
    } else if (network.enterprise && !network.saved) {
      // A user name and certificates: Settings.
      _openSettings();
    } else {
      unawaited(_wifi.connect(network));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: QsTitlebar(
        title: "Wi-Fi",
        trailing: [
          QuickActionButton(
            leading: const Icon(Icons.settings_outlined, size: 20),
            title: "Settings",
            margin: EdgeInsets.zero,
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _wifi,
        builder: (context, _) {
          final Color muted = theme.foregroundColor.withValues(alpha: 0.7);
          if (!_wifi.available) {
            return Center(
              child: Text("No Wi-Fi device", style: TextStyle(color: muted)),
            );
          }
          if (!_wifi.enabled) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Wi-Fi is off", style: TextStyle(color: muted)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await _wifi.setEnabled(true);
                      await _wifi.scan();
                    },
                    child: const Text("Turn on"),
                  ),
                ],
              ),
            );
          }
          if (_wifi.networks.isEmpty) {
            return Center(
              child: Text("Looking for networks…", style: TextStyle(color: muted)),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final WifiNetwork n in _wifi.networks)
                _NetworkRow(
                  network: n,
                  connecting: _wifi.connecting == n.ssid,
                  failed: _wifi.failed == n.ssid,
                  onTap: () => _tap(n),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.network,
    required this.connecting,
    required this.failed,
    required this.onTap,
  });

  final WifiNetwork network;
  final bool connecting;
  final bool failed;
  final VoidCallback onTap;

  static IconData _bars(int strength) => switch (strength) {
        >= 75 => Icons.network_wifi_rounded,
        >= 50 => Icons.network_wifi_3_bar_rounded,
        >= 25 => Icons.network_wifi_2_bar_rounded,
        _ => Icons.network_wifi_1_bar_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = connecting
        ? "Connecting…"
        : network.active
            ? "Connected"
            : failed
                ? "Couldn't connect"
                : network.saved
                    ? "Saved"
                    : network.secured
                        ? (network.enterprise ? "Set up in Settings" : "Secured")
                        : "Open";
    return ListTile(
      hoverColor: Colors.transparent,
      leading: Icon(
        _bars(network.strength),
        color: network.active ? theme.colorScheme.primary : null,
      ),
      title: Text(network.ssid, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        style: failed ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: connecting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : network.secured
              ? const Icon(Icons.lock_outline_rounded, size: 18)
              : null,
      onTap: onTap,
    );
  }
}
