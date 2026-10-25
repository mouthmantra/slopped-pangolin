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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:display_config/display_config.dart' show SharedUserFiles;
import 'package:flutter/material.dart';
import 'package:pangolin/components/login/login_kit.dart';
import 'package:pangolin/services/display_manager.dart';
import 'package:pangolin/services/greetd.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/splash_cache.dart';
import 'package:pangolin/services/wallpaper_share.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

/// Pangolin's login screen, run by pangolin-dm (or greetd), as ChromeOS's:
/// the user's wallpaper blurred, the user with one password field, the other
/// users below, and a shelf with power and the time.
///
/// river draws the selected user's wallpaper, sharp (river_blur keeps its
/// splash, PANGOLIN_WALLPAPER): this screen only blurs it. Once logged in,
/// the blur goes and leaves that wallpaper, which the desktop then starts
/// on (its own splash, the same image).
class GreeterScreen extends StatefulWidget {
  const GreeterScreen({super.key});

  @override
  State<GreeterScreen> createState() => _GreeterScreenState();
}

class _GreeterScreenState extends State<GreeterScreen>
    with TickerProviderStateMixin {
  final List<LoginUser> _users = LoginUser.all();
  final List<LoginSession> _sessions = LoginSession.all();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: "greeter password");
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// The blur comes over the sharp wallpaper (river's, shown since boot),
  /// and the user and field rise in.
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  /// Logged in: the user and field go, then the blur, down to the sharp
  /// wallpaper the desktop starts on.
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  late final Animation<double> _contentOpacity = _AnimationProduct(
    CurvedAnimation(parent: _appear, curve: Curves.easeOut),
    ReverseAnimation(
      CurvedAnimation(
        parent: _leave,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    ),
  );

  late final Animation<double> _backdropOpacity = _AnimationProduct(
    CurvedAnimation(parent: _appear, curve: Curves.easeOut),
    _riverDrawsWallpaper
        ? ReverseAnimation(
            CurvedAnimation(
              parent: _leave,
              curve: const Interval(0.25, 1, curve: Curves.easeInOut),
            ),
          )
        : kAlwaysCompleteAnimation,
  );

  LoginBackend? _login;
  int _user = 0;
  int _session = 0;
  bool _busy = false;
  String? _error;

  /// What PAM asks for (password prompt, second factor...).
  String _prompt = "Password";
  bool _secret = true;
  bool _inSession = false;

  Object _wallpaperKey = "";
  ImageProvider? _wallpaper;

  /// river draws the wallpaper below (it has a splash file and keeps it):
  /// else the blur stays, drawn on black.
  static bool get _riverDrawsWallpaper =>
      PangolinSession.riverWallpaper &&
      Platform.environment["PANGOLIN_SPLASH"] != null;

  static File get _stateFile {
    final String dir = Platform.environment["XDG_STATE_HOME"] ??
        "${Platform.environment["HOME"] ?? "/tmp"}/.local/state";
    return File("$dir/pangolin-greeter");
  }

  @override
  void initState() {
    super.initState();
    _restoreChoices();
    unawaited(_connect());
    _showWallpaper();
    FocusManager.instance.addListener(_keepFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      // The others', blurred ahead: picking another user shows theirs at
      // once.
      for (final LoginUser user in _users) {
        final (Object key, ImageProvider? provider) = _wallpaperOf(user);
        if (provider != null) {
          unawaited(BlurredWallpaper.ofProvider(key, provider));
        }
      }
    });
  }

  bool _refocusScheduled = false;

  /// Keeps the keyboard on the password field: the surface gets the
  /// keyboard after the field asked for it (the first frame), and Flutter
  /// doesn't hand it back by itself. The user name field and the menus
  /// keep it while they have it.
  void _keepFocus() {
    if (_refocusScheduled || !mounted) return;
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    if (focused == _focus || (focused?.context?.widget is EditableText)) {
      return;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_users.isEmpty && _username.text.isEmpty) return;
    _refocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refocusScheduled = false;
      if (mounted && FocusManager.instance.primaryFocus != _focus) {
        _focus.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keepFocus);
    _password.dispose();
    _username.dispose();
    _focus.dispose();
    _shake.dispose();
    _appear.dispose();
    _leave.dispose();
    unawaited(_login?.close());
    super.dispose();
  }

  LoginUser? get _selected => _users.isEmpty ? null : _users[_user];

  /// The wallpaper [user]'s desktop shares, else this screen's own.
  (Object, ImageProvider?) _wallpaperOf(LoginUser? user) {
    final File? file = user == null
        ? null
        : SharedUserFiles.published(user.name, WallpaperShare.sharedName);
    if (file != null) {
      int stamp = 0;
      try {
        stamp = file.lastModifiedSync().millisecondsSinceEpoch;
      } on FileSystemException {
        // Read as it is.
      }
      return ("${file.path}:$stamp", FileImage(file));
    }
    final ImageResource fallback = CustomizationService.current.wallpaper;
    return (fallback, BlurredWallpaper.providerFor(fallback));
  }

  /// The selected user's wallpaper: blurred here, sharp below (river's
  /// splash, which the next login screen also starts on).
  void _showWallpaper() {
    final (Object key, ImageProvider? provider) = _wallpaperOf(_selected);
    setState(() {
      _wallpaperKey = key;
      _wallpaper = provider;
    });
    if (provider != null) {
      unawaited(SplashCache.writeForScreens(provider, key.toString()));
    }
  }

  Future<void> _connect() async {
    if (!LoginBackend.available) {
      setState(() => _error = "No display manager runs this login screen");
      return;
    }
    try {
      _login = await LoginBackend.connect();
    } on Object catch (e) {
      setState(() => _error = "Can't reach the display manager: $e");
    }
  }

  /// The last user and session chosen on this computer.
  void _restoreChoices() {
    try {
      final List<String> lines = _stateFile.readAsLinesSync();
      if (lines.isNotEmpty) {
        final int user = _users.indexWhere((u) => u.name == lines[0]);
        if (user >= 0) _user = user;
      }
      if (lines.length > 1) {
        final int session = _sessions.indexWhere((s) => s.id == lines[1]);
        if (session >= 0) _session = session;
      }
    } on FileSystemException {
      // First login on this computer.
    }
  }

  void _saveChoices(String user, String session) {
    try {
      _stateFile.parent.createSync(recursive: true);
      _stateFile.writeAsStringSync("$user\n$session\n");
    } on FileSystemException {
      // Not remembered, that's all.
    }
  }

  String get _userName => _selected?.name ?? _username.text.trim();

  void _fail(String message) {
    setState(() {
      _busy = false;
      _error = message;
      _prompt = "Password";
      _secret = true;
    });
    _shake.forward(from: 0);
    _refocus();
  }

  void _refocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _cancel() async {
    if (_inSession) {
      _inSession = false;
      await _login?.cancel();
    }
  }

  Future<void> _submit() async {
    final LoginBackend? login = _login;
    if (login == null || _busy) return;
    final String user = _userName;
    if (user.isEmpty) return;
    // The field is emptied right away: what is typed while the answer is
    // checked (the next attempt, after a wrong one) stays in it.
    final String answer = _password.text;
    _password.clear();
    setState(() {
      _busy = true;
      _error = null;
    });

    // Messages before the first question (or between questions) need an
    // empty answer to go on; the last one stays in sight.
    Future<LoginReply> skipMessages(LoginReply first) async {
      LoginReply reply = first;
      while (reply is LoginInfo) {
        final String text = reply.text.trim();
        if (text.isNotEmpty && mounted) setState(() => _error = text);
        reply = await login.answer(null);
      }
      return reply;
    }

    LoginReply reply;
    if (!_inSession) {
      reply = await skipMessages(await login.begin(user));
      _inSession = true;
      // Answer the first question with what was typed.
      if (reply is LoginQuestion) reply = await login.answer(answer);
    } else {
      reply = await login.answer(answer);
    }
    reply = await skipMessages(reply);

    switch (reply) {
      case LoginVerified() || LoginStarted():
        await _start(login, user);
      case LoginQuestion(:final String text, :final bool secret):
        // Another question (a second factor, a security key's PIN, a new
        // password for an expired one).
        setState(() {
          _busy = false;
          _prompt = text.trim().isEmpty ? "Password" : text.trim();
          _secret = secret;
        });
        _refocus();
      case LoginFailed(:final bool wrongAnswer, :final String text):
        _inSession = false;
        _fail(
          wrongAnswer
              ? "Incorrect password, try again"
              : text.isNotEmpty
                  ? text
                  : "Couldn't log in",
        );
      case LoginInfo():
        break;
    }
  }

  Future<void> _start(LoginBackend login, String user) async {
    final LoginSession? session =
        _sessions.isEmpty ? null : _sessions[_session];
    // Wayland sessions only (the display manager sets XDG_SESSION_TYPE and
    // the session's desktop names). The desktop starts on the wallpaper this
    // screen leaves behind, instead of fading in from black.
    final LoginReply reply = await login.start(session, const ["PANGOLIN_FROM_GREETER=1"]);
    if (reply is! LoginStarted) {
      await _cancel();
      _fail(
        reply is LoginFailed && reply.text.isNotEmpty
            ? reply.text
            : "Couldn't start the session",
      );
      return;
    }
    _saveChoices(user, session?.id ?? "");
    // Down to the sharp wallpaper, then leave: the display manager starts
    // the session once the greeter (and its compositor) exit.
    await _leave.forward();
    await login.close();
    exit(0);
  }

  Future<void> _selectUser(int i) async {
    if (i == _user) {
      _focus.requestFocus();
      return;
    }
    await _cancel();
    _password.clear();
    setState(() {
      _user = i;
      _error = null;
      _prompt = "Password";
      _secret = true;
    });
    _showWallpaper();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final LoginUser? user = _selected;

    final Widget content = Column(
      children: [
        const Spacer(flex: 5),
        if (user != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: LoginUserPod(
              key: ValueKey(user.name),
              name: user.displayName,
              user: user.name,
            ),
          )
        else
          LoginField(
            controller: _username,
            hint: "User name",
            secret: false,
            showSubmit: false,
            onSubmit: _focus.requestFocus,
          ),
        const SizedBox(height: 28),
        LoginShake(
          animation: _shake,
          child: LoginField(
            controller: _password,
            focus: _focus,
            hint: _prompt,
            secret: _secret,
            busy: _busy,
            onSubmit: _submit,
          ),
        ),
        const SizedBox(height: 12),
        LoginMessage(_error),
        if (_users.length > 1) ...[
          const SizedBox(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (int i = 0; i < _users.length; i++)
                if (i != _user)
                  LoginUserPod(
                    name: _users[i].displayName,
                    user: _users[i].name,
                    large: false,
                    onTap: () => _selectUser(i),
                  ),
            ],
          ),
        ],
        const Spacer(flex: 6),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // A click anywhere else goes back to the password field.
        onTap: () {
          if (_users.isNotEmpty || _username.text.isNotEmpty) {
            _focus.requestFocus();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            LoginBackdrop(
              wallpaperKey: _wallpaperKey,
              wallpaper: _wallpaper,
              opacity: _backdropOpacity,
              opaque: !_riverDrawsWallpaper,
            ),
            AnimatedBuilder(
              animation: _contentOpacity,
              builder: (context, child) => Opacity(
                opacity: _contentOpacity.value,
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - _appear.value)),
                  child: child,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LoginFitHeight(child: content),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LoginShelf(
                      leading: [
                        ShelfButton(
                          icon: Icons.power_settings_new_rounded,
                          label: "Shut down",
                          onTap: () => _power("poweroff"),
                        ),
                        ShelfButton(
                          icon: Icons.restart_alt_rounded,
                          label: "Restart",
                          onTap: () => _power("reboot"),
                        ),
                        if (_sessions.length > 1)
                          ShelfMenuButton(
                            icon: Icons.desktop_windows_outlined,
                            label: _sessions[_session].name,
                            items: [
                              for (int i = 0; i < _sessions.length; i++)
                                (
                                  i == _session
                                      ? Icons.check_rounded
                                      : Icons.desktop_windows_outlined,
                                  _sessions[i].name,
                                  () => setState(() => _session = i),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restarts or shuts down through logind (allowed to the active session's
/// user, the greeter's included).
void _power(String action) {
  unawaited(
    Process.run("systemctl", [action]).catchError(
      (Object _) => Process.run("loginctl", [action]),
    ),
  );
}

/// [a] times [b].
class _AnimationProduct extends CompoundAnimation<double> {
  _AnimationProduct(Animation<double> a, Animation<double> b)
      : super(first: a, next: b);

  @override
  double get value => first.value * next.value;
}
