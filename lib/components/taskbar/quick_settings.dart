/*
Copyright 2021 The dahliaOS Authors

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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/overlays/quick_settings/quick_settings_overlay.dart';
import 'package:pangolin/components/taskbar/taskbar_element.dart';
import 'package:pangolin/services/bluetooth.dart';
import 'package:pangolin/services/date_time.dart';
import 'package:pangolin/services/network_status.dart';
import 'package:pangolin/services/power.dart';
import 'package:pangolin/services/privacy.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/vpn.dart';
import 'package:pangolin/widgets/battery_indicator.dart';
import 'package:pangolin/widgets/separated_flex.dart';
import 'package:zenit_ui/zenit_ui.dart';

class QuickSettingsButton extends StatelessWidget
    with StatelessServiceListener<CustomizationService> {
  const QuickSettingsButton({super.key});

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    final theme = Theme.of(context);
    return TaskbarElement(
      iconSize: 18,
      overlayID: QuickSettingsOverlay.overlayId,
      height: 40.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: ValueListenableBuilder<bool>(
          valueListenable: ShellService.current
              .getShowingNotifier(QuickSettingsOverlay.overlayId),
          builder: (context, showing, child) {
            final foregroundColor =
                showing ? theme.accentForegroundColor : theme.foregroundColor;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusIcons(
                  color: foregroundColor,
                  customization: service,
                ),
                const SizedBox(width: 12),
                ListenableServiceBuilder<DateTimeService>(
                  builder: (BuildContext context, _) {
                    final DateTimeService service = DateTimeService.current;
                    return Text(
                      service.formattedTime,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: foregroundColor,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The status icons: apps using the screen, the microphone or the camera
/// (in their colors), then the network, VPN, Bluetooth and battery.
class _StatusIcons extends StatelessWidget {
  const _StatusIcons({required this.color, required this.customization});

  final Color color;
  final CustomizationService customization;

  static const Map<PrivacyUse, IconData> privacyIcons = {
    PrivacyUse.screen: Icons.screen_share_rounded,
    PrivacyUse.microphone: Icons.mic_rounded,
    PrivacyUse.camera: Icons.videocam_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PrivacyMonitor.instance,
        NetworkStatus.instance,
        VpnService.instance,
        BluetoothService.instance,
      ]),
      builder: (context, _) {
        final PrivacyMonitor privacy = PrivacyMonitor.instance;
        final List<Widget> icons = [
          for (final PrivacyUse use in PrivacyUse.values)
            if (privacy.inUse(use))
              Icon(privacyIcons[use], color: use.color),
          if (_networkIcon(NetworkStatus.instance) case final Widget icon)
            icon,
          if (VpnService.instance.anyActive) const Icon(Icons.vpn_key_rounded),
          if (BluetoothService.instance.powered)
            Icon(
              BluetoothService.instance.connected.isNotEmpty
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
            ),
          if (PowerService.current.hasBattery)
            PowerServiceBuilder(
              builder: (context, child, percentage, charging, powerSaver) {
                return BatteryIndicator(
                  percentage: percentage,
                  charging: charging,
                  color: color,
                  powerSaving: powerSaver,
                  size: 18,
                );
              },
            ),
        ];
        return SeparatedFlex(
          axis: Axis.horizontal,
          separator: const SizedBox(width: 8),
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: icons,
        );
      },
    );
  }

  /// Wi-Fi when connected over Wi-Fi, ethernet only when wired is the
  /// connection, nothing when NetworkManager can't be reached.
  static Widget? _networkIcon(NetworkStatus status) {
    if (!status.available) return null;
    if (status.wifiConnected) {
      return Icon(
        status.wifiStrength >= 70
            ? Icons.wifi_rounded
            : status.wifiStrength >= 40
                ? Icons.wifi_2_bar_rounded
                : Icons.wifi_1_bar_rounded,
      );
    }
    if (status.wiredConnected) return const Icon(Icons.settings_ethernet);
    return const Icon(Icons.wifi_off_rounded);
  }
}
