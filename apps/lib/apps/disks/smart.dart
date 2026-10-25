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

import 'package:dahlia_apps/apps/disks/dialogs.dart';
import 'package:dahlia_apps/apps/disks/udisks.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dbus/dbus.dart';
import 'package:intl/intl.dart';

/// One line of the overall health shown in the drive's details and here.
String? smartAssessment(UObject drive) {
  if (drive.has(iAta) && drive.flag(iAta, "SmartEnabled")) {
    if (drive.flag(iAta, "SmartFailing")) return "Disk is failing";
    final int bad = drive.integer(iAta, "SmartNumBadSectors");
    final String temp = _celsius(drive.get(iAta, "SmartTemperature"));
    return [
      if (bad > 0) "Disk is OK, $bad bad sectors" else "Disk is OK",
      if (temp.isNotEmpty) temp,
    ].join(", ");
  }
  if (drive.has(iNvme) && drive.integer(iNvme, "SmartUpdated") > 0) {
    final Object? warnings = drive.get(iNvme, "SmartCriticalWarning");
    final String temp = _celsius(drive.get(iNvme, "SmartTemperature"));
    return [
      if (warnings is List && warnings.isNotEmpty)
        "Warning: ${warnings.map(_nvmeWarning).join(", ")}"
      else
        "Disk is OK",
      if (temp.isNotEmpty) temp,
    ].join(", ");
  }
  return null;
}

String _celsius(Object? kelvin) =>
    kelvin is num && kelvin > 0 ? "${(kelvin - 273.15).round()} °C" : "";

String _nvmeWarning(Object? w) => switch (w) {
      "spare" => "low spare capacity",
      "temperature" => "temperature",
      "degraded" => "reliability degraded",
      "readonly" => "read-only",
      "volatile_mem" => "backup memory failed",
      "pmr_readonly" => "persistent memory read-only",
      _ => "$w",
    };

String _selftest(String status) => switch (status) {
      "success" || "" => "Last self-test passed",
      // NVMe has several kinds ("aborted_format", "aborted_sanitize"…).
      final String s when s.startsWith("aborted") => "Last self-test was aborted",
      "interrupted" => "Last self-test was interrupted",
      "inprogress" => "Self-test in progress",
      "fatal" || "fatal_error" => "Last self-test FAILED",
      _ => "Last self-test failed ($status)",
    };

/// The rows of the attribute table of an ATA drive
/// (Drive.Ata.SmartGetAttributes): ID, name, value, normalized, threshold,
/// worst, type, assessment.
List<List<String>> ataAttributeRows(DBusValue attributes) => [
      for (final DBusValue a in (attributes as DBusArray).children)
        _ataRow((a as DBusStruct).children),
    ];

List<String> _ataRow(List<DBusValue> f) {
  final int flags = (f[2] as DBusUint16).value;
  final int value = (f[3] as DBusInt32).value;
  final int worst = (f[4] as DBusInt32).value;
  final int threshold = (f[5] as DBusInt32).value;
  final int pretty = (f[6] as DBusInt64).value;
  final String shown = switch ((f[7] as DBusInt32).value) {
    2 => formatDuration(Duration(milliseconds: pretty)),
    3 => "$pretty sectors",
    4 => "${((pretty - 273150) / 1000).round()} °C",
    _ => "$pretty",
  };
  final String assessment = threshold > 0 && value > 0 && value <= threshold
      ? (flags & 1 != 0 ? "FAILING" : "Failing (old age)")
      : threshold > 0 && worst > 0 && worst <= threshold
          ? "Failed in the past"
          : "OK";
  String known(int v) => v < 0 ? "N/A" : "$v";
  return [
    "${(f[0] as DBusByte).value}",
    (f[1] as DBusString).value,
    shown,
    known(value),
    known(threshold),
    known(worst),
    if (flags & 1 != 0) "Pre-fail" else "Old-age",
    assessment,
  ];
}

/// The attribute rows of an NVMe drive (NVMe.Controller.SmartGetAttributes):
/// label, value; unknown values are left out.
List<List<String>> nvmeAttributeRows(DBusValue attributes) {
  final Map<String, Object?> a = {
    for (final MapEntry<String, DBusValue> e in attributes.asStringVariantDict().entries)
      e.key: e.value.toNative(),
  };
  final NumberFormat number = NumberFormat.decimalPattern();
  String? percent(String key) => a[key] is int ? "${a[key]}%" : null;
  String? count(String key) => a[key] is int ? number.format(a[key]) : null;
  String? bytes(String key) => a[key] is int ? formatSize(a[key]! as int) : null;
  String? minutes(String key) =>
      a[key] is int ? formatDuration(Duration(minutes: a[key]! as int)) : null;
  return [
    for (final (String label, String? value) in [
      ("Available spare", percent("avail_spare")),
      ("Spare threshold", percent("spare_thresh")),
      ("Life used", percent("percent_used")),
      ("Data read", bytes("total_data_read")),
      ("Data written", bytes("total_data_written")),
      ("Busy time", minutes("ctrl_busy_time")),
      ("Power cycles", count("power_cycles")),
      ("Unsafe shutdowns", count("unsafe_shutdowns")),
      ("Media errors", count("media_errors")),
      ("Error log entries", count("num_err_log_entries")),
      ("Time above warning temperature", minutes("warning_temp_time")),
      ("Time above critical temperature", minutes("critical_temp_time")),
    ])
      if (value != null) [label, value],
  ];
}

/// SMART Data & Self-Tests of an ATA or NVMe drive.
class SmartDialog extends StatefulWidget {
  const SmartDialog({required this.udisks, required this.drive, super.key});

  final UDisksClient udisks;
  final DBusObjectPath drive;

  @override
  State<SmartDialog> createState() => _SmartDialogState();
}

class _SmartDialogState extends State<SmartDialog> {
  List<List<String>> _rows = [];
  String? _error;

  UObject? get _drive => widget.udisks[widget.drive];
  bool get _nvme => _drive?.has(iNvme) ?? false;
  String get _iface => _nvme ? iNvme : iAta;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _call(String method, [List<DBusValue> args = const []]) async {
    try {
      await widget.udisks.call(widget.drive, _iface, method, [...args, options()]);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _load() async {
    try {
      final List<DBusValue> r = await widget.udisks.call(
        widget.drive,
        _iface,
        "SmartGetAttributes",
        [options()],
      );
      if (!mounted) return;
      setState(() => _rows = _nvme ? nvmeAttributeRows(r.first) : ataAttributeRows(r.first));
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.udisks,
      builder: (context, _) {
        final UObject? drive = _drive;
        if (drive == null) {
          return const AlertDialog(content: Text("The drive was removed."));
        }
        final String status = drive.str(_iface, "SmartSelftestStatus");
        final bool testing = status == "inprogress";
        final int updated = drive.integer(_iface, "SmartUpdated");
        final int powerOn = _nvme
            ? drive.integer(iNvme, "SmartPowerOnHours") * 3600
            : drive.integer(iAta, "SmartPowerOnSeconds");
        return AlertDialog(
          title: const Text("SMART Data & Self-Tests"),
          content: SizedBox(
            width: 760,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                SettingsGroup(
                  children: [
                    if (!_nvme)
                      SettingsRow(
                        title: "SMART",
                        subtitle: "The drive tracks its own health",
                        trailing: ZenitSwitch(
                          value: drive.flag(iAta, "SmartEnabled"),
                          theme: ZenitTheme.switchTheme(context)
                              .copyWith(inactiveTrackColor: trackColor(theme)),
                          onChanged: (on) async {
                            await _call("SmartSetEnabled", [DBusBoolean(on)]);
                            if (on) await _load();
                          },
                        ),
                      ),
                    InfoRow(label: "Assessment", value: smartAssessment(drive) ?? "Unknown"),
                    InfoRow(label: "Self-test", value: _selftest(status)),
                    if (powerOn > 0)
                      InfoRow(label: "Powered on", value: formatDuration(Duration(seconds: powerOn))),
                    if (updated > 0)
                      InfoRow(
                        label: "Updated",
                        value: DateFormat.yMMMd().add_jm().format(
                              DateTime.fromMillisecondsSinceEpoch(updated * 1000),
                            ),
                      ),
                  ],
                ),
                if (testing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      value: 1 - drive.integer(_iface, "SmartSelftestPercentRemaining") / 100,
                      backgroundColor: progressTrackColor(theme),
                    ),
                  ),
                Expanded(child: _table(theme)),
              ],
            ),
          ),
          actions: [
            if (testing)
              TextButton(onPressed: () => _call("SmartSelftestAbort"), child: const Text("Stop Self-Test"))
            else
              MenuAnchor(
                menuChildren: [
                  for (final (String type, String label) in [
                    ("short", "Short (about 2 minutes)"),
                    ("extended", "Extended (an hour or more)"),
                    if (!_nvme) ("conveyance", "Conveyance"),
                  ])
                    MenuItemButton(
                      onPressed: () => _call("SmartSelftestStart", [DBusString(type)]),
                      child: Text(label),
                    ),
                ],
                builder: (context, menu, _) => TextButton(
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  child: const Text("Start Self-Test…"),
                ),
              ),
            TextButton(
              onPressed: () async {
                await _call("SmartUpdate");
                await _load();
              },
              child: const Text("Refresh"),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
          ],
        );
      },
    );
  }

  Widget _table(ThemeData theme) {
    final List<String> header = _nvme
        ? const ["Attribute", "Value"]
        : const ["ID", "Attribute", "Value", "Normalized", "Threshold", "Worst", "Type", "Assessment"];
    final List<int> flex = _nvme ? const [3, 2] : const [2, 9, 6, 4, 4, 3, 3, 4];
    Widget row(List<String> cells, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              for (int i = 0; i < cells.length; i++)
                Expanded(
                  flex: flex[i],
                  child: Text(
                    cells[i],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: bold ? FontWeight.w600 : null,
                      color: color ?? (i == cells.length - 1 && cells[i] == "FAILING" ? theme.colorScheme.error : null),
                    ),
                  ),
                ),
            ],
          ),
        );
    return ZenitSection(
      child: Column(
        children: [
          row(header, bold: true),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text("No attributes"))
                : ListView(children: [for (final List<String> r in _rows) row(r)]),
          ),
        ],
      ),
    );
  }
}
