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
import 'package:display_config/display_config.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

/// Keeps the image river shows from its first frame up to date (river's
/// splash, see river/Splash.zig and PANGOLIN_SPLASH in pangolin-session):
/// the next session starts on the wallpaper instead of a black screen.
abstract final class SplashCache {
  static final Logger _logger = Logger("SplashCache");

  /// As wide as the widest screen, in its real pixels (GTK only knows
  /// integer scales: at 1.5 it would say 5120 for a 3840 wide screen): with
  /// PANGOLIN_WALLPAPER river shows it as the wallpaper for good.
  static Future<int> _width() async {
    int widest = 0;
    try {
      final DisplayConfigurator? displays = await DisplayConfigurator.connect()
          .timeout(const Duration(seconds: 2));
      if (displays != null) {
        for (final OutputHeadState head in displays.heads) {
          final OutputModeState? mode = head.currentMode;
          if (!head.enabled || mode == null) continue;
          // Turned by 90 or 270 degrees (odd transforms).
          final int width = head.transform.isOdd ? mode.height : mode.width;
          if (width > widest) widest = width;
        }
        await displays.close();
      }
    } on Object catch (e) {
      _logger.info("Couldn't read the screens' sizes: $e");
    }
    return widest >= 1280 ? widest : 2560;
  }

  static ImageResource? _written;

  static File get file {
    final Map<String, String> env = Platform.environment;
    // Where river reads it (pangolin-session, pangolin-greeter).
    final String? splash = env["PANGOLIN_SPLASH"];
    if (splash != null && splash.isNotEmpty) return File(splash);
    final String cache = env["XDG_CACHE_HOME"]?.isNotEmpty == true
        ? env["XDG_CACHE_HOME"]!
        : "${env["HOME"] ?? "."}/.cache";
    return File("$cache/pangolin/splash.bgra");
  }

  static void follow() {
    final CustomizationService service = CustomizationService.current;
    void update() => unawaited(_update(service.wallpaper));
    service.addListener(update);
    if (PangolinSession.riverWallpaper) {
      // A screen changed size: the wallpaper follows (once things settle).
      Timer? settle;
      WidgetsBinding.instance.addObserver(
        _MetricsObserver(() {
          settle?.cancel();
          settle = Timer(const Duration(seconds: 1), () {
            _written = null;
            update();
          });
        }),
      );
      // river shows it as the wallpaper: right away (skipped when the file
      // is already this wallpaper at this size).
      update();
    } else {
      // Once startup is over: decoding the wallpaper again isn't urgent.
      Timer(const Duration(seconds: 5), update);
    }
  }

  static Future<void> _update(ImageResource wallpaper) async {
    if (wallpaper == _written) return;
    _written = wallpaper;
    final ImageProvider? provider = BlurredWallpaper.providerFor(wallpaper);
    if (provider == null) {
      // Not an image: the desktop surface draws it, river shows nothing.
      if (PangolinSession.riverWallpaper) {
        try {
          file.deleteSync();
        } on FileSystemException {
          // Already gone.
        }
      }
      return;
    }
    final int width = await _width();
    await write(provider, "$wallpaper@$width", width: width);
  }

  /// Saves [provider] as the splash image at the width of the monitors (the
  /// login screen, for the user it shows).
  static Future<void> writeForScreens(
      ImageProvider provider, String key) async {
    final int width = await _width();
    await write(provider, "$key@$width", width: width);
  }

  /// Saves [provider] as the splash image, unless it was already saved under
  /// [key] (by an earlier session). The login screen uses this with the
  /// wallpaper of the user who logged in last.
  static Future<void> write(
    ImageProvider provider,
    String key, {
    int width = 2560,
  }) async {
    final File source = File("${file.path}.source");
    try {
      if (file.existsSync() && source.readAsStringSync() == key) return;
    } on FileSystemException {
      // Saved below.
    }
    try {
      final ui.Image image = await BlurredWallpaper.load(
        ResizeImage(provider, width: width, policy: ResizeImagePolicy.fit),
      );
      final ByteData? rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int imageWidth = image.width;
      final int imageHeight = image.height;
      image.dispose();
      if (rgba == null) return;
      final String path = file.path;
      final Uint8List pixels = rgba.buffer.asUint8List();
      await Isolate.run(
        () => _write(path, imageWidth, imageHeight, pixels),
      );
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

class _MetricsObserver with WidgetsBindingObserver {
  _MetricsObserver(this.onChange);

  final VoidCallback onChange;

  @override
  void didChangeMetrics() => onChange();
}
