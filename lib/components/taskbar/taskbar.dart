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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:pangolin/widgets/input_region.dart';
import 'package:pangolin/widgets/separated_flex.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';
import 'package:zenit_ui/zenit_ui.dart';

class Taskbar extends StatefulWidget {
  final List<Widget> leading;
  final List<Widget> center;
  final List<Widget> trailing;
  final bool centerRelativeToScreen;

  const Taskbar({
    this.leading = const [],
    this.center = const [],
    this.trailing = const [],
    this.centerRelativeToScreen = false,
    super.key,
  });

  @override
  State<Taskbar> createState() => _TaskbarState();
}

class _TaskbarState extends State<Taskbar>
    with
        SingleTickerProviderStateMixin,
        StateServiceListener<CustomizationService, Taskbar> {
  /// Brings the taskbar into view from the bottom when the shell starts, so
  /// the session appears smoothly after the login screen; with autohide it
  /// also slides the bar away and back.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 1.1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  static const Duration _autohideSlide = Duration(milliseconds: 220);

  bool _started = false;
  bool _autohide = false;
  bool _hovered = false;

  /// Whether the bar is out (it takes input); with autohide it hides a
  /// moment after the pointer leaves it.
  bool _shown = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _autohide = _readAutohide();
    _shown = !_autohide;
    PreferencesService.current.addListener(_onPreferences);
    ShellInputRegion.instance.modal.addListener(_sync);
    // Let the wallpaper settle first.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _started = true;
      if (_shown) _entrance.forward();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    PreferencesService.current.removeListener(_onPreferences);
    ShellInputRegion.instance.modal.removeListener(_sync);
    _entrance.dispose();
    super.dispose();
  }

  static bool _readAutohide() =>
      PreferencesService.current
          .get<bool>(SessionSetting.taskbarAutohide.key) ??
      SessionSetting.taskbarAutohide.defaultValue;

  void _onPreferences() {
    // Size and alignment.
    setState(() {});
    final bool autohide = _readAutohide();
    if (autohide == _autohide) return;
    _autohide = autohide;
    _sync();
  }

  void _setHovered(bool hovered) {
    _hovered = hovered;
    _sync();
  }

  /// Out while autohide is off, the pointer is on it, or an overlay or a
  /// menu (opened from it, usually) is open.
  void _sync() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_autohide || _hovered || ShellInputRegion.instance.modal.value) {
      if (!_shown) setState(() => _shown = true);
      if (_started) _entrance.animateTo(1, duration: _autohideSlide);
    } else if (_shown) {
      _hideTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        // Input goes to the windows below once the bar is gone (not
        // completed when it comes back meanwhile).
        _entrance.animateBack(0, duration: _autohideSlide).then((_) {
          if (mounted) setState(() => _shown = false);
        });
      });
    }
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    final double height = PangolinSession.taskbarHeight;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: height,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The input region stays put while the bar slides in underneath
            // it.
            InputRegion(
              enabled: _shown,
              child: SlideTransition(
                position: _slide,
                child: _frosted(
                  context,
                  service.enableEffects,
                  SurfaceLayer(
                    // Frosted glass over the wallpaper like in the dahliaOS
                    // design (opaque with visual effects off).
                    color: Theme.of(context).colorScheme.background.withValues(
                          alpha: !service.enableEffects
                              ? 1
                              : ZenitBlur.fillOpacity,
                        ),
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: SizedBox.expand(
                      child: Material(
                        type: MaterialType.transparency,
                        child: _scaled(
                          height,
                          _layout(
                            PreferencesService.current.get<String>(
                                  SessionSetting.taskbarAlignment.key,
                                ) ==
                                "left",
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Hidden: the bottom edge of the screen brings it back.
            if (!_shown)
              const Align(
                alignment: Alignment.bottomCenter,
                child: InputRegion(
                  child: SizedBox(height: 2, width: double.infinity),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The bar is laid out at the medium height and scaled to [height], so
  /// every size keeps its proportions.
  Widget _scaled(double height, Widget bar) {
    const double medium = 48;
    if (height == medium) return bar;
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        child: SizedBox(
          width: constraints.maxWidth * medium / height,
          height: medium,
          child: bar,
        ),
      ),
    );
  }

  /// The leading buttons on the left, the trailing ones on the right, and
  /// the app icons in the middle of the screen, or right after the leading
  /// buttons with [left] (Windows 11's left alignment).
  Widget _layout(bool left) {
    final bool screenCenter = widget.centerRelativeToScreen && !left;
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: [
              SeparatedFlex(
                axis: Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.center,
                separator: const SizedBox(width: 4),
                children: widget.leading,
              ),
              if (left) const SizedBox(width: 8),
              Expanded(
                child: screenCenter
                    ? const SizedBox.shrink()
                    : Row(
                        mainAxisAlignment: left
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: widget.center,
                      ),
              ),
              SeparatedFlex(
                axis: Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.center,
                separator: const SizedBox(width: 4),
                children: widget.trailing,
              ),
            ],
          ),
        ),
        if (screenCenter)
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.center,
            ),
          ),
      ],
    );
  }

  /// The bar over the blurred wallpaper when visual effects are on.
  Widget _frosted(BuildContext context, bool effects, Widget bar) {
    if (!effects) return bar;
    return ListenableBuilder(
      listenable: ZenitBlur.state,
      builder: (context, _) {
        // River blurs what is behind the bar; elsewhere fall back to a
        // blurred copy of the wallpaper.
        if (ZenitBlur.available.value) return BlurRegion(child: bar);
        return Stack(
          fit: StackFit.expand,
          children: [
            const WallpaperBlur(),
            bar,
          ],
        );
      },
    );
  }
}
