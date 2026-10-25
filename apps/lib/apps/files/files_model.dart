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

import 'package:dahlia_apps/apps/files/file_ops.dart';
import 'package:dahlia_apps/apps/files/file_tags.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// One file or folder of a listing.
class FileEntry {
  FileEntry(this.entity, this.stat)
      : name = p.basename(entity.path),
        isDir = stat.type == FileSystemEntityType.directory;

  final FileSystemEntity entity;
  final FileStat stat;
  final String name;
  final bool isDir;

  String get path => entity.path;
  bool get hidden => name.startsWith(".");
  late final FileKind kind = kindOf(path, isDirectory: isDir);
  late final String typeName = describeType(name, kind);
  late List<String> tags = FileTags.read(path);
}

/// The type column: "PDF Document", "PNG Image", "Folder"…
String describeType(String name, FileKind kind) {
  final String ext = p.extension(name).replaceFirst(".", "").toUpperCase();
  const Map<String, String> known = {
    "TXT": "Text Document",
    "MD": "Markdown Document",
    "FIG": "Figma Design",
    "DESKTOP": "App Shortcut",
    "SH": "Shell Script",
    "PY": "Python Script",
    "HTML": "Web Page",
    "ISO": "Disc Image",
    "IMG": "Disk Image",
  };
  if (kind == FileKind.folder) return "Folder";
  if (known[ext] != null) return known[ext]!;
  if (ext.isEmpty) return kind == FileKind.text ? "Text Document" : "File";
  return switch (kind) {
    FileKind.image => "$ext Image",
    FileKind.video => "$ext Video",
    FileKind.audio => "$ext Audio",
    FileKind.archive => "$ext Archive",
    FileKind.document => "$ext Document",
    FileKind.executable => "Program",
    _ => "$ext File",
  };
}

enum SortKey { name, modified, size, type }

/// The view switcher's modes.
enum FilesViewMode {
  details("Details", Icons.format_list_bulleted_rounded),
  tiles("Tiles", Icons.checklist_rtl_rounded),
  small("Small icons", Icons.grid_on_rounded),
  medium("Medium icons", Icons.tag_rounded),
  large("Large icons", Icons.grid_view_rounded);

  const FilesViewMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Location, history and view options of one tab.
class FolderTab extends ChangeNotifier {
  FolderTab(
    this._path, {
    this.view = FilesViewMode.details,
    this.showHidden = false,
    this.sort = SortKey.name,
    this.ascending = true,
  });

  String _path;
  final List<String> _back = [];
  final List<String> _forward = [];

  /// View options, kept per tab and inherited by tabs opened from it.
  FilesViewMode view;
  bool showHidden;
  SortKey sort;
  bool ascending;

  /// The search field's text: shows only matching names.
  String filter = "";

  /// Increments to make the tab's view read its folder again.
  int reloads = 0;

  String get path => _path;
  bool get canBack => _back.isNotEmpty;
  bool get canForward => _forward.isNotEmpty;
  bool get canGoUp => p.dirname(_path) != _path;
  bool get inTrash => _path == FileOps.trashFiles;

  String get title {
    if (inTrash) return "Trash";
    if (_path == SystemUtils.home) return "Home";
    if (_path == "/") return "Local drive";
    return p.basename(_path);
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  void reload() => update(() => reloads++);

  void navigate(String location, {bool record = true}) {
    final String path = p.normalize(location);
    if (path == _path) return;
    if (record) {
      _back.add(_path);
      _forward.clear();
    }
    _path = path;
    filter = "";
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

enum ClipboardMode { copy, cut }

/// Files cut or copied in any tab of the window.
class FileClipboard extends ChangeNotifier {
  List<String> _items = const [];
  ClipboardMode _mode = ClipboardMode.copy;

  List<String> get items => _items;
  bool get isEmpty => _items.isEmpty;
  bool isCut(String path) => _mode == ClipboardMode.cut && _items.contains(path);

  void set(Iterable<String> items, ClipboardMode mode) {
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
      final (List<String>, bool) result = (_items, _mode == ClipboardMode.cut);
      if (_mode == ClipboardMode.cut) {
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

/// What files being dragged carry.
class FileDragData {
  const FileDragData(this.paths);
  final List<String> paths;
}

/// Drops [paths] into the folder [target]: moved, or copied ([copy], by
/// default when Ctrl is held); into the trash when [target] is it. Throws a
/// FileSystemException for what can't be done.
Future<void> dropFiles(List<String> paths, String target, {bool? copy}) async {
  copy ??= HardwareKeyboard.instance.isControlPressed;
  for (final String path in paths) {
    if (p.equals(path, target) || p.isWithin(path, target)) {
      throw FileSystemException("Can't put a folder inside itself", path);
    }
    if (p.equals(p.dirname(path), target) && !copy) continue;
    if (p.equals(target, FileOps.trashFiles)) {
      await FileOps.trash(path);
    } else if (copy) {
      await FileOps.copy(path, target);
    } else {
      await FileOps.move(path, target);
    }
  }
}
