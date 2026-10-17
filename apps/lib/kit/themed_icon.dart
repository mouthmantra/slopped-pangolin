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
import 'dart:io';

import 'package:dahlia_apps/kit/system.dart';
import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

/// Finds icons of the icon theme (an app's Icon= name), after the Icon
/// Theme Specification without its full index: the theme of the desktop,
/// what it inherits, hicolor, then /usr/share/pixmaps.
abstract final class IconLookup {
  static final Map<String, String?> _found = {};
  static List<String>? _themes;

  static List<String> get _roots => [
        p.join(xdg.dataHome.path, "icons"),
        p.join(SystemUtils.home, ".icons"),
        for (final Directory d in xdg.dataDirs) p.join(d.path, "icons"),
      ];

  /// The desktop's icon theme and the ones it inherits.
  static Future<List<String>> _loadThemes() async {
    if (_themes != null) return _themes!;
    String? theme = (await SystemUtils.run(
      "gsettings",
      ["get", "org.gnome.desktop.interface", "icon-theme"],
      timeout: const Duration(seconds: 2),
    ))
        ?.trim()
        .replaceAll("'", "");
    if (theme == null || theme.isEmpty) theme = "Adwaita";
    final List<String> themes = [];
    void add(String name) {
      if (themes.contains(name) || themes.length > 8) return;
      themes.add(name);
      for (final String root in _roots) {
        final File index = File(p.join(root, name, "index.theme"));
        if (!index.existsSync()) continue;
        try {
          final String? inherits = index
              .readAsLinesSync()
              .firstWhere((l) => l.startsWith("Inherits="), orElse: () => "")
              .split("=")
              .skip(1)
              .firstOrNull;
          for (final String parent in (inherits ?? "").split(",")) {
            if (parent.trim().isNotEmpty) add(parent.trim());
          }
        } on FileSystemException {
          continue;
        }
        break;
      }
    }

    add(theme);
    if (!themes.contains("hicolor")) themes.add("hicolor");
    return _themes = themes;
  }

  static const List<String> _sizes = [
    "scalable/apps",
    "256x256/apps",
    "128x128/apps",
    "96x96/apps",
    "64x64/apps",
    "48x48/apps",
    "apps/scalable",
    "apps/256",
    "apps/128",
    "apps/64",
    "apps/48",
    "512x512/apps",
    "32x32/apps",
    "24x24/apps",
  ];

  /// The file of icon [name], or null.
  static Future<String?> find(String name) async {
    if (_found.containsKey(name)) return _found[name];
    if (p.isAbsolute(name)) {
      return _found[name] = File(name).existsSync() ? name : null;
    }
    final List<String> themes = await _loadThemes();
    for (final String theme in themes) {
      for (final String root in _roots) {
        final String base = p.join(root, theme);
        if (!Directory(base).existsSync()) continue;
        for (final String size in _sizes) {
          for (final String ext in const [".svg", ".png"]) {
            final String path = p.join(base, size, "$name$ext");
            if (File(path).existsSync()) return _found[name] = path;
          }
        }
      }
    }
    for (final String ext in const [".svg", ".png", ".xpm"]) {
      final String path = "/usr/share/pixmaps/$name$ext";
      if (File(path).existsSync()) return _found[name] = path;
    }
    return _found[name] = null;
  }
}

/// An icon of the icon theme ([IconLookup]), with [fallback] meanwhile and
/// when there is none.
class ThemedIcon extends StatefulWidget {
  const ThemedIcon({
    required this.name,
    this.size = 32,
    this.fallback = Icons.apps_rounded,
    super.key,
  });

  final String? name;
  final double size;
  final IconData fallback;

  @override
  State<ThemedIcon> createState() => _ThemedIconState();
}

class _ThemedIconState extends State<ThemedIcon> {
  String? _path;
  ScalableImage? _svg;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ThemedIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _path = null;
      _svg = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final String? name = widget.name;
    if (name == null || name.isEmpty) return;
    final String? path = await IconLookup.find(name);
    if (path == null || !mounted || widget.name != name) return;
    ScalableImage? svg;
    if (path.endsWith(".svg")) {
      try {
        List<int> bytes = await File(path).readAsBytes();
        if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
          bytes = gzip.decode(bytes);
        }
        svg = ScalableImage.fromSvgString(utf8.decode(bytes), warnF: (_) {});
      } on Object {
        return;
      }
    } else if (path.endsWith(".xpm")) {
      return;
    }
    if (!mounted || widget.name != name) return;
    setState(() {
      _path = path;
      _svg = svg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    final Widget child;
    if (_svg != null) {
      child = ScalableImageWidget(si: _svg!, fit: BoxFit.contain);
    } else if (_path != null) {
      child = Image.file(
        File(_path!),
        width: size,
        height: size,
        cacheWidth: (size * 2).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, __) => Icon(widget.fallback, size: size * 0.8),
      );
    } else {
      child = Icon(
        widget.fallback,
        size: size * 0.8,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      );
    }
    return SizedBox.square(dimension: size, child: Center(child: child));
  }
}
