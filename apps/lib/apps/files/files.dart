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

import 'package:dahlia_apps/apps/files/file_ops.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:yaru_window/yaru_window.dart';

final DahliaAppSpec filesApp = DahliaAppSpec(
  name: "files",
  title: "Files",
  builder: (context, args) => FilesPage(initialPaths: args),
);

class _Entry {
  _Entry(this.entity, this.stat)
      : name = p.basename(entity.path),
        isDir = stat.type == FileSystemEntityType.directory;

  final FileSystemEntity entity;
  final FileStat stat;
  final String name;
  final bool isDir;

  String get path => entity.path;
  bool get hidden => name.startsWith(".");
  late final FileKind kind = kindOf(path, isDirectory: isDir);
}

enum _SortKey { name, size, modified, type }

enum _ClipboardMode { copy, cut }

/// Files cut or copied in any tab of the window.
class _FileClipboard extends ChangeNotifier {
  List<String> _items = const [];
  _ClipboardMode _mode = _ClipboardMode.copy;

  List<String> get items => _items;
  bool get isEmpty => _items.isEmpty;
  bool isCut(String path) => _mode == _ClipboardMode.cut && _items.contains(path);

  void set(Iterable<String> items, _ClipboardMode mode) {
    _items = List.unmodifiable(items);
    _mode = mode;
    // Plain paths on the system clipboard: other windows (and the terminal)
    // can paste them too.
    Clipboard.setData(ClipboardData(text: _items.join("\n")));
    notifyListeners();
  }

  /// The items to paste and whether they should be moved. A cut is consumed
  /// by its paste. When nothing was copied in this window, existing paths on
  /// the system clipboard (e.g. copied in another Files window) are copied.
  Future<(List<String>, bool)> take() async {
    if (_items.isNotEmpty) {
      final (List<String>, bool) result = (_items, _mode == _ClipboardMode.cut);
      if (_mode == _ClipboardMode.cut) {
        _items = const [];
        notifyListeners();
      }
      return result;
    }
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final List<String> paths = [];
    for (String line in (data?.text ?? "").split("\n")) {
      line = line.trim();
      if (line.startsWith("file://")) line = Uri.tryParse(line)?.toFilePath() ?? "";
      if (p.isAbsolute(line) &&
          FileSystemEntity.typeSync(line, followLinks: false) != FileSystemEntityType.notFound) {
        paths.add(line);
      }
    }
    return (paths, false);
  }
}

/// Location and navigation history of one tab.
class _FolderTab extends ChangeNotifier {
  _FolderTab(this._path, {this.grid = true, this.showHidden = false});

  String _path;
  final List<String> _back = [];
  final List<String> _forward = [];

  /// View options, kept per tab and inherited by tabs opened from it.
  bool grid;
  bool showHidden;

  String get path => _path;
  bool get canBack => _back.isNotEmpty;
  bool get canForward => _forward.isNotEmpty;
  bool get canGoUp => p.dirname(_path) != _path;
  bool get inTrash => _path == FileOps.trashFiles;

  String get title {
    if (inTrash) return "Trash";
    if (_path == SystemUtils.home) return "Home";
    if (_path == "/") return "Computer";
    return p.basename(_path);
  }

  void navigate(String location, {bool record = true}) {
    final String path = p.normalize(location);
    if (path == _path) return;
    if (record) {
      _back.add(_path);
      _forward.clear();
    }
    _path = path;
    notifyListeners();
  }

  void back() {
    if (_back.isEmpty) return;
    _forward.add(_path);
    navigate(_back.removeLast(), record: false);
  }

  void forward() {
    if (_forward.isEmpty) return;
    _back.add(_path);
    navigate(_forward.removeLast(), record: false);
  }

  void up() {
    if (canGoUp) navigate(p.dirname(_path));
  }
}

/// The Files window: a tab strip in the title bar, the places sidebar, and
/// one folder view per tab.
class FilesPage extends StatefulWidget {
  const FilesPage({this.initialPaths = const [], super.key});

  /// Folders (or files, whose folder is opened) to open, one tab each.
  final List<String> initialPaths;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  static const int _maxClosedTabs = 16;

  final List<_FolderTab> _tabs = [];
  final List<String> _closedTabs = [];
  final _FileClipboard _clipboard = _FileClipboard();
  late final List<Place> _places = FileOps.userPlaces();
  int _current = 0;
  String? _windowTitle;

  _FolderTab get _tab => _tabs[_current];

  @override
  void initState() {
    super.initState();
    for (final String arg in widget.initialPaths) {
      final String? path = _resolveArgument(arg);
      if (path != null) _insertTab(_FolderTab(path));
    }
    if (_tabs.isEmpty) _insertTab(_FolderTab(SystemUtils.home));
    _current = 0;
  }

  @override
  void dispose() {
    for (final _FolderTab tab in _tabs) {
      tab.dispose();
    }
    _clipboard.dispose();
    super.dispose();
  }

  /// Accepts paths and file:// URIs; a file opens its containing folder.
  static String? _resolveArgument(String arg) {
    String path = arg;
    if (arg.startsWith("file://")) {
      final Uri? uri = Uri.tryParse(arg);
      if (uri == null) return null;
      path = uri.toFilePath();
    }
    path = p.normalize(p.absolute(path));
    return switch (FileSystemEntity.typeSync(path)) {
      FileSystemEntityType.directory => path,
      FileSystemEntityType.notFound => null,
      _ => p.dirname(path),
    };
  }

  void _insertTab(_FolderTab tab, {int? at}) {
    tab.addListener(_onTabChanged);
    _tabs.insert(at ?? _tabs.length, tab);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// Opens [path] in a new tab next to the current one.
  void _openTab(String path, {bool activate = true}) {
    final _FolderTab tab = _FolderTab(path, grid: _tab.grid, showHidden: _tab.showHidden);
    setState(() {
      _insertTab(tab, at: _current + 1);
      if (activate) _current++;
    });
  }

  void _newTab() => _openTab(_tab.path);

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length == 1) {
      YaruWindow.of(context).close();
      return;
    }
    final _FolderTab tab = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (index < _current || _current == _tabs.length) _current--;
    });
    _closedTabs.add(tab.path);
    if (_closedTabs.length > _maxClosedTabs) _closedTabs.removeAt(0);
    // The view still listens until it is unmounted at the end of this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
  }

  void _closeOtherTabs(int index) {
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (i != index) _closeTab(i);
    }
  }

  void _closeTabsToTheRight(int index) {
    for (int i = _tabs.length - 1; i > index; i--) {
      _closeTab(i);
    }
  }

  void _reopenClosedTab() {
    while (_closedTabs.isNotEmpty) {
      final String path = _closedTabs.removeLast();
      if (Directory(path).existsSync()) {
        _openTab(path);
        return;
      }
    }
  }

  void _selectTab(int index) {
    if (index == _current || index < 0 || index >= _tabs.length) return;
    setState(() => _current = index);
  }

  void _cycleTabs(int delta) => _selectTab((_current + delta) % _tabs.length);

  void _moveTab(int from, int to) {
    if (from == to || to < 0 || to >= _tabs.length) return;
    setState(() {
      final _FolderTab current = _tab;
      _tabs.insert(to, _tabs.removeAt(from));
      _current = _tabs.indexOf(current);
    });
  }

  IconData _iconFor(_FolderTab tab) {
    if (tab.inTrash) return Icons.delete_outline_rounded;
    if (tab.path == "/") return Icons.computer_rounded;
    for (final Place place in _places) {
      if (place.path == tab.path) return place.icon;
    }
    return Icons.folder_rounded;
  }

  Future<void> _showTabMenu(int index, Offset position) async {
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(value: "new", child: Text("New Tab")),
        const PopupMenuItem(value: "duplicate", child: Text("Duplicate Tab")),
        const PopupMenuDivider(),
        PopupMenuItem(value: "left", enabled: index > 0, child: const Text("Move Left")),
        PopupMenuItem(
          value: "right",
          enabled: index < _tabs.length - 1,
          child: const Text("Move Right"),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: "reopen",
          enabled: _closedTabs.isNotEmpty,
          child: const Text("Reopen Closed Tab"),
        ),
        PopupMenuItem(
          value: "others",
          enabled: _tabs.length > 1,
          child: const Text("Close Other Tabs"),
        ),
        PopupMenuItem(
          value: "right-close",
          enabled: index < _tabs.length - 1,
          child: const Text("Close Tabs to the Right"),
        ),
        const PopupMenuItem(value: "close", child: Text("Close Tab")),
      ],
    );
    if (!mounted || action == null || index >= _tabs.length) return;
    switch (action) {
      case "new":
        _newTab();
      case "duplicate":
        _selectTab(index);
        _openTab(_tabs[index].path);
      case "left":
        _moveTab(index, index - 1);
      case "right":
        _moveTab(index, index + 1);
      case "reopen":
        _reopenClosedTab();
      case "others":
        _closeOtherTabs(index);
      case "right-close":
        _closeTabsToTheRight(index);
      case "close":
        _closeTab(index);
    }
  }

  /// Keeps the toplevel title (shown by the shell's switcher and taskbar
  /// tooltips) in sync with the current folder.
  void _syncWindowTitle() {
    final String title = "${_tab.title} – Files";
    if (title == _windowTitle) return;
    _windowTitle = title;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      YaruWindow.of(context).setTitle(title).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncWindowTitle();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): _newTab,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            SystemUtils.launchApp("files", [_tab.path]),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeTab(_current),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): _reopenClosedTab,
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _cycleTabs(1),
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () => _cycleTabs(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () => _cycleTabs(1),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () => _cycleTabs(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true, shift: true): () =>
            _moveTab(_current, _current + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true, shift: true): () =>
            _moveTab(_current, _current - 1),
        for (int i = 1; i <= 9; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1), alt: true): () =>
              _selectTab(i == 9 ? _tabs.length - 1 : i - 1),
      },
      child: DahliaScaffold(
        title: DahliaTabStrip(
          tabs: [
            for (final _FolderTab tab in _tabs)
              DahliaTabData(
                id: tab,
                title: tab.title,
                icon: _iconFor(tab),
                tooltip: tab.inTrash ? "Trash" : tab.path,
              ),
          ],
          current: _current,
          onSelect: _selectTab,
          onClose: _closeTab,
          onReorder: _moveTab,
          onNew: _newTab,
          newTooltip: "New tab (Ctrl+T)",
          onContextMenu: _showTabMenu,
        ),
        body: Row(
          children: [
            SidebarPane(
              width: 200,
              child: _Sidebar(
                places: _places,
                current: _tab.path,
                onNavigate: (path) => _tab.navigate(path),
                onOpenInNewTab: (path) => _openTab(path, activate: false),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _current,
                children: [
                  for (int i = 0; i < _tabs.length; i++)
                    ExcludeFocus(
                      key: ObjectKey(_tabs[i]),
                      excluding: i != _current,
                      child: _FolderView(
                        tab: _tabs[i],
                        active: i == _current,
                        clipboard: _clipboard,
                        onOpenInNewTab: _openTab,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contents of one tab: toolbar, files and status bar.
class _FolderView extends StatefulWidget {
  const _FolderView({
    required this.tab,
    required this.active,
    required this.clipboard,
    required this.onOpenInNewTab,
  });

  final _FolderTab tab;
  final bool active;
  final _FileClipboard clipboard;
  final void Function(String path, {bool activate}) onOpenInNewTab;

  @override
  State<_FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends State<_FolderView> {
  List<_Entry> _entries = [];
  String? _error;
  bool _loading = true;
  String? _loadedPath;

  final Set<String> _selection = {};
  String? _anchor;
  _SortKey _sort = _SortKey.name;
  bool _ascending = true;
  String _filter = "";
  bool _editingPath = false;
  int? _freeSpace;

  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _refreshDebounce;
  final FocusNode _focus = FocusNode(debugLabel: "folder view");
  final TextEditingController _filterController = TextEditingController();

  _FolderTab get _tab => widget.tab;
  String get _path => _tab.path;
  bool get _inTrash => _tab.inTrash;

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onLocationChanged);
    widget.clipboard.addListener(_onClipboardChanged);
    _load();
    if (widget.active) _requestFocus();
  }

  @override
  void didUpdateWidget(_FolderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab.removeListener(_onLocationChanged);
      widget.tab.addListener(_onLocationChanged);
      _onLocationChanged();
    }
    if (widget.active && !oldWidget.active) _requestFocus();
  }

  @override
  void dispose() {
    _tab.removeListener(_onLocationChanged);
    widget.clipboard.removeListener(_onClipboardChanged);
    _watcher?.cancel();
    _refreshDebounce?.cancel();
    _focus.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _focus.requestFocus();
    });
  }

  void _onClipboardChanged() {
    if (mounted) setState(() {});
  }

  void _onLocationChanged() {
    if (_path == _loadedPath) return;
    setState(() {
      _selection.clear();
      _anchor = null;
      _filter = "";
      _filterController.clear();
      _editingPath = false;
      _loading = true;
    });
    _load();
  }

  Future<void> _load() async {
    final String path = _path;
    final Directory dir = Directory(path);
    final List<_Entry> entries = [];
    String? error;
    try {
      if (path == FileOps.trashFiles) await dir.create(recursive: true);
      await for (final FileSystemEntity e in dir.list(followLinks: false)) {
        try {
          entries.add(_Entry(e, await FileStat.stat(e.path)));
        } on FileSystemException {
          // Broken link or vanished file.
        }
      }
    } on FileSystemException catch (e) {
      error = e.osError?.message ?? e.message;
    }
    final int? free = error == null ? await FileOps.freeSpace(path) : null;

    // The tab may have moved on while this folder was being read.
    if (!mounted || path != _path) return;

    if (_loadedPath != path) {
      _watcher?.cancel();
      _watcher = null;
      if (error == null) {
        _watcher = dir.watch().listen(
          (_) {
            _refreshDebounce?.cancel();
            _refreshDebounce = Timer(const Duration(milliseconds: 250), _load);
          },
          onError: (_) {},
        );
      }
    }

    setState(() {
      _loadedPath = path;
      _loading = false;
      _entries = entries;
      _error = error;
      _freeSpace = free;
      _selection.removeWhere((selected) => !entries.any((e) => e.path == selected));
    });
  }

  List<_Entry> get _visible {
    final List<_Entry> list = _entries
        .where((e) => _tab.showHidden || !e.hidden)
        .where((e) => _filter.isEmpty || e.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    int compare(_Entry a, _Entry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final int result = switch (_sort) {
        _SortKey.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _SortKey.size => a.stat.size.compareTo(b.stat.size),
        _SortKey.modified => a.stat.modified.compareTo(b.stat.modified),
        _SortKey.type => p.extension(a.name).compareTo(p.extension(b.name)),
      };
      return _ascending ? result : -result;
    }

    return list..sort(compare);
  }

  List<_Entry> get _selectedEntries => _entries.where((e) => _selection.contains(e.path)).toList();

  void _toggleHidden() => setState(() => _tab.showHidden = !_tab.showHidden);

  /// Folders open here; files with their default app (Open With… changes
  /// it), else with the dahliaOS app for them, else the user picks one.
  Future<void> _open(_Entry entry) async {
    if (entry.isDir) {
      _tab.navigate(entry.path);
      return;
    }
    final DesktopApp? app = DesktopApps.load().defaultFor(DesktopApps.typeOf(entry.path));
    if (app != null && await DesktopApps.launch(app, paths: [entry.path])) return;
    switch (entry.kind) {
      case FileKind.text || FileKind.code:
        SystemUtils.launchApp("text_editor", [entry.path]);
      case FileKind.image:
        SystemUtils.launchApp("gallery", [entry.path]);
      default:
        if (mounted) await showOpenWithDialog(context, [entry.path]);
    }
  }

  void _openSelectedInNewTabs() {
    for (final _Entry entry in _selectedEntries.where((e) => e.isDir)) {
      widget.onOpenInNewTab(entry.path, activate: false);
    }
  }

  void _select(_Entry entry, {bool toggle = false, bool range = false}) {
    setState(() {
      if (range && _anchor != null) {
        final List<_Entry> visible = _visible;
        final int a = visible.indexWhere((e) => e.path == _anchor);
        final int b = visible.indexOf(entry);
        if (a != -1 && b != -1) {
          _selection
            ..clear()
            ..addAll(visible.sublist(a < b ? a : b, (a < b ? b : a) + 1).map((e) => e.path));
          return;
        }
      }
      if (toggle) {
        _selection.contains(entry.path) ? _selection.remove(entry.path) : _selection.add(entry.path);
      } else {
        _selection
          ..clear()
          ..add(entry.path);
      }
      _anchor = entry.path;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
    } on FileSystemException catch (e) {
      final String reason = e.osError?.message ?? e.message;
      _showMessage("$reason${e.path != null ? ": ${p.basename(e.path!)}" : ""}");
    } catch (e) {
      _showMessage("$e");
    }
    await _load();
  }

  void _copySelection({bool cut = false}) {
    if (_selection.isEmpty || _inTrash) return;
    widget.clipboard.set(_selection, cut ? _ClipboardMode.cut : _ClipboardMode.copy);
  }

  Future<void> _paste() async {
    if (_inTrash) return;
    final (List<String> items, bool move) = await widget.clipboard.take();
    if (items.isEmpty) return;
    await _run(() async {
      for (final String item in items) {
        if (p.equals(item, _path) || p.isWithin(item, _path)) {
          throw FileSystemException("Can't paste a folder into itself", item);
        }
        move ? await FileOps.move(item, _path) : await FileOps.copy(item, _path);
      }
    });
  }

  Future<void> _trashSelection() async {
    if (_selection.isEmpty) return;
    if (_inTrash) {
      await _deleteSelection();
      return;
    }
    final List<String> items = _selection.toList();
    await _run(() async {
      for (final String item in items) {
        await FileOps.trash(item);
      }
    });
  }

  Future<void> _deleteSelection() async {
    if (_selection.isEmpty) return;
    final int count = _selection.length;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Permanently delete $count item${count == 1 ? "" : "s"}?"),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;
    final List<String> items = _selection.toList();
    final bool inTrash = _inTrash;
    await _run(() async {
      for (final String item in items) {
        await FileOps.deletePermanently(item);
        if (inTrash) {
          final File info = File(p.join(FileOps.trashInfo, "${p.basename(item)}.trashinfo"));
          if (info.existsSync()) await info.delete();
        }
      }
    });
  }

  Future<void> _restoreSelection() async {
    final List<String> items = _selection.toList();
    await _run(() async {
      for (final String item in items) {
        await FileOps.restore(item);
      }
    });
  }

  Future<String?> _askName(String title, String initial, String action) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: title, initial: initial, action: action),
    );
    if (name != null && (name.contains("/") || name == "." || name == "..")) {
      _showMessage("Names can't contain “/” or be “.” or “..”");
      return null;
    }
    return name;
  }

  Future<void> _rename(_Entry entry) async {
    final String? name = await _askName("Rename", entry.name, "Rename");
    if (name == null || name.isEmpty || name == entry.name) return;
    await _run(() => FileOps.rename(entry.path, name));
  }

  Future<void> _newFolder() async {
    if (_inTrash) return;
    final String? name = await _askName("New Folder", FileOps.uniqueName(_path, "New Folder"), "Create");
    if (name == null || name.isEmpty) return;
    await _run(() => Directory(p.join(_path, name)).create());
  }

  Future<void> _newFile() async {
    if (_inTrash) return;
    final String? name = await _askName("New File", FileOps.uniqueName(_path, "Untitled.txt"), "Create");
    if (name == null || name.isEmpty) return;
    await _run(() => File(p.join(_path, name)).create(exclusive: true));
  }

  Future<void> _properties(_Entry entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PropertiesDialog(entry: entry),
    );
  }

  void _goToTypedPath(String value) {
    _setEditingPath(false);
    String path = value.trim();
    if (path == "~" || path.startsWith("~/")) path = SystemUtils.home + path.substring(1);
    if (path.isEmpty) return;
    path = p.normalize(p.isAbsolute(path) ? path : p.join(_path, path));
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.directory:
        _tab.navigate(path);
      case FileSystemEntityType.notFound:
        _showMessage("“$value” doesn't exist");
      default:
        _tab.navigate(p.dirname(path));
    }
  }

  Future<void> _showContextMenu(Offset position, _Entry? entry) async {
    if (entry != null && !_selection.contains(entry.path)) _select(entry);
    final bool multi = _selection.length > 1;
    final bool allDirs = _selectedEntries.isNotEmpty && _selectedEntries.every((e) => e.isDir);
    final List<PopupMenuEntry<String>> items = [
      if (entry != null) ...[
        if (!multi) const PopupMenuItem(value: "open", child: Text("Open")),
        if (!_inTrash && _selectedEntries.isNotEmpty && _selectedEntries.every((e) => !e.isDir))
          const PopupMenuItem(value: "openwith", child: Text("Open With…")),
        if (allDirs && !_inTrash)
          PopupMenuItem(value: "newtab", child: Text(multi ? "Open in New Tabs" : "Open in New Tab")),
        if (!multi && !entry.isDir)
          const PopupMenuItem(value: "edit", child: Text("Open in Text Editor")),
        if (!multi && entry.isDir && !_inTrash)
          const PopupMenuItem(value: "terminal", child: Text("Open in Terminal")),
        const PopupMenuDivider(),
        if (_inTrash) ...[
          const PopupMenuItem(value: "restore", child: Text("Restore")),
          const PopupMenuItem(value: "delete", child: Text("Delete Permanently")),
        ] else ...[
          const PopupMenuItem(value: "cut", child: Text("Cut")),
          const PopupMenuItem(value: "copy", child: Text("Copy")),
          if (!multi) const PopupMenuItem(value: "rename", child: Text("Rename…")),
          const PopupMenuItem(value: "trash", child: Text("Move to Trash")),
        ],
        if (!multi) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: "properties", child: Text("Properties")),
        ],
      ] else ...[
        if (!_inTrash) ...[
          const PopupMenuItem(value: "newfolder", child: Text("New Folder…")),
          const PopupMenuItem(value: "newfile", child: Text("New File…")),
          const PopupMenuItem(value: "paste", child: Text("Paste")),
          const PopupMenuItem(value: "terminalhere", child: Text("Open in Terminal")),
        ] else
          PopupMenuItem(value: "empty", enabled: _entries.isNotEmpty, child: const Text("Empty Trash")),
        const PopupMenuDivider(),
        const PopupMenuItem(value: "selectall", child: Text("Select All")),
        CheckedPopupMenuItem(value: "hidden", checked: _tab.showHidden, child: const Text("Show Hidden Files")),
      ],
    ];

    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: items,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case "open":
        await _open(entry!);
      case "openwith":
        await showOpenWithDialog(context, [for (final _Entry e in _selectedEntries) e.path]);
      case "newtab":
        _openSelectedInNewTabs();
      case "edit":
        SystemUtils.launchApp("text_editor", [entry!.path]);
      case "terminal":
        SystemUtils.launchApp("terminal", ["--working-directory", entry!.path]);
      case "terminalhere":
        SystemUtils.launchApp("terminal", ["--working-directory", _path]);
      case "cut":
        _copySelection(cut: true);
      case "copy":
        _copySelection();
      case "rename":
        await _rename(entry!);
      case "trash":
        await _trashSelection();
      case "delete":
        await _deleteSelection();
      case "restore":
        await _restoreSelection();
      case "properties":
        await _properties(entry!);
      case "newfolder":
        await _newFolder();
      case "newfile":
        await _newFile();
      case "paste":
        await _paste();
      case "empty":
        await _run(FileOps.emptyTrash);
      case "selectall":
        setState(() => _selection.addAll(_visible.map((e) => e.path)));
      case "hidden":
        _toggleHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_Entry> visible = _visible;
    final int selectedSize = _selectedEntries.where((e) => !e.isDir).fold(0, (sum, e) => sum + e.stat.size);
    final int clipboardCount = widget.clipboard.items.length;

    // The toolbar (with the location and filter fields) sits outside the
    // view's shortcuts, so typing there isn't mistaken for file commands.
    final Widget toolbar = _Toolbar(
      path: _path,
      inTrash: _inTrash,
      canBack: _tab.canBack,
      canForward: _tab.canForward,
      canGoUp: _tab.canGoUp,
      grid: _tab.grid,
      editingPath: _editingPath,
      filterController: _filterController,
      onBack: _tab.back,
      onForward: _tab.forward,
      onUp: _tab.up,
      onNavigate: (path) => _tab.navigate(path),
      onOpenInNewTab: (path) => widget.onOpenInNewTab(path, activate: false),
      onSubmitPath: _goToTypedPath,
      onEditPath: _setEditingPath,
      onToggleView: () => setState(() => _tab.grid = !_tab.grid),
      onFilter: (v) => setState(() => _filter = v),
      onNewFolder: _newFolder,
      onEmptyTrash: () => _run(FileOps.emptyTrash),
    );

    final Widget files = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        setState(_selection.clear);
        _focus.requestFocus();
      },
      onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition, null),
      child: _loading && _entries.isEmpty
          ? const SizedBox.expand()
          : _error != null
              ? EmptyState(icon: Icons.block_rounded, title: "Can't open this folder", subtitle: _error)
              : visible.isEmpty
                  ? EmptyState(
                      icon: _inTrash ? Icons.delete_outline_rounded : Icons.folder_open_rounded,
                      title: _filter.isNotEmpty
                          ? "No matches"
                          : _inTrash
                              ? "Trash is empty"
                              : "This folder is empty",
                    )
                  : _tab.grid
                      ? _buildGrid(visible)
                      : _buildList(visible),
    );

    final Widget statusBar = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.surface,
      child: DefaultTextStyle.merge(
        style: theme.textTheme.bodySmall,
        child: Row(
          children: [
            Text(
              _selection.isEmpty
                  ? "${visible.length} item${visible.length == 1 ? "" : "s"}"
                  : "${_selection.length} selected${selectedSize > 0 ? " (${formatBytes(selectedSize)})" : ""}",
            ),
            const Spacer(),
            if (clipboardCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text("$clipboardCount item${clipboardCount == 1 ? "" : "s"} on clipboard"),
              ),
            if (_freeSpace != null) Text("${formatBytes(_freeSpace!)} free"),
          ],
        ),
      ),
    );

    return Column(
      children: [
        toolbar,
        const Divider(height: 1),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.delete): _trashSelection,
              const SingleActivator(LogicalKeyboardKey.delete, shift: true): _deleteSelection,
              const SingleActivator(LogicalKeyboardKey.f2): () {
                final List<_Entry> selected = _selectedEntries;
                if (selected.length == 1) _rename(selected.first);
              },
              const SingleActivator(LogicalKeyboardKey.f5): _load,
              const SingleActivator(LogicalKeyboardKey.keyR, control: true): _load,
              const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copySelection,
              const SingleActivator(LogicalKeyboardKey.keyX, control: true): () => _copySelection(cut: true),
              const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
              const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): _newFolder,
              const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
                  setState(() => _selection.addAll(visible.map((e) => e.path))),
              const SingleActivator(LogicalKeyboardKey.keyH, control: true): _toggleHidden,
              const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => _setEditingPath(true),
              const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _tab.back,
              const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _tab.forward,
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _tab.up,
              const SingleActivator(LogicalKeyboardKey.home, alt: true): () => _tab.navigate(SystemUtils.home),
              const SingleActivator(LogicalKeyboardKey.backspace): _tab.back,
              const SingleActivator(LogicalKeyboardKey.escape): () => setState(_selection.clear),
              const SingleActivator(LogicalKeyboardKey.enter): () {
                final List<_Entry> selected = _selectedEntries;
                if (selected.length == 1) _open(selected.first);
              },
              const SingleActivator(LogicalKeyboardKey.enter, control: true): _openSelectedInNewTabs,
            },
            child: Focus(
              focusNode: _focus,
              autofocus: widget.active,
              child: Column(
                children: [
                  Expanded(child: files),
                  statusBar,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _setEditingPath(bool editing) {
    if (editing == _editingPath) return;
    setState(() => _editingPath = editing);
    if (!editing) _focus.requestFocus();
  }

  Widget _gestures(_Entry entry, Widget child) {
    return GestureDetector(
      onTap: () {
        _select(
          entry,
          toggle: HardwareKeyboard.instance.isControlPressed,
          range: HardwareKeyboard.instance.isShiftPressed,
        );
        _focus.requestFocus();
      },
      onDoubleTap: () => _open(entry),
      onTertiaryTapUp: entry.isDir && !_inTrash ? (_) => widget.onOpenInNewTab(entry.path, activate: false) : null,
      onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition, entry),
      child: child,
    );
  }

  Widget _buildGrid(List<_Entry> entries) {
    final ThemeData theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisExtent: 120,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final _Entry entry = entries[index];
        final bool selected = _selection.contains(entry.path);
        final bool cut = widget.clipboard.isCut(entry.path);
        return _gestures(
          entry,
          Opacity(
            opacity: cut || entry.hidden ? 0.5 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: selected ? theme.colorScheme.primary.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Expanded(child: Center(child: _EntryIcon(entry: entry, size: 56))),
                  const SizedBox(height: 4),
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildList(List<_Entry> entries) {
    final ThemeData theme = Theme.of(context);
    final DateFormat format = DateFormat.yMMMd().add_Hm();

    Widget header(String label, _SortKey key, {int flex = 1}) => Expanded(
          flex: flex,
          child: InkWell(
            onTap: () => setState(() {
              if (_sort == key) {
                _ascending = !_ascending;
              } else {
                _sort = key;
                _ascending = true;
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  if (_sort == key)
                    Icon(_ascending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, size: 18),
                ],
              ),
            ),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const SizedBox(width: 32),
              header("Name", _SortKey.name, flex: 4),
              header("Size", _SortKey.size),
              header("Type", _SortKey.type),
              header("Modified", _SortKey.modified, flex: 2),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemExtent: 36,
            itemBuilder: (context, index) {
              final _Entry entry = entries[index];
              final bool selected = _selection.contains(entry.path);
              final bool cut = widget.clipboard.isCut(entry.path);
              return _gestures(
                entry,
                Container(
                  color: selected ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Opacity(
                    opacity: cut || entry.hidden ? 0.55 : 1,
                    child: Row(
                      children: [
                        SizedBox(width: 32, child: _EntryIcon(entry: entry, size: 20)),
                        Expanded(flex: 4, child: Text(entry.name, overflow: TextOverflow.ellipsis)),
                        Expanded(child: Text(entry.isDir ? "—" : formatBytes(entry.stat.size), style: theme.textTheme.bodySmall)),
                        Expanded(
                          child: Text(
                            entry.isDir ? "Folder" : entry.kind.name[0].toUpperCase() + entry.kind.name.substring(1),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Expanded(flex: 2, child: Text(format.format(entry.stat.modified), style: theme.textTheme.bodySmall)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntryIcon extends StatelessWidget {
  const _EntryIcon({required this.entry, required this.size});

  final _Entry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (entry.kind == FileKind.image && size > 32 && entry.stat.size < 30 * 1024 * 1024) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(entry.path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 2).round(),
          errorBuilder: (context, _, __) => _icon(context),
        ),
      );
    }
    return _icon(context);
  }

  Widget _icon(BuildContext context) {
    final (IconData icon, Color color) = iconFor(entry.kind, Theme.of(context).colorScheme);
    return Icon(icon, size: size, color: color);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.places,
    required this.current,
    required this.onNavigate,
    required this.onOpenInNewTab,
  });

  final List<Place> places;
  final String current;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenInNewTab;

  Future<void> _showMenu(BuildContext context, Offset position, String path) async {
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: "open", child: Text("Open")),
        PopupMenuItem(value: "newtab", child: Text("Open in New Tab")),
      ],
    );
    switch (action) {
      case "open":
        onNavigate(path);
      case "newtab":
        onOpenInNewTab(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Place> volumes = FileOps.volumes();

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Text(title, style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor)),
        );

    // Middle click or the context menu opens a place in a new tab.
    Widget tile(IconData icon, String label, String path) => GestureDetector(
          onTertiaryTapUp: (_) => onOpenInNewTab(path),
          onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition, path),
          child: SidebarTile(
            icon: icon,
            label: label,
            selected: current == path,
            onTap: () => onNavigate(path),
          ),
        );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        section("Places"),
        for (final Place place in places) tile(place.icon, place.label, place.path),
        section("Devices"),
        tile(Icons.computer_rounded, "Computer", "/"),
        for (final Place volume in volumes) tile(volume.icon, volume.label, volume.path),
        const SizedBox(height: 8),
        tile(Icons.delete_outline_rounded, "Trash", FileOps.trashFiles),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.path,
    required this.inTrash,
    required this.canBack,
    required this.canForward,
    required this.canGoUp,
    required this.grid,
    required this.editingPath,
    required this.filterController,
    required this.onBack,
    required this.onForward,
    required this.onUp,
    required this.onNavigate,
    required this.onOpenInNewTab,
    required this.onSubmitPath,
    required this.onEditPath,
    required this.onToggleView,
    required this.onFilter,
    required this.onNewFolder,
    required this.onEmptyTrash,
  });

  final String path;
  final bool inTrash;
  final bool canBack;
  final bool canForward;
  final bool canGoUp;
  final bool grid;
  final bool editingPath;
  final TextEditingController filterController;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onUp;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onSubmitPath;
  final ValueChanged<bool> onEditPath;
  final VoidCallback onToggleView;
  final ValueChanged<String> onFilter;
  final VoidCallback onNewFolder;
  final VoidCallback onEmptyTrash;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = p.split(path);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(tooltip: "Back (Alt+Left)", icon: const Icon(Icons.arrow_back_rounded), onPressed: canBack ? onBack : null),
          IconButton(tooltip: "Forward (Alt+Right)", icon: const Icon(Icons.arrow_forward_rounded), onPressed: canForward ? onForward : null),
          IconButton(tooltip: "Up (Alt+Up)", icon: const Icon(Icons.arrow_upward_rounded), onPressed: canGoUp ? onUp : null),
          const SizedBox(width: 4),
          Expanded(
            child: editingPath
                ? Focus(
                    // Leaving the field (click elsewhere) cancels editing.
                    onFocusChange: (focused) {
                      if (!focused) onEditPath(false);
                    },
                    child: TextFormField(
                      key: ValueKey(path),
                      initialValue: path,
                      autofocus: true,
                      decoration: const InputDecoration(isDense: true),
                      onFieldSubmitted: onSubmitPath,
                    ),
                  )
                : GestureDetector(
                    onDoubleTap: () => onEditPath(true),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        children: [
                          for (int i = 0; i < parts.length; i++) ...[
                            if (i > 1) const Icon(Icons.chevron_right_rounded, size: 16),
                            GestureDetector(
                              onTertiaryTapUp: (_) => onOpenInNewTab(p.joinAll(parts.sublist(0, i + 1))),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                ),
                                onPressed: () => onNavigate(p.joinAll(parts.sublist(0, i + 1))),
                                child: Text(i == 0 ? "/" : parts[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          IconButton(
            tooltip: "Edit location (Ctrl+L)",
            icon: Icon(editingPath ? Icons.close_rounded : Icons.edit_location_alt_outlined),
            onPressed: () => onEditPath(!editingPath),
          ),
          const SizedBox(width: 4),
          SearchField(width: 180, hint: "Filter", controller: filterController, onChanged: onFilter),
          const SizedBox(width: 4),
          if (inTrash)
            TextButton.icon(onPressed: onEmptyTrash, icon: const Icon(Icons.delete_forever_rounded), label: const Text("Empty"))
          else
            IconButton(tooltip: "New folder (Ctrl+Shift+N)", icon: const Icon(Icons.create_new_folder_outlined), onPressed: onNewFolder),
          IconButton(
            tooltip: grid ? "List view" : "Grid view",
            icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: onToggleView,
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial, required this.action});

  final String title;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  // Owned here so it outlives the dialog's closing animation.
  late final TextEditingController _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: p.basenameWithoutExtension(widget.initial).length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _PropertiesDialog extends StatefulWidget {
  const _PropertiesDialog({required this.entry});
  final _Entry entry;

  @override
  State<_PropertiesDialog> createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends State<_PropertiesDialog> {
  int? _size;

  @override
  void initState() {
    super.initState();
    if (widget.entry.isDir) {
      FileOps.directorySize(widget.entry.path).then((s) {
        if (mounted) setState(() => _size = s);
      });
    } else {
      _size = widget.entry.stat.size;
    }
  }

  @override
  Widget build(BuildContext context) {
    final _Entry entry = widget.entry;
    final DateFormat format = DateFormat.yMMMMd().add_jms();
    final String? original = p.isWithin(FileOps.trashFiles, entry.path)
        ? FileOps.trashedOriginalPath(entry.path)
        : null;
    return AlertDialog(
      title: Row(
        children: [
          _EntryIcon(entry: entry, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoRow(label: "Type", value: entry.isDir ? "Folder" : (FileOps.mimeType(entry.path) ?? "File")),
            InfoRow(label: "Location", value: p.dirname(entry.path)),
            if (original != null) InfoRow(label: "Original location", value: original),
            InfoRow(
              label: "Size",
              value: _size == null ? "Calculating…" : "${formatBytes(_size!)} ($_size bytes)",
            ),
            InfoRow(label: "Modified", value: format.format(entry.stat.modified)),
            InfoRow(label: "Accessed", value: format.format(entry.stat.accessed)),
            InfoRow(label: "Permissions", value: permissionString(entry.stat)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
      ],
    );
  }
}
