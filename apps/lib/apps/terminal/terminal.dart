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

import 'dart:convert';
import 'dart:io';

import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:dahlia_apps/apps/terminal/themes.dart';
import 'package:dahlia_shared/dahlia_shared.dart' show PreferencesService;
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:xterm/xterm.dart';
import 'package:yaru_window/yaru_window.dart';

final DahliaAppSpec terminalApp = DahliaAppSpec(
  name: "terminal",
  title: "Terminal",
  builder: (context, args) => TerminalPage(args: args),
);

/// One shell running in a pseudo terminal.
class _Session {
  _Session({
    required int scrollback,
    String? workingDirectory,
    List<String>? command,
  }) : terminal = Terminal(maxLines: scrollback) {
    final String shell = Platform.environment["SHELL"] ??
        (File("/bin/bash").existsSync() ? "/bin/bash" : "/bin/sh");
    final List<String> argv = command ?? [shell, "-l"];

    pty = Pty.start(
      argv.first,
      arguments: argv.sublist(1),
      workingDirectory: workingDirectory ?? SystemUtils.home,
      // Keep the whole session environment so programs started from the
      // terminal can reach the compositor, D-Bus, etc.
      environment: {
        ...Platform.environment,
        "TERM": "xterm-256color",
        "COLORTERM": "truecolor",
        "TERM_PROGRAM": "dahliaOS Terminal",
      },
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
    pty.exitCode.then((code) {
      exited = true;
      terminal.write("\r\n[Process exited with code $code]\r\n");
      onExit?.call();
    });

    terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));
    terminal.onResize = (w, h, pw, ph) => pty.resize(h, w);
    terminal.onTitleChange = (t) {
      title = t;
      onTitleChange?.call();
    };
  }

  final Terminal terminal;
  final TerminalController controller = TerminalController();
  final FocusNode focusNode = FocusNode(debugLabel: "terminal");
  late final Pty pty;
  String title = "Terminal";
  bool exited = false;
  VoidCallback? onTitleChange;
  VoidCallback? onExit;

  void dispose() {
    if (!exited) pty.kill(ProcessSignal.sighup);
    controller.dispose();
    focusNode.dispose();
  }
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({required this.args, super.key});

  /// `-e <command...>` runs a command instead of the login shell,
  /// `--working-directory <dir>` starts in a given directory.
  final List<String> args;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final List<_Session> _sessions = [];
  int _current = 0;

  /// Ctrl+= / Ctrl+- on top of the font size from Settings.
  double _zoomDelta = 0;

  PreferencesService get _prefs => PreferencesService.current;
  T _setting<T extends Object>(SessionSetting<T> setting) =>
      _prefs.get<T>(setting.key) ?? setting.defaultValue;

  TerminalTheme get _theme =>
      terminalThemeFor(_setting(SessionSetting.terminalTheme));
  double get _fontSize =>
      (_setting(SessionSetting.terminalFontSize) + _zoomDelta).clamp(8, 32);
  double get _opacity => ZenitBlur.active
      ? _setting(SessionSetting.terminalOpacity).clamp(0.5, 1.0)
      : 1;
  TerminalCursorType get _cursorType =>
      switch (_setting(SessionSetting.terminalCursorShape)) {
        "underline" => TerminalCursorType.underline,
        "bar" => TerminalCursorType.verticalBar,
        _ => TerminalCursorType.block,
      };

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    String? cwd;
    List<String>? command;
    final List<String> args = widget.args;
    for (int i = 0; i < args.length; i++) {
      if (args[i] == "--working-directory" && i + 1 < args.length) {
        cwd = args[++i];
      } else if (args[i] == "-e" && i + 1 < args.length) {
        command = args.sublist(i + 1);
        break;
      }
    }
    _newTab(workingDirectory: cwd, command: command);
    _prefs.addListener(_onSettingsChanged);
    ZenitBlur.state.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onSettingsChanged);
    ZenitBlur.state.removeListener(_onSettingsChanged);
    for (final _Session s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  void _newTab({String? workingDirectory, List<String>? command}) {
    final _Session session = _Session(
      scrollback:
          _setting(SessionSetting.terminalScrollback).clamp(100, 1000000),
      workingDirectory: workingDirectory,
      command: command,
    );
    session.onTitleChange = () => setState(() {});
    session.onExit = () {
      if (!mounted) return;
      // Close the tab when its shell exits (unless it ran a one-off command).
      if (command == null) _closeTab(_sessions.indexOf(session));
    };
    setState(() {
      _sessions.add(session);
      _current = _sessions.length - 1;
    });
    _focusCurrent();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _sessions.length) return;
    setState(() => _current = index);
    _focusCurrent();
  }

  void _moveTab(int from, int to) {
    if (from == to || to < 0 || to >= _sessions.length) return;
    final _Session current = _session;
    setState(() {
      _sessions.insert(to, _sessions.removeAt(from));
      _current = _sessions.indexOf(current);
    });
  }

  /// Keyboard input goes to the visible terminal.
  void _focusCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sessions.isNotEmpty) _session.focusNode.requestFocus();
    });
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _sessions.length) return;
    if (_sessions.length == 1) {
      YaruWindow.of(context).close();
      return;
    }
    final _Session session = _sessions[index];
    setState(() {
      _sessions.removeAt(index);
      if (index < _current || _current == _sessions.length) _current--;
    });
    _focusCurrent();
    // Its view is unmounted at the end of this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => session.dispose());
  }

  _Session get _session => _sessions[_current];

  Future<void> _copy() async {
    final selection = _session.controller.selection;
    if (selection == null) return;
    await Clipboard.setData(
      ClipboardData(text: _session.terminal.buffer.getText(selection)),
    );
    _session.controller.clearSelection();
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    if (text != null) _session.terminal.paste(text);
  }

  void _zoom(double delta) => setState(() => _zoomDelta += delta);

  @override
  Widget build(BuildContext context) {
    if (_sessions.isEmpty) return const SizedBox();
    final ThemeData theme = Theme.of(context);

    // The window (frosted tab bar included) follows the terminal theme's
    // brightness, keeping the user's accent color.
    final Brightness brightness =
        ThemeData.estimateBrightnessForColor(_theme.background);
    return Theme(
      data: theme.brightness == brightness
          ? theme
          : createZenitTheme(
              brightness: brightness,
              primaryColor: theme.colorScheme.primary,
              fontFamily: theme.textTheme.bodyMedium?.fontFamily,
              monospaceFontFamily: ZenitFonts.monospaceOf(context),
            ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT,
              control: true, shift: true): _newTab,
          const SingleActivator(LogicalKeyboardKey.keyW,
              control: true, shift: true): () => _closeTab(_current),
          const SingleActivator(LogicalKeyboardKey.pageDown, control: true):
              () => _selectTab((_current + 1) % _sessions.length),
          const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () =>
              _selectTab((_current - 1) % _sessions.length),
          const SingleActivator(LogicalKeyboardKey.keyC,
              control: true, shift: true): _copy,
          const SingleActivator(LogicalKeyboardKey.keyV,
              control: true, shift: true): _paste,
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
              _zoom(1),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
              _zoom(-1),
          const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
              setState(() => _zoomDelta = 0),
        },
        child: Scaffold(
          // The tab bar is the frosted title bar: only the terminal itself
          // is opaque.
          backgroundColor: Colors.transparent,
          appBar: DahliaTitlebar(
            title: DahliaTabStrip(
              tabs: [
                for (final _Session s in _sessions)
                  DahliaTabData(
                      id: s, title: s.title, icon: Icons.terminal_rounded),
              ],
              current: _current,
              onSelect: _selectTab,
              onClose: _closeTab,
              onReorder: _moveTab,
              onNew: _newTab,
              newTooltip: "New tab (Ctrl+Shift+T)",
            ),
          ),
          // Translucent over river's blur when set below 100% in Settings.
          body: BlurRegion(
            enabled: _opacity < 1,
            child: ColoredBox(
              color: _theme.background.withValues(alpha: _opacity),
              child: IndexedStack(
                index: _current,
                children: [
                  for (final _Session session in _sessions)
                    GestureDetector(
                      key: ObjectKey(session),
                      onSecondaryTapDown: (details) =>
                          _showMenu(details.globalPosition),
                      child: TerminalView(
                        session.terminal,
                        controller: session.controller,
                        focusNode: session.focusNode,
                        theme: terminalThemeWithAccent(
                            _theme, theme.colorScheme.primary),
                        backgroundOpacity: 0,
                        cursorType: _cursorType,
                        autofocus: true,
                        padding: const EdgeInsets.all(6),
                        textStyle: TerminalStyle(
                          fontSize: _fontSize,
                          fontFamily: ZenitFonts.monospaceOf(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(Offset position) async {
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: "copy", child: Text("Copy")),
        PopupMenuItem(value: "paste", child: Text("Paste")),
        PopupMenuDivider(),
        PopupMenuItem(value: "tab", child: Text("New Tab")),
        PopupMenuItem(value: "close", child: Text("Close Tab")),
      ],
    );
    switch (action) {
      case "copy":
        await _copy();
      case "paste":
        await _paste();
      case "tab":
        _newTab();
      case "close":
        _closeTab(_current);
    }
  }
}
