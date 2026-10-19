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

import 'package:flutter/material.dart';
import 'package:pangolin/services/hardware_controls.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';

enum OsdKind { volume, brightness }

/// The little pop-up confirming a volume or brightness change made with the
/// keyboard.
class Osd extends ChangeNotifier {
  Osd._();

  static final Osd instance = Osd._();

  OsdKind? _kind;
  OsdKind? get kind => _kind;
  bool get visible => _visible;
  bool _visible = false;
  Timer? _hide;

  void show(OsdKind kind) {
    _kind = kind;
    _visible = true;
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1500), () {
      _visible = false;
      notifyListeners();
    });
    notifyListeners();
  }
}

/// Shows [Osd] above the taskbar, never taking input.
class OsdLayer extends StatelessWidget {
  const OsdLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Osd.instance,
        builder: (context, _) {
          final Osd osd = Osd.instance;
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: PangolinSession.taskbarReserved + 24,
              ),
              child: AnimatedSlide(
                offset: osd.visible ? Offset.zero : const Offset(0, 0.4),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: osd.visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: osd.kind == null
                      ? const SizedBox.shrink()
                      : _OsdPanel(kind: osd.kind!),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OsdPanel extends StatelessWidget {
  const _OsdPanel({required this.kind});

  final OsdKind kind;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Listenable source = switch (kind) {
      OsdKind.volume => VolumeControl.instance,
      OsdKind.brightness => BrightnessControl.instance,
    };
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final (IconData icon, double value) = switch (kind) {
          OsdKind.volume => (
              VolumeControl.instance.muted || VolumeControl.instance.volume == 0
                  ? Icons.volume_off_rounded
                  : VolumeControl.instance.volume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              VolumeControl.instance.muted ? 0.0 : VolumeControl.instance.volume,
            ),
          OsdKind.brightness => (
              Icons.brightness_6_rounded,
              BrightnessControl.instance.brightness,
            ),
        };
        return SurfaceLayer(
          shape: const StadiumBorder(),
          width: 300,
          height: 56,
          dropShadow: true,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: value.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 120),
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 36,
                child: Text(
                  "${(value * 100).round()}",
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
