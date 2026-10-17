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

/// xkbcommon keysyms used by Pangolin's key bindings
/// (see xkbcommon/xkbcommon-keysyms.h).
abstract final class Keysym {
  static const int tab = 0xff09;
  static const int returnKey = 0xff0d;
  static const int escape = 0xff1b;
  static const int delete = 0xffff;
  static const int left = 0xff51;
  static const int up = 0xff52;
  static const int right = 0xff53;
  static const int down = 0xff54;
  static const int pageUp = 0xff55;
  static const int pageDown = 0xff56;
  static const int print = 0xff61;
  static const int f4 = 0xffc1;
  static const int superL = 0xffeb;
  static const int superR = 0xffec;
  static const int space = 0x0020;

  /// Lowercase latin letter, e.g. `letter('e')`.
  static int letter(String char) => char.toLowerCase().codeUnitAt(0);

  static const int audioLowerVolume = 0x1008ff11;
  static const int audioMute = 0x1008ff12;
  static const int audioRaiseVolume = 0x1008ff13;
  static const int monBrightnessUp = 0x1008ff02;
  static const int monBrightnessDown = 0x1008ff03;
}

/// `river_seat_v1.modifiers`
abstract final class Mod {
  static const int none = 0;
  static const int shift = 1;
  static const int ctrl = 4;
  static const int alt = 8;
  static const int logo = 64;
}

/// Linux input event codes for pointer buttons (linux/input-event-codes.h).
abstract final class Button {
  static const int left = 0x110;
  static const int right = 0x111;
  static const int middle = 0x112;
}
