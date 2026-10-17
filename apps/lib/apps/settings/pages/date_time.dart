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

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:intl/intl.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

const Map<String, String> _languages = {
  "en_US": "English (United States)",
  "ar_SA": "العربية",
  "cs_CZ": "Čeština",
  "de_DE": "Deutsch",
  "es_ES": "Español",
  "fr_FR": "Français",
  "he_IL": "עברית",
  "hi_IN": "हिन्दी",
  "hr_HR": "Hrvatski",
  "hu_HU": "Magyar",
  "it_IT": "Italiano",
  "nl_NL": "Nederlands",
  "pl_PL": "Polski",
  "pt_BR": "Português (Brasil)",
  "pt_PT": "Português (Portugal)",
  "ro_RO": "Română",
  "sv_SE": "Svenska",
  "tr_TR": "Türkçe",
  "uk_UA": "Українська",
};

class DateTimePage extends StatefulWidget {
  const DateTimePage({super.key});

  @override
  State<DateTimePage> createState() => _DateTimePageState();
}

class _DateTimePageState extends State<DateTimePage> {
  late final Timer _timer;
  DateTime _now = DateTime.now();
  String? _timezone;
  bool? _ntp;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    _loadTimezone();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _loadTimezone() async {
    String? tz = (await SystemUtils.run("timedatectl", ["show", "-p", "Timezone", "--value"]))?.trim();
    final String? ntp = (await SystemUtils.run("timedatectl", ["show", "-p", "NTP", "--value"]))?.trim();
    if (tz == null || tz.isEmpty) {
      try {
        tz = File("/etc/localtime").resolveSymbolicLinksSync().split("zoneinfo/").last;
      } on FileSystemException {
        tz = Platform.environment["TZ"];
      }
    }
    if (mounted) {
      setState(() {
        _timezone = tz;
        _ntp = ntp == null ? null : ntp == "yes";
      });
    }
  }

  /// Time zones from tzdata, for systems without timedatectl.
  static List<String> _tzdataZones() {
    for (final String tab in ["zone1970.tab", "zone.tab"]) {
      try {
        return {
          for (final String line in File("/usr/share/zoneinfo/$tab").readAsLinesSync())
            if (!line.startsWith("#") && line.split("\t").length > 2) line.split("\t")[2],
        }.toList()
          ..sort();
      } on FileSystemException {
        continue;
      }
    }
    return [];
  }

  Future<void> _changeTimezone() async {
    final bool timedated = SystemUtils.which("timedatectl") != null;
    final String list = await SystemUtils.run("timedatectl", ["list-timezones"]) ?? "";
    List<String> zones = list.split("\n").where((z) => z.isNotEmpty).toList();
    if (zones.isEmpty) zones = _tzdataZones();
    if (!mounted || zones.isEmpty) return;
    final String? zone = await showDialog<String>(
      context: context,
      builder: (context) => _ZonePicker(zones: zones),
    );
    if (zone == null) return;
    final String? ok = await SystemUtils.run("timedatectl", ["set-timezone", zone]);
    if (!mounted) return;
    if (ok == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            timedated
                ? "Changing the time zone requires administrator rights"
                // No systemd (e.g. Alpine): the distribution's own tool.
                : "Set the time zone with your system's tools (e.g. setup-timezone)",
          ),
        ),
      );
    }
    await _loadTimezone();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PreferencesService prefs = PreferencesService.current;

    return ListenableServiceBuilder<CustomizationService>(
      builder: (context, _) {
        final bool use24h = prefs.get<bool>(SessionSetting.clock24Hour.key) ?? SessionSetting.clock24Hour.defaultValue;
        final bool seconds =
            prefs.get<bool>(SessionSetting.clockShowSeconds.key) ?? SessionSetting.clockShowSeconds.defaultValue;
        final String locale = CustomizationService.current.locale;

        return SettingsPageBody(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(
                    DateFormat(use24h ? (seconds ? "HH:mm:ss" : "HH:mm") : (seconds ? "h:mm:ss a" : "h:mm a"))
                        .format(_now),
                    style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w300),
                  ),
                  Text(DateFormat.yMMMMEEEEd().format(_now), style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            SettingsGroup(
              title: "Time",
              children: [
                SettingsRow(
                  icon: Icons.public_rounded,
                  title: "Time zone",
                  subtitle: _timezone ?? "Unknown",
                  trailing: SystemUtils.which("timedatectl") != null
                      ? TextButton(onPressed: _changeTimezone, child: const Text("Change"))
                      : null,
                ),
                if (_ntp != null)
                  SettingsRow(
                    icon: Icons.sync_rounded,
                    title: "Set time automatically",
                    subtitle: _ntp! ? "Synchronized over the network" : "Off",
                  ),
                SettingsRow(
                  icon: Icons.schedule_rounded,
                  title: "24-hour clock",
                  trailing: ZenitSwitch(
                    value: use24h,
                    onChanged: (v) {
                      prefs.set<bool>(SessionSetting.clock24Hour.key, v);
                      setState(() {});
                    },
                  ),
                ),
                SettingsRow(
                  icon: Icons.timer_outlined,
                  title: "Show seconds in the taskbar",
                  trailing: ZenitSwitch(
                    value: seconds,
                    onChanged: (v) {
                      prefs.set<bool>(SessionSetting.clockShowSeconds.key, v);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: "Language",
              children: [
                SettingsRow(
                  icon: Icons.translate_rounded,
                  title: "Desktop language",
                  subtitle: "Used by Pangolin and dahliaOS apps",
                  trailing: DropdownButton<String>(
                    value: _languages.containsKey(locale) ? locale : "en_US",
                    underline: const SizedBox(),
                    items: [
                      for (final MapEntry<String, String> l in _languages.entries)
                        DropdownMenuItem(value: l.key, child: Text(l.value)),
                    ],
                    onChanged: (v) => CustomizationService.current.locale = v,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ZonePicker extends StatefulWidget {
  const _ZonePicker({required this.zones});
  final List<String> zones;

  @override
  State<_ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends State<_ZonePicker> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final List<String> zones =
        widget.zones.where((z) => z.toLowerCase().contains(_query.toLowerCase())).toList();
    return AlertDialog(
      title: const Text("Time zone"),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            SearchField(autofocus: true, onChanged: (v) => setState(() => _query = v)),
            Expanded(
              child: ListView.builder(
                itemCount: zones.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text(zones[i].replaceAll("_", " ")),
                  onTap: () => Navigator.pop(context, zones[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
