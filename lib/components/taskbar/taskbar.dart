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
  /// the session appears smoothly after the login screen.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 1.1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    // Let the wallpaper settle first.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _entrance.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: PangolinSession.taskbarHeight,
      // The input region stays put while the bar slides in underneath it.
      child: InputRegion(
        child: SlideTransition(
          position: _slide,
          child: _frosted(
            context,
            service.enableEffects,
            SurfaceLayer(
              // Frosted glass over the wallpaper like in the dahliaOS design
              // (opaque with visual effects off).
              color: Theme.of(context).colorScheme.background.withValues(
                    alpha: !service.enableEffects
                        ? 1
                        : ZenitBlur.fillOpacity,
                  ),
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: SizedBox.expand(
                child: Material(
                  type: MaterialType.transparency,
                  child: ListenableBuilder(
                    listenable: PreferencesService.current,
                    builder: (context, _) => _layout(
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
