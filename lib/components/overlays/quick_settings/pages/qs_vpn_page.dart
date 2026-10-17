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

import 'package:flutter/material.dart';
import 'package:pangolin/components/overlays/quick_settings/widgets/qs_titlebar.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/widgets/quick_button.dart';
import 'package:zenit_ui/zenit_ui.dart';

import 'package:pangolin/services/vpn.dart';

/// The VPN connections set up in NetworkManager, each with its switch.
class QsVpnPage extends StatelessWidget {
  const QsVpnPage({super.key});

  static void _openEditor() {
    final String? editor = VpnService.editor;
    if (editor == null) return;
    unawaited(Process.start(editor, [], mode: ProcessStartMode.detached));
    ShellService.current.dismissEverything();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: QsTitlebar(
        title: "VPN",
        trailing: [
          if (VpnService.editor != null)
            const QuickActionButton(
              leading: Icon(Icons.settings_outlined, size: 20),
              title: "Edit connections",
              margin: EdgeInsets.zero,
              onPressed: _openEditor,
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: VpnService.instance,
        builder: (context, _) {
          final VpnService vpn = VpnService.instance;
          if (vpn.connections.isEmpty) {
            return Center(
              child: Text(
                "No VPN connections are set up",
                style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.7)),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final VpnConnection c in vpn.connections)
                      _VpnRow(connection: c, state: vpn.stateOf(c)),
                  ],
                ),
              ),
              if (vpn.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    vpn.error!,
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VpnRow extends StatelessWidget {
  const _VpnRow({required this.connection, required this.state});

  final VpnConnection connection;
  final VpnState state;

  @override
  Widget build(BuildContext context) {
    final String subtitle = switch (state) {
      VpnState.connecting => "Connecting…",
      VpnState.disconnecting => "Disconnecting…",
      VpnState.on => "Connected · ${connection.kind}",
      VpnState.off => connection.kind,
    };
    return ZenitSwitchListTile(
      hoverColor: Colors.transparent,
      secondary: Icon(
        state == VpnState.on ? Icons.vpn_key_rounded : Icons.vpn_key_outlined,
      ),
      title: Text(connection.name),
      subtitle: Text(subtitle),
      value: state == VpnState.on || state == VpnState.connecting,
      onChanged: (_) => unawaited(VpnService.instance.toggle(connection)),
    );
  }
}
