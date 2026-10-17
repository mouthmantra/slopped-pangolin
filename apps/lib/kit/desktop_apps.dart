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

import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

/// An installed application (a desktop entry), as far as opening files
/// goes.
class DesktopApp {
  DesktopApp({
    required this.id,
    required this.path,
    required this.name,
    required this.exec,
    this.genericName,
    this.icon,
    this.mimeTypes = const [],
    this.terminal = false,
  });

  /// Desktop file id, without ".desktop" (e.g. "org.gnome.eog").
  final String id;
  final String path;
  final String name;
  final String? genericName;
  final String? icon;
  final String exec;
  final List<String> mimeTypes;
  final bool terminal;

  /// Whether the app takes files (or URLs) on its command line.
  bool get takesFiles => RegExp("%[fFuU]").hasMatch(exec);
}

/// The installed applications and which ones open what, after the
/// freedesktop.org specifications: desktop entries' MimeType, mimeapps.list
/// for defaults and the user's associations, shared-mime-info for type
/// hierarchies.
class DesktopApps {
  DesktopApps._();

  static DesktopApps? _cache;
  static DateTime _loaded = DateTime.fromMillisecondsSinceEpoch(0);

  /// The applications, read again when the last read is a few seconds old
  /// (apps get installed while dialogs are open).
  static DesktopApps load() {
    final DateTime now = DateTime.now();
    if (_cache != null && now.difference(_loaded) < const Duration(seconds: 5)) {
      return _cache!;
    }
    _loaded = now;
    return _cache = DesktopApps._().._read();
  }

  /// By id, every app that can be started (NoDisplay ones included: some
  /// handlers are meant to be found only this way).
  final Map<String, DesktopApp> apps = {};
  final Set<String> _hidden = {};
  final Map<String, String> _aliases = {};
  final Map<String, List<String>> _parents = {};

  /// From mimeapps.list files, most important first.
  final Map<String, List<String>> _defaults = {};
  final Map<String, List<String>> _added = {};
  final Map<String, Set<String>> _removed = {};

  static List<String> get _dataDirs => [
        xdg.dataHome.path,
        for (final Directory d in xdg.dataDirs) d.path,
      ];

  static String get _desktopName =>
      (Platform.environment["XDG_CURRENT_DESKTOP"] ?? "Pangolin")
          .split(":")
          .first
          .toLowerCase();

  void _read() {
    for (final String dir in _dataDirs) {
      _readApplications(p.join(dir, "applications"));
    }
    for (final String dir in _dataDirs.reversed) {
      _readMimeTable(p.join(dir, "mime", "aliases"), (a, b) => _aliases[a] = b);
      _readMimeTable(
        p.join(dir, "mime", "subclasses"),
        (child, parent) => (_parents[child] ??= []).add(parent),
      );
    }
    for (final String file in _mimeappsFiles) {
      _readMimeapps(file);
    }
  }

  /// mimeapps.list files by precedence (Association between MIME types and
  /// applications, "File name and location").
  static List<String> get _mimeappsFiles {
    final String desktop = _desktopName;
    return [
      for (final String config in [
        xdg.configHome.path,
        for (final Directory d in xdg.configDirs) d.path,
      ]) ...[
        p.join(config, "$desktop-mimeapps.list"),
        p.join(config, "mimeapps.list"),
      ],
      for (final String data in _dataDirs) ...[
        p.join(data, "applications", "$desktop-mimeapps.list"),
        p.join(data, "applications", "mimeapps.list"),
      ],
    ];
  }

  void _readApplications(String root) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) return;
    final List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(recursive: true);
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity entity in entities) {
      if (!entity.path.endsWith(".desktop")) continue;
      // The desktop file id: the path below applications/, "/" made "-".
      final String id = p
          .relative(entity.path, from: root)
          .replaceAll("/", "-")
          .replaceFirst(RegExp(r"\.desktop$"), "");
      // A directory earlier in the search path wins (also when it hides
      // the app).
      if (apps.containsKey(id) || _hidden.contains(id)) continue;
      final Map<String, String> fields = _readEntry(entity.path);
      if (fields["Type"] != "Application" ||
          fields["Hidden"] == "true" ||
          (fields["Exec"] ?? "").isEmpty ||
          !_showsHere(fields) ||
          !_tryExec(fields["TryExec"])) {
        _hidden.add(id);
        continue;
      }
      apps[id] = DesktopApp(
        id: id,
        path: entity.path,
        name: fields["Name"] ?? id,
        genericName: fields["GenericName"],
        icon: fields["Icon"],
        exec: fields["Exec"]!,
        mimeTypes: (fields["MimeType"] ?? "")
            .split(";")
            .map((m) => m.trim())
            .where((m) => m.isNotEmpty)
            .toList(),
        terminal: fields["Terminal"] == "true",
      );
    }
  }

  /// The [Desktop Entry] group, with the name in the user's language.
  static Map<String, String> _readEntry(String path) {
    final Map<String, String> fields = {};
    final String lang =
        (Platform.environment["LANG"] ?? "").split(".").first; // e.g. de_DE
    final String shortLang = lang.split("_").first;
    bool inEntry = false;
    try {
      for (final String line in File(path).readAsLinesSync()) {
        final String trimmed = line.trim();
        if (trimmed.startsWith("[")) {
          inEntry = trimmed == "[Desktop Entry]";
          continue;
        }
        if (!inEntry || trimmed.startsWith("#")) continue;
        final int eq = trimmed.indexOf("=");
        if (eq <= 0) continue;
        final String key = trimmed.substring(0, eq).trim();
        final String value = trimmed.substring(eq + 1).trim();
        if (key == "Name[$lang]" || key == "GenericName[$lang]") {
          fields[key.split("[").first] = value;
          fields["_${key.split("[").first}_lang"] = "full";
        } else if (key == "Name[$shortLang]" || key == "GenericName[$shortLang]") {
          final String base = key.split("[").first;
          if (fields["_${base}_lang"] != "full") {
            fields[base] = value;
            fields["_${base}_lang"] = "short";
          }
        } else if (!key.contains("[")) {
          fields.putIfAbsent(key, () => value);
        }
      }
    } on FileSystemException {
      return const {};
    }
    return fields;
  }

  static bool _showsHere(Map<String, String> fields) {
    final List<String> desktops = (Platform.environment["XDG_CURRENT_DESKTOP"] ?? "Pangolin")
        .split(":")
        .map((d) => d.toLowerCase())
        .toList();
    bool listed(String? value) =>
        (value ?? "").split(";").any((d) => desktops.contains(d.trim().toLowerCase()));
    if (fields["OnlyShowIn"] != null && !listed(fields["OnlyShowIn"])) {
      return false;
    }
    return !listed(fields["NotShowIn"]);
  }

  static bool _tryExec(String? tryExec) {
    if (tryExec == null || tryExec.isEmpty) return true;
    if (p.isAbsolute(tryExec)) return File(tryExec).existsSync();
    return (Platform.environment["PATH"] ?? "/usr/bin:/bin")
        .split(":")
        .any((dir) => dir.isNotEmpty && File(p.join(dir, tryExec)).existsSync());
  }

  static void _readMimeTable(String path, void Function(String, String) add) {
    final File file = File(path);
    if (!file.existsSync()) return;
    try {
      for (final String line in file.readAsLinesSync()) {
        final List<String> parts = line.trim().split(RegExp(r"\s+"));
        if (parts.length == 2) add(parts[0], parts[1]);
      }
    } on FileSystemException {
      return;
    }
  }

  void _readMimeapps(String path) {
    final File file = File(path);
    if (!file.existsSync()) return;
    String? group;
    try {
      for (final String raw in file.readAsLinesSync()) {
        final String line = raw.trim();
        if (line.startsWith("[")) {
          group = line;
          continue;
        }
        final int eq = line.indexOf("=");
        if (eq <= 0 || line.startsWith("#")) continue;
        final String type = canonical(line.substring(0, eq).trim());
        final List<String> ids = line
            .substring(eq + 1)
            .split(";")
            .map((e) => e.trim().replaceFirst(RegExp(r"\.desktop$"), ""))
            .where((e) => e.isNotEmpty)
            .toList();
        switch (group) {
          case "[Default Applications]":
            (_defaults[type] ??= []).addAll(ids);
          case "[Added Associations]":
            (_added[type] ??= []).addAll(ids);
          case "[Removed Associations]":
            (_removed[type] ??= {}).addAll(ids);
        }
      }
    } on FileSystemException {
      return;
    }
  }

  /// [type] with aliases resolved (e.g. "application/x-pdf" is
  /// "application/pdf").
  String canonical(String type) => _aliases[type.toLowerCase()] ?? type.toLowerCase();

  /// [type] and the types it is a kind of, closest first (a shell script is
  /// also plain text; everything is application/octet-stream).
  List<String> lineage(String type) {
    final List<String> result = [];
    void visit(String t) {
      final String c = canonical(t);
      if (result.contains(c)) return;
      result.add(c);
      for (final String parent in _parents[c] ?? const []) {
        visit(parent);
      }
      // Implicit parents (shared-mime-info: "Subclassing").
      if (c.startsWith("text/") && c != "text/plain") visit("text/plain");
    }

    visit(type);
    return result;
  }

  /// Apps that open [type], best first: the default, the user's
  /// associations, then the ones that declare the type (or a type it's a
  /// kind of).
  List<DesktopApp> appsFor(String type) {
    final List<String> ids = [];
    for (final String t in lineage(type)) {
      final Set<String> removed = _removed[t] ?? const {};
      void add(String id) {
        if (!ids.contains(id) && !removed.contains(id) && apps.containsKey(id)) {
          ids.add(id);
        }
      }

      for (final String id in _defaults[t] ?? const []) {
        add(id);
      }
      for (final String id in _added[t] ?? const []) {
        add(id);
      }
      for (final DesktopApp app in apps.values) {
        if (app.mimeTypes.any((m) => canonical(m) == t)) add(app.id);
      }
    }
    return [for (final String id in ids) apps[id]!];
  }

  /// The app that opens [type] by default.
  DesktopApp? defaultFor(String type) {
    for (final String t in lineage(type)) {
      for (final String id in _defaults[t] ?? const []) {
        final DesktopApp? app = apps[id];
        if (app != null) return app;
      }
    }
    final List<DesktopApp> candidates = appsFor(type);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Makes [app] the default for [type] (in the user's mimeapps.list, as
  /// `xdg-mime default` does).
  static void setDefault(String type, DesktopApp app) {
    final File file = File(p.join(xdg.configHome.path, "mimeapps.list"));
    final List<String> lines =
        file.existsSync() ? file.readAsLinesSync() : <String>[];
    void put(String group, String value, {bool prepend = false}) {
      int start = lines.indexWhere((l) => l.trim() == group);
      if (start < 0) {
        if (lines.isNotEmpty && lines.last.trim().isNotEmpty) lines.add("");
        lines.add(group);
        start = lines.length - 1;
      }
      int end = start + 1;
      while (end < lines.length && !lines[end].trim().startsWith("[")) {
        end++;
      }
      for (int i = start + 1; i < end; i++) {
        final String line = lines[i];
        final int eq = line.indexOf("=");
        if (eq <= 0 || line.substring(0, eq).trim() != type) continue;
        if (!prepend) {
          lines[i] = "$type=$value";
          return;
        }
        final List<String> rest = line
            .substring(eq + 1)
            .split(";")
            .where((e) => e.isNotEmpty && e != value.replaceAll(";", ""))
            .toList();
        lines[i] = "$type=$value${rest.map((e) => "$e;").join()}";
        return;
      }
      lines.insert(end, "$type=$value");
    }

    put("[Default Applications]", "${app.id}.desktop;");
    put("[Added Associations]", "${app.id}.desktop;", prepend: true);
    file.parent.createSync(recursive: true);
    final File temp = File("${file.path}.tmp");
    temp.writeAsStringSync("${lines.join("\n")}\n");
    temp.renameSync(file.path);
    _cache = null;
  }

  /// The MIME type of [path] (from its name, then its first bytes).
  static String typeOf(String path) {
    final FileSystemEntityType kind = FileSystemEntity.typeSync(path);
    if (kind == FileSystemEntityType.directory) return "inode/directory";
    List<int> head = const [];
    try {
      final RandomAccessFile file = File(path).openSync();
      try {
        head = file.readSync(512);
      } finally {
        file.closeSync();
      }
    } on FileSystemException {
      // Unreadable: the name alone says what it is.
    }
    final String? type = lookupMimeType(path, headerBytes: head);
    if (type != null) return type;
    if (head.isEmpty) return "application/x-zerosize";
    // No NUL bytes: text.
    return head.contains(0) ? "application/octet-stream" : "text/plain";
  }

  /// A readable name of [type] ("PNG image", "PDF document").
  static String describe(String type) {
    final List<String> parts = type.split("/");
    if (parts.length != 2) return type;
    String sub = parts[1]
        .replaceFirst(RegExp(r"^(x-|vnd\.)"), "")
        .split(RegExp(r"[.+-]"))
        .last;
    if (sub.length <= 4) sub = sub.toUpperCase();
    return switch (parts[0]) {
      "image" => "$sub images",
      "video" => "$sub videos",
      "audio" => "$sub audio",
      "text" => sub == "PLAIN" ? "Text files" : "$sub files",
      "inode" => "Folders",
      _ => sub == "PDF" ? "PDF documents" : "$sub files",
    };
  }

  /// Starts [app] with [paths] (files) or [uris], following its Exec line's
  /// field codes. Completes with whether it could be started.
  static Future<bool> launch(
    DesktopApp app, {
    List<String> paths = const [],
    List<String> uris = const [],
  }) async {
    final List<String> targets = [
      ...paths,
      ...uris.map((u) => u.startsWith("file://") ? Uri.parse(u).toFilePath() : u),
    ];
    final List<String> asUris = [
      ...paths.map((f) => Uri.file(f).toString()),
      ...uris,
    ];
    final List<String> template = splitExec(app.exec);
    final bool single = !app.exec.contains("%F") && !app.exec.contains("%U");
    // %f/%u take one file: one process per file.
    final List<List<String>> runs = single && targets.length > 1
        ? [
            for (int i = 0; i < targets.length; i++)
              _expand(template, app, [targets[i]], [asUris[i]]),
          ]
        : [_expand(template, app, targets, asUris)];
    bool started = true;
    for (List<String> argv in runs) {
      if (argv.isEmpty) return false;
      if (app.terminal) {
        argv = [Platform.resolvedExecutable, "terminal", "-e", ...argv];
      }
      started &= await spawnDetached(argv);
    }
    return started;
  }

  static List<String> _expand(
    List<String> template,
    DesktopApp app,
    List<String> files,
    List<String> uris,
  ) {
    final List<String> argv = [];
    for (final String arg in template) {
      switch (arg) {
        case "%f":
          if (files.isNotEmpty) argv.add(files.first);
        case "%F":
          argv.addAll(files);
        case "%u":
          if (uris.isNotEmpty) argv.add(uris.first);
        case "%U":
          argv.addAll(uris);
        case "%i":
          if (app.icon != null) argv.addAll(["--icon", app.icon!]);
        case "%c":
          argv.add(app.name);
        case "%k":
          argv.add(app.path);
        default:
          // Field codes inside an argument; deprecated ones go away.
          final String expanded = arg
              .replaceAll("%f", files.isEmpty ? "" : files.first)
              .replaceAll("%u", uris.isEmpty ? "" : uris.first)
              .replaceAll("%c", app.name)
              .replaceAll("%k", app.path)
              .replaceAll(RegExp("%[dDnNvmFU]"), "")
              .replaceAll("%%", "%");
          if (expanded.isNotEmpty || arg.isEmpty) argv.add(expanded);
      }
    }
    return argv;
  }

  /// Splits an Exec value into arguments (quoting as in the Desktop Entry
  /// Specification).
  static List<String> splitExec(String exec) {
    final List<String> args = [];
    final StringBuffer current = StringBuffer();
    bool quoted = false;
    bool token = false;
    for (int i = 0; i < exec.length; i++) {
      final String c = exec[i];
      if (quoted) {
        if (c == r"\" && i + 1 < exec.length) {
          current.write(exec[++i]);
        } else if (c == '"') {
          quoted = false;
        } else {
          current.write(c);
        }
      } else if (c == '"') {
        quoted = true;
        token = true;
      } else if (c == " " || c == "\t") {
        if (token) {
          args.add(current.toString());
          current.clear();
          token = false;
        }
      } else if (c == r"\" && i + 1 < exec.length) {
        current.write(exec[++i]);
        token = true;
      } else {
        current.write(c);
        token = true;
      }
    }
    if (token) args.add(current.toString());
    return args;
  }

  /// Starts [argv] in a session of its own, outliving this app. setsid's
  /// fork is waited for here, so nothing is left behind as a zombie.
  static Future<bool> spawnDetached(List<String> argv, {String? workingDirectory}) async {
    try {
      if (_which("setsid") != null) {
        final Process process = await Process.start(
          "setsid",
          ["-f", "--", ...argv],
          mode: ProcessStartMode.inheritStdio,
          workingDirectory: workingDirectory,
        );
        return await process.exitCode == 0;
      }
      await Process.start(
        argv.first,
        argv.sublist(1),
        mode: ProcessStartMode.detached,
        workingDirectory: workingDirectory,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }

  static String? _which(String name) {
    for (final String dir in (Platform.environment["PATH"] ?? "/usr/bin:/bin").split(":")) {
      if (dir.isEmpty) continue;
      final String candidate = p.join(dir, name);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
