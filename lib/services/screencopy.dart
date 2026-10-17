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
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:wayland/wayland.dart';

/// Captures what the screen shows, through wlr-screencopy (no external
/// program needed).
abstract final class Screencopy {
  static final Logger _logger = Logger("Screencopy");

  // wl_shm formats Flutter can decode: [AX]RGB8888 are B, G, R, A in
  // memory (bgra8888), [AX]BGR8888 are R, G, B, A (rgba8888).
  static const int _argb8888 = 0;
  static const int _xrgb8888 = 1;
  static const int _abgr8888 = 0x34324241;
  static const int _xbgr8888 = 0x34324258;
  static const Set<int> _formats = {_argb8888, _xrgb8888, _abgr8888, _xbgr8888};

  /// The screen, or [region] of it (logical coordinates of the output), at
  /// full resolution. Null when the compositor can't be captured.
  static Future<ui.Image?> capture({ui.Rect? region}) async {
    final WaylandConnection connection = await WaylandConnection.connect();
    try {
      final GlobalRegistry globals = await GlobalRegistry.create(connection);
      final ZwlrScreencopyManagerV1? manager =
          globals.bind(ZwlrScreencopyManagerV1.interface, maxVersion: 3);
      final WlShm? shm = globals.bind(WlShm.interface);
      final WlOutput? output = globals.bind(WlOutput.interface, maxVersion: 4);
      if (manager == null || shm == null || output == null) {
        _logger.warning("The compositor doesn't support screencopy");
        return null;
      }

      final ZwlrScreencopyFrameV1 frame = region == null
          ? manager.captureOutput(0, output)
          : manager.captureOutputRegion(
              0,
              output,
              region.left.round(),
              region.top.round(),
              region.width.round(),
              region.height.round(),
            );

      (int, int, int, int)? format;
      bool described = false;
      bool flipped = false;
      final Completer<bool> done = Completer();
      frame
        ..onBuffer = (fmt, width, height, stride) {
          if (!_formats.contains(fmt)) return;
          format ??= (fmt, width, height, stride);
        }
        ..onBufferDone = (() => described = true)
        ..onFlags = ((flags) => flipped = flags & 1 != 0)
        ..onReady = (_, __, ___) {
          if (!done.isCompleted) done.complete(true);
        }
        ..onFailed = () {
          if (!done.isCompleted) done.complete(false);
        };
      // Version 3 lists every format then sends buffer_done; older versions
      // send a single buffer event.
      for (int i = 0; i < 20 && !described; i++) {
        await connection.roundtrip();
        if (frame.version < 3 && format != null) break;
      }
      final (int, int, int, int)? chosen = format;
      if (chosen == null) {
        _logger.warning("No shared memory format to capture into");
        return null;
      }
      final (int fmt, int width, int height, int stride) = chosen;

      final String dir =
          Platform.environment["XDG_RUNTIME_DIR"] ?? Directory.systemTemp.path;
      final File file = File("$dir/pangolin-screencopy-$pid");
      final int size = stride * height;
      await file.writeAsBytes(Uint8List(size), flush: true);
      final RandomAccessFile fd = await file.open(mode: FileMode.append);
      final WlShmPool pool = shm.createPool(fd, size);
      final WlBuffer buffer = pool.createBuffer(0, width, height, stride, fmt);
      frame.copy(buffer);
      connection.flush();
      final bool ok = await done.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      buffer.destroy();
      pool.destroy();
      frame.destroy();
      await fd.close();
      final Uint8List pixels = await file.readAsBytes();
      await file.delete();
      if (!ok) return null;

      // X888 has no alpha: make it opaque.
      if (fmt == _xrgb8888 || fmt == _xbgr8888) {
        for (int i = 3; i < pixels.length; i += 4) {
          pixels[i] = 255;
        }
      }
      final Completer<ui.Image> image = Completer();
      ui.decodeImageFromPixels(
        pixels,
        width,
        height,
        fmt == _argb8888 || fmt == _xrgb8888
            ? ui.PixelFormat.bgra8888
            : ui.PixelFormat.rgba8888,
        image.complete,
        rowBytes: stride,
      );
      final ui.Image result = await image.future;
      if (!flipped) return result;
      return await _flip(result);
    } on Object catch (e) {
      _logger.warning("Screen capture failed: $e");
      return null;
    } finally {
      await connection.close();
    }
  }

  static Future<ui.Image> _flip(ui.Image image) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(0, image.height.toDouble())
      ..scale(1, -1)
      ..drawImage(image, ui.Offset.zero, ui.Paint());
    final ui.Image flipped =
        await recorder.endRecording().toImage(image.width, image.height);
    image.dispose();
    return flipped;
  }
}
