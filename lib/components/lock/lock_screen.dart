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
import 'dart:math' as math;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pangolin/services/session_lock.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/widgets/login_backdrop.dart';
import 'package:pangolin/widgets/resource/image/image.dart';

/// The lock screen shown on every monitor while the session is locked: the
/// wallpaper, the time, and the password field.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  /// Shared by the lock screens of every monitor: typing on one shows on all.
  static final TextEditingController password = TextEditingController();

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  /// The lock screens of every monitor, oldest first.
  static final List<_LockScreenState> _screens = [];

  final FocusNode _focus = FocusNode(debugLabel: "lock password");
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  Timer? _clock;
  DateTime _now = DateTime.now();
  int _failures = SessionLock.instance.failures;
  bool _capsLock = false;
  bool _refocusScheduled = false;

  SessionLock get _lock => SessionLock.instance;

  @override
  void initState() {
    super.initState();
    _screens.add(this);
    _lock.addListener(_onLockChanged);
    FocusManager.instance.addListener(_keepFocus);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _capsLock = HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
    _scheduleTick();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _screens.remove(this);
    _lock.removeListener(_onLockChanged);
    FocusManager.instance.removeListener(_keepFocus);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _clock?.cancel();
    _focus.dispose();
    _shake.dispose();
    _appear.dispose();
    super.dispose();
  }

  static bool get _fieldFocused =>
      _screens.any((screen) => screen._focus.hasPrimaryFocus);

  /// Keeps the keyboard on a password field: whatever is typed while
  /// locked is the password. Without this, keys go nowhere when a monitor
  /// comes back after suspend (its new lock screen's route takes the focus
  /// once it's pushed) or when the monitor whose field had the focus goes
  /// away.
  void _keepFocus() {
    if (_screens.isEmpty || _screens.last != this) return;
    if (_refocusScheduled || _fieldFocused) return;
    _refocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refocusScheduled = false;
      if (mounted && !_fieldFocused) _focus.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _onHardwareKey(KeyEvent event) {
    final bool capsLock = HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
    if (capsLock != _capsLock && mounted) setState(() => _capsLock = capsLock);
    return false;
  }

  void _scheduleTick() {
    _clock?.cancel();
    final DateTime now = DateTime.now();
    _clock = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
        _scheduleTick();
      },
    );
  }

  void _onLockChanged() {
    if (!mounted) return;
    if (_lock.failures != _failures) {
      _failures = _lock.failures;
      _shake.forward(from: 0);
    }
    setState(() {});
  }

  /// The field is emptied as soon as the password is sent: what is typed
  /// while it's checked (the next attempt, typed right after a wrong one)
  /// stays in it instead of being lost.
  Future<void> _submit() async {
    final String password = LockScreen.password.text;
    if (password.isEmpty || _lock.checking) return;
    LockScreen.password.clear();
    await _lock.unlock(password);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      LockScreen.password.clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Locale locale = Localizations.localeOf(context);
    final String time = DateFormat.Hm(locale.toLanguageTag()).format(_now);
    final String date =
        DateFormat.MMMMEEEEd(locale.toLanguageTag()).format(_now);
    final String name = SessionLock.displayName;
    final Color accent = theme.colorScheme.secondary;
    final String? message = _lock.error ??
        (_capsLock ? "Caps Lock is on" : null);

    final Widget content = Column(
      children: [
        const Spacer(flex: 3),
        Text(
          time,
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
          date,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            shadows: loginTextShadows,
          ),
        ),
        const Spacer(flex: 2),
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            name.isNotEmpty ? name.characters.first.toUpperCase() : "?",
            style: TextStyle(
              color: theme.colorScheme.onSecondary,
              fontSize: 40,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            shadows: loginTextShadows,
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: _PasswordField(
            focus: _focus,
            checking: _lock.checking,
            accent: accent,
            onKey: _onKey,
            onSubmit: _submit,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: AnimatedOpacity(
            opacity: message != null ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Text(
              message ?? "",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: loginTextShadows,
              ),
            ),
          ),
        ),
        const Spacer(flex: 4),
      ],
    );

    return Material(
      color: Colors.black,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _appear, curve: Curves.easeOut),
        // A click anywhere goes back to the password field.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focus.requestFocus,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const LoginBackdrop(wallpaper: _LockWallpaper()),
              _FitHeight(child: content),
              const Positioned(
                right: 24,
                bottom: 24,
                child: _PowerButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The desktop's wallpaper.
class _LockWallpaper extends StatelessWidget
    with StatelessServiceListener<CustomizationService> {
  const _LockWallpaper();

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    return ResourceImage(resource: service.wallpaper, fit: BoxFit.cover);
  }
}

/// Lays [child] out at least [minHeight] tall and scales it down to fit
/// shorter screens (a laptop at a large scale), instead of overflowing.
class _FitHeight extends StatelessWidget {
  const _FitHeight({required this.child});

  static const double minHeight = 640;

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

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.focus,
    required this.checking,
    required this.accent,
    required this.onKey,
    required this.onSubmit,
  });

  final FocusNode focus;
  final bool checking;
  final Color accent;
  final FocusOnKeyEventCallback onKey;
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
            child: Focus(
              onKeyEvent: onKey,
              child: TextField(
                controller: LockScreen.password,
                focusNode: focus,
                autofocus: true,
                obscureText: true,
                // Focus comes back by itself (keys, clicks anywhere): keep
                // what was typed instead of selecting it, and keep the focus
                // when clicking elsewhere.
                selectAllOnFocus: false,
                onTapOutside: (_) {},
                onSubmitted: (_) => onSubmit(),
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: "Password",
                  hintStyle: TextStyle(color: Color(0xB3FFFFFF), fontSize: 16),
                  filled: false,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
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
                onTap: checking ? null : onSubmit,
                child: Center(
                  child: checking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Suspend, restart and shut down without unlocking.
class _PowerButton extends StatelessWidget {
  const _PowerButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void Function()>(
      tooltip: "Power",
      color: const Color(0xE6202020),
      shape: Constants.mediumShape,
      position: PopupMenuPosition.over,
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        _item(Icons.bedtime_outlined, "Suspend", ActionManager.suspend),
        _item(Icons.restart_alt_rounded, "Restart", ActionManager.reboot),
        _item(Icons.power_settings_new_rounded, "Shut down",
            ActionManager.powerOff),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Color(0x33FFFFFF),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.power_settings_new_rounded,
          color: Colors.white,
        ),
      ),
    );
  }

  static PopupMenuItem<void Function()> _item(
    IconData icon,
    String label,
    void Function() action,
  ) {
    return PopupMenuItem(
      value: action,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
