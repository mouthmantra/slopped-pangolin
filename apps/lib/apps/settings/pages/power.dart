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

import 'package:dahlia_apps/apps/settings/power_profiles.dart';
import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/apps/settings/pages/session_settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dbus/dbus.dart';

class _Battery {
  _Battery(this.name, this.capacity, this.status, this.energyFull, this.energyDesign);
  final String name;
  final int capacity;
  final String status;
  final int? energyFull;
  final int? energyDesign;
}

/// Battery information from sysfs and power profiles over D-Bus
/// (power-profiles-daemon or tuned-ppd).
class PowerPage extends StatefulWidget {
  const PowerPage({super.key});

  @override
  State<PowerPage> createState() => _PowerPageState();
}

class _PowerPageState extends State<PowerPage> {
  List<_Battery> _batteries = [];
  bool _onAc = true;
  final PowerProfiles _power = PowerProfiles();
  bool _powerChecked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    _power.addListener(_onPowerChanged);
    _power.connect().whenComplete(() {
      if (mounted) setState(() => _powerChecked = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _power.removeListener(_onPowerChanged);
    _power.dispose();
    super.dispose();
  }

  void _onPowerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setProfile(String profile) async {
    try {
      await _power.setActive(profile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't change the power mode: ${e is DBusMethodResponseException ? e.response.errorName : e}")),
      );
    }
  }

  String? _read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _load() async {
    final List<_Battery> batteries = [];
    bool onAc = true;
    final Directory supplies = Directory("/sys/class/power_supply");
    if (supplies.existsSync()) {
      for (final FileSystemEntity e in supplies.listSync()) {
        final String? type = _read("${e.path}/type");
        if (type == "Battery" && _read("${e.path}/scope") != "Device") {
          batteries.add(_Battery(
            e.path.split("/").last,
            int.tryParse(_read("${e.path}/capacity") ?? "") ?? 0,
            _read("${e.path}/status") ?? "Unknown",
            int.tryParse(_read("${e.path}/energy_full") ?? _read("${e.path}/charge_full") ?? ""),
            int.tryParse(_read("${e.path}/energy_full_design") ?? _read("${e.path}/charge_full_design") ?? ""),
          ));
        } else if (type == "Mains") {
          onAc = _read("${e.path}/online") == "1";
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _batteries = batteries;
      _onAc = onAc;
    });
  }

  @override
  Widget build(BuildContext context) {
    const Map<String, (String, IconData)> profileInfo = {
      "power-saver": ("Power saver", Icons.eco_outlined),
      "balanced": ("Balanced", Icons.balance_rounded),
      "performance": ("Performance", Icons.bolt_rounded),
    };

    return SettingsPageBody(
      children: [
        const ScreenOffGroup(),
        SettingsGroup(
          title: "Battery",
          children: [
            if (_batteries.isEmpty)
              SettingsRow(
                icon: Icons.power_rounded,
                title: "No battery",
                subtitle: _onAc ? "Running on external power" : null,
              ),
            for (final _Battery b in _batteries) ...[
              SettingsRow(
                icon: b.status == "Charging" ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                title: "${b.capacity}%",
                subtitle: b.status,
                trailing: SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(value: b.capacity / 100, minHeight: 8),
                ),
              ),
              if (b.energyFull != null && b.energyDesign != null && b.energyDesign! > 0)
                InfoRow(
                  label: "Battery health",
                  value: "${(b.energyFull! / b.energyDesign! * 100).clamp(0, 100).round()}%",
                ),
            ],
          ],
        ),
        SettingsGroup(
          title: "Power mode",
          children: [
            if (_powerChecked && !_power.available)
              const SettingsRow(
                icon: Icons.tune_rounded,
                title: "Power profiles unavailable",
                subtitle: "Install tuned-ppd or power-profiles-daemon to switch power modes",
              ),
            for (final String p in _power.profiles)
              SettingsRow(
                icon: profileInfo[p]?.$2 ?? Icons.tune_rounded,
                title: profileInfo[p]?.$1 ?? p,
                subtitle: p == "performance" && _power.degradedReason.isNotEmpty
                    ? switch (_power.degradedReason) {
                        "lap-detected" => "Limited: the computer is on your lap",
                        "high-operating-temperature" => "Limited: the computer is too hot",
                        final String other => "Limited ($other)",
                      }
                    : null,
                trailing: Radio<String>(
                  value: p,
                  groupValue: _power.active,
                  onChanged: (_) => _setProfile(p),
                ),
                onTap: () => _setProfile(p),
              ),
          ],
        ),
      ],
    );
  }
}
