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
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

/// Keeps the image river shows from its first frame up to date (river's
/// splash, see river/Splash.zig and PANGOLIN_SPLASH in pangolin-session):
/// the next session starts on the wallpaper instead of a black screen.
abstract final class SplashCache {
  static final Logger _logger = Logger("SplashCache");

  /// Wide enough to look sharp while it is shown (about a second).
  static const int _width = 2560;

  static ImageResource? _written;

  static File get file {
    final Map<String, String> env = Platform.environment;
    final String cache = env["XDG_CACHE_HOME"]?.isNotEmpty == true
        ? env["XDG_CACHE_HOME"]!
        : "${env["HOME"] ?? "."}/.cache";
    return File("$cache/pangolin/splash.bgra");
  }

  static void follow() {
    final CustomizationService service = CustomizationService.current;
    void update() => unawaited(_update(service.wallpaper));
    service.addListener(update);
    // Once startup is over: decoding the wallpaper again isn't urgent.
    Timer(const Duration(seconds: 5), update);
  }

  static Future<void> _update(ImageResource wallpaper) async {
    if (wallpaper == _written) return;
    _written = wallpaper;
    final ImageProvider? provider = BlurredWallpaper.providerFor(wallpaper);
    if (provider == null) return;
    await write(provider, wallpaper.toString());
  }

  /// Saves [provider] as the splash image, unless it was already saved under
  /// [key] (by an earlier session). The login screen uses this with the
  /// wallpaper of the user who logged in last.
  static Future<void> write(ImageProvider provider, String key) async {
    final File source = File("${file.path}.source");
    try {
      if (file.existsSync() && source.readAsStringSync() == key) return;
    } on FileSystemException {
      // Saved below.
    }
    try {
      final ui.Image image = await BlurredWallpaper.load(
        ResizeImage(provider, width: _width, policy: ResizeImagePolicy.fit),
      );
      final ByteData? rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int width = image.width;
      final int height = image.height;
      image.dispose();
      if (rgba == null) return;
      final String path = file.path;
      final Uint8List pixels = rgba.buffer.asUint8List();
      await Isolate.run(() => _write(path, width, height, pixels));
      await source.writeAsString(key);
    } on Object catch (e) {
      _logger.info("Couldn't save the splash image: $e");
    }
  }

  static void _write(String path, int width, int height, Uint8List rgba) {
    final Uint8List data = Uint8List(16 + rgba.length);
    data.setRange(0, 4, "PSPL".codeUnits);
    final ByteData header = ByteData.sublistView(data, 0, 16)
      ..setUint32(4, width, Endian.little)
      ..setUint32(8, height, Endian.little)
      ..setUint32(12, 0, Endian.little);
    assert(header.lengthInBytes == 16);
    // RGBA to BGRA, opaque.
    for (int i = 0; i < rgba.length; i += 4) {
      data[16 + i] = rgba[i + 2];
      data[16 + i + 1] = rgba[i + 1];
      data[16 + i + 2] = rgba[i];
      data[16 + i + 3] = 255;
    }
    final File target = File(path);
    target.parent.createSync(recursive: true);
    final File temp = File("$path.tmp");
    temp.writeAsBytesSync(data, flush: true);
    temp.renameSync(path);
  }
}
