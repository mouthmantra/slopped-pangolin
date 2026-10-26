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

import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Color themes of the Terminal, by settings key.
final Map<String, (String, TerminalTheme)> terminalThemes = {
  "dahlia": ("dahliaOS", _theme(
    background: 0xFF161616, foreground: 0xFFE6E6E6, cursor: 0xFFFF5722,
    ansi: [
      0xFF1E1E1E, 0xFFE5534B, 0xFF57AB5A, 0xFFC69026,
      0xFF539BF5, 0xFFB083F0, 0xFF39C5CF, 0xFFD0D0D0,
      0xFF636E7B, 0xFFFF938A, 0xFF6BC46D, 0xFFDAAA3F,
      0xFF6CB6FF, 0xFFDCBDFB, 0xFF56D4DD, 0xFFFFFFFF,
    ],
  )),
  "light": ("Light", _theme(
    background: 0xFFFAFAFA, foreground: 0xFF242424, cursor: 0xFFFF5722,
    ansi: [
      0xFF242424, 0xFFC4262E, 0xFF2E8540, 0xFF946300,
      0xFF1F6FEB, 0xFF8250DF, 0xFF1B7C83, 0xFFC9C9C9,
      0xFF6E7781, 0xFFD73A49, 0xFF3FA052, 0xFFB08800,
      0xFF388BFD, 0xFFA475F9, 0xFF3192AA, 0xFFFFFFFF,
    ],
  )),
  "one_dark": ("One Dark", _theme(
    background: 0xFF282C34, foreground: 0xFFABB2BF, cursor: 0xFF528BFF,
    ansi: [
      0xFF282C34, 0xFFE06C75, 0xFF98C379, 0xFFE5C07B,
      0xFF61AFEF, 0xFFC678DD, 0xFF56B6C2, 0xFFABB2BF,
      0xFF5C6370, 0xFFE06C75, 0xFF98C379, 0xFFE5C07B,
      0xFF61AFEF, 0xFFC678DD, 0xFF56B6C2, 0xFFFFFFFF,
    ],
  )),
  "dracula": ("Dracula", _theme(
    background: 0xFF282A36, foreground: 0xFFF8F8F2, cursor: 0xFFF8F8F2,
    ansi: [
      0xFF21222C, 0xFFFF5555, 0xFF50FA7B, 0xFFF1FA8C,
      0xFFBD93F9, 0xFFFF79C6, 0xFF8BE9FD, 0xFFF8F8F2,
      0xFF6272A4, 0xFFFF6E6E, 0xFF69FF94, 0xFFFFFFA5,
      0xFFD6ACFF, 0xFFFF92DF, 0xFFA4FFFF, 0xFFFFFFFF,
    ],
  )),
  "nord": ("Nord", _theme(
    background: 0xFF2E3440, foreground: 0xFFD8DEE9, cursor: 0xFF88C0D0,
    ansi: [
      0xFF3B4252, 0xFFBF616A, 0xFFA3BE8C, 0xFFEBCB8B,
      0xFF81A1C1, 0xFFB48EAD, 0xFF88C0D0, 0xFFE5E9F0,
      0xFF4C566A, 0xFFBF616A, 0xFFA3BE8C, 0xFFEBCB8B,
      0xFF81A1C1, 0xFFB48EAD, 0xFF8FBCBB, 0xFFECEFF4,
    ],
  )),
  "gruvbox": ("Gruvbox Dark", _theme(
    background: 0xFF282828, foreground: 0xFFEBDBB2, cursor: 0xFFEBDBB2,
    ansi: [
      0xFF282828, 0xFFCC241D, 0xFF98971A, 0xFFD79921,
      0xFF458588, 0xFFB16286, 0xFF689D6A, 0xFFA89984,
      0xFF928374, 0xFFFB4934, 0xFFB8BB26, 0xFFFABD2F,
      0xFF83A598, 0xFFD3869B, 0xFF8EC07C, 0xFFEBDBB2,
    ],
  )),
  "solarized": ("Solarized Dark", _theme(
    background: 0xFF002B36, foreground: 0xFF839496, cursor: 0xFF93A1A1,
    ansi: [
      0xFF073642, 0xFFDC322F, 0xFF859900, 0xFFB58900,
      0xFF268BD2, 0xFFD33682, 0xFF2AA198, 0xFFEEE8D5,
      0xFF002B36, 0xFFCB4B16, 0xFF586E75, 0xFF657B83,
      0xFF839496, 0xFF6C71C4, 0xFF93A1A1, 0xFFFDF6E3,
    ],
  )),
};

TerminalTheme terminalThemeFor(String key) =>
    (terminalThemes[key] ?? terminalThemes["dahlia"]!).$2;

final Map<(TerminalTheme, Color), TerminalTheme> _accented = {};

/// [theme] with its cursor and selection in the desktop's [accent] color,
/// as the rest of Pangolin. The same object for the same colors: xterm
/// drops its text layout cache when the theme changes.
TerminalTheme terminalThemeWithAccent(TerminalTheme theme, Color accent) {
  final Color cursor = accent.withValues(alpha: 1);
  // Wallpaper accents change: keep a few.
  if (_accented.length > 32) _accented.clear();
  return _accented[(theme, cursor)] ??= TerminalTheme(
    cursor: cursor,
    selection: cursor.withValues(alpha: 0.4),
    foreground: theme.foreground,
    background: theme.background,
    black: theme.black,
    red: theme.red,
    green: theme.green,
    yellow: theme.yellow,
    blue: theme.blue,
    magenta: theme.magenta,
    cyan: theme.cyan,
    white: theme.white,
    brightBlack: theme.brightBlack,
    brightRed: theme.brightRed,
    brightGreen: theme.brightGreen,
    brightYellow: theme.brightYellow,
    brightBlue: theme.brightBlue,
    brightMagenta: theme.brightMagenta,
    brightCyan: theme.brightCyan,
    brightWhite: theme.brightWhite,
    searchHitBackground: theme.searchHitBackground,
    searchHitBackgroundCurrent: theme.searchHitBackgroundCurrent,
    searchHitForeground: theme.searchHitForeground,
  );
}

TerminalTheme _theme({
  required int background,
  required int foreground,
  required int cursor,
  required List<int> ansi,
}) {
  final List<Color> c = ansi.map(Color.new).toList();
  return TerminalTheme(
    cursor: Color(cursor),
    selection: Color(cursor).withValues(alpha: 0.4),
    foreground: Color(foreground),
    background: Color(background),
    black: c[0],
    red: c[1],
    green: c[2],
    yellow: c[3],
    blue: c[4],
    magenta: c[5],
    cyan: c[6],
    white: c[7],
    brightBlack: c[8],
    brightRed: c[9],
    brightGreen: c[10],
    brightYellow: c[11],
    brightBlue: c[12],
    brightMagenta: c[13],
    brightCyan: c[14],
    brightWhite: c[15],
    searchHitBackground: const Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: const Color(0xFF31FF26),
    searchHitForeground: const Color(0xFF000000),
  );
}
