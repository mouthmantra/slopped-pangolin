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
import 'package:dahlia_apps/apps/files/files_model.dart';
import 'package:dahlia_apps/apps/files/folder_view.dart';
import 'package:dahlia_apps/apps/files/papirus.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:yaru_window/yaru_window.dart';

final DahliaAppSpec filesApp = DahliaAppSpec(
  name: "files",
  title: "Files",
  builder: (context, args) => FilesPage(initialPaths: args),
);

/// The Files window, as the dahliaOS design draws it: tabs in the title
/// bar; a navigation row (back, forward, up, refresh, the path, search,
/// settings); a sidebar of collapsible sections (Favourites, Drives, Cloud
/// Drives); and one folder view per tab. Translucent over the wallpaper.
class FilesPage extends StatefulWidget {
  const FilesPage({this.initialPaths = const [], super.key});

  /// Folders (or files, whose folder is opened) to open, one tab each.
  final List<String> initialPaths;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  static const int _maxClosedTabs = 16;

  final List<FolderTab> _tabs = [];
  final List<String> _closedTabs = [];
  final FileClipboard _clipboard = FileClipboard();
  late final List<Place> _places = FileOps.userPlaces();
  final GlobalKey<_NavigationBarState> _navigation = GlobalKey();
  int _current = 0;
  String? _windowTitle;
  Timer? _tabSpring;

  FolderTab get _tab => _tabs[_current];

  @override
  void initState() {
    super.initState();
    for (final String arg in widget.initialPaths) {
      final String? path = _resolveArgument(arg);
      if (path != null) _insertTab(FolderTab(path));
    }
    if (_tabs.isEmpty) _insertTab(FolderTab(SystemUtils.home));
    _current = 0;
    // Glyphs until Papirus' index is read (a few milliseconds).
    unawaited(Papirus.load().then((_) {
      if (mounted) setState(() {});
    }));
  }

  @override
  void dispose() {
    for (final FolderTab tab in _tabs) {
      tab.dispose();
    }
    _clipboard.dispose();
    _tabSpring?.cancel();
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

  void _insertTab(FolderTab tab, {int? at}) {
    tab.addListener(_onTabChanged);
    _tabs.insert(at ?? _tabs.length, tab);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// Opens [path] in a new tab next to the current one.
  void _openTab(String path, {bool activate = true}) {
    final FolderTab tab = FolderTab(
      path,
      view: _tab.view,
      showHidden: _tab.showHidden,
      sort: _tab.sort,
      ascending: _tab.ascending,
    );
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
    final FolderTab tab = _tabs[index];
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
      final FolderTab current = _tab;
      _tabs.insert(to, _tabs.removeAt(from));
      _current = _tabs.indexOf(current);
    });
  }

  IconData _iconFor(FolderTab tab) {
    if (tab.inTrash) return Icons.delete_outline_rounded;
    if (tab.path == "/") return Icons.computer_outlined;
    for (final Place place in _places) {
      if (place.path == tab.path) return place.icon;
    }
    return Icons.folder_outlined;
  }

  /// Files dropped on a folder, a tab or a sidebar place.
  Future<void> _drop(List<String> paths, String target) async {
    try {
      await dropFiles(paths, target);
    } on FileSystemException catch (e) {
      if (!mounted) return;
      final String reason = e.osError?.message ?? e.message;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("$reason${e.path != null ? ": ${p.basename(e.path!)}" : ""}")));
    }
    for (final FolderTab tab in _tabs) {
      if (p.equals(tab.path, target) || paths.any((path) => p.equals(p.dirname(path), tab.path))) tab.reload();
    }
  }

  /// A tab takes drops into its folder, and comes forward when files are
  /// held over it.
  Widget _tabDropTarget(int index, Widget tab) {
    return DragTarget<FileDragData>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (_) {
        if (index == _current) return;
        _tabSpring ??= Timer(const Duration(milliseconds: 600), () {
          _tabSpring = null;
          if (mounted) _selectTab(index);
        });
      },
      onLeave: (_) {
        _tabSpring?.cancel();
        _tabSpring = null;
      },
      onAcceptWithDetails: (d) {
        _tabSpring?.cancel();
        _tabSpring = null;
        _drop(d.data.paths, _tabs[index].path);
      },
      builder: (context, candidates, _) => candidates.isEmpty
          ? tab
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: tab,
            ),
    );
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
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _navigation.currentState?.editPath(true),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _navigation.currentState?.focusSearch(),
        for (int i = 1; i <= 9; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1), alt: true): () =>
              _selectTab(i == 9 ? _tabs.length - 1 : i - 1),
      },
      child: DahliaScaffold(
        glass: true,
        // Tabs from the window's edge, in a taller row, as the design has.
        showIcon: false,
        titlebarHeight: 54,
        title: DahliaTabStrip(
          tabs: [
            for (final FolderTab tab in _tabs)
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
          wrapTab: _tabDropTarget,
          maxTabWidth: 224,
        ),
        body: Column(
          children: [
            _NavigationBar(
              key: _navigation,
              tab: _tab,
              onOpenInNewTab: (path) => _openTab(path, activate: false),
            ),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(
                    places: _places,
                    current: _tab.path,
                    onNavigate: (path) => _tab.navigate(path),
                    onOpenInNewTab: (path) => _openTab(path, activate: false),
                    onDrop: _drop,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _current,
                      children: [
                        for (int i = 0; i < _tabs.length; i++)
                          ExcludeFocus(
                            key: ObjectKey(_tabs[i]),
                            excluding: i != _current,
                            child: FolderView(
                              tab: _tabs[i],
                              active: i == _current,
                              clipboard: _clipboard,
                              onOpenInNewTab: _openTab,
                              onDrop: _drop,
                            ),
                          ),
                      ],
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

/// Back, forward, up and refresh; the path as breadcrumbs (Home ›
/// Documents), editable with a double click or Ctrl+L; search in the
/// folder; and the settings menu.
class _NavigationBar extends StatefulWidget {
  const _NavigationBar({required this.tab, required this.onOpenInNewTab, super.key});

  final FolderTab tab;
  final ValueChanged<String> onOpenInNewTab;

  @override
  State<_NavigationBar> createState() => _NavigationBarState();
}

class _NavigationBarState extends State<_NavigationBar> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _editing = false;

  FolderTab get _tab => widget.tab;

  @override
  void initState() {
    super.initState();
    _search.text = _tab.filter;
  }

  @override
  void didUpdateWidget(_NavigationBar old) {
    super.didUpdateWidget(old);
    // Another tab, or the folder changed (which clears its search).
    if (_search.text != _tab.filter) _search.text = _tab.filter;
    if (old.tab != widget.tab) _editing = false;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void editPath(bool editing) => setState(() => _editing = editing);

  void focusSearch() => _searchFocus.requestFocus();

  void _submitPath(String value) {
    setState(() => _editing = false);
    String path = value.trim();
    if (path == "~" || path.startsWith("~/")) path = SystemUtils.home + path.substring(1);
    if (path.isEmpty) return;
    path = p.normalize(p.isAbsolute(path) ? path : p.join(_tab.path, path));
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.directory:
        _tab.navigate(path);
      case FileSystemEntityType.notFound:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text("“$value” doesn't exist")));
      default:
        _tab.navigate(p.dirname(path));
    }
  }

  /// The path's crumbs: from Home inside the home folder, from the local
  /// drive elsewhere.
  List<(String, String)> _crumbs() {
    final String path = _tab.path;
    if (_tab.inTrash) return [("Trash", path)];
    final String home = SystemUtils.home;
    final (String root, String label) =
        p.equals(path, home) || p.isWithin(home, path) ? (home, "Home") : ("/", "Local drive");
    final List<(String, String)> crumbs = [(label, root)];
    String at = root;
    for (final String part in p.split(p.relative(path, from: root))) {
      if (part == ".") continue;
      at = p.join(at, part);
      crumbs.add((part, at));
    }
    return crumbs;
  }

  Future<void> _showSettings(Offset position) async {
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        CheckedPopupMenuItem(value: "hidden", checked: _tab.showHidden, child: const Text("Show Hidden Files")),
        const PopupMenuDivider(),
        const PopupMenuItem(value: "window", child: Text("New Window")),
        const PopupMenuItem(value: "terminal", child: Text("Open in Terminal")),
      ],
    );
    switch (action) {
      case "hidden":
        _tab.update(() => _tab.showHidden = !_tab.showHidden);
      case "window":
        SystemUtils.launchApp("files", [_tab.path]);
      case "terminal":
        SystemUtils.launchApp("terminal", ["--working-directory", _tab.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color dim = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final Color field = theme.colorScheme.onSurface.withValues(alpha: theme.brightness == Brightness.dark ? 0.08 : 0.045);
    final List<(String, String)> crumbs = _crumbs();

    Widget nav(String tooltip, IconData icon, VoidCallback? onPressed) => IconButton(
          tooltip: tooltip,
          iconSize: 20,
          color: theme.colorScheme.onSurface,
          icon: Icon(icon),
          onPressed: onPressed,
        );

    final Widget location = _editing
        ? Focus(
            // Leaving the field (click elsewhere) cancels editing.
            onFocusChange: (focused) {
              if (!focused) setState(() => _editing = false);
            },
            child: TextFormField(
              key: ValueKey(_tab.path),
              initialValue: _tab.path,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              ),
              onFieldSubmitted: _submitPath,
            ),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => editPath(true),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    for (int i = 0; i < crumbs.length; i++) ...[
                      if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: dim),
                      GestureDetector(
                        onTertiaryTapUp: (_) => widget.onOpenInNewTab(crumbs[i].$2),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: i == crumbs.length - 1 ? theme.colorScheme.onSurface : dim,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            textStyle: const TextStyle(fontSize: 14),
                          ),
                          onPressed: () => _tab.navigate(crumbs[i].$2),
                          child: Text(crumbs[i].$1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );

    return Container(
      // A step between the title bar and the window: the dahliaOS design's
      // second row.
      color: Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(alpha: theme.brightness == Brightness.dark ? 0.04 : 0.03),
        DahliaTitlebar.backgroundOf(context).withValues(alpha: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          nav("Back (Alt+Left)", Icons.arrow_back_rounded, _tab.canBack ? _tab.back : null),
          const SizedBox(width: 8),
          nav("Forward (Alt+Right)", Icons.arrow_forward_rounded, _tab.canForward ? _tab.forward : null),
          const SizedBox(width: 8),
          nav("Up (Alt+Up)", Icons.arrow_upward_rounded, _tab.canGoUp ? _tab.up : null),
          const SizedBox(width: 8),
          nav("Refresh (F5)", Icons.refresh_rounded, _tab.reload),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(color: field, borderRadius: BorderRadius.circular(6)),
              child: location,
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 250,
            height: 40,
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: const TextStyle(fontSize: 14),
              onChanged: (v) => _tab.update(() => _tab.filter = v),
              decoration: InputDecoration(
                hintText: "Search in ${_tab.title}",
                hintStyle: TextStyle(color: dim, fontSize: 14),
                suffixIcon: _search.text.isEmpty
                    ? Icon(Icons.search_rounded, size: 18, color: dim)
                    : IconButton(
                        tooltip: "Clear",
                        iconSize: 16,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _tab.update(() => _tab.filter = "");
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: field,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                focusedBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Builder(
            builder: (context) => nav("Settings", Icons.settings_outlined, () {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              _showSettings(box.localToGlobal(Offset(0, box.size.height)));
            }),
          ),
        ],
      ),
    );
  }
}

/// Favourites, Drives and Cloud Drives, each a collapsible section; the
/// current place filled in the accent colour. Places take dropped files.
class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.places,
    required this.current,
    required this.onNavigate,
    required this.onOpenInNewTab,
    required this.onDrop,
  });

  final List<Place> places;
  final String current;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenInNewTab;
  final Future<void> Function(List<String> paths, String target) onDrop;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final Set<String> _collapsed = {};

  Future<void> _showMenu(Offset position, String path) async {
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
        widget.onNavigate(path);
      case "newtab":
        widget.onOpenInNewTab(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color line = theme.colorScheme.onSurface.withValues(alpha: 0.1);
    final List<Place> drives = [
      const Place("Local drive", Icons.computer_outlined, "/"),
      ...FileOps.volumes(),
    ];
    final List<Place> cloud = FileOps.cloudPlaces();

    Widget section(String title, IconData icon, List<Place> places, {bool divider = true}) {
      final bool open = !_collapsed.contains(title);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (divider)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SizedBox(height: 1, child: ColoredBox(color: line)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => open ? _collapsed.add(title) : _collapsed.remove(title)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500, fontSize: 15),
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0 : -0.25,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.expand_more_rounded, size: 22, color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            for (final Place place in places)
              _PlaceTile(
                place: place,
                selected: widget.current == place.path,
                onTap: () => widget.onNavigate(place.path),
                onMiddleClick: () => widget.onOpenInNewTab(place.path),
                onContextMenu: (position) => _showMenu(position, place.path),
                onDrop: (paths) => widget.onDrop(paths, place.path),
              ),
        ],
      );
    }

    return Container(
      width: 260,
      color: theme.colorScheme.onSurface.withValues(alpha: theme.brightness == Brightness.dark ? 0.05 : 0.03),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          section(
            "Favourites",
            Icons.star_outline_rounded,
            [...widget.places, Place("Trash", Icons.delete_outline_rounded, FileOps.trashFiles)],
            divider: false,
          ),
          section("Drives", Icons.laptop_rounded, drives),
          if (cloud.isNotEmpty) section("Cloud Drives", Icons.cloud_outlined, cloud),
        ],
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.place,
    required this.selected,
    required this.onTap,
    required this.onMiddleClick,
    required this.onContextMenu,
    required this.onDrop,
  });

  final Place place;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMiddleClick;
  final ValueChanged<Offset> onContextMenu;
  final ValueChanged<List<String>> onDrop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return DragTarget<FileDragData>(
      onWillAcceptWithDetails: (d) => !d.data.paths.contains(place.path),
      onAcceptWithDetails: (d) => onDrop(d.data.paths),
      builder: (context, candidates, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 1, 16, 1),
        child: GestureDetector(
          onTertiaryTapUp: (_) => onMiddleClick(),
          onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
          child: Material(
            color: selected
                ? theme.colorScheme.primary
                : candidates.isNotEmpty
                    ? theme.colorScheme.primary.withValues(alpha: 0.2)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(place.icon, size: 19, color: foreground),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        place.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: foreground, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
