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
import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:logging/logging.dart';

/// Blurred copies of wallpapers, made once per wallpaper from a small decode
/// of it: drawing one costs no more than drawing a small image, whatever the
/// output resolution, unlike a live blur of a 5K surface on every frame.
abstract final class BlurredWallpaper {
  static final Logger _logger = Logger("BlurredWallpaper");
  static final Map<ImageResource, Future<ui.Image?>> _cache = {};

  /// Width of the copy that is blurred; stretched over the screen it reads
  /// as a strong blur.
  static const int _width = 320;
  static const double _sigma = 6;

  static Future<ui.Image?> of(ImageResource resource) {
    final Future<ui.Image?>? cached = _cache[resource];
    if (cached != null) return cached;
    // Only the current wallpaper (and the previous one, while switching).
    while (_cache.length > 1) {
      final ImageResource oldest = _cache.keys.first;
      unawaited(_cache.remove(oldest)!.then((image) => image?.dispose()));
    }
    return _cache[resource] = _make(resource);
  }

  static ImageProvider? providerFor(ImageResource resource) =>
      _provider(resource);

  /// Decodes [provider] once.
  static Future<ui.Image> load(ImageProvider provider) => _load(provider);

  static ImageProvider? _provider(ImageResource resource) {
    switch (resource.subtype) {
      case ImageResourceType.file:
        return FileImage(File(resource.resolve()));
      case ImageResourceType.dahlia:
        return AssetImage(resource.resolve());
      case ImageResourceType.network:
        return NetworkImage(resource.resolve());
    }
  }

  static Future<ui.Image?> _make(ImageResource resource) async {
    final ImageProvider? base = _provider(resource);
    if (base == null) return null;
    try {
      final ui.Image small = await _load(
        ResizeImage(base, width: _width, policy: ResizeImagePolicy.fit),
      );
      final Rect bounds =
          Offset.zero & Size(small.width.toDouble(), small.height.toDouble());
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..clipRect(bounds)
        ..drawImage(
          small,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: _sigma,
              sigmaY: _sigma,
              tileMode: TileMode.clamp,
            ),
        );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image blurred = await picture.toImage(small.width, small.height);
      picture.dispose();
      small.dispose();
      return blurred;
    } catch (e) {
      _logger.info("Couldn't blur wallpaper $resource: $e");
      return null;
    }
  }

  static Future<ui.Image> _load(ImageProvider provider) {
    final Completer<ui.Image> completer = Completer();
    final ImageStream stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image.clone());
        info.dispose();
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}

/// The blurred wallpaper, as it lies behind this widget on the screen: a
/// translucent surface drawn on top of it looks frosted (the shell is its own
/// surface, a [BackdropFilter] would have nothing to blur).
class WallpaperBlur extends StatefulWidget {
  const WallpaperBlur({this.opacity = 1, super.key});

  /// Drawn straight with this opacity: cheaper than an [Opacity] around it,
  /// which renders the whole area to a layer first.
  final double opacity;

  @override
  State<WallpaperBlur> createState() => _WallpaperBlurState();
}

class _WallpaperBlurState extends State<WallpaperBlur>
    with StateServiceListener<CustomizationService, WallpaperBlur> {
  ImageResource? _resource;
  ui.Image? _image;

  void _load(ImageResource resource) {
    if (resource == _resource) return;
    _resource = resource;
    BlurredWallpaper.of(resource).then((image) {
      if (!mounted || _resource != resource) return;
      setState(() => _image = image);
    });
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    _load(service.wallpaper);
    return _WallpaperBlurPainter(
      image: _image,
      screen: MediaQuery.sizeOf(context),
      opacity: widget.opacity,
    );
  }
}

class _WallpaperBlurPainter extends LeafRenderObjectWidget {
  const _WallpaperBlurPainter({
    required this.image,
    required this.screen,
    required this.opacity,
  });

  final ui.Image? image;
  final Size screen;
  final double opacity;

  @override
  _RenderWallpaperBlur createRenderObject(BuildContext context) =>
      _RenderWallpaperBlur(image, screen, opacity);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWallpaperBlur renderObject,
  ) {
    renderObject
      ..image = image
      ..screen = screen
      ..opacity = opacity;
  }
}

class _RenderWallpaperBlur extends RenderBox {
  _RenderWallpaperBlur(this._image, this._screen, this._opacity);

  double _opacity;
  set opacity(double value) {
    if (value == _opacity) return;
    _opacity = value;
    markNeedsPaint();
  }

  ui.Image? _image;
  set image(ui.Image? value) {
    if (value == _image) return;
    _image = value;
    markNeedsPaint();
  }

  Size _screen;
  set screen(Size value) {
    if (value == _screen) return;
    _screen = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final ui.Image? image = _image;
    if (image == null || _screen.isEmpty || _opacity <= 0) return;

    // Where the screen is relative to this box, following any transform
    // (e.g. the taskbar sliding in).
    final Offset origin = localToGlobal(Offset.zero);
    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());
    // Fitted like the wallpaper itself (BoxFit.cover, centered).
    final FittedSizes fitted = applyBoxFit(BoxFit.cover, imageSize, _screen);
    final Rect source =
        Alignment.center.inscribe(fitted.source, Offset.zero & imageSize);
    final Rect destination = (Offset.zero & _screen).shift(offset - origin);

    context.canvas
      ..save()
      ..clipRect(offset & size)
      ..drawImageRect(
        image,
        source,
        destination,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, _opacity.clamp(0.0, 1.0)),
      )
      ..restore();
  }
}
