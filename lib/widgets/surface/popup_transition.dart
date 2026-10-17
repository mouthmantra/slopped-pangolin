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

import 'dart:io';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

/// Opens and closes a popup of the shell (quick settings, launcher, menus).
///
/// In a river session river runs the animation at the refresh rate of the
/// outputs (Flutter on Linux draws at most 60 frames per second): Flutter
/// draws the popup once, in place, and river shows it growing and fading in
/// (and the reverse when it closes), blur included. Elsewhere Flutter
/// animates it with [animation].
class PopupTransition extends StatefulWidget {
  const PopupTransition({
    required this.animation,
    required this.showing,
    required this.child,
    this.alignment = Alignment.bottomCenter,
    this.margin = const EdgeInsets.all(24),
    super.key,
  });

  /// The popup's own animation (0 hidden, 1 shown), used when river doesn't
  /// animate it.
  final Animation<double> animation;

  /// Whether the popup is open (or opening).
  final bool showing;

  /// Point of the popup it grows from (towards what opened it).
  final Alignment alignment;

  /// Room around the popup that is animated with it (its shadow), clear of
  /// other things on the surface.
  final EdgeInsets margin;

  final Widget child;

  /// PANGOLIN_ANIMATION_SCALE slows popup animations down (e.g. 10), to
  /// look at them closely.
  static final double _timeScale = (double.tryParse(
            Platform.environment["PANGOLIN_ANIMATION_SCALE"] ?? "",
          ) ??
          1)
      .clamp(0.1, 50.0);

  static Duration get openDuration =>
      const Duration(milliseconds: 240) * _timeScale;
  static Duration get closeDuration =>
      const Duration(milliseconds: 150) * _timeScale;

  /// Material 3 emphasized decelerate / accelerate.
  static const Cubic openCurve = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Cubic closeCurve = Cubic(0.3, 0.0, 0.8, 0.15);

  static const double openScale = 0.92;
  static const double closeScale = 0.95;

  @override
  State<PopupTransition> createState() => _PopupTransitionState();
}

class _PopupTransitionState extends State<PopupTransition> {
  final GlobalKey _key = GlobalKey();

  /// Drawn in place (river animates it, or it is fully shown).
  bool _visible = false;
  bool _revealScheduled = false;

  bool get _river =>
      PangolinSession.isSession &&
      PangolinSession.partAnimations.value &&
      (PreferencesService.current.get<bool>(SessionSetting.windowAnimations.key) ??
          SessionSetting.windowAnimations.defaultValue);

  @override
  void initState() {
    super.initState();
    if (widget.showing) _scheduleReveal();
  }

  @override
  void didUpdateWidget(PopupTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showing && !oldWidget.showing) {
      _scheduleReveal();
    } else if (!widget.showing && oldWidget.showing) {
      _conceal();
    }
  }

  /// Where the popup is drawn (with its margin), its view and the point it
  /// grows from.
  (int, Rect, Offset)? _measure() {
    final RenderObject? object = _key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    final int? view = View.maybeOf(_key.currentContext!)?.viewId;
    if (view == null) return null;
    final Rect rect = object.localToGlobal(Offset.zero) & object.size;
    final Offset anchor = widget.alignment.withinRect(rect);
    return (view, widget.margin.inflateRect(rect), anchor);
  }

  /// The offset that makes scaling around the center of [rect] look like
  /// scaling around [anchor].
  static Offset _shift(Rect rect, Offset anchor, double scale) =>
      (anchor - rect.center) * (1 - scale);

  void _scheduleReveal() {
    _visible = false;
    if (!_river) {
      _visible = true;
      return;
    }
    if (_revealScheduled) return;
    _revealScheduled = true;
    // The first frame lays the popup out without drawing it, then river is
    // told to animate it before the frame drawing it is committed.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !widget.showing) {
        _revealScheduled = false;
        return;
      }
      final (int, Rect, Offset)? measured = _measure();
      if (measured != null) {
        final (int view, Rect rect, Offset anchor) = measured;
        const double scale = PopupTransition.openScale;
        // river hides the part before the frame drawing the popup arrives.
        await PangolinSession.animatePart(
          view: view,
          reveal: true,
          rect: rect,
          offset: _shift(rect, anchor, scale),
          scale: scale,
          duration: PopupTransition.openDuration,
          curve: PopupTransition.openCurve,
        );
      }
      _revealScheduled = false;
      if (mounted && widget.showing) setState(() => _visible = true);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _conceal() {
    if (!_visible) return;
    final (int, Rect, Offset)? measured = _river ? _measure() : null;
    if (measured == null) {
      _visible = false;
      return;
    }
    final (int view, Rect rect, Offset anchor) = measured;
    const double scale = PopupTransition.closeScale;
    // river copies the popup as shown now: it is only taken away once river
    // has the request.
    PangolinSession.animatePart(
      view: view,
      reveal: false,
      rect: rect,
      offset: _shift(rect, anchor, scale),
      scale: scale,
      duration: PopupTransition.closeDuration,
      curve: PopupTransition.closeCurve,
    ).whenComplete(() {
      if (mounted && !widget.showing) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = KeyedSubtree(key: _key, child: widget.child);
    if (!_river) {
      return FadeTransition(
        opacity: widget.animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: PopupTransition.openScale, end: 1)
              .animate(widget.animation),
          alignment: widget.alignment,
          child: child,
        ),
      );
    }
    return IgnorePointer(
      ignoring: !widget.showing,
      child: Opacity(opacity: _visible ? 1 : 0, child: child),
    );
  }
}
