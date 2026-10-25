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
import 'package:dahlia_apps/apps/files/file_tags.dart';
import 'package:dahlia_apps/apps/files/files_model.dart';
import 'package:dahlia_apps/apps/files/papirus.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;

/// Contents of one tab: the toolbar (New, the view switcher, actions) and
/// the files, in one of five views, with selection by click, Ctrl, Shift,
/// a rubber band or the selection mode, and dragging onto folders.
class FolderView extends StatefulWidget {
  const FolderView({
    required this.tab,
    required this.active,
    required this.clipboard,
    required this.onOpenInNewTab,
    required this.onDrop,
    super.key,
  });

  final FolderTab tab;
  final bool active;
  final FileClipboard clipboard;
  final void Function(String path, {bool activate}) onOpenInNewTab;

  /// Files dropped on a folder (or on the view, for its own folder).
  final Future<void> Function(List<String> paths, String target) onDrop;

  @override
  State<FolderView> createState() => _FolderViewState();
}

/// Where the items of a view are, in the scrollable's content coordinates,
/// for the rubber band and to tell a click on an item from one beside it.
abstract class _Geometry {
  Rect itemRect(int index);

  /// The part of an item that picks it up: its name cell in Details, the
  /// whole item elsewhere.
  Rect grabRect(int index) => itemRect(index);
  int get count;

  int? grabbedAt(Offset content) {
    for (int i = 0; i < count; i++) {
      if (grabRect(i).contains(content)) return i;
    }
    return null;
  }
}

class _ListGeometry extends _Geometry {
  _ListGeometry(this.count, this.width, this.labelWidth);

  static const double top = 4;
  static const double inset = 8;
  static const double row = _FolderViewState.rowHeight;
  @override
  final int count;
  final double width;

  /// The width of a row's icon and name, from the row's start: as in
  /// Windows, the rest of the row starts a rubber band.
  final double Function(int index) labelWidth;

  @override
  Rect itemRect(int index) => Rect.fromLTWH(inset, top + index * row, width - 2 * inset, row);

  @override
  Rect grabRect(int index) => Rect.fromLTWH(inset, top + index * row, labelWidth(index), row);

  @override
  int? grabbedAt(Offset content) {
    final int index = ((content.dy - top) / row).floor();
    if (index < 0 || index >= count) return null;
    return grabRect(index).contains(content) ? index : null;
  }
}

class _GridGeometry extends _Geometry {
  _GridGeometry(this.count, double width, this.itemWidth, this.itemHeight)
      : columns = math.max(1, ((width - 2 * pad + gap) / (itemWidth + gap)).floor()) {
    cellWidth = (width - 2 * pad - gap * (columns - 1)) / columns;
  }

  static const double pad = 16;
  static const double gap = 8;
  @override
  final int count;
  final double itemWidth;
  final double itemHeight;
  final int columns;
  late final double cellWidth;

  @override
  Rect itemRect(int index) => Rect.fromLTWH(
        pad + (index % columns) * (cellWidth + gap),
        pad + (index ~/ columns) * (itemHeight + gap),
        cellWidth,
        itemHeight,
      );

  @override
  int? grabbedAt(Offset content) {
    final int column = ((content.dx - pad) / (cellWidth + gap)).floor();
    final int row = ((content.dy - pad) / (itemHeight + gap)).floor();
    if (column < 0 || column >= columns || row < 0) return null;
    final int index = row * columns + column;
    return index < count && itemRect(index).contains(content) ? index : null;
  }
}

/// A row of fixed-width cells, cut off at the right instead of overflowing
/// when the columns are wider than the view.
Widget _clipRow(Widget row) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: row,
    );

class _FolderViewState extends State<FolderView> {
  static const double rowHeight = 48;

  List<FileEntry> _entries = [];
  String? _error;
  bool _loading = true;
  String? _loadedPath;
  int _reloads = 0;

  final Set<String> _selection = {};
  String? _anchor;
  bool _selectMode = false;

  // Details columns (the name column takes the rest until resized).
  double? _nameWidth;
  double _modifiedWidth = 190;
  double _sizeWidth = 110;
  double _typeWidth = 150;
  static const double _tagWidth = 64;

  // The rubber band, in content coordinates.
  Offset? _bandOrigin;
  Offset? _bandPointer;
  bool _banding = false;
  Set<String> _bandBase = const {};
  Timer? _autoScroll;
  _Geometry? _geometry;
  double _viewportHeight = 0;

  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _refreshDebounce;
  final FocusNode _focus = FocusNode(debugLabel: "folder view");
  final ScrollController _scroll = ScrollController();

  FolderTab get _tab => widget.tab;
  String get _path => _tab.path;
  bool get _inTrash => _tab.inTrash;

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    widget.clipboard.addListener(_onClipboardChanged);
    _reloads = _tab.reloads;
    _load();
    if (widget.active) _requestFocus();
  }

  @override
  void didUpdateWidget(FolderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab.removeListener(_onTabChanged);
      widget.tab.addListener(_onTabChanged);
      _onTabChanged();
    }
    if (widget.active && !oldWidget.active) _requestFocus();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    widget.clipboard.removeListener(_onClipboardChanged);
    _watcher?.cancel();
    _refreshDebounce?.cancel();
    _autoScroll?.cancel();
    _focus.dispose();
    _scroll.dispose();
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

  void _onTabChanged() {
    if (_tab.reloads != _reloads) {
      _reloads = _tab.reloads;
      _load();
    }
    if (_path == _loadedPath) {
      setState(() {});
      return;
    }
    setState(() {
      _selection.clear();
      _anchor = null;
      _loading = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  Future<void> _load() async {
    final String path = _path;
    final Directory dir = Directory(path);
    final List<FileEntry> entries = [];
    String? error;
    try {
      if (path == FileOps.trashFiles) await dir.create(recursive: true);
      await for (final FileSystemEntity e in dir.list(followLinks: false)) {
        try {
          entries.add(FileEntry(e, await FileStat.stat(e.path)));
        } on FileSystemException {
          // Broken link or vanished file.
        }
      }
    } on FileSystemException catch (e) {
      error = e.osError?.message ?? e.message;
    }

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
      _selection.removeWhere((selected) => !entries.any((e) => e.path == selected));
    });
  }

  List<FileEntry> get _visible {
    final String filter = _tab.filter.toLowerCase();
    final List<FileEntry> list = _entries
        .where((e) => _tab.showHidden || !e.hidden)
        .where((e) => filter.isEmpty || e.name.toLowerCase().contains(filter))
        .toList();
    int compare(FileEntry a, FileEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final int result = switch (_tab.sort) {
        SortKey.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortKey.size => a.stat.size.compareTo(b.stat.size),
        SortKey.modified => a.stat.modified.compareTo(b.stat.modified),
        SortKey.type => a.typeName.compareTo(b.typeName),
      };
      return _tab.ascending ? result : -result;
    }

    return list..sort(compare);
  }

  List<FileEntry> get _selectedEntries => _entries.where((e) => _selection.contains(e.path)).toList();

  void _setSort(SortKey key) => _tab.update(() {
        if (_tab.sort == key) {
          _tab.ascending = !_tab.ascending;
        } else {
          _tab.sort = key;
          _tab.ascending = true;
        }
      });

  /// Folders open here; files with their default app (Open With… changes
  /// it), else with the dahliaOS app for them, else the user picks one.
  Future<void> _open(FileEntry entry) async {
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
    for (final FileEntry entry in _selectedEntries.where((e) => e.isDir)) {
      widget.onOpenInNewTab(entry.path, activate: false);
    }
  }

  void _select(FileEntry entry, {bool toggle = false, bool range = false}) {
    setState(() {
      if (range && _anchor != null) {
        final List<FileEntry> visible = _visible;
        final int a = visible.indexWhere((e) => e.path == _anchor);
        final int b = visible.indexOf(entry);
        if (a != -1 && b != -1) {
          _selection
            ..clear()
            ..addAll(visible.sublist(math.min(a, b), math.max(a, b) + 1).map((e) => e.path));
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
    widget.clipboard.set(_selection, cut ? ClipboardMode.cut : ClipboardMode.copy);
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

  Future<void> _rename(FileEntry entry) async {
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

  Future<void> _properties([FileEntry? entry]) async {
    FileEntry? target = entry ?? (_selectedEntries.length == 1 ? _selectedEntries.first : null);
    if (target == null) {
      try {
        target = FileEntry(Directory(_path), await FileStat.stat(_path));
      } on FileSystemException {
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _PropertiesDialog(entry: target!),
    );
  }

  void _openTerminal() {
    final List<FileEntry> selected = _selectedEntries;
    final String dir = selected.length == 1 && selected.first.isDir ? selected.first.path : _path;
    SystemUtils.launchApp("terminal", ["--working-directory", dir]);
  }

  Future<void> _tag(Offset position) async {
    final List<FileEntry> selected = _selectedEntries;
    if (selected.isEmpty) return;
    final String? choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        for (final MapEntry<String, Color> c in FileTags.colors.entries)
          PopupMenuItem(
            value: c.key,
            child: Row(
              children: [
                _TagDot(color: c.value),
                const SizedBox(width: 12),
                Text(c.key),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: "", child: Text("No Tag")),
      ],
    );
    if (choice == null) return;
    bool failed = false;
    for (final FileEntry e in selected) {
      final List<String> tags = FileTags.withColor(e.tags, choice.isEmpty ? null : choice);
      if (FileTags.write(e.path, tags)) {
        e.tags = tags;
      } else {
        failed = true;
      }
    }
    if (failed) _showMessage("This drive can't keep tags");
    if (mounted) setState(() {});
  }

  Future<void> _showSortMenu(Offset position) async {
    final SortKey? key = await showMenu<SortKey>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        for (final (SortKey k, String label) in const [
          (SortKey.name, "Name"),
          (SortKey.modified, "Date modified"),
          (SortKey.size, "Size"),
          (SortKey.type, "Type"),
        ])
          CheckedPopupMenuItem(
            value: k,
            checked: _tab.sort == k,
            child: Text("$label${_tab.sort == k ? (_tab.ascending ? " (A–Z)" : " (Z–A)") : ""}"),
          ),
      ],
    );
    if (key != null) _setSort(key);
  }

  Future<void> _showNewMenu(Offset position) async {
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: "folder", child: Text("New Folder…")),
        PopupMenuItem(value: "file", child: Text("New File…")),
      ],
    );
    switch (action) {
      case "folder":
        await _newFolder();
      case "file":
        await _newFile();
    }
  }

  Future<void> _showContextMenu(Offset position, FileEntry? entry) async {
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
          const PopupMenuItem(value: "tag", child: Text("Tag…")),
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
        await showOpenWithDialog(context, [for (final FileEntry e in _selectedEntries) e.path]);
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
      case "tag":
        await _tag(position);
      case "trash":
        await _trashSelection();
      case "delete":
        await _deleteSelection();
      case "restore":
        await _restoreSelection();
      case "properties":
        await _properties(entry);
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
        _tab.update(() => _tab.showHidden = !_tab.showHidden);
    }
  }

  // The rubber band.

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

  void _onPointerDown(PointerDownEvent event) {
    final _Geometry? geometry = _geometry;
    if (geometry == null || event.buttons != kPrimaryButton) return;
    final Offset content = event.localPosition + Offset(0, _offset);
    if (geometry.grabbedAt(content) != null) return;
    _bandOrigin = content;
    _bandPointer = event.localPosition;
    _banding = false;
    _bandBase = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed
        ? {..._selection}
        : const {};
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_bandOrigin == null) return;
    _bandPointer = event.localPosition;
    if (!_banding && (event.localPosition + Offset(0, _offset) - _bandOrigin!).distance < kTouchSlop) return;
    _banding = true;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollStep());
    _updateBand();
  }

  void _onPointerEnd(PointerEvent event) {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (_banding || _bandOrigin != null) {
      setState(() {
        _bandOrigin = null;
        _bandPointer = null;
        _banding = false;
      });
    }
  }

  /// Scrolls while the band's corner is held above or below the files.
  void _autoScrollStep() {
    final Offset? pointer = _bandPointer;
    if (pointer == null || !_scroll.hasClients) return;
    const double edge = 32;
    double delta = 0;
    if (pointer.dy < edge) delta = -(edge - pointer.dy) * 0.5;
    if (pointer.dy > _viewportHeight - edge) delta = (pointer.dy - (_viewportHeight - edge)) * 0.5;
    if (delta == 0) return;
    final ScrollPosition position = _scroll.position;
    final double target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    _scroll.jumpTo(target);
    _updateBand();
  }

  void _updateBand() {
    final _Geometry? geometry = _geometry;
    final Offset? origin = _bandOrigin;
    final Offset? pointer = _bandPointer;
    if (geometry == null || origin == null || pointer == null) return;
    final Rect band = Rect.fromPoints(origin, pointer + Offset(0, _offset));
    final List<FileEntry> visible = _visible;
    final Set<String> inside = {
      for (int i = 0; i < math.min(geometry.count, visible.length); i++)
        if (geometry.itemRect(i).overlaps(band)) visible[i].path,
    };
    setState(() {
      _selection
        ..clear()
        ..addAll(_bandBase)
        ..addAll(inside);
    });
  }

  Widget _withBand(Widget scrollable) {
    final ThemeData theme = Theme.of(context);
    final Offset? origin = _bandOrigin;
    final Offset? pointer = _bandPointer;
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: Stack(
            children: [
              Positioned.fill(child: scrollable),
              if (_banding && origin != null && pointer != null)
                Positioned.fromRect(
                  rect: Rect.fromPoints(origin - Offset(0, _offset), pointer),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.14),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Items.

  /// Taps, the context menu and dragging for one item; folders also take
  /// drops.
  Widget _item(FileEntry entry, {required Widget child}) {
    final Widget item = GestureDetector(
      onTap: () {
        _select(
          entry,
          toggle: _selectMode || HardwareKeyboard.instance.isControlPressed,
          range: HardwareKeyboard.instance.isShiftPressed,
        );
        _focus.requestFocus();
      },
      onDoubleTap: _selectMode ? null : () => _open(entry),
      onTertiaryTapUp: entry.isDir && !_inTrash ? (_) => widget.onOpenInNewTab(entry.path, activate: false) : null,
      onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition, entry),
      child: child,
    );
    if (!entry.isDir || _inTrash) return item;
    return DragTarget<FileDragData>(
      onWillAcceptWithDetails: (d) => !d.data.paths.contains(entry.path),
      onAcceptWithDetails: (d) => widget.onDrop(d.data.paths, entry.path),
      builder: (context, candidates, _) => candidates.isEmpty
          ? item
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: item,
            ),
    );
  }

  /// Dragging [entry] (with the rest of the selection when it's selected).
  Widget _draggable(FileEntry entry, Widget child) {
    if (_inTrash) return child;
    final bool selected = _selection.contains(entry.path);
    final List<String> paths = selected ? _selection.toList() : [entry.path];
    final ThemeData theme = Theme.of(context);
    return Draggable<FileDragData>(
      data: FileDragData(paths),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        if (!selected) _select(entry);
      },
      feedback: Transform.translate(
        offset: const Offset(12, 12),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EntryIcon(entry: entry, size: 24),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    paths.length == 1 ? entry.name : "${paths.length} items",
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: child),
      child: child,
    );
  }

  Widget _check(FileEntry entry) {
    final ThemeData theme = Theme.of(context);
    final bool selected = _selection.contains(entry.path);
    return Icon(
      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
      size: 18,
      color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );
  }

  Color? _itemFill(ThemeData theme, bool selected) => selected
      ? theme.colorScheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.32 : 0.2)
      : null;

  Widget _buildDetails(List<FileEntry> entries) {
    final ThemeData theme = Theme.of(context);
    final DateFormat format = DateFormat("dd.MM.yyyy - HH:mm");
    final TextStyle cell = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      fontSize: 13,
    );
    final Color line = theme.colorScheme.onSurface.withValues(alpha: 0.1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double fixed = _modifiedWidth + _sizeWidth + _typeWidth + _tagWidth;
        final double nameWidth = math.max(160, _nameWidth ?? width - 2 * _ListGeometry.inset - fixed);
        final TextStyle nameStyle = theme.textTheme.bodyMedium!.copyWith(fontSize: 14);
        _geometry = _ListGeometry(entries.length, width, (index) {
          final TextPainter text = TextPainter(
            text: TextSpan(text: entries[index].name, style: nameStyle),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final double label = 12 + (_selectMode ? 28 : 0) + 20 + 12 + text.width + 12;
          text.dispose();
          return math.min(label, nameWidth);
        });

        // A header cell; its right edge drags to resize the column.
        Widget header(String label, SortKey? key, double w, ValueChanged<double>? resize) {
          final bool sorted = key != null && _tab.sort == key;
          return SizedBox(
            width: w,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: key == null ? null : () => _setSort(key),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: cell)),
                          if (sorted) ...[
                            const SizedBox(width: 6),
                            Icon(
                              _tab.ascending ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                              size: 16,
                              color: cell.color,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (resize != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) => setState(() => resize(d.delta.dx)),
                      child: SizedBox(
                        width: 9,
                        height: 30,
                        child: Center(child: SizedBox(width: 1, height: 30, child: ColoredBox(color: line))),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final Widget headerRow = Padding(
          padding: const EdgeInsets.symmetric(horizontal: _ListGeometry.inset),
          child: _clipRow(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              header("Name", SortKey.name, nameWidth, (dx) => _nameWidth = math.max(160, nameWidth + dx)),
              header("Date modified", SortKey.modified, _modifiedWidth, (dx) => _modifiedWidth = math.max(90, _modifiedWidth + dx)),
              header("Size", SortKey.size, _sizeWidth, (dx) => _sizeWidth = math.max(60, _sizeWidth + dx)),
              header("Type", SortKey.type, _typeWidth, (dx) => _typeWidth = math.max(70, _typeWidth + dx)),
              header("Tag", null, _tagWidth, null),
            ],
          )),
        );

        final Widget rows = ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(top: _ListGeometry.top, bottom: 24),
          itemExtent: rowHeight,
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final FileEntry entry = entries[index];
            final bool selected = _selection.contains(entry.path);
            final bool cut = widget.clipboard.isCut(entry.path);
            final Color? tag = FileTags.colorOf(entry.tags);
            final Widget name = SizedBox(
              width: nameWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (_selectMode) ...[_check(entry), const SizedBox(width: 10)],
                    _EntryIcon(entry: entry, size: 22),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                  ],
                ),
              ),
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: _ListGeometry.inset),
              child: _item(
                entry,
                child: _Hover(
                  fill: _itemFill(theme, selected),
                  child: Opacity(
                    opacity: cut || entry.hidden ? 0.5 : 1,
                    child: _clipRow(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _draggable(entry, name),
                        _cell(format.format(entry.stat.modified), _modifiedWidth, cell),
                        _cell(entry.isDir ? "" : formatBytes(entry.stat.size, decimals: 2), _sizeWidth, cell),
                        _cell(entry.typeName, _typeWidth, cell),
                        SizedBox(
                          width: _tagWidth,
                          child: tag == null
                              ? null
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: _TagDot(color: tag),
                                  ),
                                ),
                        ),
                      ],
                    )),
                  ),
                ),
              ),
            );
          },
        );

        return Column(
          children: [
            headerRow,
            SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: line)),
            Expanded(child: _withBand(rows)),
          ],
        );
      },
    );
  }

  Widget _cell(String text, double width, TextStyle style) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text, overflow: TextOverflow.ellipsis, style: style),
        ),
      );

  /// Small, Medium and Large icons, and Tiles.
  Widget _buildGrid(List<FileEntry> entries, FilesViewMode mode) {
    final ThemeData theme = Theme.of(context);
    final (double w, double h, double icon) = switch (mode) {
      FilesViewMode.small => (92.0, 88.0, 36.0),
      FilesViewMode.medium => (124.0, 124.0, 60.0),
      FilesViewMode.large => (172.0, 176.0, 104.0),
      _ => (280.0, 72.0, 44.0),
    };
    final bool tiles = mode == FilesViewMode.tiles;
    final TextStyle dim = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final _GridGeometry geometry = _GridGeometry(entries.length, constraints.maxWidth, w, h);
        _geometry = geometry;
        final Widget grid = GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(_GridGeometry.pad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: geometry.columns,
            mainAxisExtent: h,
            crossAxisSpacing: _GridGeometry.gap,
            mainAxisSpacing: _GridGeometry.gap,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final FileEntry entry = entries[index];
            final bool selected = _selection.contains(entry.path);
            final bool cut = widget.clipboard.isCut(entry.path);
            final Color? tag = FileTags.colorOf(entry.tags);
            final Widget body = tiles
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        if (_selectMode) ...[_check(entry), const SizedBox(width: 8)],
                        _EntryIcon(entry: entry, size: icon),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
                                  if (tag != null) ...[const SizedBox(width: 6), _TagDot(color: tag, size: 8)],
                                ],
                              ),
                              Text(entry.typeName, style: dim, overflow: TextOverflow.ellipsis),
                              if (!entry.isDir) Text(formatBytes(entry.stat.size, decimals: 2), style: dim),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Expanded(child: Center(child: _EntryIcon(entry: entry, size: icon))),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (tag != null) ...[_TagDot(color: tag, size: 8), const SizedBox(width: 4)],
                                Flexible(
                                  child: Text(
                                    entry.name,
                                    maxLines: mode == FilesViewMode.small ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_selectMode) Positioned(left: 0, top: 0, child: _check(entry)),
                      ],
                    ),
                  );
            return _item(
              entry,
              child: _draggable(
                entry,
                _Hover(
                  fill: _itemFill(theme, selected),
                  radius: 10,
                  child: Opacity(opacity: cut || entry.hidden ? 0.5 : 1, child: body),
                ),
              ),
            );
          },
        );
        return _withBand(grid);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<FileEntry> visible = _visible;

    final Widget toolbar = _ContentToolbar(
      inTrash: _inTrash,
      view: _tab.view,
      hasSelection: _selection.isNotEmpty,
      canPaste: !_inTrash,
      selectMode: _selectMode,
      onNew: _showNewMenu,
      onEmptyTrash: () => _run(FileOps.emptyTrash),
      onView: (mode) => _tab.update(() => _tab.view = mode),
      onCopy: _copySelection,
      onPaste: _paste,
      onDelete: _trashSelection,
      onTerminal: _openTerminal,
      onSelectMode: () => setState(() => _selectMode = !_selectMode),
      onSort: _showSortMenu,
      onProperties: _properties,
    );

    final Widget content = _loading && _entries.isEmpty
        ? const SizedBox.expand()
        : _error != null
            ? EmptyState(icon: Icons.block_rounded, title: "Can't open this folder", subtitle: _error)
            : visible.isEmpty
                ? EmptyState(
                    icon: _inTrash ? Icons.delete_outline_rounded : Icons.folder_open_rounded,
                    title: _tab.filter.isNotEmpty
                        ? "No matches"
                        : _inTrash
                            ? "Trash is empty"
                            : "This folder is empty",
                  )
                : _tab.view == FilesViewMode.details
                    ? _buildDetails(visible)
                    : _buildGrid(visible, _tab.view);
    if (visible.isEmpty) _geometry = null;

    // Clicks beside the files clear the selection; drops on the view land
    // in its folder.
    final Widget files = DragTarget<FileDragData>(
      onWillAcceptWithDetails: (d) => !_inTrash && d.data.paths.any((path) => !p.equals(p.dirname(path), _path)),
      onAcceptWithDetails: (d) => widget.onDrop(d.data.paths, _path),
      builder: (context, candidates, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!HardwareKeyboard.instance.isControlPressed) setState(_selection.clear);
          _focus.requestFocus();
        },
        onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition, null),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: candidates.isEmpty ? null : Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          ),
          child: content,
        ),
      ),
    );

    return Column(
      children: [
        toolbar,
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.delete): _trashSelection,
              const SingleActivator(LogicalKeyboardKey.delete, shift: true): _deleteSelection,
              const SingleActivator(LogicalKeyboardKey.f2): () {
                final List<FileEntry> selected = _selectedEntries;
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
              const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
                  _tab.update(() => _tab.showHidden = !_tab.showHidden),
              const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _tab.back,
              const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _tab.forward,
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _tab.up,
              const SingleActivator(LogicalKeyboardKey.home, alt: true): () => _tab.navigate(SystemUtils.home),
              const SingleActivator(LogicalKeyboardKey.backspace): _tab.back,
              const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
                    _selection.clear();
                    _selectMode = false;
                  }),
              const SingleActivator(LogicalKeyboardKey.enter): () {
                final List<FileEntry> selected = _selectedEntries;
                if (selected.length == 1) _open(selected.first);
              },
              const SingleActivator(LogicalKeyboardKey.enter, control: true): _openSelectedInNewTabs,
            },
            child: Focus(
              focusNode: _focus,
              autofocus: widget.active,
              child: files,
            ),
          ),
        ),
      ],
    );
  }
}

/// A light fill on hover, the selection's when selected.
class _Hover extends StatefulWidget {
  const _Hover({required this.child, this.fill, this.radius = 8});

  final Widget child;
  final Color? fill;
  final double radius;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.fill ?? (_hover ? theme.colorScheme.onSurface.withValues(alpha: 0.05) : null),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: widget.child,
      ),
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.color, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The row above the files: New, the view switcher and the actions.
class _ContentToolbar extends StatelessWidget {
  const _ContentToolbar({
    required this.inTrash,
    required this.view,
    required this.hasSelection,
    required this.canPaste,
    required this.selectMode,
    required this.onNew,
    required this.onEmptyTrash,
    required this.onView,
    required this.onCopy,
    required this.onPaste,
    required this.onDelete,
    required this.onTerminal,
    required this.onSelectMode,
    required this.onSort,
    required this.onProperties,
  });

  final bool inTrash;
  final FilesViewMode view;
  final bool hasSelection;
  final bool canPaste;
  final bool selectMode;
  final ValueChanged<Offset> onNew;
  final VoidCallback onEmptyTrash;
  final ValueChanged<FilesViewMode> onView;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onDelete;
  final VoidCallback onTerminal;
  final VoidCallback onSelectMode;
  final ValueChanged<Offset> onSort;
  final VoidCallback onProperties;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.75);

    Widget action(String tooltip, IconData icon, VoidCallback? onPressed, {bool active = false}) => IconButton(
          tooltip: tooltip,
          iconSize: 20,
          isSelected: active,
          color: iconColor,
          selectedIcon: Icon(icon, color: theme.colorScheme.primary),
          icon: Icon(icon),
          onPressed: onPressed,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Labels go before the switcher squeezes the actions out.
        final bool labels = constraints.maxWidth > 900;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Builder(
                builder: (context) => inTrash
                    ? FilledButton.icon(
                        style: _squareButton(theme, theme.colorScheme.error, theme.colorScheme.onError),
                        onPressed: onEmptyTrash,
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: const Text("Empty"),
                      )
                    : FilledButton.icon(
                        style: _squareButton(theme, theme.colorScheme.primary, theme.colorScheme.onPrimary),
                        onPressed: () {
                          final RenderBox box = context.findRenderObject()! as RenderBox;
                          onNew(box.localToGlobal(Offset(0, box.size.height + 4)));
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text("New"),
                      ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ViewSwitcher(view: view, labels: labels, onView: onView),
                ),
              ),
              const SizedBox(width: 12),
              action("Copy (Ctrl+C)", Icons.copy_rounded, hasSelection && !inTrash ? onCopy : null),
              action("Paste (Ctrl+V)", Icons.content_paste_rounded, canPaste ? onPaste : null),
              action(inTrash ? "Delete permanently" : "Move to Trash (Delete)", Icons.delete_outline_rounded,
                  hasSelection ? onDelete : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(width: 1.5, height: 20, child: ColoredBox(color: iconColor)),
              ),
              action("Open in Terminal", Icons.terminal_rounded, inTrash ? null : onTerminal),
              action("Select items", Icons.checklist_rounded, onSelectMode, active: selectMode),
              Builder(
                builder: (context) => action("Sort", Icons.sort_by_alpha_rounded, () {
                  final RenderBox box = context.findRenderObject()! as RenderBox;
                  onSort(box.localToGlobal(Offset(0, box.size.height)));
                }),
              ),
              action("Properties", Icons.info_outline_rounded, onProperties),
            ],
          ),
        );
      },
    );
  }

  static ButtonStyle _squareButton(ThemeData theme, Color background, Color foreground) => FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      );
}

/// Details, Tiles, Small, Medium and Large icons: a pill with the current
/// mode filled in the accent color.
class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.view, required this.labels, required this.onView});

  final FilesViewMode view;
  final bool labels;
  final ValueChanged<FilesViewMode> onView;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: theme.brightness == Brightness.dark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(17),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final FilesViewMode mode in FilesViewMode.values)
              Tooltip(
                message: labels ? "" : mode.label,
                child: Material(
                  color: mode == view ? theme.colorScheme.primary : Colors.transparent,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onView(mode),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: labels ? 14 : 10),
                      child: SizedBox(
                        height: 34,
                        child: Row(
                          children: [
                            Icon(
                              mode.icon,
                              size: 16,
                              color: mode == view
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                            if (labels) ...[
                              const SizedBox(width: 6),
                              Text(
                                mode.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  color: mode == view ? theme.colorScheme.onPrimary : null,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A file's Papirus icon (beige folders), or for pictures at a size where
/// it reads, the picture itself.
class _EntryIcon extends StatelessWidget {
  const _EntryIcon({required this.entry, required this.size});

  final FileEntry entry;
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
    final String? asset = Papirus.assetFor(entry.path, entry.kind, size);
    if (asset != null) return PapirusIcon(asset: asset, size: size);
    final (IconData icon, Color color) = iconFor(entry.kind, Theme.of(context).colorScheme);
    return Icon(icon, size: size, color: color);
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
  final FileEntry entry;

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
    final FileEntry entry = widget.entry;
    final DateFormat format = DateFormat.yMMMMd().add_jms();
    final String? original = p.isWithin(FileOps.trashFiles, entry.path)
        ? FileOps.trashedOriginalPath(entry.path)
        : null;
    final List<String> tags = entry.tags;
    return AlertDialog(
      title: Row(
        children: [
          _EntryIcon(entry: entry, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(entry.name.isEmpty ? entry.path : entry.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoRow(label: "Type", value: entry.isDir ? "Folder" : (FileOps.mimeType(entry.path) ?? entry.typeName)),
            InfoRow(label: "Location", value: p.dirname(entry.path)),
            if (original != null) InfoRow(label: "Original location", value: original),
            InfoRow(
              label: "Size",
              value: _size == null ? "Calculating…" : "${formatBytes(_size!)} ($_size bytes)",
            ),
            InfoRow(label: "Modified", value: format.format(entry.stat.modified)),
            InfoRow(label: "Accessed", value: format.format(entry.stat.accessed)),
            InfoRow(label: "Permissions", value: permissionString(entry.stat)),
            if (tags.isNotEmpty) InfoRow(label: "Tags", value: tags.join(", ")),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
      ],
    );
  }
}
