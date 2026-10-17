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
import 'dart:math' as math;

import 'package:dahlia_apps/apps/files/file_ops.dart';
import 'package:dahlia_apps/kit/system.dart';
import 'package:dahlia_apps/kit/widgets.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;
import 'package:zenit_ui/zenit_ui.dart';

enum FileChooserMode {
  /// Pick one file, or several with [FileChooserRequest.multiple].
  open,

  /// Pick where to save one file, and its name.
  save,

  /// Pick the folder several files ([FileChooserRequest.files]) are saved
  /// in.
  saveFiles,

  /// Pick a folder.
  folder,
}

/// A named set of patterns the files shown must match (a portal filter).
class FileChooserFilter {
  const FileChooserFilter(this.name, this.patterns);

  final String name;

  /// (0, glob pattern) or (1, MIME type, maybe with a wildcard subtype).
  final List<(int, String)> patterns;

  bool accepts(String path) {
    final String name = p.basename(path);
    String? mime;
    for (final (int kind, String pattern) in patterns) {
      if (kind == 0) {
        if (_glob(pattern).hasMatch(name)) return true;
      } else {
        mime ??= lookupMimeType(path) ?? "application/octet-stream";
        if (pattern == mime ||
            pattern == "*" ||
            pattern == "*/*" ||
            (pattern.endsWith("/*") &&
                mime.startsWith(pattern.substring(0, pattern.length - 1)))) {
          return true;
        }
      }
    }
    return false;
  }

  static final Map<String, RegExp> _globs = {};

  static RegExp _glob(String pattern) => _globs.putIfAbsent(pattern, () {
        final StringBuffer re = StringBuffer("^");
        for (int i = 0; i < pattern.length; i++) {
          final String c = pattern[i];
          switch (c) {
            case "*":
              re.write(".*");
            case "?":
              re.write(".");
            case "[":
              final int end = pattern.indexOf("]", i + 1);
              if (end < 0) {
                re.write(r"\[");
              } else {
                re.write("[${pattern.substring(i + 1, end).replaceAll(r"\", r"\\")}]");
                i = end;
              }
            default:
              re.write(RegExp.escape(c));
          }
        }
        re.write(r"$");
        // Names in other cases too ("*.png" for PHOTO.PNG).
        return RegExp(re.toString(), caseSensitive: false);
      });
}

/// An extra option of the dialog, given by the app (a portal choice): a
/// checkbox when it has no [options], else a list to choose from.
class FileChooserChoice {
  FileChooserChoice({
    required this.id,
    required this.label,
    required this.value,
    this.options = const [],
  });

  final String id;
  final String label;

  /// (id, label) pairs.
  final List<(String, String)> options;
  String value;
}

class FileChooserRequest {
  FileChooserRequest({
    this.mode = FileChooserMode.open,
    this.title,
    this.acceptLabel,
    this.multiple = false,
    this.filters = const [],
    this.currentFilter,
    this.choices = const [],
    this.folder,
    this.name,
    this.files = const [],
  });

  final FileChooserMode mode;
  final String? title;
  final String? acceptLabel;
  final bool multiple;
  final List<FileChooserFilter> filters;

  /// Index in [filters] selected first.
  final int? currentFilter;
  final List<FileChooserChoice> choices;

  /// Folder shown first.
  final String? folder;

  /// Suggested name (save).
  final String? name;

  /// Names of the files saved together (saveFiles).
  final List<String> files;

  String get defaultTitle => switch (mode) {
        FileChooserMode.open => multiple ? "Open Files" : "Open File",
        FileChooserMode.save => "Save File",
        FileChooserMode.saveFiles => "Save Files",
        FileChooserMode.folder => "Choose a Folder",
      };
}

class FileChooserResult {
  const FileChooserResult({
    required this.paths,
    this.filter,
    this.choices = const {},
  });

  final List<String> paths;

  /// Index of the filter in use.
  final int? filter;

  /// Choice id to value.
  final Map<String, String> choices;
}

/// Pangolin's file chooser: places on the side, the folder's files in the
/// middle, the name, filters and options of the app at the bottom. Used by
/// the dahliaOS apps' dialogs and the desktop portal (any app's Open and
/// Save dialogs). [onDone] gets null when cancelled.
class FileChooser extends StatefulWidget {
  const FileChooser({
    required this.request,
    required this.onDone,
    this.showTitle = false,
    super.key,
  });

  final FileChooserRequest request;
  final ValueChanged<FileChooserResult?> onDone;

  /// The title is drawn in the toolbar (no window title bar shows it).
  final bool showTitle;

  @override
  State<FileChooser> createState() => _FileChooserState();
}

class _Item {
  _Item(this.path, this.isDir, this.size, this.modified);

  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;

  late final String name = p.basename(path);
  bool get hidden => name.startsWith(".") || name.endsWith("~");
}

enum _Sort { name, size, modified }

class _FileChooserState extends State<FileChooser> {
  static const double _rowHeight = 36;

  FileChooserRequest get _request => widget.request;
  FileChooserMode get _mode => _request.mode;

  /// The folder shown, null while showing recent files.
  String? _dir;
  final List<String?> _back = [];
  final List<String?> _forward = [];

  List<_Item> _items = [];
  bool _loading = false;
  String? _error;

  final Set<String> _selected = {};
  String? _anchor;
  bool _showHidden = false;
  _Sort _sort = _Sort.name;
  bool _ascending = true;
  int? _filter;
  String _query = "";
  bool _editingLocation = false;

  late final TextEditingController _name =
      TextEditingController(text: _request.name ?? "");
  final TextEditingController _location = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _listFocus = FocusNode(debugLabel: "file chooser list");
  final FocusNode _nameFocus = FocusNode(debugLabel: "file chooser name");
  final FocusNode _searchFocus = FocusNode(debugLabel: "file chooser search");
  final FocusNode _locationFocus = FocusNode(debugLabel: "file chooser location");
  final ScrollController _scroll = ScrollController();
  final ScrollController _crumbs = ScrollController();

  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _reload;

  late final List<Place> _places = FileOps.userPlaces();
  late final List<Place> _bookmarks = _readBookmarks();
  late final List<Place> _volumes = FileOps.volumes();

  bool get _saving =>
      _mode == FileChooserMode.save || _mode == FileChooserMode.saveFiles;

  @override
  void initState() {
    super.initState();
    _filter = _request.filters.isEmpty
        ? null
        : (_request.currentFilter ?? 0).clamp(0, _request.filters.length - 1);
    String start = _request.folder ?? "";
    if (start.isEmpty || !Directory(start).existsSync()) {
      start = _saving
          ? _places
                  .where((pl) => pl.label == "Documents")
                  .firstOrNull
                  ?.path ??
              SystemUtils.home
          : SystemUtils.home;
    }
    _go(start, record: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mode == FileChooserMode.save) {
        _nameFocus.requestFocus();
        // The name without its extension, ready to be typed over.
        final String text = _name.text;
        final int dot = text.lastIndexOf(".");
        _name.selection = TextSelection(
          baseOffset: 0,
          extentOffset: dot > 0 ? dot : text.length,
        );
      } else {
        _listFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_watcher?.cancel());
    _reload?.cancel();
    _name.dispose();
    _location.dispose();
    _search.dispose();
    _listFocus.dispose();
    _nameFocus.dispose();
    _searchFocus.dispose();
    _locationFocus.dispose();
    _scroll.dispose();
    _crumbs.dispose();
    super.dispose();
  }

  static List<Place> _readBookmarks() {
    final File file = File(p.join(xdg.configHome.path, "gtk-3.0", "bookmarks"));
    if (!file.existsSync()) return const [];
    final List<Place> places = [];
    try {
      for (final String line in file.readAsLinesSync()) {
        final int space = line.indexOf(" ");
        final String uri = space < 0 ? line : line.substring(0, space);
        if (!uri.startsWith("file://")) continue;
        final String path = Uri.parse(uri).toFilePath();
        if (!Directory(path).existsSync()) continue;
        final String label = space < 0 ? p.basename(path) : line.substring(space + 1);
        places.add(Place(label, Icons.bookmark_outline_rounded, path));
      }
    } on Object {
      return places;
    }
    return places;
  }

  /// Recently used files (GTK's recently-used.xbel), newest first.
  static Future<List<_Item>> _recentItems() async {
    final File file = File(p.join(xdg.dataHome.path, "recently-used.xbel"));
    if (!file.existsSync()) return const [];
    final String xml = await file.readAsString();
    final List<_Item> items = [];
    final Set<String> seen = {};
    for (final RegExpMatch m in RegExp(r'<bookmark\s+href="([^"]+)"[^>]*?modified="([^"]+)"')
        .allMatches(xml)) {
      final String href = m.group(1)!.replaceAll("&amp;", "&");
      if (!href.startsWith("file://")) continue;
      final String path;
      try {
        path = Uri.parse(href).toFilePath();
      } on Object {
        continue;
      }
      if (!seen.add(path)) continue;
      final FileStat stat = await FileStat.stat(path);
      if (stat.type != FileSystemEntityType.file) continue;
      items.add(_Item(path, false, stat.size,
          DateTime.tryParse(m.group(2)!)?.toLocal() ?? stat.modified));
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items.take(60).toList();
  }

  void _go(String? dir, {bool record = true}) {
    if (record && dir != _dir) {
      _back.add(_dir);
      _forward.clear();
    }
    setState(() {
      _dir = dir;
      _editingLocation = false;
      _selected.clear();
      _anchor = null;
      _search.clear();
      _query = "";
    });
    unawaited(_load());
    unawaited(_watcher?.cancel());
    _watcher = null;
    if (dir != null) {
      try {
        _watcher = Directory(dir).watch().listen((_) {
          _reload?.cancel();
          _reload = Timer(const Duration(milliseconds: 300), () => _load(keepSelection: true));
        }, onError: (Object _) {});
      } on FileSystemException {
        // Not watchable: shown as it is now.
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbs.hasClients) _crumbs.jumpTo(_crumbs.position.maxScrollExtent);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _load({bool keepSelection = false}) async {
    final String? dir = _dir;
    setState(() {
      _loading = true;
      _error = null;
    });
    List<_Item> items = [];
    String? error;
    if (dir == null) {
      items = await _recentItems();
    } else {
      try {
        await for (final FileSystemEntity entity in Directory(dir).list(followLinks: false)) {
          final FileStat stat = await FileStat.stat(entity.path);
          final bool isDir = stat.type == FileSystemEntityType.directory;
          if (stat.type == FileSystemEntityType.notFound && entity is! Link) continue;
          items.add(_Item(entity.path, isDir, stat.size, stat.modified));
        }
      } on FileSystemException catch (e) {
        error = e.osError?.errorCode == 13
            ? "You don't have permission to open this folder"
            : "This folder can't be opened";
      }
    }
    if (!mounted || dir != _dir) return;
    setState(() {
      _items = items;
      _loading = false;
      _error = error;
      if (keepSelection) {
        _selected.retainWhere((s) => items.any((i) => i.path == s));
      }
    });
  }

  /// What the list shows, in order.
  List<_Item> get _visible {
    final String query = _query.toLowerCase();
    final FileChooserFilter? filter = _filter == null ? null : _request.filters[_filter!];
    final List<_Item> visible = _items.where((item) {
      if (!_showHidden && item.hidden) return false;
      if (query.isNotEmpty && !item.name.toLowerCase().contains(query)) return false;
      if (item.isDir) return true;
      if (_mode == FileChooserMode.folder || _mode == FileChooserMode.saveFiles) {
        return false;
      }
      return filter == null || filter.accepts(item.path);
    }).toList();
    if (_dir == null) return visible; // Recent: newest first.
    int compare(_Item a, _Item b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      final int result = switch (_sort) {
        _Sort.name => byName,
        _Sort.size => a.size.compareTo(b.size),
        _Sort.modified => a.modified.compareTo(b.modified),
      };
      return (_ascending ? result : -result) == 0 ? byName : (_ascending ? result : -result);
    }

    return visible..sort(compare);
  }

  void _select(_Item item, List<_Item> visible) {
    final bool multiple = _request.multiple && _mode == FileChooserMode.open;
    setState(() {
      if (multiple && HardwareKeyboard.instance.isShiftPressed && _anchor != null) {
        final int from = visible.indexWhere((i) => i.path == _anchor);
        final int to = visible.indexOf(item);
        if (from >= 0 && to >= 0) {
          _selected
            ..clear()
            ..addAll(visible
                .sublist(math.min(from, to), math.max(from, to) + 1)
                .map((i) => i.path));
          return;
        }
      }
      if (multiple && HardwareKeyboard.instance.isControlPressed) {
        if (!_selected.remove(item.path)) _selected.add(item.path);
      } else {
        _selected
          ..clear()
          ..add(item.path);
      }
      _anchor = item.path;
    });
    if (_mode == FileChooserMode.save && !item.isDir) _name.text = item.name;
  }

  void _activate(_Item item) {
    if (item.isDir) {
      _go(item.path);
    } else if (_mode == FileChooserMode.open) {
      _done([item.path]);
    } else if (_mode == FileChooserMode.save) {
      _name.text = item.name;
      unawaited(_accept());
    }
  }

  Future<void> _accept() async {
    final List<_Item> selected = _items.where((i) => _selected.contains(i.path)).toList();
    switch (_mode) {
      case FileChooserMode.open:
        final List<String> files = [for (final _Item i in selected) if (!i.isDir) i.path];
        if (files.isNotEmpty) {
          _done(files);
        } else if (selected.length == 1) {
          _go(selected.first.path);
        }
      case FileChooserMode.folder:
        final String? folder = selected.length == 1 && selected.first.isDir
            ? selected.first.path
            : _dir;
        if (folder != null) _done([folder]);
      case FileChooserMode.save:
        String name = _name.text.trim();
        if (name.isEmpty) return;
        final String? dir = _dir;
        if (name.startsWith("~/")) name = p.join(SystemUtils.home, name.substring(2));
        final String target = p.isAbsolute(name) ? name : p.join(dir ?? SystemUtils.home, name);
        // A folder typed (or a path to one): go there.
        if (Directory(target).existsSync()) {
          _name.clear();
          _go(target);
          return;
        }
        if (!Directory(p.dirname(target)).existsSync()) {
          _toast("The folder “${p.dirname(target)}” doesn't exist");
          return;
        }
        if (File(target).existsSync() && !await _confirmReplace([p.basename(target)])) {
          return;
        }
        if (!_writable(p.dirname(target))) {
          _toast("You can't save files in “${p.basename(p.dirname(target))}”");
          return;
        }
        _done([target]);
      case FileChooserMode.saveFiles:
        final String? dir = _dir;
        if (dir == null) return;
        final String folder = selected.length == 1 && selected.first.isDir
            ? selected.first.path
            : dir;
        if (!_writable(folder)) {
          _toast("You can't save files in “${p.basename(folder)}”");
          return;
        }
        final List<String> existing = [
          for (final String f in _request.files)
            if (FileSystemEntity.typeSync(p.join(folder, f)) != FileSystemEntityType.notFound) f,
        ];
        if (existing.isNotEmpty && !await _confirmReplace(existing)) return;
        _done([for (final String f in _request.files) p.join(folder, f)]);
    }
  }

  static bool _writable(String dir) {
    try {
      final File probe = File(p.join(dir, ".pangolin-write-test-$pid"));
      probe.writeAsStringSync("");
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _confirmReplace(List<String> names) async {
    final bool? replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          names.length == 1
              ? "Replace “${names.first}”?"
              : "Replace ${names.length} files?",
        ),
        content: Text(
          names.length == 1
              ? "A file with this name already exists here. Replacing it overwrites what it contains."
              : "Files with these names already exist here: ${names.take(5).join(", ")}"
                  "${names.length > 5 ? "…" : ""}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Replace"),
          ),
        ],
      ),
    );
    return replace ?? false;
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _done(List<String> paths) {
    widget.onDone(
      FileChooserResult(
        paths: paths,
        filter: _filter,
        choices: {for (final FileChooserChoice c in _request.choices) c.id: c.value},
      ),
    );
  }

  Future<void> _newFolder() async {
    final String? dir = _dir;
    if (dir == null) return;
    final TextEditingController name = TextEditingController(text: "New Folder");
    name.selection = TextSelection(baseOffset: 0, extentOffset: name.text.length);
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Folder"),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Folder name"),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name.text),
            child: const Text("Create"),
          ),
        ],
      ),
    );
    name.dispose();
    final String folder = chosen?.trim() ?? "";
    if (folder.isEmpty || folder.contains("/")) return;
    final String path = p.join(dir, folder);
    try {
      Directory(path).createSync();
    } on FileSystemException catch (e) {
      _toast("Couldn't create the folder: ${e.osError?.message ?? e.message}");
      return;
    }
    // Where it's made to be used.
    _go(path);
  }

  void _up() {
    final String? dir = _dir;
    if (dir == null || p.dirname(dir) == dir) return;
    final String previous = dir;
    _go(p.dirname(dir));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The folder we came from stays selected, as in Files.
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted && _items.any((i) => i.path == previous)) {
          setState(() {
            _selected
              ..clear()
              ..add(previous);
            _anchor = previous;
          });
        }
      });
    });
  }

  void _history(bool forward) {
    final List<String?> from = forward ? _forward : _back;
    final List<String?> to = forward ? _back : _forward;
    if (from.isEmpty) return;
    to.add(_dir);
    _go(from.removeLast(), record: false);
  }

  void _moveSelection(int delta, List<_Item> visible) {
    if (visible.isEmpty) return;
    final int current = _anchor == null ? -1 : visible.indexWhere((i) => i.path == _anchor);
    final int next = (current < 0 ? (delta > 0 ? 0 : visible.length - 1) : current + delta)
        .clamp(0, visible.length - 1);
    final _Item item = visible[next];
    setState(() {
      _selected
        ..clear()
        ..add(item.path);
      _anchor = item.path;
    });
    if (_mode == FileChooserMode.save && !item.isDir) _name.text = item.name;
    if (_scroll.hasClients) {
      final double top = next * _rowHeight;
      final double view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowHeight - view);
      }
    }
  }

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final List<_Item> visible = _visible;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, visible);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, visible);
    } else if (key == LogicalKeyboardKey.home) {
      _moveSelection(-visible.length, visible);
    } else if (key == LogicalKeyboardKey.end) {
      _moveSelection(visible.length, visible);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final _Item? item = visible.where((i) => _selected.contains(i.path)).firstOrNull;
      if (item != null && _selected.length == 1 && item.isDir) {
        _go(item.path);
      } else {
        unawaited(_accept());
      }
    } else if (key == LogicalKeyboardKey.backspace) {
      _up();
    } else if (key == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isControlPressed &&
        _request.multiple) {
      setState(() => _selected
        ..clear()
        ..addAll(visible.where((i) => !i.isDir).map((i) => i.path)));
    } else if (event.character != null &&
        event.character!.trim().isNotEmpty &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      // Typing searches the folder.
      _search.text = _search.text + event.character!;
      _search.selection = TextSelection.collapsed(offset: _search.text.length);
      setState(() => _query = _search.text);
      _searchFocus.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_Item> visible = _visible;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_editingLocation) {
            setState(() => _editingLocation = false);
          } else {
            widget.onDone(null);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): _editLocation,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          setState(() => _showHidden = !_showHidden);
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _history(false),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _history(true),
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _up,
        const SingleActivator(LogicalKeyboardKey.home, alt: true): () => _go(SystemUtils.home),
      },
      child: Material(
        color: theme.colorScheme.surface.themedLightness(context, 0.02),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarPane(width: 200, child: _sidebar()),
            Expanded(
              child: Column(
                children: [
                  _toolbar(theme),
                  Expanded(
                    child: Focus(
                      focusNode: _listFocus,
                      onKeyEvent: _onListKey,
                      child: _list(theme, visible),
                    ),
                  ),
                  _footer(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() {
    Widget tile(IconData icon, String label, String? path) => SidebarTile(
          icon: icon,
          label: label,
          selected: _dir == path,
          onTap: () => _go(path),
        );
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_mode == FileChooserMode.open) tile(Icons.history_rounded, "Recent", null),
        for (final Place place in _places) tile(place.icon, place.label, place.path),
        if (_bookmarks.isNotEmpty) ...[
          heading("Bookmarks"),
          for (final Place place in _bookmarks) tile(place.icon, place.label, place.path),
        ],
        heading("Devices"),
        for (final Place place in _volumes) tile(place.icon, place.label, place.path),
        tile(Icons.computer_rounded, "Computer", "/"),
      ],
    );
  }

  void _editLocation() {
    setState(() {
      _editingLocation = true;
      _location.text = _dir == null ? "" : "${_dir!}${_dir == "/" ? "" : "/"}";
      // Selected: typing a location replaces it, as in GTK and browsers.
      _location.selection = TextSelection(baseOffset: 0, extentOffset: _location.text.length);
    });
    _locationFocus.requestFocus();
  }

  void _submitLocation(String value) {
    String path = value.trim();
    if (path.isEmpty) return;
    if (path == "~" || path.startsWith("~/")) {
      path = p.join(SystemUtils.home, path.length > 2 ? path.substring(2) : "");
    }
    if (!p.isAbsolute(path)) path = p.join(_dir ?? SystemUtils.home, path);
    path = p.normalize(path);
    if (Directory(path).existsSync()) {
      _go(path);
    } else if (File(path).existsSync() && _mode == FileChooserMode.open) {
      _done([path]);
    } else if (_mode == FileChooserMode.save && Directory(p.dirname(path)).existsSync()) {
      _go(p.dirname(path));
      _name.text = p.basename(path);
    } else {
      _toast("“$value” doesn't exist");
    }
  }

  Widget _toolbar(ThemeData theme) {
    final String? dir = _dir;
    final Color fill = theme.colorScheme.onSurface.withValues(alpha: 0.06);
    Widget navButton(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
        );

    final Widget location;
    if (_editingLocation) {
      location = SizedBox(
        height: 36,
        child: TextField(
          controller: _location,
          focusNode: _locationFocus,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: fill,
            hintText: "Type a location",
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: _submitLocation,
          onTapOutside: (_) => setState(() => _editingLocation = false),
        ),
      );
    } else {
      location = GestureDetector(
        onDoubleTap: _editLocation,
        child: Container(
          height: 36,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _crumbs,
                  scrollDirection: Axis.horizontal,
                  child: Row(children: _breadcrumbs(theme, dir)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 16),
                tooltip: "Type a location (Ctrl+L)",
                visualDensity: VisualDensity.compact,
                onPressed: _editLocation,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          if (widget.showTitle) ...[
            const SizedBox(width: 8),
            Text(
              _request.title ?? _request.defaultTitle,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
          ],
          navButton(Icons.arrow_back_rounded, "Back", _back.isEmpty ? null : () => _history(false)),
          navButton(Icons.arrow_forward_rounded, "Forward", _forward.isEmpty ? null : () => _history(true)),
          navButton(
            Icons.arrow_upward_rounded,
            "Enclosing folder",
            dir == null || p.dirname(dir) == dir ? null : _up,
          ),
          const SizedBox(width: 4),
          Expanded(child: location),
          const SizedBox(width: 8),
          SearchField(
            controller: _search,
            width: 180,
            hint: "Search",
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (_) => _listFocus.requestFocus(),
          ),
          if (dir != null && _mode != FileChooserMode.open)
            navButton(Icons.create_new_folder_outlined, "New folder", _newFolder),
          navButton(
            _showHidden ? Icons.visibility_rounded : Icons.visibility_off_outlined,
            _showHidden ? "Hide hidden files (Ctrl+H)" : "Show hidden files (Ctrl+H)",
            () => setState(() => _showHidden = !_showHidden),
          ),
        ],
      ),
    );
  }

  List<Widget> _breadcrumbs(ThemeData theme, String? dir) {
    if (dir == null) {
      return [
        _Crumb(icon: Icons.history_rounded, label: "Recent", current: true, onTap: () {}),
      ];
    }
    final String home = SystemUtils.home;
    final List<(String, String, IconData?)> parts = [];
    String rest;
    if (dir == home || p.isWithin(home, dir)) {
      parts.add(("Home", home, Icons.home_rounded));
      rest = p.relative(dir, from: home);
      if (rest == ".") rest = "";
    } else {
      parts.add(("Computer", "/", Icons.computer_rounded));
      rest = dir.substring(1);
    }
    String path = parts.first.$2;
    for (final String segment in rest.split("/")) {
      if (segment.isEmpty) continue;
      path = p.join(path, segment);
      parts.add((segment, path, null));
    }
    return [
      for (int i = 0; i < parts.length; i++) ...[
        if (i > 0)
          Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
        _Crumb(
          icon: parts[i].$3,
          label: parts[i].$1,
          current: i == parts.length - 1,
          onTap: () => _go(parts[i].$2),
        ),
      ],
    ];
  }

  Widget _list(ThemeData theme, List<_Item> visible) {
    final TextStyle? label = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    Widget header(String text, _Sort sort, {double? width, bool end = false}) {
      final Widget content = InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _dir == null
            ? null
            : () => setState(() {
                  if (_sort == sort) {
                    _ascending = !_ascending;
                  } else {
                    _sort = sort;
                    _ascending = true;
                  }
                }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(text, style: label),
              if (_sort == sort && _dir != null)
                Icon(
                  _ascending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: label?.color,
                ),
            ],
          ),
        ),
      );
      return width == null ? Expanded(child: content) : SizedBox(width: width, child: content);
    }

    final Widget body;
    if (_error != null) {
      body = Center(child: EmptyState(icon: Icons.lock_outline_rounded, title: _error!));
    } else if (visible.isEmpty && !_loading) {
      body = Center(
        child: EmptyState(
          icon: _query.isNotEmpty ? Icons.search_off_rounded : Icons.folder_open_rounded,
          title: _query.isNotEmpty
              ? "Nothing here matches “$_query”"
              : _dir == null
                  ? "No recent files"
                  : "This folder is empty",
        ),
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        itemExtent: _rowHeight,
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final _Item item = visible[index];
          return _Row(
            item: item,
            selected: _selected.contains(item.path),
            dimmed: item.hidden,
            subtitle: _dir == null ? p.dirname(item.path) : null,
            date: _formatDate(item.modified),
            onTap: () {
              _select(item, visible);
              _listFocus.requestFocus();
            },
            onDoubleTap: () => _activate(item),
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              const SizedBox(width: 34),
              header("Name", _Sort.name),
              header("Size", _Sort.size, width: 90, end: true),
              const SizedBox(width: 16),
              header("Modified", _Sort.modified, width: 110),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  static String _formatDate(DateTime time) {
    final DateTime now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return DateFormat.Hm().format(time);
    }
    if (now.difference(time).inDays < 6 && time.isBefore(now)) {
      return DateFormat.E().format(time);
    }
    if (time.year == now.year) return DateFormat.MMMd().format(time);
    return DateFormat.yMMMd().format(time);
  }

  Widget _footer(ThemeData theme) {
    final String accept = _request.acceptLabel?.replaceAll("_", "") ??
        switch (_mode) {
          FileChooserMode.open => "Open",
          FileChooserMode.save || FileChooserMode.saveFiles => "Save",
          FileChooserMode.folder => "Select",
        };
    final bool canAccept = switch (_mode) {
      FileChooserMode.open => _selected.isNotEmpty,
      FileChooserMode.folder || FileChooserMode.saveFiles => _dir != null,
      FileChooserMode.save => _name.text.trim().isNotEmpty,
    };
    final Color fill = theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return Container(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_request.choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [for (final FileChooserChoice c in _request.choices) _choice(c)],
              ),
            ),
          Row(
            children: [
              if (_mode == FileChooserMode.save)
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: fill,
                        hintText: "File name",
                        prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(19),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => unawaited(_accept()),
                    ),
                  ),
                )
              else if (_mode == FileChooserMode.saveFiles)
                Expanded(
                  child: Text(
                    _request.files.length == 1
                        ? "Saves “${_request.files.first}” in this folder"
                        : "Saves ${_request.files.length} files in this folder",
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              if (_request.filters.isNotEmpty) ...[
                const SizedBox(width: 12),
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(19)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _filter,
                      borderRadius: BorderRadius.circular(12),
                      items: [
                        for (int i = 0; i < _request.filters.length; i++)
                          DropdownMenuItem(value: i, child: Text(_request.filters[i].name)),
                      ],
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              TextButton(onPressed: () => widget.onDone(null), child: const Text("Cancel")),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: canAccept ? () => unawaited(_accept()) : null,
                child: Text(accept),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice(FileChooserChoice choice) {
    if (choice.options.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => choice.value = choice.value == "true" ? "false" : "true"),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: choice.value == "true",
              onChanged: (v) => setState(() => choice.value = v == true ? "true" : "false"),
            ),
            Text(choice.label.replaceAll("_", "")),
            const SizedBox(width: 8),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("${choice.label.replaceAll("_", "")}:"),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: choice.options.any((o) => o.$1 == choice.value) ? choice.value : choice.options.first.$1,
          underline: const SizedBox(),
          items: [
            for (final (String id, String label) in choice.options)
              DropdownMenuItem(value: id, child: Text(label.replaceAll("_", ""))),
          ],
          onChanged: (v) => setState(() => choice.value = v ?? choice.value),
        ),
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.current,
    required this.onTap,
    this.icon,
  });

  final IconData? icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: current ? FontWeight.w600 : FontWeight.normal,
                color: current ? null : theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.item,
    required this.selected,
    required this.dimmed,
    required this.date,
    required this.onTap,
    required this.onDoubleTap,
    this.subtitle,
  });

  final _Item item;
  final bool selected;
  final bool dimmed;
  final String date;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _Item item = widget.item;
    final Color? foreground = widget.selected ? theme.colorScheme.onPrimary : null;
    final TextStyle secondary = TextStyle(
      fontSize: 12,
      color: (foreground ?? theme.colorScheme.onSurface).withValues(alpha: 0.65),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Opacity(
          opacity: widget.dimmed ? 0.55 : 1,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.colorScheme.primary
                  : _hovered
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _FileIcon(item: item, size: 22, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: foreground),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary.copyWith(fontSize: 11),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    item.isDir ? "" : formatBytes(item.size),
                    textAlign: TextAlign.end,
                    style: secondary,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 110,
                  child: Text(widget.date, style: secondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.item, required this.size, this.color});

  final _Item item;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final FileKind kind = kindOf(item.path, isDirectory: item.isDir);
    if (kind == FileKind.image && item.size < 20 * 1024 * 1024) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(item.path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 2).round(),
          errorBuilder: (context, _, __) => _glyph(context, kind),
        ),
      );
    }
    return _glyph(context, kind);
  }

  Widget _glyph(BuildContext context, FileKind kind) {
    final (IconData icon, Color tint) = iconFor(kind, Theme.of(context).colorScheme);
    return Icon(icon, size: size, color: color ?? tint);
  }
}
