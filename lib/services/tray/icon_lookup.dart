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

import 'package:logging/logging.dart';
import 'package:pangolin/services/icon.dart';
import 'package:path/path.dart' as p;

/// Finds the files of tray icons given by name: an absolute path, a file in
/// the item's IconThemePath (flat, or laid out like an icon theme), or the
/// icon theme.
class TrayIconLookup {
  TrayIconLookup._();

  static const Set<String> _extensions = {".png", ".svg", ".svgz", ".xpm"};

  /// Theme path directories: icon name to its files by size (0: unknown,
  /// -1: scalable).
  static final Map<String, _ThemePathIndex> _indexes = {};
  static final Map<String, String?> _cache = {};

  /// A result of [resolve] for these arguments, if there is one already.
  static String? cached(String name, String? themePath, int size) =>
      _cache[_key(name, themePath, size)];

  static bool isCached(String name, String? themePath, int size) =>
      _cache.containsKey(_key(name, themePath, size));

  /// Forgets what was found (the icon theme changed).
  static void clear() {
    _cache.clear();
    _indexes.clear();
  }

  static String _key(String name, String? themePath, int size) =>
      "$name\n${themePath ?? ""}\n$size";

  static bool _listening = false;

  static Future<String?> resolve(
    String name,
    String? themePath,
    int size,
  ) async {
    if (!_listening) {
      try {
        // Another icon theme: everything found in the old one is wrong.
        IconService.current.addListener(clear);
        _listening = true;
      } catch (_) {}
    }
    final String key = _key(name, themePath, size);
    if (_cache.containsKey(key)) return _cache[key];
    final String? result = await _resolve(name, themePath, size);
    // Misses are not kept: the app may write the file next.
    if (result != null) _cache[key] = result;
    return result;
  }

  static Future<String?> _resolve(
    String requested,
    String? themePath,
    int size,
  ) async {
    String name = requested;
    if (name.startsWith("file://")) {
      final Uri? uri = Uri.tryParse(name);
      if (uri == null) return null;
      name = uri.toFilePath();
    }
    if (name.startsWith("/")) {
      return await File(name).exists() ? name : null;
    }

    // "name.png" asks for the same icon as "name".
    final String bare = _extensions.contains(p.extension(name).toLowerCase())
        ? p.basenameWithoutExtension(name)
        : name;

    if (themePath != null && themePath.isNotEmpty) {
      final String? found = await _fromThemePath(themePath, bare, size);
      if (found != null) return found;
    }

    try {
      return IconService.current.lookup(bare, size: size);
    } catch (_) {
      // The icon service isn't running.
      return null;
    }
  }

  static Future<String?> _fromThemePath(
    String themePath,
    String name,
    int size,
  ) async {
    _ThemePathIndex? index = _indexes[themePath];
    if (index == null || (!index.has(name) && index.stale)) {
      index = await _ThemePathIndex.read(themePath);
      _indexes[themePath] = index;
    }
    return index.best(name, size);
  }
}

class _ThemePathIndex {
  final Map<String, Map<String, int>> files;
  final DateTime readAt;

  _ThemePathIndex(this.files) : readAt = DateTime.now();

  bool has(String name) => files.containsKey(name);

  /// Apps write new icon files into their theme path and then signal the
  /// new name: read it again on a miss, though not more than once a second.
  bool get stale =>
      DateTime.now().difference(readAt) > const Duration(seconds: 1);

  String? best(String name, int size) {
    final Map<String, int>? candidates = files[name];
    if (candidates == null || candidates.isEmpty) return null;
    String? best;
    double bestScore = double.infinity;
    for (final MapEntry(key: path, value: fileSize) in candidates.entries) {
      final double score = switch (fileSize) {
        -1 => 0.5, // scalable: always the right size
        0 => 32, // a flat directory: probably made for a tray
        _ => (fileSize - size).abs().toDouble() +
            // Rather scaled down than up.
            (fileSize < size ? 0.25 : 0),
      };
      if (score < bestScore) {
        best = path;
        bestScore = score;
      }
    }
    return best;
  }

  static final RegExp _sizeDir = RegExp(r"^(\d+)x(\d+)(?:@(\d+))?$");

  /// Files looked at in one theme path at most: some apps give a whole
  /// system icons directory.
  static const int _maxFiles = 5000;

  static Future<_ThemePathIndex> read(String root) async {
    final Map<String, Map<String, int>> files = {};
    int seen = 0;

    // Deep enough for <root>/<theme>/<size>/<context>/<icon>.
    Future<void> walk(Directory dir, List<String> parents) async {
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      for (final FileSystemEntity entity in entries) {
        if (seen >= _maxFiles) return;
        if (entity is Directory) {
          if (parents.length < 3) {
            await walk(entity, [...parents, p.basename(entity.path)]);
          }
          continue;
        }
        seen++;
        final String ext = p.extension(entity.path).toLowerCase();
        if (!TrayIconLookup._extensions.contains(ext)) continue;
        int size = 0;
        for (final String part in parents) {
          if (part == "scalable") size = -1;
          final RegExpMatch? match = _sizeDir.firstMatch(part);
          if (match != null) {
            size =
                int.parse(match.group(1)!) * int.parse(match.group(3) ?? "1");
          }
        }
        if (ext == ".svg" || ext == ".svgz") size = -1;
        (files[p.basenameWithoutExtension(entity.path)] ??= {})[entity.path] =
            size;
      }
    }

    try {
      final Directory dir = Directory(root);
      if (await dir.exists()) await walk(dir, const []);
    } catch (e) {
      Logger("TrayIconLookup").fine("Couldn't read $root: $e");
    }
    return _ThemePathIndex(files);
  }
}
