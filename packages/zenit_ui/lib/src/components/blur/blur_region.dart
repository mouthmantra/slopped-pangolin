import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A rounded rectangle behind which the compositor blurs, in the logical
/// coordinates of a view.
@immutable
class BlurRect {
  const BlurRect(
    this.rect, {
    this.radius = BorderRadius.zero,
    this.opacity = 1,
  });

  final Rect rect;

  /// Corner radii (horizontal ones are used).
  final BorderRadius radius;

  /// Opacity of the blur, following the widget's (e.g. while fading in).
  final double opacity;

  /// `[x, y, width, height, top left, top right, bottom right, bottom left
  /// radius, opacity * 10000]`.
  List<int> encode() => [
        rect.left.floor(),
        rect.top.floor(),
        rect.width.ceil(),
        rect.height.ceil(),
        radius.topLeft.x.round(),
        radius.topRight.x.round(),
        radius.bottomRight.x.round(),
        radius.bottomLeft.x.round(),
        (opacity.clamp(0.0, 1.0) * 10000).round(),
      ];

  @override
  bool operator ==(Object other) =>
      other is BlurRect &&
      listEquals(other.encode(), encode());

  @override
  int get hashCode => Object.hashAll(encode());
}

/// Frosted glass: the compositor (river with river-blur-v1) blurs what is
/// behind [BlurRegion]s. Applications plug in [sink] and set [available].
abstract final class ZenitBlur {
  /// Whether the compositor blurs behind regions.
  static final ValueNotifier<bool> available = ValueNotifier(false);

  /// Whether the user wants blur and transparency (visual effects setting).
  static final ValueNotifier<bool> effects = ValueNotifier(true);

  /// Changes when [active] may have changed.
  static final Listenable state = Listenable.merge([available, effects]);

  /// Whether translucent, blurred surfaces should be drawn.
  static bool get active => available.value && effects.value;

  /// Opacity of the fill of frosted surfaces over the blur.
  static const double fillOpacity = 0.8;

  /// Sends the blurred regions of a view to the platform.
  static Future<void> Function(int viewId, List<BlurRect> regions)? sink;

  static final Set<RenderBlurRegion> _regions = {};
  static final Map<int, List<BlurRect>> _sent = {};
  static bool _frameCallback = false;
  static bool _flushScheduled = false;

  static void _add(RenderBlurRegion region) {
    _regions.add(region);
    if (!_frameCallback) {
      _frameCallback = true;
      // Ancestors animate opacity and transforms without repainting their
      // children: measure the regions again after every frame.
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (_regions.isNotEmpty || _sent.values.any((r) => r.isNotEmpty)) {
          _scheduleFlush();
        }
      });
    }
    _scheduleFlush(visualUpdate: true);
  }

  static void _remove(RenderBlurRegion region) {
    _regions.remove(region);
    _scheduleFlush(visualUpdate: true);
  }

  static void _scheduleFlush({bool visualUpdate = false}) {
    if (!_flushScheduled) {
      _flushScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _flush());
    }
    if (visualUpdate) SchedulerBinding.instance.ensureVisualUpdate();
  }

  static void _flush() {
    _flushScheduled = false;
    final Future<void> Function(int, List<BlurRect>)? sink = ZenitBlur.sink;
    if (sink == null) return;

    final Map<int, List<BlurRect>> byView = {};
    if (active) {
      for (final RenderBlurRegion region in _regions) {
        final (int, BlurRect)? measured = region.measure();
        if (measured == null) continue;
        byView.putIfAbsent(measured.$1, () => []).add(measured.$2);
      }
    }
    for (final int view in {..._sent.keys, ...byView.keys}) {
      final List<BlurRect> regions = byView[view] ?? const [];
      if (listEquals(_sent[view], regions)) continue;
      _sent[view] = regions;
      unawaited(sink(view, regions));
    }
  }
}

/// Asks the compositor to blur what is behind its child (or behind the
/// enclosing panel, see [BlurRegion.ancestor]), when [ZenitBlur.active].
/// Draw something translucent on top for frosted glass.
class BlurRegion extends SingleChildRenderObjectWidget {
  const BlurRegion({
    this.borderRadius = BorderRadius.zero,
    this.stadium = false,
    this.enabled = true,
    super.child,
    super.key,
  }) : ancestor = false;

  /// Blurs behind the nearest enclosing physical shape (e.g. the Material of
  /// a menu panel this widget is put in) rather than behind itself.
  const BlurRegion.ancestor({
    this.borderRadius = BorderRadius.zero,
    this.enabled = true,
    super.key,
  })  : ancestor = true,
        stadium = false,
        super(child: null);

  final BorderRadius borderRadius;

  /// Fully rounded ends, whatever the size.
  final bool stadium;
  final bool ancestor;
  final bool enabled;

  @override
  RenderBlurRegion createRenderObject(BuildContext context) => RenderBlurRegion(
        borderRadius: borderRadius,
        stadium: stadium,
        ancestor: ancestor,
        enabled: enabled,
      );

  @override
  void updateRenderObject(BuildContext context, RenderBlurRegion renderObject) {
    renderObject
      ..borderRadius = borderRadius
      ..stadium = stadium
      ..ancestor = ancestor
      ..enabled = enabled;
  }
}

class RenderBlurRegion extends RenderProxyBox {
  RenderBlurRegion({
    required BorderRadius borderRadius,
    required bool stadium,
    required bool ancestor,
    required bool enabled,
  })  : _borderRadius = borderRadius,
        _stadium = stadium,
        _ancestor = ancestor,
        _enabled = enabled;

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    ZenitBlur._scheduleFlush(visualUpdate: true);
  }

  bool _stadium;
  set stadium(bool value) {
    if (value == _stadium) return;
    _stadium = value;
    ZenitBlur._scheduleFlush(visualUpdate: true);
  }

  bool _ancestor;
  set ancestor(bool value) {
    if (value == _ancestor) return;
    _ancestor = value;
    ZenitBlur._scheduleFlush(visualUpdate: true);
  }

  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (!attached) return;
    value ? ZenitBlur._add(this) : ZenitBlur._remove(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_enabled) ZenitBlur._add(this);
  }

  @override
  void detach() {
    ZenitBlur._remove(this);
    super.detach();
  }

  /// The view and the region, as currently drawn: after transforms (e.g. a
  /// popup scaling in) and with the opacity of every ancestor.
  (int, BlurRect)? measure() {
    if (!attached) return null;
    RenderBox? target = this;
    if (_ancestor) {
      target = null;
      RenderObject? node = parent;
      while (node != null) {
        if (node is RenderPhysicalShape || node is RenderPhysicalModel) {
          target = node as RenderBox;
          break;
        }
        node = node.parent;
      }
    }
    if (target == null || !target.hasSize || target.size.isEmpty) return null;

    double opacity = 1;
    RenderObject node = this;
    while (node.parent != null) {
      final RenderObject? parent = node.parent;
      if (parent is RenderOpacity) opacity *= parent.opacity;
      if (parent is RenderAnimatedOpacity) opacity *= parent.opacity.value;
      if (parent is RenderView) break;
      node = parent!;
    }
    final RenderObject? view = node.parent;
    if (view is! RenderView || opacity <= 0.01) return null;

    final Matrix4 transform = target.getTransformTo(node);
    final Rect rect =
        MatrixUtils.transformRect(transform, Offset.zero & target.size);
    final double scale = transform.getMaxScaleOnAxis();
    final BorderRadius radius = _stadium
        ? BorderRadius.circular(target.size.shortestSide / 2)
        : _borderRadius;
    return (
      view.flutterView.viewId,
      BlurRect(rect, radius: radius * scale, opacity: opacity),
    );
  }
}
