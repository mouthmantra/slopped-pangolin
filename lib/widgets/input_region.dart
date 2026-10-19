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

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pangolin/services/session.dart';

/// Decides which parts of the transparent shell surface receive input.
///
/// In session mode the shell (taskbar, launcher, notifications, ...) is a
/// full-screen transparent layer surface above application windows. Pointer
/// events must only be captured where the shell actually draws something,
/// otherwise the windows below would be unreachable. Widgets declare their
/// interactive area with [InputRegion], while modal UI (open overlays, menus,
/// dialogs) claims the whole surface and keyboard focus through [claim].
class ShellInputRegion {
  ShellInputRegion._();

  static final ShellInputRegion instance = ShellInputRegion._();

  final Map<Object, Rect> _rects = {};
  final Set<Object> _modalOwners = {};
  bool _scheduled = false;

  List<Rect>? _lastRects;
  bool? _lastModal;

  /// Number of owners currently holding the whole surface.
  bool get isModal => _modalOwners.isNotEmpty;

  /// [isModal] as of the last frame (an overlay or a menu is open), for
  /// widgets to follow.
  final ValueNotifier<bool> modal = ValueNotifier(false);

  void setRect(Object owner, Rect? rect) {
    if (rect == null || rect.isEmpty) {
      if (_rects.remove(owner) != null) _schedule();
      return;
    }
    if (_rects[owner] == rect) return;
    _rects[owner] = rect;
    _schedule();
  }

  /// While claimed, the whole shell surface receives pointer input and the
  /// keyboard (e.g. an open launcher or context menu).
  void claim(Object owner, bool claimed) {
    final bool changed =
        claimed ? _modalOwners.add(owner) : _modalOwners.remove(owner);
    if (changed) _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // Wait until the frame is done so rects reported during paint are final.
    SchedulerBinding.instance.addPostFrameCallback((_) => _flush());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _flush() {
    _scheduled = false;
    final bool modal = isModal;

    if (modal != _lastModal) {
      _lastModal = modal;
      this.modal.value = modal;
      unawaited(
        PangolinSession.setShellKeyboardMode(
          modal ? KeyboardMode.exclusive : KeyboardMode.none,
        ),
      );
    }

    // null means "the whole surface".
    final List<Rect>? region = modal ? null : _rects.values.toList();
    if (_hasSent && _sameRegion(region, _lastRects)) return;
    _hasSent = true;
    _lastRects = region;
    unawaited(PangolinSession.setShellInputRegion(region));
  }

  bool _hasSent = false;

  static bool _sameRegion(List<Rect>? a, List<Rect>? b) {
    if (a == null || b == null) return a == b;
    return const ListEquality<Rect>().equals(a, b);
  }
}

/// Marks its child's painted bounds as an interactive part of the shell
/// surface (see [ShellInputRegion]).
class InputRegion extends SingleChildRenderObjectWidget {
  const InputRegion({super.key, this.enabled = true, super.child});

  final bool enabled;

  @override
  RenderInputRegion createRenderObject(BuildContext context) =>
      RenderInputRegion(enabled: enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderInputRegion renderObject,
  ) {
    renderObject.enabled = enabled;
  }
}

class RenderInputRegion extends RenderProxyBox {
  RenderInputRegion({required bool enabled}) : _enabled = enabled;

  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    markNeedsPaint();
    if (!value) ShellInputRegion.instance.setRect(this, null);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_enabled || !hasSize) return;

    // Measure against the view's root box so the rect is in logical pixels
    // (the RenderView itself applies the device pixel ratio).
    RenderObject root = this;
    while (root.parent != null && root.parent is! RenderView) {
      root = root.parent!;
    }
    final Rect rect = MatrixUtils.transformRect(
      getTransformTo(root),
      Offset.zero & size,
    );
    ShellInputRegion.instance.setRect(this, rect);
  }

  @override
  void detach() {
    ShellInputRegion.instance.setRect(this, null);
    super.detach();
  }
}
