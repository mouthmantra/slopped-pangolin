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
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:display_config/display_config.dart' show SharedUserFiles;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pangolin/services/greetd.dart';
import 'package:pangolin/services/splash_cache.dart';
import 'package:pangolin/services/wallpaper_share.dart';
import 'package:pangolin/widgets/login_backdrop.dart';
import 'package:pangolin/widgets/resource/image/image.dart';

/// Pangolin's login screen (display manager), run by greetd: pick a user and
/// a session, enter the password, and greetd starts the session.
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

  /// The clock, the users and the password field come in over the
  /// wallpaper (which river's splash already shows when the login screen
  /// starts).
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..forward();

  /// Once logged in, the clock, the user, the field and the darkening fade
  /// away and leave the user's wallpaper: the desktop starts on that same
  /// wallpaper (river's splash, without fading in) and its shell comes in
  /// over it.
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  /// The clock, the users and the field: in with [_appear], out with
  /// [_leave].
  late final Animation<double> _contentOpacity = _AnimationProduct(
    CurvedAnimation(parent: _appear, curve: Curves.easeOut),
    ReverseAnimation(CurvedAnimation(parent: _leave, curve: Curves.easeOut)),
  );

  /// The password was right: the darkening is gone, the rest fades.
  bool _loggedIn = false;

  GreetdClient? _greetd;
  int _user = 0;
  int _session = 0;
  bool _busy = false;
  String? _error;

  /// What greetd asks for (password prompt, second factor...).
  String _prompt = "Password";
  bool _secret = true;
  bool _inSession = false;

  /// The selected user's wallpaper (shared by their desktop), null for the
  /// default one.
  ImageProvider? _wallpaper;
  String _wallpaperKey = "default";

  Timer? _clock;
  DateTime _now = DateTime.now();

  static File get _stateFile {
    final String dir = Platform.environment["XDG_STATE_HOME"] ??
        "${Platform.environment["HOME"] ?? "/tmp"}/.local/state";
    return File("$dir/pangolin-greeter");
  }

  @override
  void initState() {
    super.initState();
    _restoreChoices();
    _tick();
    unawaited(_connect());
    _setWallpaper(initial: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _precacheWallpapers();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _password.dispose();
    _username.dispose();
    _focus.dispose();
    _shake.dispose();
    _appear.dispose();
    _leave.dispose();
    unawaited(_greetd?.close());
    super.dispose();
  }

  /// Shows the selected user's wallpaper, cross-fading once it's decoded.
  void _setWallpaper({bool initial = false}) {
    final LoginUser? user = _users.isEmpty ? null : _users[_user];
    final File? file = user == null
        ? null
        : SharedUserFiles.published(user.name, WallpaperShare.sharedName);
    final String key = file == null
        ? "default"
        : "${file.path}:${file.lastModifiedSync().millisecondsSinceEpoch}";
    if (key == _wallpaperKey && !initial) return;
    final ImageProvider? provider = file == null ? null : FileImage(file);
    if (initial) {
      _wallpaper = provider;
      _wallpaperKey = key;
      // The next login screen starts on this wallpaper (river's splash).
      if (provider != null) unawaited(SplashCache.write(provider, key));
      return;
    }
    if (provider == null) {
      setState(() {
        _wallpaper = null;
        _wallpaperKey = key;
      });
      return;
    }
    unawaited(
      precacheImage(_sized(provider), context).then((_) {
        if (!mounted) return;
        // Still the selected user's?
        final LoginUser? now = _users.isEmpty ? null : _users[_user];
        if (now != user) return;
        setState(() {
          _wallpaper = provider;
          _wallpaperKey = key;
        });
      }),
    );
  }

  /// Every user's wallpaper, decoded while the screen waits for a password,
  /// so that picking another user shows theirs at once.
  void _precacheWallpapers() {
    if (_users.length < 2) return;
    for (final LoginUser user in _users) {
      final File? file =
          SharedUserFiles.published(user.name, WallpaperShare.sharedName);
      if (file == null) continue;
      unawaited(
        precacheImage(_sized(FileImage(file)), context).catchError((Object _) {}),
      );
    }
  }

  /// Decoded at the screen's size, not the image's.
  ImageProvider _sized(ImageProvider provider) {
    final ui.FlutterView view = View.of(context);
    final int width = view.physicalSize.width.round().clamp(640, 7680);
    return ResizeImage(
      provider,
      width: width,
      policy: ResizeImagePolicy.fit,
    );
  }

  void _tick() {
    _clock?.cancel();
    final DateTime now = DateTime.now();
    _clock = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick();
    });
  }

  Future<void> _connect() async {
    if (!GreetdClient.available) {
      setState(() => _error = "greetd isn't running this greeter");
      return;
    }
    try {
      _greetd = await GreetdClient.connect();
    } on Object catch (e) {
      setState(() => _error = "Can't reach greetd: $e");
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

  String get _userName =>
      _users.isEmpty ? _username.text.trim() : _users[_user].name;

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
      await _greetd?.cancelSession();
    }
  }

  Future<void> _submit() async {
    final GreetdClient? greetd = _greetd;
    if (greetd == null || _busy) return;
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

    GreetdReply reply;
    if (!_inSession) {
      reply = await greetd.createSession(user);
      _inSession = true;
      // Answer the first question with what was typed.
      if (reply is GreetdAuthMessage && reply.needsAnswer) {
        reply = await greetd.answer(answer);
      }
    } else {
      reply = await greetd.answer(answer);
    }

    // Informational messages need an empty answer to go on.
    while (reply is GreetdAuthMessage && !reply.needsAnswer) {
      reply = await greetd.answer(null);
    }

    switch (reply) {
      case GreetdSuccess():
        await _start(greetd, user);
      case GreetdAuthMessage(:final String message, :final String type):
        // Another question (e.g. a second factor).
        setState(() {
          _busy = false;
          _prompt = message.trim().isEmpty ? "Password" : message.trim();
          _secret = type == "secret";
        });
        _refocus();
      case GreetdError(:final String type, :final String description):
        await _cancel();
        _fail(
          type == "auth_error"
              ? "Incorrect password, try again"
              : description.isNotEmpty
                  ? description
                  : "Couldn't log in",
        );
    }
  }

  Future<void> _start(GreetdClient greetd, String user) async {
    final LoginSession? session =
        _sessions.isEmpty ? null : _sessions[_session];
    final List<String> command = session?.command ?? ["/bin/sh", "-l"];
    final List<String> env = [
      // Wayland sessions only: nothing here starts an X server.
      "XDG_SESSION_TYPE=wayland",
      "XDG_SESSION_CLASS=user",
      // The desktop starts on the wallpaper this screen leaves behind,
      // instead of fading in from black.
      "PANGOLIN_FROM_GREETER=1",
      if (session != null && session.desktopNames.isNotEmpty)
        "XDG_CURRENT_DESKTOP=${session.desktopNames}",
      if (session != null) "XDG_SESSION_DESKTOP=${session.id}",
    ];
    final GreetdReply reply = await greetd.startSession(command, env);
    if (reply is! GreetdSuccess) {
      await _cancel();
      _fail(
        reply is GreetdError && reply.description.isNotEmpty
            ? reply.description
            : "Couldn't start the session",
      );
      return;
    }
    _saveChoices(user, session?.id ?? "");
    // Down to the wallpaper, then leave: greetd starts the session once the
    // greeter (and its compositor) exit.
    setState(() => _loggedIn = true);
    await _leave.forward();
    await greetd.close();
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
    _setWallpaper();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Locale locale = Localizations.localeOf(context);
    final Color accent = theme.colorScheme.secondary;
    final LoginUser? user = _users.isEmpty ? null : _users[_user];
    final ImageProvider? wallpaper = _wallpaper;

    final Widget content = Column(
      children: [
        const Spacer(flex: 3),
        Text(
          DateFormat.Hm(locale.toLanguageTag()).format(_now),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 96,
            fontWeight: FontWeight.w200,
            height: 1,
            shadows: loginTextShadows,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          DateFormat.MMMMEEEEd(locale.toLanguageTag()).format(_now),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            shadows: loginTextShadows,
          ),
        ),
        const Spacer(flex: 2),
        if (_users.length > 1) ...[
          Wrap(
            spacing: 16,
            children: [
              for (int i = 0; i < _users.length; i++)
                _UserTile(
                  user: _users[i],
                  selected: i == _user,
                  accent: accent,
                  onTap: () => _selectUser(i),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ] else if (user != null) ...[
          _Avatar(user: user, accent: accent, size: 88),
          const SizedBox(height: 16),
          Text(
            user.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              shadows: loginTextShadows,
            ),
          ),
          const SizedBox(height: 20),
        ] else ...[
          _Field(
            controller: _username,
            hint: "User name",
            secret: false,
            accent: accent,
            busy: false,
            onSubmit: () => _focus.requestFocus(),
          ),
          const SizedBox(height: 12),
        ],
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: _Field(
            controller: _password,
            focus: _focus,
            hint: _prompt,
            secret: _secret,
            accent: accent,
            busy: _busy,
            onSubmit: _submit,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: Text(
            _error ?? "",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              shadows: loginTextShadows,
            ),
          ),
        ),
        if (_sessions.length > 1) ...[
          const SizedBox(height: 8),
          _SessionPicker(
            sessions: _sessions,
            current: _session,
            onChanged: (i) => setState(() => _session = i),
          ),
        ],
        const Spacer(flex: 4),
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
              // Gone at once when the password is right: the desktop starts
              // on the bare wallpaper.
              veil: _loggedIn
                  ? kAlwaysDismissedAnimation
                  : kAlwaysCompleteAnimation,
              // Another user's wallpaper shows at once (decoded ahead).
              wallpaper: AnimatedSwitcher(
                duration: Duration.zero,
                child: KeyedSubtree(
                  key: ValueKey(_wallpaperKey),
                  child: wallpaper != null
                      ? Image(
                          image: _sized(wallpaper),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          width: double.infinity,
                          height: double.infinity,
                          // The default one until it can be read.
                          errorBuilder: (context, _, __) =>
                              const _DefaultWallpaper(),
                        )
                      : const _DefaultWallpaper(),
                ),
              ),
            ),
            FadeTransition(
              opacity: _contentOpacity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _FitHeight(child: content),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: Row(
                      children: [
                        _RoundButton(
                          icon: Icons.restart_alt_rounded,
                          tooltip: "Restart",
                          onTap: () => _power("reboot"),
                        ),
                        const SizedBox(width: 12),
                        _RoundButton(
                          icon: Icons.power_settings_new_rounded,
                          tooltip: "Shut down",
                          onTap: () => _power("poweroff"),
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

/// The login screen's own wallpaper (Pangolin's default), for users who
/// haven't shared theirs yet.
class _DefaultWallpaper extends StatelessWidget
    with StatelessServiceListener<CustomizationService> {
  const _DefaultWallpaper();

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    return ResourceImage(resource: service.wallpaper, fit: BoxFit.cover);
  }
}

/// Lays [child] out at least [minHeight] tall and scales it down to fit
/// shorter screens, instead of overflowing.
class _FitHeight extends StatelessWidget {
  const _FitHeight({required this.child});

  static const double minHeight = 680;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight >= minHeight) return child;
        final double scale = constraints.maxHeight / minHeight;
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: constraints.maxWidth / scale,
            height: minHeight,
            child: child,
          ),
        );
      },
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.accent, required this.size});

  final LoginUser user;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String name = user.displayName;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : "?",
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final LoginUser user;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 132,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0x33FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _Avatar(user: user, accent: accent, size: 64),
              const SizedBox(height: 10),
              Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.secret,
    required this.accent,
    required this.busy,
    required this.onSubmit,
    this.focus,
  });

  final TextEditingController controller;
  final FocusNode? focus;
  final String hint;
  final bool secret;
  final Color accent;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      height: 52,
      padding: const EdgeInsets.only(left: 22, right: 6),
      decoration: const ShapeDecoration(
        shape: StadiumBorder(),
        color: Color(0x33FFFFFF),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              obscureText: secret,
                // Focus comes back by itself (keys, clicks anywhere): keep
                // what was typed instead of selecting it, and keep the focus
                // when clicking elsewhere.
                selectAllOnFocus: false,
                onTapOutside: (_) {},
              onSubmitted: (_) => onSubmit(),
              cursorColor: Colors.white,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 16),
                filled: false,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 40,
            child: Material(
              color: accent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: busy ? null : onSubmit,
                child: Center(
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionPicker extends StatelessWidget {
  const _SessionPicker({
    required this.sessions,
    required this.current,
    required this.onChanged,
  });

  final List<LoginSession> sessions;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: "Session",
      color: const Color(0xE6202020),
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (int i = 0; i < sessions.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              sessions[i].name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: const ShapeDecoration(
          shape: StadiumBorder(),
          color: Color(0x26FFFFFF),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.desktop_windows_outlined, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              sessions[current].name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x33FFFFFF),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// [a] times [b].
class _AnimationProduct extends CompoundAnimation<double> {
  _AnimationProduct(Animation<double> a, Animation<double> b)
      : super(first: a, next: b);

  @override
  double get value => first.value * next.value;
}
