/*
Copyright 2021 The dahliaOS Authors

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
import 'package:pangolin/components/taskbar/app_list.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/extensions/extensions.dart';
import 'package:pangolin/widgets/context_menu.dart';
import 'package:pangolin/widgets/resource/auto_image.dart';
import 'package:pangolin/widgets/taskbar_geometry_reporter.dart';
import 'package:pangolin/widgets/window_icon.dart';
import 'package:yatl_flutter/yatl_flutter.dart';

class TaskbarItem extends StatefulWidget {
  final AppSlot slot;

  /// The slot went away: the item shrinks out of the bar, then [onLeft].
  final bool leaving;
  final VoidCallback? onLeft;

  const TaskbarItem({
    required this.slot,
    this.leaving = false,
    this.onLeft,
    super.key,
  });

  @override
  _TaskbarItemState createState() => _TaskbarItemState();
}

class _TaskbarItemState extends State<TaskbarItem>
    with TickerProviderStateMixin {
  bool _hovering = false;
  bool _pressed = false;

  /// New items grow into place, pushing the others aside; leaving ones
  /// shrink away and the others slide over.
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();

  /// Hops while the app starts, until its first window shows up.
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  Timer? _bounceTimeout;

  AppSlot get slot => widget.slot;

  @override
  void initState() {
    super.initState();
    if (slot.launching && slot.windows.isEmpty) _startBounce();
  }

  @override
  void didUpdateWidget(TaskbarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (slot.windows.isNotEmpty) {
      _stopBounce();
    } else if (slot.launching && !_bounce.isAnimating) {
      _startBounce();
    }
    if (widget.leaving && !oldWidget.leaving) {
      _stopBounce();
      _hovering = false;
      _pressed = false;
      // Completes only if it isn't brought back meanwhile.
      _appear.reverse().then((_) {
        if (mounted && widget.leaving) widget.onLeft?.call();
      });
    } else if (!widget.leaving && oldWidget.leaving) {
      _appear.forward();
    }
  }

  @override
  void dispose() {
    _bounceTimeout?.cancel();
    _appear.dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _startBounce() {
    _bounce.repeat();
    _bounceTimeout?.cancel();
    _bounceTimeout = Timer(const Duration(seconds: 6), _stopBounce);
  }

  void _stopBounce() {
    _bounceTimeout?.cancel();
    if (!_bounce.isAnimating) return;
    // Finish the current hop rather than snapping down.
    _bounce.forward(from: _bounce.value).whenComplete(_bounce.reset);
  }

  String _label(BuildContext context) {
    final entry = slot.entry;
    if (entry != null) return entry.getLocalizedName(context.locale);
    return slot.windows.firstOrNull?.title ?? slot.key;
  }

  void _onTap() {
    final List<ShellWindow> windows = slot.windows;

    if (windows.isEmpty) {
      _startBounce();
      ApplicationService.current.startApp(slot.key);
      return;
    }

    final ShellWindow? focused = windows.where((w) => w.focused).firstOrNull;
    if (windows.length == 1) {
      // Clicking the focused app minimizes it, anything else brings it up.
      if (focused != null) {
        focused.minimize();
      } else {
        windows.first.activate();
      }
      return;
    }

    // Several windows: cycle through them, most recently used first.
    final List<ShellWindow> byRecency = WindowManagerService
        .current.windowsByRecency
        .where(windows.contains)
        .toList();
    if (focused == null) {
      byRecency.first.activate();
    } else {
      final int next = (byRecency.indexOf(focused) + 1) % byRecency.length;
      byRecency[next].activate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CustomizationService customization = CustomizationService.current;
    final bool running = slot.running;
    final bool focused = slot.windows.any((w) => w.focused);

    // Drawn at 36 and scaled into the 30 pixels the button has inside its
    // padding: a glyph (the fallback icons) laid out wider than its box
    // would otherwise spill out to the right instead of staying centered.
    final Widget icon = SizedBox.square(
      dimension: 30,
      child: FittedBox(
        child: slot.entry?.icon != null
            ? AutoVisualResource(resource: slot.entry!.icon!.main, size: 36)
            : running
                ? WindowIcon(window: slot.windows.first, size: 36)
                : const Icon(Icons.apps_rounded, size: 36),
      ),
    );

    final WindowManagerService wm = WindowManagerService.current;
    final DeskState desks = wm.desks.value;
    // The window the desktop actions apply to: the slot's most recent one.
    final ShellWindow? recent =
        wm.windowsByRecency.where(slot.windows.contains).firstOrNull;

    final Animation<double> appear = CurvedAnimation(
      parent: _appear,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return IgnorePointer(
      ignoring: widget.leaving,
      child: SizeTransition(
        axis: Axis.horizontal,
        sizeFactor: CurvedAnimation(
          parent: _appear,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInOutCubic,
        ),
        child: FadeTransition(
          opacity: _appear,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.4, end: 1).animate(appear),
            child: _item(context, theme, customization, running, focused,
                icon, wm, desks, recent),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    ThemeData theme,
    CustomizationService customization,
    bool running,
    bool focused,
    Widget icon,
    WindowManagerService wm,
    DeskState desks,
    ShellWindow? recent,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
      child: TaskbarGeometryReporter(
        windowIds: [
          if (!widget.leaving)
            for (final ShellWindow w in slot.windows) w.id,
        ],
        child: SizedBox(
          height: 44,
          width: 42,
          child: Tooltip(
            message: _label(context),
            waitDuration: const Duration(milliseconds: 600),
            child: ContextMenu(
              entries: [
                ContextMenuItem(
                  leading: const Icon(Icons.info_outline_rounded),
                  child: Text(_label(context)),
                  onTap: () {},
                ),
                if (slot.entry != null)
                  ContextMenuItem(
                    leading: const Icon(Icons.add_rounded),
                    child: const Text("New Window"),
                    onTap: () => ApplicationService.current.startApp(slot.key),
                  ),
                if (slot.entry != null)
                  ContextMenuItem(
                    leading: const Icon(Icons.push_pin_outlined),
                    child: Text(
                      customization.pinnedApps.contains(slot.key)
                          ? "Unpin from Taskbar"
                          : "Pin to Taskbar",
                    ),
                    onTap: () => customization.togglePinnedApp(slot.key),
                  ),
                if (recent != null && wm.managesSessionWindows)
                  SubmenuMenuItem(
                    leading: const Icon(Icons.view_carousel_outlined),
                    child: const Text("Move to Desktop"),
                    menuChildren: [
                      for (int d = 0; d < desks.count; d++)
                        ContextMenuItem(
                          enabled: wm.deskOf(recent) != d,
                          leading: Icon(
                            wm.deskOf(recent) == d
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                          ),
                          child: Text("Desktop ${d + 1}"),
                          onTap: () => wm.moveWindowToDesk(recent, d),
                        ),
                      ContextMenuItem(
                        leading: const Icon(Icons.add_rounded),
                        child: const Text("New Desktop"),
                        onTap: () {
                          wm.addDesk();
                          wm.moveWindowToDesk(recent, desks.count);
                        },
                      ),
                    ],
                  ),
                if (running)
                  ContextMenuItem(
                    leading: const Icon(Icons.close_outlined),
                    child: Text(
                      slot.windows.length > 1
                          ? "Close All Windows"
                          : "Close Window",
                    ),
                    onTap: () {
                      for (final ShellWindow w in slot.windows) {
                        w.close();
                      }
                    },
                  ),
              ],
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: focused
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.14)
                      : _hovering
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.07)
                          : Colors.transparent,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onHover: (value) => setState(() => _hovering = value),
                    onTapDown: (_) => setState(() => _pressed = true),
                    onTapCancel: () => setState(() => _pressed = false),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _pressed = false);
                      _onTap();
                    },
                    child: Stack(
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6.0, 5, 6, 7),
                            child: AnimatedBuilder(
                              animation: _bounce,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(
                                  0,
                                  -7 * math.sin(math.pi * _bounce.value).abs(),
                                ),
                                child: child,
                              ),
                              child: AnimatedScale(
                                scale: _pressed
                                    ? 0.86
                                    : _hovering
                                        ? 1.08
                                        : 1,
                                duration: const Duration(milliseconds: 160),
                                curve: _pressed
                                    ? Curves.easeOut
                                    : Curves.easeOutBack,
                                child: icon,
                              ),
                            ),
                          ),
                        ),
                        // A short dash for a running app that stretches
                        // into an accent pill when it has focus.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 1,
                          height: 3,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: !running
                                  ? 0
                                  : focused
                                      ? 18
                                      : _hovering
                                          ? 10
                                          : 6,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(1.5),
                                color: focused
                                    ? theme.colorScheme.secondary
                                    : theme.colorScheme.onSurface.withValues(
                                        alpha: running ? 0.5 : 0,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
