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
import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/services/tray/icon_lookup.dart';
import 'package:pangolin/services/tray/item.dart';
import 'package:pangolin/services/tray/pixmap.dart';
import 'package:pangolin/widgets/resource/image/image.dart';

/// The icon of a tray item, or of an entry of its menu: the named icon if
/// it can be found (in the item's IconThemePath or the icon theme), else
/// the pixmap closest to the size it is shown at.
class TrayIconImage extends StatelessWidget {
  final TrayIconSource source;
  final String? themePath;
  final double size;

  /// Scale applied on top of the device pixel ratio by an ancestor (the
  /// taskbar is laid out at one height and scaled to the chosen one).
  final double extraScale;

  /// Drawn over the bottom right corner (OverlayIconName/Pixmap).
  final TrayIconSource overlay;

  /// Shown when the icon can't be found: a generic one by default.
  final Widget? fallback;

  const TrayIconImage({
    required this.source,
    required this.size,
    this.themePath,
    this.extraScale = 1,
    this.overlay = const TrayIconSource(),
    this.fallback,
    super.key,
  });

  /// The icon a tray item shows now.
  factory TrayIconImage.item(
    TrayItem item, {
    required double size,
    double extraScale = 1,
    Key? key,
  }) =>
      TrayIconImage(
        key: key,
        source: item.currentIcon,
        themePath: item.iconThemePath,
        overlay: item.overlayIcon,
        size: size,
        extraScale: extraScale,
      );

  @override
  Widget build(BuildContext context) {
    final Widget icon = _TrayIconLayer(
      source: source,
      themePath: themePath,
      size: size,
      extraScale: extraScale,
      fallback: fallback ?? Icon(Icons.apps_rounded, size: size * 0.9),
    );
    if (overlay.isEmpty) return icon;
    final double overlaySize = (size * 0.55).roundToDouble();
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: icon),
          Positioned(
            right: -2,
            bottom: -2,
            child: _TrayIconLayer(
              source: overlay,
              themePath: themePath,
              size: overlaySize,
              extraScale: extraScale,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayIconLayer extends StatefulWidget {
  final TrayIconSource source;
  final String? themePath;
  final double size;
  final double extraScale;
  final Widget fallback;

  const _TrayIconLayer({
    required this.source,
    required this.themePath,
    required this.size,
    required this.extraScale,
    required this.fallback,
  });

  @override
  State<_TrayIconLayer> createState() => _TrayIconLayerState();
}

class _TrayIconLayerState extends State<_TrayIconLayer> {
  /// What [_path] was looked up for.
  String? _lookupKey;
  String? _path;
  bool _lookingUp = false;

  TrayPixmap? _pixmap;
  ui.Image? _image;

  int get _pixels {
    final double ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return (widget.size * ratio * widget.extraScale).round();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant _TrayIconLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.themePath != widget.themePath ||
        oldWidget.size != widget.size ||
        oldWidget.extraScale != widget.extraScale) {
      _update();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _update() {
    final int pixels = _pixels;
    final String? name = widget.source.name;

    if (name == null) {
      _lookupKey = null;
      _path = null;
      _lookingUp = false;
    } else {
      final String key = "$name\n${widget.themePath}\n$pixels";
      if (key != _lookupKey) {
        _lookupKey = key;
        if (TrayIconLookup.isCached(name, widget.themePath, pixels)) {
          _path = TrayIconLookup.cached(name, widget.themePath, pixels);
          _lookingUp = false;
        } else {
          _lookingUp = true;
          unawaited(_lookUp(key, name, widget.themePath, pixels));
        }
      }
    }

    final TrayPixmap? pixmap = pickTrayPixmap(
      widget.source.pixmaps,
      pixels.toDouble(),
    );
    if (pixmap != _pixmap) {
      _pixmap = pixmap;
      if (pixmap == null) {
        _image?.dispose();
        _image = null;
      } else {
        unawaited(_decode(pixmap));
      }
    }
  }

  Future<void> _lookUp(
    String key,
    String name,
    String? themePath,
    int pixels,
  ) async {
    final String? path = await TrayIconLookup.resolve(name, themePath, pixels);
    if (!mounted || key != _lookupKey) return;
    setState(() {
      _path = path;
      _lookingUp = false;
    });
  }

  Future<void> _decode(TrayPixmap pixmap) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromPixels(
      pixmap.toRgba(),
      pixmap.width,
      pixmap.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final ui.Image image = await completer.future;
    if (!mounted || _pixmap != pixmap) {
      image.dispose();
      return;
    }
    // RawImage keeps a clone of what it paints.
    _image?.dispose();
    setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    final String? path = _path;
    final String? name = widget.source.name;

    if (path != null) {
      Widget image = ResourceImage(
        resource: ImageResource(type: ImageResourceType.file, value: path),
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
      // Symbolic icons take the color of the text around them, as in GTK.
      if (name != null && name.endsWith("-symbolic")) {
        final Color? color = IconTheme.of(context).color;
        if (color != null) {
          image = ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: image,
          );
        }
      }
      return SizedBox.square(dimension: size, child: image);
    }

    final ui.Image? image = _image;
    if (image != null) {
      return RawImage(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    // Still looking, with nothing else to show meanwhile.
    if (_lookingUp || _pixmap != null) return SizedBox.square(dimension: size);
    return SizedBox.square(dimension: size, child: Center(child: widget.fallback));
  }
}
