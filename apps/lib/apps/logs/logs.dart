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
import 'dart:io';

import 'package:dahlia_apps/kit/kit.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

final DahliaAppSpec logsApp = DahliaAppSpec(
  name: "logs",
  title: "Logs",
  builder: (context, args) => const LogsPage(),
);

class _LogEntry {
  _LogEntry({
    required this.time,
    required this.priority,
    required this.source,
    required this.message,
    this.fields = const {},
  });

  final DateTime? time;

  /// syslog priority: 0 (emergency) to 7 (debug).
  final int priority;
  final String source;
  final String message;
  final Map<String, String> fields;
}

enum _Source { journal, kernel, files }

enum _Level { all, errors, warnings, info }

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  _Source _source = _Source.journal;
  _Level _level = _Level.all;
  String _search = "";
  String? _logFile;
  List<String> _logFiles = [];

  final List<_LogEntry> _entries = [];
  bool _loading = false;
  String? _error;
  bool _follow = false;
  Process? _followProcess;
  _LogEntry? _selected;
  final ScrollController _scroll = ScrollController();

  bool get _hasJournal => SystemUtils.which("journalctl") != null;

  /// pangolin-read-logs next to this installation (session/libexec): reads
  /// the system logs as root through pkexec.
  static final String? _reader = () {
    final String path = p.normalize(p.join(p.dirname(Platform.resolvedExecutable),
        "..", "..", "libexec", "pangolin", "pangolin-read-logs"));
    return File(path).existsSync() ? path : null;
  }();

  static final bool _canAuthorize = _reader != null && SystemUtils.which("pkexec") != null;

  /// Reading through [_reader] once authorized.
  bool _elevated = false;

  /// The last read left out what only administrators may read.
  bool _restricted = false;

  @override
  void initState() {
    super.initState();
    _logFiles = _findLogFiles();
    if (!_hasJournal) _source = _Source.kernel;
    _load();
  }

  @override
  void dispose() {
    _followProcess?.kill();
    _scroll.dispose();
    super.dispose();
  }

  List<String> _findLogFiles() {
    final List<String> files = [];
    try {
      for (final FileSystemEntity e in Directory("/var/log").listSync(recursive: true)) {
        if (e is File &&
            (e.path.endsWith(".log") || p.basename(e.path) == "syslog" || p.basename(e.path) == "messages")) {
          try {
            e.openSync().closeSync();
            files.add(e.path);
          } on FileSystemException {
            // Not readable by this user.
          }
        }
      }
    } on FileSystemException {
      // No /var/log.
    }
    return files..sort();
  }

  Future<void> _load() async {
    _stopFollow();
    setState(() {
      _loading = true;
      _error = null;
      _restricted = false;
      _entries.clear();
      _selected = null;
    });

    try {
      switch (_source) {
        case _Source.journal:
          final ProcessResult result = _elevated
              ? await Process.run("pkexec", [_reader!, "journal"], stdoutEncoding: utf8)
              : await Process.run(
                  "journalctl",
                  ["-o", "json", "--no-pager", "-n", "3000"],
                  stdoutEncoding: utf8,
                );
          _checkAuthorization(result);
          // Not in the groups that may read the whole journal (wheel, adm,
          // systemd-journal): only this user's own messages.
          final String hint = "${result.stderr}";
          _restricted = !_elevated &&
              (hint.contains("not seeing messages from other users") ||
                  hint.contains("insufficient permissions"));
          if (result.exitCode != 0 && (result.stdout as String).isEmpty) {
            throw ProcessException("journalctl", [], "${result.stderr}".trim(), result.exitCode);
          }
          for (final String line in (result.stdout as String).split("\n")) {
            final _LogEntry? entry = _parseJournal(line);
            if (entry != null) _entries.add(entry);
          }
        case _Source.kernel:
          ProcessResult result;
          if (_elevated) {
            result = await Process.run("pkexec", [_reader!, "kernel"]);
            _checkAuthorization(result);
          } else {
            result = await Process.run("dmesg", ["--time-format=iso", "--decode"]);
            // busybox's dmesg doesn't know util-linux's options.
            if (result.exitCode != 0) result = await Process.run("dmesg", []);
            // kernel.dmesg_restrict (Fedora's default).
            _restricted = result.exitCode != 0 &&
                "${result.stderr}".contains("Operation not permitted");
          }
          if (result.exitCode != 0) {
            throw ProcessException(
              "dmesg",
              [],
              _restricted
                  ? "Kernel messages can only be read by an administrator"
                  : "${result.stderr}".trim(),
              result.exitCode,
            );
          }
          for (final String line in (result.stdout as String).split("\n")) {
            final _LogEntry? entry = _parseDmesg(line);
            if (entry != null) _entries.add(entry);
          }
        case _Source.files:
          final String? file = _logFile ?? _logFiles.firstOrNull;
          if (file == null) throw const FileSystemException("No readable log files in /var/log");
          _logFile = file;
          final List<String> lines = await File(file).readAsLines();
          for (final String line in lines.skip(lines.length > 5000 ? lines.length - 5000 : 0)) {
            if (line.trim().isEmpty) continue;
            _entries.add(_LogEntry(
              time: null,
              priority: _guessPriority(line),
              source: p.basename(file),
              message: line,
            ));
          }
      }
    } on Object catch (e) {
      _error = e is ProcessException ? (e.message.isEmpty ? "${e.executable} failed" : e.message) : "$e";
    }

    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    if (_follow) _startFollow();
  }

  /// pkexec ends with 126 when its password dialog was dismissed, 127 when
  /// not authorized.
  void _checkAuthorization(ProcessResult result) {
    if (!_elevated || (result.exitCode != 126 && result.exitCode != 127)) return;
    _elevated = false;
    _restricted = true;
    throw const ProcessException("pkexec", [], "Not authorized", 126);
  }

  void _authorize() {
    setState(() => _elevated = true);
    _load();
  }

  static int _guessPriority(String line) {
    final String l = line.toLowerCase();
    if (l.contains("error") || l.contains("fail") || l.contains("crit")) return 3;
    if (l.contains("warn")) return 4;
    return 6;
  }

  /// Terminal color codes some programs write into the journal.
  static final RegExp _ansi = RegExp(r"\x1B\[[0-?]*[ -/]*[@-~]");

  /// journalctl's JSON: a list of numbers is a binary field (bytes), any
  /// other list a field the entry has several times (audit records do).
  static String _fieldString(Object? value) {
    if (value is List) {
      if (value.every((e) => e is int)) {
        return utf8.decode(value.cast<int>(), allowMalformed: true);
      }
      return value.map(_fieldString).join("\n");
    }
    return value?.toString() ?? "";
  }

  static _LogEntry? _parseJournal(String line) {
    if (line.trim().isEmpty) return null;
    try {
      final Map<String, Object?> json = (jsonDecode(line) as Map).cast<String, Object?>();
      final int? micros = int.tryParse(json["__REALTIME_TIMESTAMP"]?.toString() ?? "");
      final String source = _fieldString(json["SYSLOG_IDENTIFIER"] ?? json["_COMM"] ?? json["_SYSTEMD_UNIT"] ?? "system");
      return _LogEntry(
        time: micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros),
        priority: int.tryParse(json["PRIORITY"]?.toString() ?? "") ?? 6,
        source: source,
        message: _fieldString(json["MESSAGE"]).replaceAll(_ansi, ""),
        fields: {
          for (final MapEntry<String, Object?> e in json.entries)
            if (!e.key.startsWith("__")) e.key: _fieldString(e.value),
        },
      );
    } on FormatException {
      return null;
    }
  }

  static _LogEntry? _parseDmesg(String line) {
    // e.g. "kern  :info  : 2026-10-12T21:00:00,123456+00:00 message"
    final Match? m = RegExp(r"^(\w+)\s*:(\w+)\s*:\s*(\S+)\s(.*)$").firstMatch(line);
    if (m == null) {
      return line.trim().isEmpty
          ? null
          : _LogEntry(time: null, priority: 6, source: "kernel", message: line);
    }
    const Map<String, int> levels = {
      "emerg": 0, "alert": 1, "crit": 2, "err": 3, "warn": 4, "notice": 5, "info": 6, "debug": 7, //
    };
    return _LogEntry(
      time: DateTime.tryParse(m.group(3)!.replaceFirst(",", ".")),
      priority: levels[m.group(2)] ?? 6,
      source: m.group(1) == "kern" ? "kernel" : m.group(1)!,
      message: m.group(4)!,
    );
  }

  Future<void> _startFollow() async {
    if (_source != _Source.journal) return;
    final Process process = _elevated
        ? await Process.start("pkexec", [_reader!, "journal-follow"])
        : await Process.start("journalctl", ["-o", "json", "-f", "-n", "0"]);
    _followProcess = process;
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final _LogEntry? entry = _parseJournal(line);
      if (entry == null || !mounted) return;
      final bool atBottom = !_scroll.hasClients ||
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
      setState(() => _entries.add(entry));
      if (atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    });
  }

  void _stopFollow() {
    final Process? process = _followProcess;
    _followProcess = null;
    if (process == null) return;
    // The elevated reader runs as root: it stops when its input closes.
    unawaited(process.stdin.close().catchError((Object _) {}));
    process.kill();
  }

  List<_LogEntry> get _visible {
    final String q = _search.toLowerCase();
    return _entries.where((e) {
      final bool levelOk = switch (_level) {
        _Level.all => true,
        _Level.errors => e.priority <= 3,
        _Level.warnings => e.priority == 4,
        _Level.info => e.priority >= 5,
      };
      if (!levelOk) return false;
      return q.isEmpty || e.message.toLowerCase().contains(q) || e.source.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _export(List<_LogEntry> entries) async {
    final String? path = await showFileDialog(
      context,
      mode: FileDialogMode.save,
      suggestedName: "logs-${DateFormat("yyyyMMdd-HHmmss").format(DateTime.now())}.txt",
    );
    if (path == null) return;
    final DateFormat format = DateFormat("yyyy-MM-dd HH:mm:ss");
    await File(path).writeAsString(
      entries
          .map((e) => "${e.time != null ? format.format(e.time!) : "-"} [${e.priority}] ${e.source}: ${e.message}")
          .join("\n"),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved ${entries.length} entries")));
    }
  }

  Color _priorityColor(int priority, ThemeData theme) => switch (priority) {
        <= 3 => theme.colorScheme.error,
        4 => Colors.orange,
        5 => theme.colorScheme.primary,
        7 => theme.disabledColor,
        _ => theme.colorScheme.onSurface.withValues(alpha: 0.4),
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_LogEntry> entries = _visible;
    final DateFormat format = DateFormat("MMM d HH:mm:ss");
    final int errors = _entries.where((e) => e.priority <= 3).length;
    final int warnings = _entries.where((e) => e.priority == 4).length;

    return DahliaScaffold(
      titlebarActions: [
        if (_source == _Source.journal)
          FilterChip(
            avatar: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text("Live"),
            selected: _follow,
            onSelected: (v) {
              setState(() => _follow = v);
              v ? _startFollow() : _stopFollow();
            },
          ),
        IconButton(tooltip: "Refresh", icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        IconButton(tooltip: "Export", icon: const Icon(Icons.save_alt_rounded), onPressed: () => _export(entries)),
      ],
      body: Row(
        children: [
          SidebarPane(
            width: 220,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                  child: Text("Source", style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor)),
                ),
                if (_hasJournal)
                  SidebarTile(
                    icon: Icons.receipt_long_rounded,
                    label: "System journal",
                    selected: _source == _Source.journal,
                    onTap: () {
                      setState(() => _source = _Source.journal);
                      _load();
                    },
                  ),
                SidebarTile(
                  icon: Icons.memory_rounded,
                  label: "Kernel",
                  selected: _source == _Source.kernel,
                  onTap: () {
                    setState(() => _source = _Source.kernel);
                    _load();
                  },
                ),
                for (final String file in _logFiles)
                  SidebarTile(
                    icon: Icons.description_outlined,
                    label: p.relative(file, from: "/var/log"),
                    selected: _source == _Source.files && _logFile == file,
                    onTap: () {
                      setState(() {
                        _source = _Source.files;
                        _logFile = file;
                      });
                      _load();
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                  child: Text("Level", style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor)),
                ),
                SidebarTile(
                  icon: Icons.all_inclusive_rounded,
                  label: "Everything",
                  selected: _level == _Level.all,
                  trailing: Text("${_entries.length}", style: theme.textTheme.bodySmall),
                  onTap: () => setState(() => _level = _Level.all),
                ),
                SidebarTile(
                  icon: Icons.error_outline_rounded,
                  label: "Errors",
                  selected: _level == _Level.errors,
                  trailing: Text("$errors", style: theme.textTheme.bodySmall),
                  onTap: () => setState(() => _level = _Level.errors),
                ),
                SidebarTile(
                  icon: Icons.warning_amber_rounded,
                  label: "Warnings",
                  selected: _level == _Level.warnings,
                  trailing: Text("$warnings", style: theme.textTheme.bodySmall),
                  onTap: () => setState(() => _level = _Level.warnings),
                ),
                SidebarTile(
                  icon: Icons.info_outline_rounded,
                  label: "Information",
                  selected: _level == _Level.info,
                  onTap: () => setState(() => _level = _Level.info),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(child: SearchField(hint: "Search messages", onChanged: (v) => setState(() => _search = v))),
                      if (_restricted && _canAuthorize && _error == null && !_loading) ...[
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: _authorize,
                          icon: const Icon(Icons.lock_open_rounded, size: 18),
                          label: const Text("Show system messages"),
                        ),
                      ],
                      const SizedBox(width: 12),
                      Text("${entries.length} entries", style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? EmptyState(
                              icon: _restricted ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
                              title: "Couldn't read logs",
                              subtitle: _error,
                              action: _restricted && _canAuthorize
                                  ? FilledButton.icon(
                                      onPressed: _authorize,
                                      icon: const Icon(Icons.lock_open_rounded),
                                      label: const Text("Authorize"),
                                    )
                                  : null,
                            )
                          : entries.isEmpty
                              ? const EmptyState(icon: Icons.inbox_outlined, title: "No log entries")
                              : ListView.builder(
                                  controller: _scroll,
                                  itemCount: entries.length,
                                  itemExtent: 28,
                                  itemBuilder: (context, index) {
                                    final _LogEntry e = entries[index];
                                    final bool selected = identical(e, _selected);
                                    return InkWell(
                                      onTap: () => setState(() => _selected = e),
                                      child: Container(
                                        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _priorityColor(e.priority, theme),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                e.time != null ? format.format(e.time!) : "",
                                                style: theme.textTheme.bodySmall?.copyWith(fontFamily: ZenitFonts.monospaceOf(context)),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 140,
                                              child: Text(
                                                e.source,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                e.message,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: e.priority <= 3 ? theme.colorScheme.error : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                ),
                if (_selected != null)
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(fontFamily: ZenitFonts.monospaceOf(context)),
                          children: [
                            TextSpan(text: "${_selected!.message}\n\n", style: const TextStyle(fontWeight: FontWeight.bold)),
                            for (final MapEntry<String, String> f in _selected!.fields.entries)
                              if (f.key != "MESSAGE") TextSpan(text: "${f.key}=${f.value}\n"),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
