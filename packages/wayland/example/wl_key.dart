// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

// Sends keyboard input through zwp_virtual_keyboard_v1 (for automated tests
// of compositors and shells).
//
// usage: wl_key [type TEXT] [key NAME] [combo MOD+...+NAME] [sleep MS] ...
//   names: a-z, 0-9, space, enter, escape, backspace, tab
//   mods: super, ctrl, alt, shift

import 'dart:io';

import 'package:wayland/wayland.dart';

const Map<String, int> _keys = {
  'escape': 1, 'backspace': 14, 'tab': 15, 'enter': 28, 'space': 57,
  '1': 2, '2': 3, '3': 4, '4': 5, '5': 6, '6': 7, '7': 8, '8': 9, '9': 10,
  '0': 11, '-': 12, '=': 13,
  'q': 16, 'w': 17, 'e': 18, 'r': 19, 't': 20, 'y': 21, 'u': 22, 'i': 23,
  'o': 24, 'p': 25, 'a': 30, 's': 31, 'd': 32, 'f': 33, 'g': 34, 'h': 35,
  'j': 36, 'k': 37, 'l': 38, 'z': 44, 'x': 45, 'c': 46, 'v': 47, 'b': 48,
  'n': 49, 'm': 50, '.': 52, '/': 53,
};

// Real modifier masks of the evdev keymaps (Shift, Lock, Control, Mod1,
// Mod2, Mod3, Mod4, Mod5).
const Map<String, int> _mods = {
  'shift': 1 << 0,
  'ctrl': 1 << 2,
  'alt': 1 << 3,
  'super': 1 << 6,
};

Future<void> main(List<String> args) async {
  final WaylandConnection connection = await WaylandConnection.connect();
  final GlobalRegistry globals = await GlobalRegistry.create(connection);
  final ZwpVirtualKeyboardManagerV1? manager =
      globals.bind(ZwpVirtualKeyboardManagerV1.interface);
  final WlSeat? seat = globals.bind(WlSeat.interface, maxVersion: 7);
  if (manager == null || seat == null) {
    stderr.writeln('compositor lacks zwp_virtual_keyboard_manager_v1');
    exit(1);
  }

  // A keymap file (WL_KEY_KEYMAP, e.g. for seats without a keyboard), or
  // the seat's own.
  RandomAccessFile? keymapFd;
  int keymapSize = 0;
  final String? keymapPath = Platform.environment['WL_KEY_KEYMAP'];
  if (keymapPath != null) {
    final File file = File(keymapPath);
    keymapSize = file.lengthSync();
    keymapFd = file.openSync();
  } else {
    final WlKeyboard keyboard = seat.getKeyboard();
    keyboard.onKeymap = (format, fd, size) {
      keymapFd = fd;
      keymapSize = size;
    };
    for (int i = 0; i < 20 && keymapFd == null; i++) {
      await connection.roundtrip();
    }
  }
  if (keymapFd == null) {
    stderr.writeln('no keymap');
    exit(1);
  }
  final ZwpVirtualKeyboardV1 vk = manager.createVirtualKeyboard(seat);
  vk.keymap(1, keymapFd!, keymapSize);
  await connection.roundtrip();

  int time() => DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  Future<void> settle() async {
    connection.flush();
    await connection.roundtrip();
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }

  Future<void> press(int code, {int mods = 0}) async {
    if (mods != 0) vk.modifiers(mods, 0, 0, 0);
    vk.key(time(), code, 1);
    await settle();
    vk.key(time(), code, 0);
    if (mods != 0) vk.modifiers(0, 0, 0, 0);
    await settle();
  }

  int i = 0;
  String next() => args[i++];
  while (i < args.length) {
    final String command = next();
    switch (command) {
      case 'type':
        for (final String ch in next().split('')) {
          final String lower = ch.toLowerCase();
          final int? code = ch == ' ' ? _keys['space'] : _keys[lower];
          if (code == null) continue;
          await press(code, mods: ch != lower ? _mods['shift']! : 0);
        }
      case 'key':
        await press(_keys[next()]!);
      case 'combo':
        final List<String> parts = next().split('+');
        int mods = 0;
        for (final String m in parts.take(parts.length - 1)) {
          mods |= _mods[m]!;
        }
        await press(_keys[parts.last]!, mods: mods);
      case 'sleep':
        await Future<void>.delayed(Duration(milliseconds: int.parse(next())));
      default:
        stderr.writeln('unknown command $command');
        exit(2);
    }
  }
  vk.destroy();
  await connection.close();
}
