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

// Minimal floating window manager for river, kept as a readable example of
// the manage/render state machine. Pangolin's real window manager lives in
// lib/services/wm in the shell.

import 'dart:io';

import 'package:wayland/wayland.dart';

class Window {
  Window(this.proxy) : node = proxy.getNode();

  final RiverWindowV1 proxy;
  final RiverNodeV1 node;
  bool placed = false;
  int width = 0;
  int height = 0;
  String? title;
}

Future<void> main() async {
  final WaylandConnection connection = await WaylandConnection.connect();
  final GlobalRegistry globals = await GlobalRegistry.create(connection);

  final RiverWindowManagerV1? wm = globals.bind(RiverWindowManagerV1.interface);
  if (wm == null) {
    stderr.writeln('river_window_manager_v1 is not available');
    exit(1);
  }
  globals.bind(RiverLayerShellV1.interface);

  final List<Window> windows = [];
  final List<Window> fresh = [];
  final List<RiverSeatV1> seats = [];
  int cascade = 0;

  wm.onUnavailable = () {
    stderr.writeln('another window manager is already running');
    exit(1);
  };
  wm.onWindow = (proxy) {
    final Window window = Window(proxy);
    windows.add(window);
    fresh.add(window);
    proxy.onTitle = (title) => window.title = title;
    proxy.onDimensions = (w, h) {
      window.width = w;
      window.height = h;
    };
    proxy.onClosed = () {
      windows.remove(window);
      fresh.remove(window);
      window.node.destroy();
      proxy.destroy();
    };
  };
  wm.onSeat = (seat) {
    seats.add(seat);
    seat.onWindowInteraction = (proxy) {
      for (final Window w in windows) {
        if (w.proxy == proxy) {
          w.node.placeTop();
          seat.focusWindow(proxy);
        }
      }
    };
  };

  wm.onManageStart = () {
    for (final Window w in fresh) {
      w.proxy
        ..proposeDimensions(0, 0)
        ..setBorders(RiverWindowV1Edges.top | RiverWindowV1Edges.bottom | RiverWindowV1Edges.left | RiverWindowV1Edges.right, 2, 0xffffffff, 0x80000000, 0x00000000, 0xffffffff);
      for (final RiverSeatV1 seat in seats) {
        seat.focusWindow(w.proxy);
      }
    }
    fresh.clear();
    wm.manageFinish();
  };

  wm.onRenderStart = () {
    for (final Window w in windows) {
      if (!w.placed && w.width > 0) {
        w.node
          ..setPosition(60 + cascade * 40, 60 + cascade * 40)
          ..placeTop();
        cascade = (cascade + 1) % 8;
        w.placed = true;
        stdout.writeln('placed "${w.title}" ${w.width}x${w.height}');
      }
    }
    wm.renderFinish();
  };

  stdout.writeln('river_floating_wm: managing (river_window_manager_v1 v${wm.version})');
  await connection.done;
}
