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

import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart' show PreferencesService;
import 'package:pangolin_settings/pangolin_settings.dart';

T _get<T extends Object>(SessionSetting<T> s) =>
    PreferencesService.current.get<T>(s.key) ?? s.defaultValue;

void _set<T extends Object>(SessionSetting<T> s, T value) =>
    PreferencesService.current.set<T>(s.key, value);

String _formatMinutes(int minutes) =>
    "${(minutes ~/ 60).toString().padLeft(2, "0")}:"
    "${(minutes % 60).toString().padLeft(2, "0")}";

/// Night Shift (Settings > Displays).
class NightShiftGroup extends StatelessWidget {
  const NightShiftGroup({super.key});

  Future<void> _pickTime(
    BuildContext context,
    SessionSetting<int> setting,
  ) async {
    final int current = _get(setting);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked != null) _set(setting, picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PreferencesService.current,
      builder: (context, _) {
        final bool on = _get(SessionSetting.nightShift);
        final bool scheduled = _get(SessionSetting.nightShiftScheduled);
        final int temperature = _get(SessionSetting.nightShiftTemperature);
        return SettingsGroup(
          title: "Night Shift",
          children: [
            SettingsRow(
              icon: Icons.nightlight_round,
              title: "Night Shift",
              subtitle: "Warmer colors, easier on the eyes at night",
              trailing: ZenitSwitch(
                value: on,
                onChanged: (v) => _set(SessionSetting.nightShift, v),
              ),
            ),
            if (on) ...[
              SettingsRow(
                icon: Icons.schedule_rounded,
                title: "On a schedule",
                subtitle: scheduled
                    ? "From ${_formatMinutes(_get(SessionSetting.nightShiftFrom))} "
                        "to ${_formatMinutes(_get(SessionSetting.nightShiftTo))}"
                    : "Always on",
                trailing: ZenitSwitch(
                  value: scheduled,
                  onChanged: (v) => _set(SessionSetting.nightShiftScheduled, v),
                ),
              ),
              if (scheduled)
                SettingsRow(
                  icon: Icons.access_time_rounded,
                  title: "Hours",
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _pickTime(context, SessionSetting.nightShiftFrom),
                        child: Text(
                          _formatMinutes(_get(SessionSetting.nightShiftFrom)),
                        ),
                      ),
                      const Text("–"),
                      TextButton(
                        onPressed: () =>
                            _pickTime(context, SessionSetting.nightShiftTo),
                        child: Text(
                          _formatMinutes(_get(SessionSetting.nightShiftTo)),
                        ),
                      ),
                    ],
                  ),
                ),
              SettingsRow(
                icon: Icons.thermostat_rounded,
                title: "Color temperature",
                subtitle: "$temperature K",
                trailing: SizedBox(
                  width: 220,
                  child: Slider(
                    min: 2500,
                    max: 5500,
                    divisions: 30,
                    value: temperature.clamp(2500, 5500).toDouble(),
                    onChanged: (v) => _set(
                      SessionSetting.nightShiftTemperature,
                      v.round(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Turning the screen off and locking (Settings > Power).
class ScreenOffGroup extends StatelessWidget {
  const ScreenOffGroup({super.key});

  static const List<int> _choices = [0, 1, 2, 5, 10, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PreferencesService.current,
      builder: (context, _) {
        final int minutes = _get(SessionSetting.screenOffMinutes);
        return SettingsGroup(
          title: "Screen",
          children: [
            SettingsRow(
              icon: Icons.screen_lock_portrait_outlined,
              title: "Turn off the screen after",
              subtitle: "Without keyboard or mouse input",
              trailing: DropdownButton<int>(
                value: _choices.contains(minutes) ? minutes : null,
                hint: Text("$minutes minutes"),
                underline: const SizedBox(),
                items: [
                  for (final int m in _choices)
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                        m == 0
                            ? "Never"
                            : m == 1
                                ? "1 minute"
                                : "$m minutes",
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _set(SessionSetting.screenOffMinutes, v);
                },
              ),
            ),
            SettingsRow(
              icon: Icons.lock_outline_rounded,
              title: "Lock when the screen turns off",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.lockOnScreenOff),
                onChanged: (v) => _set(SessionSetting.lockOnScreenOff, v),
              ),
            ),
          ],
        );
      },
    );
  }
}
