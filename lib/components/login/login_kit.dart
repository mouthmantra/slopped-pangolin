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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pangolin/widgets/user_avatar.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

// The login and lock screens, as ChromeOS lays them out: the blurred
// wallpaper, the user in the middle with one password field, other users
// below, and a shelf along the bottom (power on the left, the time on the
// right).

/// Shadow under the white text of the lock and login screens.
const List<Shadow> loginTextShadows = [
  Shadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 1)),
];

const Color _pill = Color(0x47000000);
const Color _pillHover = Color(0x66000000);
const Color _field = Color(0x2EFFFFFF);

/// The wallpaper, blurred and dimmed: a small blurred copy
/// ([BlurredWallpaper]) stretched over the screen, cheap at any resolution.
/// Changing wallpapers cross-fade. [opacity] fades all of it: the login
/// screen leaves the sharp wallpaper river draws below it, which the
/// desktop then starts on.
class LoginBackdrop extends StatefulWidget {
  const LoginBackdrop({
    required this.wallpaperKey,
    required this.wallpaper,
    this.opacity = kAlwaysCompleteAnimation,
    this.opaque = false,
    super.key,
  });

  final Object wallpaperKey;
  final ImageProvider? wallpaper;
  final Animation<double> opacity;

  /// Nothing is drawn below (the lock screen): a dark color shows until the
  /// blurred copy is ready.
  final bool opaque;

  @override
  State<LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<LoginBackdrop> {
  ui.Image? _image;
  Object? _loaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LoginBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wallpaperKey != oldWidget.wallpaperKey) _load();
  }

  void _load() {
    final Object key = widget.wallpaperKey;
    final ImageProvider? provider = widget.wallpaper;
    if (provider == null) return;
    BlurredWallpaper.ofProvider(key, provider).then((image) {
      if (!mounted || widget.wallpaperKey != key || image == null) return;
      setState(() {
        _image = image;
        _loaded = key;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    return RepaintBoundary(
      child: FadeTransition(
        opacity: widget.opacity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.opaque) const ColoredBox(color: Color(0xFF1C1B1F)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: image == null
                  ? const SizedBox.expand()
                  : RawImage(
                      key: ValueKey(_loaded),
                      image: image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x59000000)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A user: picture or initial, and name. [large] for the one signing in.
class LoginUserPod extends StatelessWidget {
  const LoginUserPod({
    required this.name,
    required this.user,
    this.large = true,
    this.onTap,
    super.key,
  });

  final String name;

  /// Login name, for the account's picture.
  final String user;
  final bool large;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget pod = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(
          name: name,
          size: large ? 112 : 52,
          picture: UserAvatar.pictureOf(user),
        ),
        SizedBox(height: large ? 18 : 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: large ? 360 : 120),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: large ? 24 : 13,
              fontWeight: large ? FontWeight.w600 : FontWeight.w500,
              shadows: loginTextShadows,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return pod;
    return _Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x1FFFFFFF) : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: pod,
      ),
    );
  }
}

/// The pill the password (or what PAM asks) is typed in, with its submit
/// button at the end.
class LoginField extends StatelessWidget {
  const LoginField({
    required this.controller,
    required this.onSubmit,
    this.focus,
    this.hint = "Password",
    this.secret = true,
    this.busy = false,
    this.showSubmit = true,
    this.onKey,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focus;
  final String hint;
  final bool secret;
  final bool busy;
  final bool showSubmit;
  final VoidCallback onSubmit;
  final FocusOnKeyEventCallback? onKey;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.secondary;
    // A layer of its own: typing redraws (and recomposites) the field alone,
    // not the screen around it.
    return RepaintBoundary(
      child: _buildField(accent),
    );
  }

  Widget _buildField(Color accent) {
    return Container(
      width: 300,
      height: 48,
      padding: EdgeInsets.only(left: 20, right: showSubmit ? 6 : 20),
      decoration: const ShapeDecoration(shape: StadiumBorder(), color: _field),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: onKey,
              child: TextField(
                controller: controller,
                focusNode: focus,
                obscureText: secret,
                // Focus comes back by itself (keys, clicks anywhere): keep
                // what was typed instead of selecting it, and keep the
                // focus when clicking elsewhere.
                selectAllOnFocus: false,
                onTapOutside: (_) {},
                onSubmitted: (_) => onSubmit(),
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 16,
                  ),
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
          if (showSubmit) ...[
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 36,
              child: Material(
                color: accent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: busy ? null : onSubmit,
                  child: Center(
                    child: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shakes [child] sideways while [animation] runs (a wrong password).
class LoginShake extends StatelessWidget {
  const LoginShake({required this.animation, required this.child, super.key});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          math.sin(animation.value * math.pi * 6) * 12 * (1 - animation.value),
          0,
        ),
        child: child,
      ),
      child: child,
    );
  }
}

/// One line under the field (a wrong password, Caps Lock), room kept when
/// empty.
class LoginMessage extends StatelessWidget {
  const LoginMessage(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}

/// Along the bottom: [leading] buttons on the left, the time on the right.
class LoginShelf extends StatelessWidget {
  const LoginShelf({required this.leading, super.key});

  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    // A layer of its own, like the field: redrawn when it changes, not
    // whenever something else on the screen does.
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            for (final Widget button in leading) ...[
              button,
              const SizedBox(width: 8),
            ],
            const Spacer(),
            const _Status(),
          ],
        ),
      ),
    );
  }
}

/// A shelf button: icon and label in a translucent pill.
class ShelfButton extends StatelessWidget {
  const ShelfButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return _Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: hovered && onTap != null ? _pillHover : _pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing, color: Colors.white, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shelf button that opens a menu of [items] (label, icon, action).
class ShelfMenuButton extends StatelessWidget {
  const ShelfMenuButton({
    required this.icon,
    required this.label,
    required this.items,
    super.key,
  });

  final IconData icon;
  final String label;
  final List<(IconData, String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: "",
      color: const Color(0xEB202124),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: PopupMenuPosition.over,
      offset: const Offset(0, -8),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final (IconData icon, String label, VoidCallback action) in items)
          PopupMenuItem(
            value: action,
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
      ],
      child: ShelfButton(
        icon: icon,
        label: label,
        trailing: Icons.expand_less_rounded,
      ),
    );
  }
}

/// The battery (if any), the date and the time.
class _Status extends StatefulWidget {
  const _Status();

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  ({int percent, bool charging})? _battery = _readBattery();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    final DateTime now = DateTime.now();
    _timer = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        if (!mounted) return;
        setState(() {
          _now = DateTime.now();
          _battery = _readBattery();
        });
        _schedule();
      },
    );
  }

  /// From sysfs: the login screen has no power daemon of its own.
  static ({int percent, bool charging})? _readBattery() {
    try {
      for (final FileSystemEntity entry
          in Directory("/sys/class/power_supply").listSync()) {
        final String dir = entry.path;
        if (File("$dir/type").readAsStringSync().trim() != "Battery") continue;
        final File scope = File("$dir/scope");
        // A mouse's or a keyboard's.
        if (scope.existsSync() && scope.readAsStringSync().trim() == "Device") {
          continue;
        }
        final int? percent =
            int.tryParse(File("$dir/capacity").readAsStringSync().trim());
        if (percent == null) continue;
        final String status = File("$dir/status").readAsStringSync().trim();
        return (
          percent: percent,
          charging: status == "Charging" || status == "Full",
        );
      }
    } on FileSystemException {
      // No battery information.
    }
    return null;
  }

  static IconData _batteryIcon(int percent, bool charging) {
    if (charging) return Icons.battery_charging_full_rounded;
    if (percent >= 90) return Icons.battery_full_rounded;
    if (percent >= 70) return Icons.battery_5_bar_rounded;
    if (percent >= 50) return Icons.battery_4_bar_rounded;
    if (percent >= 30) return Icons.battery_3_bar_rounded;
    if (percent >= 15) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final ({int percent, bool charging})? battery = _battery;
    const TextStyle style = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const ShapeDecoration(shape: StadiumBorder(), color: _pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (battery != null) ...[
            Icon(
              _batteryIcon(battery.percent, battery.charging),
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text("${battery.percent}%", style: style),
            const SizedBox(width: 16),
          ],
          Text(DateFormat.MMMEd(locale).format(_now), style: style),
          const SizedBox(width: 12),
          Text(
            DateFormat.Hm(locale).format(_now),
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder, this.onTap});

  final Widget Function(bool hovered) builder;
  final VoidCallback? onTap;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(_hovered),
      ),
    );
  }
}

/// Lays [child] out at least [minHeight] tall and scales it down to fit
/// shorter screens (a laptop at a large scale), instead of overflowing.
/// The same widgets at any size: the window starts small (GTK's default),
/// and a password field rebuilt when it grows would lose its keyboard.
class LoginFitHeight extends StatelessWidget {
  const LoginFitHeight({required this.child, super.key});

  static const double minHeight = 600;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double height = constraints.maxHeight;
        final double scale =
            height > 0 && height < minHeight ? height / minHeight : 1;
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: constraints.maxWidth / scale,
            height: height / scale,
            child: child,
          ),
        );
      },
    );
  }
}
