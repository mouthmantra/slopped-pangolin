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
import 'dart:convert';

import 'package:dahlia_apps/apps/files/file_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// Papirus icons for files and folders, the folders in Papirus' beige
/// ("palebrown"), in Files only (roadmap 5.1; the rest of Pangolin keeps its
/// own icons). The icons are in assets/papirus (tool/papirus_icons.py), at
/// 24 and 64 px; index.json maps every icon name to its file.
abstract final class Papirus {
  static Map<String, Map<String, Map<String, String>>>? _index;
  static Map<String, String> _special = const {};
  static Future<void>? _loading;
  static final Map<String, ScalableImage> _images = {};
  static final Map<String, Future<ScalableImage?>> _pending = {};

  /// Reads the index once; icons fall back to glyphs until it's there.
  static Future<void> load() => _loading ??= () async {
        final Map<String, Object?> json =
            jsonDecode(await rootBundle.loadString("assets/papirus/index.json")) as Map<String, Object?>;
        // The XDG folders (user-dirs.dirs), read once.
        _special = {
          for (final Place place in FileOps.userPlaces())
            if (_specialIcon(place.label) != null) place.path: _specialIcon(place.label)!,
        };
        _index = {
          for (final MapEntry<String, Object?> context in json.entries)
            context.key: {
              for (final MapEntry<String, Object?> size in (context.value! as Map<String, Object?>).entries)
                size.key: (size.value! as Map<String, Object?>).cast<String, String>(),
            },
        };
      }();

  static bool get ready => _index != null;

  /// Folder names with a Papirus folder of their own.
  static const Map<String, String> _namedFolders = {
    "templates": "templates",
    "public": "public",
    ".git": "git",
    "dropbox": "dropbox",
    "onedrive": "onedrive",
    "nextcloud": "nextcloud",
    "google drive": "google-drive",
    "googledrive": "google-drive",
    "mega": "mega",
    "projects": "projects",
    "code": "code",
    "src": "code",
    "development": "development",
    "games": "games",
    "steam": "steam",
    "backup": "backup",
    "backups": "backup",
    "books": "books",
    "notes": "notes",
    "android": "android",
    "applications": "applications",
    "github": "github",
    "gitlab": "gitlab",
    "mail": "mail",
    "screenshots": "photo",
    "photos": "photo",
    "camera": "photo",
    "recent": "recent",
    "wine": "wine",
    ".wine": "wine",
  };

  static String? _specialIcon(String label) => switch (label) {
        "Home" => "user-palebrown-home",
        "Desktop" => "user-palebrown-desktop",
        "Documents" => "folder-palebrown-documents",
        "Downloads" => "folder-palebrown-download",
        "Music" => "folder-palebrown-music",
        "Pictures" => "folder-palebrown-pictures",
        "Videos" => "folder-palebrown-video",
        _ => null,
      };

  static List<String> _folderNames(String path) {
    final String? special = _special[p.normalize(path)];
    if (special != null) return [special, "folder-palebrown"];
    final String? named = _namedFolders[p.basename(path).toLowerCase()];
    return [if (named != null) "folder-palebrown-$named", "folder-palebrown"];
  }

  static List<String> _fileNames(String path, FileKind kind) {
    final String? mime = lookupMimeType(path);
    return [
      if (mime != null) mime.replaceAll("/", "-"),
      if (mime != null && mime.startsWith("text/") && kind == FileKind.code) "text-x-script",
      ...switch (kind) {
        FileKind.archive => const ["package-x-generic"],
        FileKind.document => const ["x-office-document"],
        FileKind.executable => const ["application-x-executable"],
        FileKind.code => const ["text-x-script", "text-x-generic"],
        FileKind.text => const ["text-x-generic"],
        _ => const <String>[],
      },
      if (mime != null) "${mime.split("/").first}-x-generic",
      "unknown",
    ];
  }

  /// The icon's asset for [path] drawn at [size] logical pixels, or null
  /// until [load] is done.
  static String? assetFor(String path, FileKind kind, double size) {
    final Map<String, Map<String, Map<String, String>>>? index = _index;
    if (index == null) return null;
    final String dir = size <= 32 ? "24" : "64";
    final bool folder = kind == FileKind.folder;
    final String context = folder ? "places" : "mimetypes";
    final Map<String, String> icons = index[context]?[dir] ?? const {};
    for (final String name in folder ? _folderNames(path) : _fileNames(path, kind)) {
      final String? file = icons[name];
      if (file != null) return "assets/papirus/$dir/$context/$file.svg";
    }
    return null;
  }

  /// The parsed icon, once loaded (null the first time; [whenLoaded]
  /// completes when it is).
  static ScalableImage? image(String asset) => _images[asset];

  static Future<ScalableImage?> whenLoaded(String asset) => _pending[asset] ??= () async {
        try {
          final ScalableImage si = ScalableImage.fromSvgString(await rootBundle.loadString(asset), warnF: (_) {});
          return _images[asset] = si;
        } on Object {
          return null;
        }
      }();
}

/// A Papirus icon, drawn once its SVG is parsed (blank for that moment).
class PapirusIcon extends StatefulWidget {
  const PapirusIcon({required this.asset, required this.size, super.key});

  final String asset;
  final double size;

  @override
  State<PapirusIcon> createState() => _PapirusIconState();
}

class _PapirusIconState extends State<PapirusIcon> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(PapirusIcon old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _ensure();
  }

  void _ensure() {
    if (Papirus.image(widget.asset) != null) return;
    final String asset = widget.asset;
    unawaited(Papirus.whenLoaded(asset).then((_) {
      if (mounted && widget.asset == asset) setState(() {});
    }));
  }

  @override
  Widget build(BuildContext context) {
    final ScalableImage? si = Papirus.image(widget.asset);
    return SizedBox.square(
      dimension: widget.size,
      child: si == null ? null : ScalableImageWidget(si: si, fit: BoxFit.contain),
    );
  }
}
