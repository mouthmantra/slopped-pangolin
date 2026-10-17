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
import 'dart:ui' as ui;

import 'package:dahlia_apps/apps/files/file_ops.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

final DahliaAppSpec galleryApp = DahliaAppSpec(
  name: "gallery",
  title: "Gallery",
  builder: (context, args) => GalleryPage(args: args),
);

const Set<String> _imageExtensions = {
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".wbmp", //
};

class _Photo {
  _Photo(this.file, this.modified, this.size);
  final File file;
  final DateTime modified;
  final int size;
  String get name => p.basename(file.path);
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({this.args = const [], super.key});

  /// A file opens it in the viewer, a directory becomes the library.
  final List<String> args;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late String _root;
  String? _folder;
  List<_Photo> _photos = [];
  List<String> _folders = [];
  bool _loading = true;

  /// Started without a folder or picture: "Welcome to Gallery" until one is
  /// opened.
  bool _welcome = false;

  String get _picturesDir {
    final Iterable<Place> pictures = FileOps.userPlaces().where((pl) => pl.label == "Pictures");
    return pictures.isNotEmpty ? pictures.first.path : p.join(SystemUtils.home, "Pictures");
  }

  @override
  void initState() {
    super.initState();
    String? openFile;
    _root = _picturesDir;
    if (widget.args.isEmpty) {
      _welcome = true;
      _loading = false;
      return;
    }
    final String arg = widget.args.first;
    if (FileSystemEntity.isDirectorySync(arg)) {
      _root = arg;
    } else if (FileSystemEntity.isFileSync(arg)) {
      _root = p.dirname(arg);
      openFile = arg;
    }
    _scan().then((_) {
      if (openFile == null || !mounted) return;
      final int index = _visible.indexWhere((ph) => ph.file.path == openFile);
      if (index != -1) _openViewer(index);
    });
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final List<_Photo> photos = [];
    final Set<String> folders = {};
    final Directory dir = Directory(_root);
    if (await dir.exists()) {
      try {
        await for (final FileSystemEntity e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          if (p.split(p.relative(e.path, from: _root)).any((s) => s.startsWith("."))) continue;
          if (!_imageExtensions.contains(p.extension(e.path).toLowerCase())) continue;
          final FileStat stat = await e.stat();
          photos.add(_Photo(e, stat.modified, stat.size));
          folders.add(p.dirname(e.path));
          if (photos.length > 5000) break;
        }
      } on FileSystemException {
        // Unreadable subdirectory.
      }
    }
    photos.sort((a, b) => b.modified.compareTo(a.modified));
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _folders = folders.toList()..sort();
      _loading = false;
    });
  }

  List<_Photo> get _visible => _folder == null
      ? _photos
      : _photos.where((ph) => p.dirname(ph.file.path) == _folder).toList();

  Future<void> _openViewer(int index) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (context, _, __) => _Viewer(photos: _visible, initialIndex: index),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (changed ?? false) await _scan();
  }

  Future<void> _chooseFolder() async {
    final String? folder = await showFileDialog(
      context,
      mode: FileDialogMode.folder,
      initialDirectory: _root,
    );
    if (folder == null) return;
    setState(() {
      _root = folder;
      _folder = null;
      _welcome = false;
    });
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_welcome) return DahliaScaffold(body: _Welcome(onOpen: _chooseFolder));
    final List<_Photo> photos = _visible;

    // Group by month for headers.
    final Map<String, List<int>> groups = {};
    final DateFormat month = DateFormat.yMMMM();
    for (int i = 0; i < photos.length; i++) {
      groups.putIfAbsent(month.format(photos[i].modified), () => []).add(i);
    }

    return DahliaScaffold(
      titlebarActions: [
        IconButton(tooltip: "Open folder", icon: const Icon(Icons.folder_open_outlined), onPressed: _chooseFolder),
        IconButton(tooltip: "Refresh", icon: const Icon(Icons.refresh_rounded), onPressed: _scan),
      ],
      body: Row(
        children: [
          SidebarPane(
            width: 210,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SidebarTile(
                  icon: Icons.photo_library_rounded,
                  label: "All photos",
                  selected: _folder == null,
                  trailing: Text("${_photos.length}", style: theme.textTheme.bodySmall),
                  onTap: () => setState(() => _folder = null),
                ),
                if (_folders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                    child: Text("Folders", style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor)),
                  ),
                for (final String folder in _folders)
                  SidebarTile(
                    icon: p.basename(folder) == "Screenshots" ? Icons.screenshot_monitor_rounded : Icons.folder_outlined,
                    label: folder == _root ? p.basename(_root) : p.relative(folder, from: _root),
                    selected: _folder == folder,
                    onTap: () => setState(() => _folder = folder),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : photos.isEmpty
                    ? EmptyState(
                        icon: Icons.image_not_supported_outlined,
                        title: "No pictures here",
                        subtitle: "Pictures and screenshots in $_root will show up here",
                        action: FilledButton.tonalIcon(
                          onPressed: _chooseFolder,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text("Open another folder"),
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          for (final MapEntry<String, List<int>> group in groups.entries) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text(group.key, style: theme.textTheme.titleMedium),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              sliver: SliverGrid(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 180,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  childCount: group.value.length,
                                  (context, i) {
                                    final int index = group.value[i];
                                    return Material(
                                      clipBehavior: Clip.antiAlias,
                                      borderRadius: BorderRadius.circular(8),
                                      color: theme.colorScheme.surface,
                                      child: InkWell(
                                        onTap: () => _openViewer(index),
                                        child: Hero(
                                          tag: photos[index].file.path,
                                          child: Image.file(
                                            photos[index].file,
                                            fit: BoxFit.cover,
                                            cacheWidth: 360,
                                            errorBuilder: (context, _, __) => const Icon(Icons.broken_image_outlined),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(spec: galleryApp, size: 96),
            const SizedBox(height: 24),
            Text("Welcome to Gallery", style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              "Open a folder to browse its pictures.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text("Open Folder"),
            ),
          ],
        ),
      ),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.photos, required this.initialIndex});

  final List<_Photo> photos;
  final int initialIndex;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int _index = widget.initialIndex;
  int _quarterTurns = 0;
  bool _showInfo = false;
  bool _changed = false;
  final TransformationController _transform = TransformationController();
  Size? _dimensions;

  _Photo get _photo => widget.photos[_index];

  @override
  void initState() {
    super.initState();
    _loadDimensions();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _loadDimensions() async {
    _dimensions = null;
    try {
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(await _photo.file.readAsBytes());
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (mounted) {
        setState(() => _dimensions = Size(descriptor.width.toDouble(), descriptor.height.toDouble()));
      }
      descriptor.dispose();
      buffer.dispose();
    } on Object {
      // Undecodable: leave dimensions unknown.
    }
  }

  void _go(int delta) {
    final int next = _index + delta;
    if (next < 0 || next >= widget.photos.length) return;
    setState(() {
      _index = next;
      _quarterTurns = 0;
      _transform.value = Matrix4.identity();
    });
    _loadDimensions();
  }

  void _setWallpaper() {
    CustomizationService.current.wallpaper = ImageResource(
      type: ImageResourceType.file,
      value: _photo.file.path,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Wallpaper updated")),
    );
  }

  Future<void> _trash() async {
    await FileOps.trash(_photo.file.path);
    _changed = true;
    if (!mounted) return;
    if (widget.photos.length == 1) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      widget.photos.removeAt(_index);
      _index = _index.clamp(0, widget.photos.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final _Photo photo = _photo;
    final DateFormat format = DateFormat.yMMMMd().add_jm();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context, _changed),
        const SingleActivator(LogicalKeyboardKey.delete): _trash,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: DahliaTitlebar(
            title: Text("${photo.name}  (${_index + 1}/${widget.photos.length})"),
            leading: [
              IconButton(
                tooltip: "Back to gallery",
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context, _changed),
              ),
            ],
            actions: [
              IconButton(
                tooltip: "Rotate (Ctrl+R)",
                icon: const Icon(Icons.rotate_right_rounded),
                onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
              ),
              IconButton(
                tooltip: "Set as wallpaper",
                icon: const Icon(Icons.wallpaper_rounded),
                onPressed: _setWallpaper,
              ),
              IconButton(
                tooltip: "Move to trash",
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _trash,
              ),
              IconButton(
                tooltip: "Info",
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => setState(() => _showInfo = !_showInfo),
              ),
            ],
          ),
          body: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        maxScale: 8,
                        child: Center(
                          child: Hero(
                            tag: photo.file.path,
                            child: RotatedBox(
                              quarterTurns: _quarterTurns,
                              child: Image.file(photo.file, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_index > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _NavButton(icon: Icons.chevron_left_rounded, onTap: () => _go(-1)),
                      ),
                    if (_index < widget.photos.length - 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _NavButton(icon: Icons.chevron_right_rounded, onTap: () => _go(1)),
                      ),
                  ],
                ),
              ),
              if (_showInfo)
                Container(
                  width: 280,
                  color: Theme.of(context).colorScheme.surface,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      InfoRow(label: "Name", value: photo.name),
                      InfoRow(label: "Folder", value: p.dirname(photo.file.path)),
                      InfoRow(label: "Modified", value: format.format(photo.modified)),
                      InfoRow(label: "Size", value: formatBytes(photo.size)),
                      if (_dimensions != null)
                        InfoRow(
                          label: "Dimensions",
                          value: "${_dimensions!.width.toInt()} × ${_dimensions!.height.toInt()}",
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 32),
          onPressed: onTap,
        ),
      ),
    );
  }
}
