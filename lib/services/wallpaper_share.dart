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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:display_config/display_config.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

/// Shares the desktop's wallpaper with the login screen, which shows the
/// wallpaper of the user it's about to log in ([SharedUserFiles]).
abstract final class WallpaperShare {
  static final Logger _logger = Logger("WallpaperShare");

  static const String sharedName = "wallpaper";

  /// Wallpapers bigger than this are shared as a re-encoded copy.
  static const int _maxBytes = 48 * 1024 * 1024;

  static ImageResource? _shared;

  static File get _marker {
    final Map<String, String> env = Platform.environment;
    final String cache = env["XDG_CACHE_HOME"]?.isNotEmpty == true
        ? env["XDG_CACHE_HOME"]!
        : "${env["HOME"] ?? "."}/.cache";
    return File("$cache/pangolin/shared-wallpaper");
  }

  /// In a session: shares the wallpaper now and whenever it changes.
  static void follow() {
    final CustomizationService service = CustomizationService.current;
    void update() => unawaited(_share(service.wallpaper));
    service.addListener(update);
    // Once startup is over.
    Timer(const Duration(seconds: 6), update);
  }

  /// The wallpaper [user] shared, null when there is none.
  static ImageProvider? of(String user) {
    final File? file = SharedUserFiles.published(user, sharedName);
    return file == null ? null : FileImage(file);
  }

  static Future<void> _share(ImageResource wallpaper) async {
    if (wallpaper == _shared) return;
    _shared = wallpaper;
    final File marker = _marker;
    try {
      if (SharedUserFiles.published(SharedUserFiles.currentUser, sharedName) !=
              null &&
          marker.readAsStringSync() == wallpaper.toString()) {
        return;
      }
    } on FileSystemException {
      // Shared below.
    }
    if (!Directory(SharedUserFiles.directory).existsSync()) return;
    try {
      final Uint8List? bytes = await _bytes(wallpaper);
      if (bytes == null) return;
      if (await SharedUserFiles.publish(sharedName, bytes)) {
        marker.parent.createSync(recursive: true);
        marker.writeAsStringSync(wallpaper.toString());
      }
    } on Object catch (e) {
      _logger.info("Couldn't share the wallpaper with the login screen: $e");
    }
  }

  /// The image file as it is, when there is one; a PNG of it otherwise.
  static Future<Uint8List?> _bytes(ImageResource wallpaper) async {
    switch (wallpaper.subtype) {
      case ImageResourceType.file:
        final File file = File(wallpaper.resolve());
        if (await file.length() <= _maxBytes) return file.readAsBytes();
      case ImageResourceType.dahlia:
        final ByteData data = await rootBundle.load(wallpaper.resolve());
        if (data.lengthInBytes <= _maxBytes) {
          return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        }
      case ImageResourceType.network:
        break;
    }
    final ImageProvider? provider = BlurredWallpaper.providerFor(wallpaper);
    if (provider == null) return null;
    final ui.Image image = await BlurredWallpaper.load(
      ResizeImage(provider, width: 3840, policy: ResizeImagePolicy.fit),
    );
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png?.buffer.asUint8List();
  }
}
