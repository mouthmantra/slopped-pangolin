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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pangolin/components/login/login_kit.dart';
import 'package:pangolin/services/pam.dart';
import 'package:pangolin/services/session_lock.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

/// The lock screen shown on every monitor while the session is locked, as
/// ChromeOS's: the blurred wallpaper, the user with the password field, and
/// a shelf with the power menu and the time.
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
    // A menu of this screen (power) has the keyboard while it's open.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
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
    final String? message =
        _lock.error ?? (_capsLock ? "Caps Lock is on" : null);

    final Widget content = Column(
      children: [
        const Spacer(flex: 5),
        LoginUserPod(name: SessionLock.displayName, user: Pam.user),
        const SizedBox(height: 28),
        LoginShake(
          animation: _shake,
          child: LoginField(
            controller: LockScreen.password,
            focus: _focus,
            busy: _lock.checking,
            onKey: _onKey,
            onSubmit: _submit,
          ),
        ),
        const SizedBox(height: 12),
        LoginMessage(message),
        const Spacer(flex: 6),
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
              const _LockBackdrop(),
              LoginFitHeight(child: content),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LoginShelf(
                  leading: [
                    ShelfMenuButton(
                      icon: Icons.power_settings_new_rounded,
                      label: "Power",
                      items: [
                        (
                          Icons.bedtime_outlined,
                          "Suspend",
                          ActionManager.suspend,
                        ),
                        (
                          Icons.restart_alt_rounded,
                          "Restart",
                          ActionManager.reboot,
                        ),
                        (
                          Icons.power_settings_new_rounded,
                          "Shut down",
                          ActionManager.powerOff,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The desktop's wallpaper, blurred: its small blurred copy is in memory
/// already (the shell's frosted surfaces use it), so it shows at once.
class _LockBackdrop extends StatelessWidget
    with StatelessServiceListener<CustomizationService> {
  const _LockBackdrop();

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    return LoginBackdrop(
      wallpaperKey: service.wallpaper,
      wallpaper: BlurredWallpaper.providerFor(service.wallpaper),
      opaque: true,
    );
  }
}
