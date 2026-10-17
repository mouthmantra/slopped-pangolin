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

import 'package:dahlia_apps/kit/system.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

/// A sidebar location.
class Place {
  const Place(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

/// File system operations used by Files.
abstract final class FileOps {
  static String get trashDir => p.join(xdg.dataHome.path, "Trash");
  static String get trashFiles => p.join(trashDir, "files");
  static String get trashInfo => p.join(trashDir, "info");

  /// XDG user directories (see xdg-user-dirs), falling back to the English
  /// defaults.
  static List<Place> userPlaces() {
    final String home = SystemUtils.home;
    final Map<String, String> dirs = {};
    final File config = File(p.join(xdg.configHome.path, "user-dirs.dirs"));
    if (config.existsSync()) {
      for (final String line in config.readAsLinesSync()) {
        final Match? m = RegExp(r'^XDG_(\w+)_DIR="(.*)"$').firstMatch(line.trim());
        if (m != null) dirs[m.group(1)!] = m.group(2)!.replaceAll(r"$HOME", home);
      }
    }
    String dir(String key, String fallback) => dirs[key] ?? p.join(home, fallback);

    return [
      Place("Home", Icons.home_rounded, home),
      Place("Desktop", Icons.desktop_windows_rounded, dir("DESKTOP", "Desktop")),
      Place("Documents", Icons.description_rounded, dir("DOCUMENTS", "Documents")),
      Place("Downloads", Icons.download_rounded, dir("DOWNLOAD", "Downloads")),
      Place("Music", Icons.music_note_rounded, dir("MUSIC", "Music")),
      Place("Pictures", Icons.image_rounded, dir("PICTURES", "Pictures")),
      Place("Videos", Icons.movie_rounded, dir("VIDEOS", "Videos")),
    ].where((place) => place.path == home || Directory(place.path).existsSync()).toList();
  }

  /// Mounted removable/extra volumes.
  static List<Place> volumes() {
    final List<Place> volumes = [];
    try {
      for (final String line in File("/proc/mounts").readAsLinesSync()) {
        final List<String> parts = line.split(" ");
        if (parts.length < 2) continue;
        final String mount = parts[1].replaceAll(r"\040", " ");
        if (mount.startsWith("/media/") ||
            mount.startsWith("/run/media/") ||
            mount.startsWith("/mnt/")) {
          volumes.add(Place(p.basename(mount), Icons.usb_rounded, mount));
        }
      }
    } on FileSystemException {
      // Not Linux, nothing to show.
    }
    return volumes;
  }

  /// A name not yet used inside [dir], e.g. "file (2).txt".
  static String uniqueName(String dir, String name) {
    if (FileSystemEntity.typeSync(p.join(dir, name)) == FileSystemEntityType.notFound) {
      return name;
    }
    final String ext = p.extension(name);
    final String base = p.basenameWithoutExtension(name);
    for (int i = 2;; i++) {
      final String candidate = "$base ($i)$ext";
      if (FileSystemEntity.typeSync(p.join(dir, candidate)) == FileSystemEntityType.notFound) {
        return candidate;
      }
    }
  }

  static Future<void> copy(String source, String destinationDir) async {
    final String target = p.join(destinationDir, uniqueName(destinationDir, p.basename(source)));
    await _copyRecursive(source, target);
  }

  static Future<void> _copyRecursive(String source, String target) async {
    final FileSystemEntityType type = await FileSystemEntity.type(source, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(target).create(recursive: true);
        await for (final FileSystemEntity child in Directory(source).list(followLinks: false)) {
          await _copyRecursive(child.path, p.join(target, p.basename(child.path)));
        }
      case FileSystemEntityType.link:
        await Link(target).create(await Link(source).target());
      default:
        await File(source).copy(target);
    }
  }

  static Future<void> move(String source, String destinationDir) async {
    if (p.dirname(source) == destinationDir) return;
    final String target = p.join(destinationDir, uniqueName(destinationDir, p.basename(source)));
    try {
      await FileSystemEntity.isDirectory(source)
          ? await Directory(source).rename(target)
          : await File(source).rename(target);
    } on FileSystemException {
      // Probably a cross-device move: copy, then delete.
      await _copyRecursive(source, target);
      await _delete(source);
    }
  }

  static Future<void> _delete(String path) async {
    final FileSystemEntityType type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  static Future<void> deletePermanently(String path) => _delete(path);

  static Future<void> rename(String path, String newName) async {
    final String target = p.join(p.dirname(path), newName);
    if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
      throw FileSystemException("A file with that name already exists", target);
    }
    await (FileSystemEntity.isDirectorySync(path)
        ? Directory(path).rename(target)
        : File(path).rename(target));
  }

  /// Moves [path] to the trash following the FreeDesktop.org Trash spec.
  static Future<void> trash(String path) async {
    await Directory(trashFiles).create(recursive: true);
    await Directory(trashInfo).create(recursive: true);
    final String name = uniqueName(trashFiles, p.basename(path));
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, "0");
    final String date = "${now.year}-${two(now.month)}-${two(now.day)}T"
        "${two(now.hour)}:${two(now.minute)}:${two(now.second)}";
    await File(p.join(trashInfo, "$name.trashinfo")).writeAsString(
      "[Trash Info]\nPath=${Uri.encodeFull(p.absolute(path))}\nDeletionDate=$date\n",
    );
    try {
      await move(path, trashFiles);
      // move() may have picked a different unique name; keep them in sync.
      if (!File(p.join(trashFiles, name)).existsSync() &&
          !Directory(p.join(trashFiles, name)).existsSync()) {
        await File(p.join(trashInfo, "$name.trashinfo")).delete();
      }
    } catch (_) {
      await File(p.join(trashInfo, "$name.trashinfo")).delete();
      rethrow;
    }
  }

  /// Original location of a trashed item, from its .trashinfo file.
  static String? trashedOriginalPath(String trashedPath) {
    final File info = File(p.join(trashInfo, "${p.basename(trashedPath)}.trashinfo"));
    if (!info.existsSync()) return null;
    for (final String line in info.readAsLinesSync()) {
      if (line.startsWith("Path=")) return Uri.decodeFull(line.substring(5));
    }
    return null;
  }

  static Future<void> restore(String trashedPath) async {
    final String? original = trashedOriginalPath(trashedPath);
    if (original == null) throw FileSystemException("Unknown original location", trashedPath);
    final String dir = p.dirname(original);
    await Directory(dir).create(recursive: true);
    final String target = p.join(dir, uniqueName(dir, p.basename(original)));
    await (FileSystemEntity.isDirectorySync(trashedPath)
        ? Directory(trashedPath).rename(target)
        : File(trashedPath).rename(target));
    await File(p.join(trashInfo, "${p.basename(trashedPath)}.trashinfo")).delete();
  }

  static Future<void> emptyTrash() async {
    for (final String dir in [trashFiles, trashInfo]) {
      final Directory d = Directory(dir);
      if (!d.existsSync()) continue;
      await for (final FileSystemEntity e in d.list()) {
        await _delete(e.path);
      }
    }
  }

  static Future<int> directorySize(String path) async {
    int total = 0;
    try {
      await for (final FileSystemEntity e in Directory(path).list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } on FileSystemException {
      // Partially unreadable: report what we could count.
    }
    return total;
  }

  /// Available bytes on the file system containing [path].
  static Future<int?> freeSpace(String path) async {
    // POSIX output (GNU and busybox): "Filesystem 1024-blocks Used Available
    // Capacity Mounted-on", in kibibytes.
    final String? out = await SystemUtils.run("df", ["-P", "-k", path]);
    if (out == null) return null;
    final List<String> lines = out.trim().split("\n");
    if (lines.length < 2) return null;
    final List<String> fields = lines.last.trim().split(RegExp(r"\s+"));
    if (fields.length < 4) return null;
    final int? available = int.tryParse(fields[fields.length - 3]);
    return available == null ? null : available * 1024;
  }

  static String? mimeType(String path) => lookupMimeType(path);
}

enum FileKind { folder, image, video, audio, archive, document, code, text, executable, other }

FileKind kindOf(String path, {bool isDirectory = false}) {
  if (isDirectory) return FileKind.folder;
  final String ext = p.extension(path).toLowerCase();
  const Set<String> code = {
    ".dart", ".c", ".h", ".cc", ".cpp", ".py", ".js", ".ts", ".rs", ".go", ".java", ".kt", //
    ".sh", ".zig", ".rb", ".php", ".html", ".css", ".json", ".yaml", ".yml", ".xml", ".toml",
  };
  const Set<String> archive = {".zip", ".tar", ".gz", ".xz", ".bz2", ".zst", ".7z", ".rar", ".deb", ".rpm"};
  const Set<String> document = {".pdf", ".doc", ".docx", ".odt", ".xls", ".xlsx", ".ods", ".ppt", ".pptx", ".odp"};
  if (code.contains(ext)) return FileKind.code;
  if (archive.contains(ext)) return FileKind.archive;
  if (document.contains(ext)) return FileKind.document;
  final String? mime = lookupMimeType(path);
  if (mime != null) {
    if (mime.startsWith("image/")) return FileKind.image;
    if (mime.startsWith("video/")) return FileKind.video;
    if (mime.startsWith("audio/")) return FileKind.audio;
    if (mime.startsWith("text/")) return FileKind.text;
  }
  if (const {".txt", ".md", ".log", ".conf", ".ini", ".desktop", ".csv"}.contains(ext) || ext.isEmpty) {
    return FileKind.text;
  }
  return FileKind.other;
}

(IconData, Color) iconFor(FileKind kind, ColorScheme scheme) => switch (kind) {
      FileKind.folder => (Icons.folder_rounded, scheme.primary),
      FileKind.image => (Icons.image_outlined, Colors.purple),
      FileKind.video => (Icons.movie_outlined, Colors.red),
      FileKind.audio => (Icons.music_note_outlined, Colors.orange),
      FileKind.archive => (Icons.inventory_2_outlined, Colors.brown),
      FileKind.document => (Icons.picture_as_pdf_outlined, Colors.redAccent),
      FileKind.code => (Icons.code_rounded, Colors.blue),
      FileKind.text => (Icons.description_outlined, scheme.onSurface.withValues(alpha: 0.7)),
      FileKind.executable => (Icons.terminal_rounded, Colors.green),
      FileKind.other => (Icons.insert_drive_file_outlined, scheme.onSurface.withValues(alpha: 0.6)),
    };

String permissionString(FileStat stat) {
  final int mode = stat.mode;
  const String chars = "rwxrwxrwx";
  final StringBuffer out = StringBuffer(stat.type == FileSystemEntityType.directory ? "d" : "-");
  for (int i = 0; i < 9; i++) {
    out.write(mode & (1 << (8 - i)) != 0 ? chars[i] : "-");
  }
  return out.toString();
}
