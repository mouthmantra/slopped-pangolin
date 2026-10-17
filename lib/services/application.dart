import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/window/window_surface.dart';
import 'package:pangolin/components/window/window_toolbar.dart';
import 'package:pangolin/services/langpacks.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/extensions/extensions.dart';
import 'package:pangolin/utils/wm/wm.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_desktop/xdg_desktop.dart';
import 'package:xdg_directories/xdg_directories.dart' as xdg;

class ApplicationServiceFactory extends ServiceFactory<ApplicationService> {
  const ApplicationServiceFactory();

  @override
  ApplicationService build() => _LinuxApplicationService();

  @override
  ApplicationService? fallback() => _BuiltInApplicationService();
}

abstract class ApplicationService extends ListenableService {
  ApplicationService();

  static ApplicationService get current {
    return ServiceManager.getService<ApplicationService>()!;
  }

  List<DesktopEntry> listApplications();

  /// Starts the app [name] (a desktop entry id), with [args] after the
  /// command line of its entry.
  FutureOr<void> startApp(String name, {List<String> args = const []});
  DesktopEntry? getApp(String name);

  /// Applications started from the shell whose first window hasn't shown up
  /// yet (by desktop entry id): the taskbar shows them right away.
  final ValueNotifier<Set<String>> launching = ValueNotifier(const {});
  final Map<String, Timer> _launchTimeouts = {};

  /// [id] is starting (for at most [timeout]: some apps never show a window
  /// of their own id).
  void markLaunching(String id, {Duration timeout = const Duration(seconds: 10)}) {
    _launchTimeouts.remove(id)?.cancel();
    _launchTimeouts[id] = Timer(timeout, () => markLaunched(id));
    launching.value = {...launching.value, id};
  }

  /// [id]'s window showed up (or it took too long).
  void markLaunched(String id) {
    _launchTimeouts.remove(id)?.cancel();
    if (!launching.value.contains(id)) return;
    launching.value = {...launching.value}..remove(id);
  }

  /// Finds the desktop entry describing the application that owns [appId]
  /// (a Wayland app_id or X11 WM_CLASS).
  DesktopEntry? findForAppId(String? appId) {
    if (appId == null || appId.isEmpty) return null;
    final String needle = appId.toLowerCase();
    final List<DesktopEntry> apps = listApplications();

    return apps.firstWhereOrNull((e) => e.id.toLowerCase() == needle) ??
        apps.firstWhereOrNull(
          (e) => e.startupWmClass?.toLowerCase() == needle,
        ) ??
        apps.firstWhereOrNull(
          (e) => e.id.toLowerCase().split(".").last == needle.split(".").last,
        ) ??
        apps.firstWhereOrNull(
          (e) => _execName(e)?.toLowerCase() == needle,
        );
  }

  static String? _execName(DesktopEntry entry) {
    final List<String> argv = parseExec(entry.exec ?? "");
    if (argv.isEmpty) return null;
    return p.basename(argv.first);
  }

  /// Splits a desktop entry Exec value into argv following the Desktop Entry
  /// Specification: double quotes group arguments, backslash escapes the next
  /// character inside quotes, and field codes are expanded or dropped.
  static List<String> parseExec(String exec, {DesktopEntry? entry}) {
    final List<String> args = [];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;
    bool hasToken = false;

    for (int i = 0; i < exec.length; i++) {
      final String c = exec[i];
      if (inQuotes) {
        if (c == r"\" && i + 1 < exec.length) {
          current.write(exec[++i]);
        } else if (c == '"') {
          inQuotes = false;
        } else {
          current.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
        hasToken = true;
      } else if (c == " " || c == "\t") {
        if (hasToken) {
          args.add(current.toString());
          current.clear();
          hasToken = false;
        }
      } else {
        current.write(c);
        hasToken = true;
      }
    }
    if (hasToken) args.add(current.toString());

    final List<String> expanded = [];
    for (final String arg in args) {
      switch (arg) {
        case "%f" || "%F" || "%u" || "%U" || "%d" || "%D" || "%n" || "%N" ||
              "%v" || "%m":
          continue;
        case "%i":
          final String? icon = entry?.icon?.main;
          if (icon != null) expanded.addAll(["--icon", icon]);
        case "%c":
          if (entry != null) expanded.add(entry.name.main);
        case "%k":
          if (entry?.filePath != null) expanded.add(entry!.filePath!);
        default:
          expanded.add(arg.replaceAll("%%", "%"));
      }
    }
    return expanded;
  }
}

class _LinuxApplicationService extends ApplicationService {
  /// Entries keyed by file path.
  final Map<String, DesktopEntry> entries = {};

  /// Application directories in order of precedence.
  final List<String> _directories = [];

  int _rank(DesktopEntry entry) {
    final String? path = entry.filePath;
    if (path == null) return _directories.length;
    final int index = _directories.indexWhere((d) => p.isWithin(d, path));
    return index == -1 ? _directories.length : index;
  }

  @override
  List<DesktopEntry> listApplications() {
    // The same desktop file id may exist in several directories; the one in
    // the directory with the highest precedence wins (e.g. a user override in
    // ~/.local/share/applications hides the system entry).
    final Map<String, DesktopEntry> byId = {};
    for (final DesktopEntry entry in entries.values) {
      final DesktopEntry? existing = byId[entry.id];
      if (existing == null || _rank(entry) < _rank(existing)) {
        byId[entry.id] = entry;
      }
    }
    return byId.values.toList();
  }

  @override
  void startApp(String name, {List<String> args = const []}) {
    final DesktopEntry? app = getApp(name);

    if (app == null) {
      logger.warning(
        "The specified app $name can't be opened as it doesn't exist",
      );
      return;
    }

    final List<String> argv = [
      ...ApplicationService.parseExec(app.exec ?? "", entry: app),
      ...args,
    ];
    if (argv.isEmpty) {
      logger.warning("The app $name has no Exec line");
      return;
    }

    final String? workingDirectory =
        app.path != null && Directory(app.path!).existsSync() ? app.path : null;

    // Detached so applications outlive a restart of the shell.
    Process.start(
      argv.first,
      argv.sublist(1),
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    ).then(
      (process) {
        logger.info("Started $name (pid ${process.pid})");
        markLaunching(app.id);
      },
      onError: (Object e) => logger.warning("Failed to start $name: $e"),
    );
  }

  @override
  Future<void> start() async {
    await ServiceManager.waitForService<LangPacksService>();
    logger.info("Starting loading app service");

    _directories
      ..add(p.join(xdg.dataHome.path, "applications"))
      ..addAll(xdg.dataDirs.map((d) => p.join(d.path, "applications")));
    if (!_directories.contains("/usr/share/applications")) {
      _directories.add("/usr/share/applications");
    }

    for (final String dir in _directories.toSet()) {
      if (Directory(dir).existsSync()) {
        await _loadTree(dir);
      } else {
        _missing.add(dir);
      }
    }
    // Directories that appear later (the first flatpak app installed for
    // the user creates its exports directory): checked now and then.
    _missingPoll = Timer.periodic(const Duration(seconds: 5), (_) {
      for (final String dir in _missing.toList()) {
        if (!Directory(dir).existsSync()) continue;
        _missing.remove(dir);
        logger.info("Applications directory $dir appeared");
        unawaited(_loadTree(dir));
      }
    });
  }

  @override
  DesktopEntry? getApp(String name) =>
      listApplications().firstWhereOrNull((e) => e.id == name);

  /// Application directories (from [_directories]) that don't exist yet.
  final Set<String> _missing = {};
  Timer? _missingPoll;

  /// Watchers by directory: each directory of the trees is watched on its
  /// own, as a recursive watch doesn't see directories created after it
  /// started (wine's ~/.local/share/applications/wine/Programs/...).
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};

  /// Loads every entry below [path] and watches its directories.
  Future<void> _loadTree(String path) async {
    if (_watchers.containsKey(path)) return;
    _watch(path);
    final List<FileSystemEntity> entities;
    try {
      entities = await Directory(path).list(recursive: true).toList();
    } on FileSystemException catch (e) {
      logger.info("Couldn't list applications in $path: ${e.message}");
      return;
    }
    for (final FileSystemEntity entity in entities) {
      if (entity is Directory) {
        _watch(entity.path);
      } else {
        await _parseEntity(entity);
      }
    }
  }

  void _watch(String path) {
    if (_watchers.containsKey(path)) return;
    try {
      _watchers[path] = Directory(path).watch().listen(
            _onDirectoryEvent,
            // The directory went away (an uninstalled flatpak's last app
            // takes the exports directory with it).
            onError: (Object _) => _forget(path),
            onDone: () => _forget(path),
          );
    } on FileSystemException catch (e) {
      logger.info("Can't watch $path for applications: ${e.message}");
    }
  }

  /// [path] (a directory) is gone: its entries too, and a top level
  /// directory is waited for again.
  void _forget(String path) {
    unawaited(_watchers.remove(path)?.cancel());
    for (final String dir in _watchers.keys.toList()) {
      if (p.isWithin(path, dir)) unawaited(_watchers.remove(dir)?.cancel());
    }
    final int before = entries.length;
    entries.removeWhere((file, _) => p.isWithin(path, file));
    if (entries.length != before) notifyListeners();
    if (_directories.contains(path) && !Directory(path).existsSync()) {
      _missing.add(path);
    }
  }

  Future<void> _parseEntity(FileSystemEntity entity) async {
    if (p.extension(entity.path) != ".desktop") return;
    // Symbolic links (flatpak's exports) count as the file they point to.
    if (FileSystemEntity.typeSync(entity.path) != FileSystemEntityType.file) {
      if (entries.remove(entity.path) != null) notifyListeners();
      return;
    }

    // Re-parsing a modified entry may hide it, so start from scratch.
    if (entries.remove(entity.path) != null) notifyListeners();

    final String content;
    try {
      content = await File(entity.path).readAsString();
    } on FileSystemException {
      return;
    }
    try {
      final DesktopEntry entry = parseDesktopEntry(entity.path, content);
      if (entry.noDisplay == true || entry.hidden == true) return;

      if (entry.tryExec != null && !_executableExists(entry.tryExec!)) return;

      final List<String> onlyShowIn = entry.onlyShowIn ?? [];
      final List<String> notShowIn = entry.notShowIn ?? [];

      if (onlyShowIn.isNotEmpty && !onlyShowIn.contains("Pangolin") ||
          notShowIn.contains("Pangolin")) {
        return;
      }

      if (entry.domainKey != null) {
        LangPacksService.current.warmup(entry.domain!);
      }

      entries[entity.path] = entry;
      notifyListeners();
    } catch (e) {
      // Third-party entries that can't be repaired: not worth a warning.
      logger.info("Skipping invalid desktop entry '${entity.path}': $e");
      return;
    }
  }

  /// TryExec: an absolute path, or a program name looked up in $PATH.
  static bool _executableExists(String tryExec) {
    if (p.isAbsolute(tryExec)) return File(tryExec).existsSync();
    final String path = Platform.environment["PATH"] ?? "/usr/bin:/bin";
    return path
        .split(":")
        .any((dir) => dir.isNotEmpty && File(p.join(dir, tryExec)).existsSync());
  }

  Future<void> _onDirectoryEvent(FileSystemEvent event) async {
    if (event.isDirectory) {
      switch (event) {
        case FileSystemCreateEvent():
          await _loadTree(event.path);
        case FileSystemMoveEvent(:final String? destination):
          _forget(event.path);
          if (destination != null) await _loadTree(destination);
        case FileSystemDeleteEvent():
          _forget(event.path);
        default:
          break;
      }
      return;
    }

    switch (event) {
      case FileSystemDeleteEvent():
        if (entries.remove(event.path) != null) notifyListeners();
      // Package managers (rpm, dpkg, flatpak) write entries aside and
      // rename them into place.
      case FileSystemMoveEvent(:final String? destination):
        if (entries.remove(event.path) != null) notifyListeners();
        if (destination != null) await _parseEntity(File(destination));
      case FileSystemCreateEvent() || FileSystemModifyEvent():
        await _parseEntity(File(event.path));
    }
  }

  @override
  Future<void> stop() async {
    _missingPoll?.cancel();
    for (final StreamSubscription watcher in _watchers.values) {
      await watcher.cancel();
    }
    _watchers.clear();
  }
}

class _BuiltInApplicationService extends ApplicationService {
  final List<_BuiltinDesktopEntry> entries = [];
  final Map<DesktopEntry, Widget> builders = {};

  static const WindowEntry windowEntry = WindowEntry(
    features: [
      ResizeWindowFeature(),
      SurfaceWindowFeature(),
      FocusableWindowFeature(),
      ToolbarWindowFeature(),
    ],
    layoutInfo: FreeformLayoutInfo(
      position: Offset(32, 32),
      size: Size(1280, 720),
    ),
    properties: {
      ResizeWindowFeature.minSize: Size(480, 360),
      SurfaceWindowFeature.elevation: 4.0,
      SurfaceWindowFeature.shape: Constants.mediumShape,
      SurfaceWindowFeature.background: PangolinWindowSurface(),
      ToolbarWindowFeature.widget: PangolinWindowToolbar(
        barColor: Colors.transparent,
        textColor: Colors.black,
      ),
      ToolbarWindowFeature.size: 40.0,
    },
  );

  @override
  void start() {}

  @override
  _BuiltinDesktopEntry? getApp(String name) =>
      entries.firstWhereOrNull((e) => e.id == name);

  @override
  List<_BuiltinDesktopEntry> listApplications() => entries;

  @override
  void startApp(String name, {List<String> args = const []}) {
    final _BuiltinDesktopEntry? app = getApp(name);

    if (app == null) {
      logger.warning(
        "The specified app $name can't be opened as it doesn't exist",
      );
      return;
    }

    WindowManagerService.current.push(
      windowEntry.newInstance(
        content: app.content,
        overrideProperties: {
          WindowExtras.stableId: app.id,
          WindowEntry.title: app.name.main,
          WindowEntry.icon: app.icon != null
              ? AssetImage(
                  app.icon!.main.toResource().resolve().toString(),
                )
              : null,
        },
      ),
    );
  }

  @override
  void stop() {
    entries.clear();
    builders.clear();
  }
}

class _BuiltinDesktopEntry extends DesktopEntry {
  final Widget content;

  const _BuiltinDesktopEntry({
    required super.id,
    required this.content,
    required super.type,
    required super.name,
  });
}

/// Parses a desktop entry, repairing the mistakes common in third-party
/// entries instead of rejecting the whole application: non-standard booleans
/// ("yes", "No", ...) are converted, and other invalid optional keys are
/// dropped. Entries whose Type or Exec is invalid are still rejected.
DesktopEntry parseDesktopEntry(String path, String content) {
  String source = content;
  for (int attempt = 0; attempt < 16; attempt++) {
    try {
      return DesktopEntry.fromIni(path, source);
    } on ValueCastException catch (e) {
      final String? repaired = _repairDesktopEntry(source, e);
      if (repaired == null) rethrow;
      source = repaired;
    }
  }
  return DesktopEntry.fromIni(path, source);
}

String? _repairDesktopEntry(String source, ValueCastException error) {
  if (const {"Type", "Exec", "TryExec"}.contains(error.key)) return null;

  final List<String> lines = source.split("\n");
  String? group;
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i].trim();
    if (line.startsWith("[") && line.endsWith("]")) {
      group = line.substring(1, line.length - 1);
      continue;
    }
    if (group != error.group) continue;
    final int eq = line.indexOf("=");
    if (eq <= 0 || line.substring(0, eq).trim() != error.key) continue;

    if (error.requestedType == "boolean") {
      final String? value = switch (line.substring(eq + 1).trim().toLowerCase()) {
        "yes" || "on" || "y" => "true",
        "no" || "off" || "n" => "false",
        _ => null,
      };
      if (value != null) {
        lines[i] = "${error.key}=$value";
        return lines.join("\n");
      }
    }
    lines.removeAt(i);
    return lines.join("\n");
  }
  return null;
}
