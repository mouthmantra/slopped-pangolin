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

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Colour tags of files, kept where other file managers (Dolphin, Baloo)
/// keep them: the `user.xdg.tags` extended attribute, a comma separated
/// list of names. The Files tag column shows the first tag that is one of
/// [colors].
abstract final class FileTags {
  static const String _attribute = "user.xdg.tags";

  /// The tags Files offers, in menu order.
  static const Map<String, Color> colors = {
    "Red": Color(0xFFE53935),
    "Orange": Color(0xFFFB8C00),
    "Yellow": Color(0xFFFDD835),
    "Green": Color(0xFF43A047),
    "Blue": Color(0xFF1E88E5),
    "Purple": Color(0xFF8E24AA),
    "Gray": Color(0xFF8D8D8D),
  };

  static final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();
  static final int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int)
      _lgetxattr = _libc.lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Size),
          int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int)>("lgetxattr");
  static final int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int, int)
      _lsetxattr = _libc.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Int32),
          int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int, int)>("lsetxattr");
  static final int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>) _lremovexattr =
      _libc.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>),
          int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>)>("lremovexattr");
  static final ffi.Pointer<ffi.Uint8> Function(int) _malloc =
      _libc.lookupFunction<ffi.Pointer<ffi.Uint8> Function(ffi.Size), ffi.Pointer<ffi.Uint8> Function(int)>("malloc");
  static final void Function(ffi.Pointer<ffi.Uint8>) _free =
      _libc.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Uint8>), void Function(ffi.Pointer<ffi.Uint8>)>("free");

  static ffi.Pointer<ffi.Uint8> _cString(String s) {
    final Uint8List bytes = utf8.encode(s);
    final ffi.Pointer<ffi.Uint8> out = _malloc(bytes.length + 1);
    out.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return out;
  }

  /// The tags of [path] (none when the file system keeps no attributes).
  static List<String> read(String path) {
    final ffi.Pointer<ffi.Uint8> file = _cString(path);
    final ffi.Pointer<ffi.Uint8> name = _cString(_attribute);
    final ffi.Pointer<ffi.Uint8> value = _malloc(1024);
    try {
      final int n = _lgetxattr(file, name, value, 1024);
      if (n <= 0) return const [];
      return utf8
          .decode(value.asTypedList(n), allowMalformed: true)
          .split(",")
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } finally {
      _free(file);
      _free(name);
      _free(value);
    }
  }

  /// Replaces the tags of [path]; false when the file system refused.
  static bool write(String path, List<String> tags) {
    final ffi.Pointer<ffi.Uint8> file = _cString(path);
    final ffi.Pointer<ffi.Uint8> name = _cString(_attribute);
    try {
      if (tags.isEmpty) {
        // Nothing to remove counts as done.
        return _lremovexattr(file, name) == 0 || read(path).isEmpty;
      }
      final Uint8List bytes = utf8.encode(tags.join(","));
      final ffi.Pointer<ffi.Uint8> value = _malloc(bytes.length);
      try {
        value.asTypedList(bytes.length).setAll(0, bytes);
        return _lsetxattr(file, name, value, bytes.length, 0) == 0;
      } finally {
        _free(value);
      }
    } finally {
      _free(file);
      _free(name);
    }
  }

  /// The colour shown for [tags]: the first colour tag, grey for others.
  static Color? colorOf(List<String> tags) {
    if (tags.isEmpty) return null;
    for (final String tag in tags) {
      for (final MapEntry<String, Color> c in colors.entries) {
        if (c.key.toLowerCase() == tag.toLowerCase()) return c.value;
      }
    }
    return colors["Gray"];
  }

  /// [tags] with the colour tag set to [color] (null removes it); other
  /// tags stay.
  static List<String> withColor(List<String> tags, String? color) {
    final Set<String> colorNames = colors.keys.map((c) => c.toLowerCase()).toSet();
    return [
      if (color != null) color,
      ...tags.where((t) => !colorNames.contains(t.toLowerCase())),
    ];
  }
}
