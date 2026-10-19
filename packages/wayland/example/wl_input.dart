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

// Scripted pointer and keyboard input through wlr-virtual-pointer and
// zwp-virtual-keyboard, used by Pangolin's session tests:
//
//   dart run example/wl_input.dart move 640 360 click sleep 200 \
//       drag 100 100 400 300 click right key ctrl+t type hello
//
// Commands: move X Y | glide X Y | click [left|right|middle] | down [btn] | up [btn] |
//           drag X1 Y1 X2 Y2 | scroll DY | sleep MS |
//           key [ctrl+][shift+][alt+][super+]NAME | type TEXT

import 'dart:async';
import 'dart:io';

import 'package:wayland/wayland.dart';

const Map<String, int> _buttons = {
  'left': 0x110,
  'right': 0x111,
  'middle': 0x112,
};

// Linux evdev key codes.
const Map<String, int> _keys = {
  'esc': 1, 'escape': 1, 'minus': 12, '-': 12, 'equal': 13, '=': 13,
  'backspace': 14, 'tab': 15, 'enter': 28, 'return': 28, 'space': 57, ' ': 57,
  'comma': 51, ',': 51, 'period': 52, '.': 52, 'slash': 53, '/': 53,
  'home': 102, 'up': 103, 'pageup': 104, 'left': 105, 'right': 106,
  'end': 107, 'down': 108, 'pagedown': 109, 'insert': 110, 'delete': 111,
  'f1': 59, 'f2': 60, 'f3': 61, 'f4': 62, 'f5': 63, 'f6': 64, 'f7': 65,
  'f8': 66, 'f9': 67, 'f10': 68, 'f11': 87, 'f12': 88,
  '1': 2, '2': 3, '3': 4, '4': 5, '5': 6, '6': 7, '7': 8, '8': 9, '9': 10, '0': 11,
  'q': 16, 'w': 17, 'e': 18, 'r': 19, 't': 20, 'y': 21, 'u': 22, 'i': 23,
  'o': 24, 'p': 25, 'a': 30, 's': 31, 'd': 32, 'f': 33, 'g': 34, 'h': 35,
  'j': 36, 'k': 37, 'l': 38, 'z': 44, 'x': 45, 'c': 46, 'v': 47, 'b': 48,
  'n': 49, 'm': 50,
};

// Modifier key code and xkb modifier mask (pc+us keymap).
const Map<String, (int, int)> _modifiers = {
  'shift': (42, 1),
  'ctrl': (29, 4),
  'alt': (56, 8),
  'super': (125, 64),
};

// libxkbcommon resolves the includes on the receiving side.
const String _keymap = """
xkb_keymap {
  xkb_keycodes { include "evdev+aliases(qwerty)" };
  xkb_types { include "complete" };
  xkb_compat { include "complete" };
  xkb_symbols { include "pc+us+inet(evdev)" };
};
""";

Future<void> main(List<String> args) async {
  final WaylandConnection connection = await WaylandConnection.connect();
  final GlobalRegistry globals = await GlobalRegistry.create(connection);

  final ZwlrVirtualPointerManagerV1? manager =
      globals.bind(ZwlrVirtualPointerManagerV1.interface);
  if (manager == null) {
    stderr.writeln('compositor lacks zwlr_virtual_pointer_manager_v1');
    exit(1);
  }

  // Output size, for absolute motion.
  int width = 1280;
  int height = 720;
  final WlOutput? output = globals.bind(WlOutput.interface, maxVersion: 2);
  output?.onMode = (flags, w, h, refresh) {
    if (flags & WlOutputMode.current != 0) {
      width = w;
      height = h;
    }
  };
  await connection.roundtrip();

  final ZwlrVirtualPointerV1 pointer = manager.createVirtualPointer(null);
  int time() => DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  Future<void> settle() async {
    connection.flush();
    await connection.roundtrip();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  // The keyboard is created on first use: not every compositor has it.
  ZwpVirtualKeyboardV1? keyboard;
  Future<ZwpVirtualKeyboardV1> ensureKeyboard() async {
    if (keyboard != null) return keyboard!;
    final ZwpVirtualKeyboardManagerV1? keyboards =
        globals.bind(ZwpVirtualKeyboardManagerV1.interface);
    final WlSeat? seat = globals.bind(WlSeat.interface);
    if (keyboards == null || seat == null) {
      stderr.writeln('compositor lacks zwp_virtual_keyboard_manager_v1');
      exit(1);
    }
    final File file = File('${Directory.systemTemp.path}/wl_input-keymap-$pid');
    file.writeAsStringSync('$_keymap\u0000', flush: true);
    final RandomAccessFile handle = file.openSync();
    file.deleteSync();
    keyboard = keyboards.createVirtualKeyboard(seat)
      ..keymap(1 /* xkb_v1 */, handle, _keymap.length + 1);
    // The seat only gains its keyboard capability now: give clients time to
    // bind a wl_keyboard, or the first keys go nowhere.
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return keyboard!;
  }

  Future<void> move(int x, int y) async {
    pointer
      ..motionAbsolute(time(), x, y, width, height)
      ..frame();
    await settle();
  }

  Future<void> button(int code, bool pressed) async {
    pointer
      ..button(time(), code, pressed ? 1 : 0)
      ..frame();
    await settle();
  }

  Future<void> key(String combo) async {
    final ZwpVirtualKeyboardV1 kb = await ensureKeyboard();
    final List<String> parts = combo.toLowerCase().split('+');
    final String name = parts.removeLast();
    final int? code = _keys[name.isEmpty ? '+' : name];
    if (code == null) {
      stderr.writeln('unknown key $name');
      exit(2);
    }
    int mask = 0;
    for (final String mod in parts) {
      final (int, int)? m = _modifiers[mod];
      if (m == null) {
        stderr.writeln('unknown modifier $mod');
        exit(2);
      }
      kb.key(time(), m.$1, 1);
      mask |= m.$2;
      kb.modifiers(mask, 0, 0, 0);
    }
    kb
      ..key(time(), code, 1)
      ..key(time(), code, 0);
    for (final String mod in parts.reversed) {
      final (int, int) m = _modifiers[mod]!;
      kb.key(time(), m.$1, 0);
      mask &= ~m.$2;
      kb.modifiers(mask, 0, 0, 0);
    }
    await settle();
  }

  int i = 0;
  String next() => args[i++];
  while (i < args.length) {
    final String command = next();
    switch (command) {
      case 'move':
        await move(int.parse(next()), int.parse(next()));
      case 'glide':
        // Like a real mouse: no waiting for the compositor (use sleep).
        pointer
          ..motionAbsolute(time(), int.parse(next()), int.parse(next()), width, height)
          ..frame();
        connection.flush();
      case 'click':
        final int code = i < args.length && _buttons.containsKey(args[i])
            ? _buttons[next()]!
            : _buttons['left']!;
        await button(code, true);
        await button(code, false);
      case 'down':
      case 'up':
        final int code = i < args.length && _buttons.containsKey(args[i])
            ? _buttons[next()]!
            : _buttons['left']!;
        await button(code, command == 'down');
      case 'drag':
        final int x1 = int.parse(next());
        final int y1 = int.parse(next());
        final int x2 = int.parse(next());
        final int y2 = int.parse(next());
        await move(x1, y1);
        await button(_buttons['left']!, true);
        const int steps = 12;
        for (int s = 1; s <= steps; s++) {
          await move(x1 + (x2 - x1) * s ~/ steps, y1 + (y2 - y1) * s ~/ steps);
        }
        await button(_buttons['left']!, false);
      case 'scroll':
        pointer
          ..axis(time(), WlPointerAxis.verticalScroll, double.parse(next()))
          ..frame();
        await settle();
      case 'key':
        await key(next());
      case 'type':
        for (final String char in next().split('')) {
          final String lower = char.toLowerCase();
          await key(char != lower ? 'shift+$lower' : char);
        }
      case 'sleep':
        await Future<void>.delayed(Duration(milliseconds: int.parse(next())));
      default:
        stderr.writeln('unknown command $command');
        exit(2);
    }
  }

  if (keyboard != null) {
    // Removing the keyboard right away makes clients drop keys they haven't
    // processed yet.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    keyboard!.destroy();
  }
  pointer.destroy();
  await connection.close();
}
