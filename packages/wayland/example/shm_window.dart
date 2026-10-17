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

// A tiny xdg_toplevel client that fills its window with a solid color using a
// wl_shm buffer. Useful to exercise a window manager without a toolkit.
//
//   dart run example/shm_window.dart [title] [0xAARRGGBB]

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:wayland/wayland.dart';

Future<void> main(List<String> args) async {
  final String title = args.isNotEmpty ? args[0] : 'shm window';
  final int color = args.length > 1 ? int.parse(args[1]) : 0xff3f51b5;

  final WaylandConnection connection = await WaylandConnection.connect();
  final GlobalRegistry globals = await GlobalRegistry.create(connection);

  final WlCompositor compositor = globals.bind(WlCompositor.interface)!;
  final WlShm shm = globals.bind(WlShm.interface)!;
  final XdgWmBase wmBase = globals.bind(XdgWmBase.interface)!;
  wmBase.onPing = wmBase.pong;

  final WlSurface surface = compositor.createSurface();
  final XdgSurface xdgSurface = wmBase.getXdgSurface(surface);
  final XdgToplevel toplevel = xdgSurface.getToplevel()
    ..setTitle(title)
    ..setAppId(Platform.environment['SHM_APP_ID'] ?? 'io.dahliaos.shm_window');
  // --ssd: ask for a title bar drawn by the window manager.
  if (args.contains('--ssd')) {
    globals
        .bind(ZxdgDecorationManagerV1.interface)
        ?.getToplevelDecoration(toplevel)
        .setMode(ZxdgToplevelDecorationV1Mode.serverSide);
  }

  int width = 480;
  int height = 320;
  final Completer<void> closed = Completer();

  toplevel.onConfigure = (w, h, states) {
    if (w > 0) width = w;
    if (h > 0) height = h;
  };
  toplevel.onClose = () {
    if (!closed.isCompleted) closed.complete();
  };

  xdgSurface.onConfigure = (serial) {
    xdgSurface.ackConfigure(serial);
    final WlBuffer buffer = _createBuffer(shm, width, height, color);
    surface
      ..attach(buffer, 0, 0)
      ..damageBuffer(0, 0, width, height)
      ..commit();
  };

  surface.commit();
  stdout.writeln('shm_window: mapped "$title"');

  await Future.any([closed.future, connection.done]);
  await connection.close();
}

WlBuffer _createBuffer(WlShm shm, int width, int height, int argb) {
  final int stride = width * 4;
  final int size = stride * height;

  final Directory dir = Directory(
    Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path,
  );
  final File file = File('${dir.path}/dart-wl-shm-$pid-${DateTime.now().microsecondsSinceEpoch}');
  final Uint32List pixels = Uint32List(width * height)..fillRange(0, width * height, argb);
  file.writeAsBytesSync(pixels.buffer.asUint8List(), flush: true);

  final RandomAccessFile handle = file.openSync(mode: FileMode.append);
  file.deleteSync(); // the fd keeps the memory alive until the compositor closes it

  final WlShmPool pool = shm.createPool(handle, size);
  final WlBuffer buffer = pool.createBuffer(0, width, height, stride, WlShmFormat.argb8888);
  pool.destroy();
  return buffer;
}
