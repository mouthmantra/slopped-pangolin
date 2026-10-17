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

part of 'river.dart';

// Server side decorations: windows that ask for them (or don't mind) get a
// Pangolin title bar like the dahliaOS apps' own (Settings, Clock): the
// title in the middle, minimize, maximize and close on the right. It is a
// decoration surface of river-window-management drawn above the window's
// top edge; Flutter's canvas paints it into a shared memory buffer.

enum _DecorationButton { minimize, maximize, close }

/// Everything a title bar's pixels depend on.
@immutable
class _DecorationLook {
  const _DecorationLook({
    required this.width,
    required this.title,
    required this.focused,
    required this.tiled,
    required this.maximized,
    required this.hover,
    required this.pressed,
    required this.dark,
    required this.accent,
    required this.tint,
    required this.font,
    required this.translucent,
  });

  final int width;
  final String title;
  final bool focused;

  /// Square corners (maximized or snapped).
  final bool tiled;
  final bool maximized;
  final _DecorationButton? hover;
  final _DecorationButton? pressed;
  final bool dark;
  final int accent;
  final bool tint;
  final String font;

  /// Frosted: drawn see-through over river's blur.
  final bool translucent;

  @override
  bool operator ==(Object other) =>
      other is _DecorationLook &&
      other.translucent == translucent &&
      other.width == width &&
      other.title == title &&
      other.focused == focused &&
      other.tiled == tiled &&
      other.maximized == maximized &&
      other.hover == hover &&
      other.pressed == pressed &&
      other.dark == dark &&
      other.accent == accent &&
      other.tint == tint &&
      other.font == font;

  @override
  int get hashCode => Object.hash(
        width,
        title,
        focused,
        tiled,
        maximized,
        hover,
        pressed,
        dark,
        accent,
        tint,
        font,
        translucent,
      );
}

/// A rendered title bar waiting to be shown.
class _DecorationBuffer {
  _DecorationBuffer(this.look, this.buffer, this.pool);

  final _DecorationLook look;
  final WlBuffer buffer;
  final WlShmPool pool;

  void destroy() {
    buffer.destroy();
    pool.destroy();
  }
}

class _Decoration {
  _Decoration(this.window, this.surface, this.role);

  final RiverWindow window;
  final WlSurface surface;
  final RiverDecorationV1 role;

  /// Blur behind the title bar, and its regions as last set.
  RiverBlurV1? blur;
  List<int>? blurRegions;

  /// Below the window: its shadow, the ring its edges are grabbed in to
  /// resize it, and the corner cutouts rounding its bottom corners.
  WlSurface? shadowSurface;
  RiverDecorationV1? shadowRole;
  WpViewport? shadowViewport;
  RiverBlurV1? shadowBlur;
  _ShadowLook? shadowRendering;
  _ShadowBuffer? shadowReady;
  _ShadowBuffer? shadowAttached;

  /// Size and state the shadow surface was last set up for.
  (int, int, bool)? shadowGeometry;

  _DecorationLook? shown;
  _DecorationLook? rendering;
  _DecorationBuffer? ready;
  _DecorationBuffer? attached;
  bool hidden = false;

  _DecorationButton? hover;
  _DecorationButton? pressed;
  int lastPress = 0;

  void destroy() {
    ready?.destroy();
    ready = null;
    attached?.destroy();
    attached = null;
    blur?.destroy();
    role.destroy();
    surface.destroy();
    shadowReady?.destroy();
    shadowReady = null;
    shadowAttached?.destroy();
    shadowAttached = null;
    shadowBlur?.destroy();
    shadowViewport?.destroy();
    shadowRole?.destroy();
    shadowSurface?.destroy();
  }
}

/// Everything a shadow's pixels depend on.
@immutable
class _ShadowLook {
  const _ShadowLook({
    required this.width,
    required this.height,
    required this.focused,
    required this.factor,
  });

  /// The window with its title bar, in logical pixels.
  final int width;
  final int height;
  final bool focused;

  /// Buffer pixels per logical pixel (shadows are soft: drawn small and
  /// stretched when the compositor can).
  final double factor;

  @override
  bool operator ==(Object other) =>
      other is _ShadowLook &&
      other.width == width &&
      other.height == height &&
      other.focused == focused &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(width, height, focused, factor);
}

class _ShadowBuffer {
  _ShadowBuffer(this.look, this.buffer, this.pool);

  final _ShadowLook look;
  final WlBuffer buffer;
  final WlShmPool pool;

  void destroy() {
    buffer.destroy();
    pool.destroy();
  }
}

/// Paints the shadows of server side decorated windows, like the ones
/// libadwaita apps draw around themselves.
abstract final class _ShadowPainter {
  /// Room around the window for the shadow.
  static const int margin = 40;

  /// Where the edges are grabbed to resize, outside the window.
  static const int grab = 8;

  /// From the corners on along the edges, resizing takes both edges.
  static const double cornerGrab = 20;

  static Future<ui.Image> paint(_ShadowLook look) async {
    const double m = 40;
    final double width = look.width + 2 * m;
    final double height = look.height + 2 * m;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)..scale(look.factor);
    final RRect frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(m, m, look.width.toDouble(), look.height.toDouble()),
      const Radius.circular(_DecorationPainter.radius),
    );
    canvas
      ..drawRRect(
        frame.shift(const Offset(0, 1)),
        Paint()
          ..color = const Color(0x24000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      )
      ..drawRRect(
        frame.shift(Offset(0, look.focused ? 8 : 4)),
        Paint()
          ..color = Color(look.focused ? 0x52000000 : 0x2E000000)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            look.focused ? 13 : 8,
          ),
      )
      // Nothing under the window: its rounded corners show what's behind.
      ..drawRRect(frame, Paint()..blendMode = BlendMode.clear);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      math.max(1, (width * look.factor).ceil()),
      math.max(1, (height * look.factor).ceil()),
    );
    picture.dispose();
    return image;
  }
}

/// Paints title bars.
abstract final class _DecorationPainter {
  /// Height of the title bar, as the dahliaOS apps' own.
  static const double height = 48;
  static const double buttonSize = 32;
  static const double buttonGap = 4;
  static const double edgePadding = 8;
  static const double radius = 12;

  /// Buffers are drawn at twice the logical size: sharp on scaled outputs.
  static const int scale = 2;

  /// Where [button] is, in surface coordinates.
  static Rect buttonRect(int width, _DecorationButton button) {
    final int fromRight = switch (button) {
      _DecorationButton.close => 0,
      _DecorationButton.maximize => 1,
      _DecorationButton.minimize => 2,
    };
    final double right =
        width - edgePadding - fromRight * (buttonSize + buttonGap);
    return Rect.fromLTWH(
      right - buttonSize,
      (height - buttonSize) / 2,
      buttonSize,
      buttonSize,
    );
  }

  static _DecorationButton? buttonAt(int width, Offset position) {
    for (final _DecorationButton button in _DecorationButton.values) {
      if (buttonRect(width, button).inflate(2).contains(position)) {
        return button;
      }
    }
    return null;
  }

  static Future<ui.Image> paint(_DecorationLook look) async {
    final double width = look.width.toDouble();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)..scale(scale.toDouble());
    final Rect bounds = Rect.fromLTWH(0, 0, width, height);

    // Same colors as DahliaTitlebar.backgroundOf.
    Color background =
        look.dark ? const Color(0xFF2B2B2B) : const Color(0xFFEFEFEF);
    if (look.tint) {
      background = Color.alphaBlend(
        Color(look.accent).withValues(alpha: look.dark ? 0.16 : 0.09),
        background,
      );
    }
    // Frosted, as the shell's panels.
    if (look.translucent) background = background.withValues(alpha: 0.8);
    canvas.drawRRect(
      look.tiled
          ? RRect.fromRectAndRadius(bounds, Radius.zero)
          : RRect.fromRectAndCorners(
              bounds,
              topLeft: const Radius.circular(radius),
              topRight: const Radius.circular(radius),
            ),
      Paint()..color = background,
    );

    // Inactive windows dim the title bar's contents.
    final Color foreground = (look.dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
        .withValues(alpha: look.focused ? 0.9 : 0.5);

    const double buttonsWidth =
        3 * buttonSize + 2 * buttonGap + edgePadding;
    final double titleWidth = math.max(0, width - 2 * (buttonsWidth + 8));
    if (titleWidth > 0 && look.title.isNotEmpty) {
      final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          maxLines: 1,
          ellipsis: "…",
          fontFamily: look.font,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      )
        ..pushStyle(ui.TextStyle(color: foreground))
        ..addText(look.title);
      final ui.Paragraph paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: titleWidth));
      canvas.drawParagraph(
        paragraph,
        Offset((width - titleWidth) / 2, (height - paragraph.height) / 2),
      );
    }

    for (final _DecorationButton button in _DecorationButton.values) {
      // A paint per glyph: drawMaximize changes its paint's color.
      final Paint stroke = Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final Rect rect = buttonRect(look.width, button);
      final Offset center = rect.center;
      if (look.hover == button || look.pressed == button) {
        canvas.drawCircle(
          center,
          16,
          Paint()
            ..color = foreground.withValues(
              alpha: look.pressed == button ? 0.18 : 0.1,
            ),
        );
      }
      final Rect glyph = Rect.fromCenter(
        center: center,
        width: buttonSize * 0.3,
        height: buttonSize * 0.3,
      );
      switch (button) {
        case _DecorationButton.minimize:
          drawMinimize(canvas, glyph, stroke);
        case _DecorationButton.maximize:
          look.maximized
              ? drawRestore(canvas, glyph, stroke, foreground)
              : drawMaximize(canvas, glyph, stroke, foreground);
        case _DecorationButton.close:
          drawClose(canvas, glyph, stroke);
      }
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      (width * scale).ceil(),
      (height * scale).ceil(),
    );
    picture.dispose();
    return image;
  }
}

/// A wl_array of 32 bit integers (native endian, as C would send them).
Uint8List _int32Array(List<int> values) =>
    Int32List.fromList(values).buffer.asUint8List();

/// The decoration half of [RiverWindowManagerService].
extension _Decorations on RiverWindowManagerService {
  /// Windows that asked for server side decorations or don't mind them.
  bool _wantsSsd(RiverWindow w) {
    final int? hint = w._decorationHint;
    return hint == RiverWindowV1DecorationHint.prefersSsd ||
        hint == RiverWindowV1DecorationHint.noPreference;
  }

  /// Height of [w]'s title bar above its content (0 without one).
  double _decorationTop(RiverWindow w) =>
      w._decoration != null && !w._fullscreen ? _DecorationPainter.height : 0;

  /// [frame] (what the window and its title bar may cover) minus the title
  /// bar: where the window's content goes.
  Rect _contentRect(RiverWindow w, Rect frame) {
    final double top = _decorationTop(w);
    return Rect.fromLTRB(frame.left, frame.top + top, frame.right, frame.bottom);
  }

  /// Manage sequence: CSD or SSD, and a decoration surface for the latter.
  void _manageDecorations(RiverWindow w, {bool initial = false}) {
    final bool ssd = _wantsSsd(w) && _compositor != null && _shm != null;
    if (ssd && w._decoration == null) {
      w.proxy.useSsd();
      final WlSurface surface = _compositor!.createSurface();
      final RiverDecorationV1 role = w.proxy.getDecorationAbove(surface);
      final _Decoration decoration = _Decoration(w, surface, role);
      w._decoration = decoration;
      _decorationSurfaces[surface.id] = decoration;
      if (_blurManager != null) decoration.blur = _blurManager!.getBlur(surface);
      // Below the window: shadow and resize ring.
      final WlSurface shadow = _compositor!.createSurface();
      decoration
        ..shadowSurface = shadow
        ..shadowRole = w.proxy.getDecorationBelow(shadow)
        ..shadowViewport = _viewporter?.getViewport(shadow);
      if ((_blurManager?.version ?? 0) >= 3) {
        decoration.shadowBlur = _blurManager!.getBlur(shadow);
      }
      _shadowSurfaces[shadow.id] = decoration;
      // Room for the title bar above a window that is already placed.
      if (!initial && w._mapped && !w._maximized && w._snap == _Snap.none) {
        final double top = workArea.top + _DecorationPainter.height;
        if (w._y < top) {
          w._y = top.round();
          _position(w);
        }
      }
    } else if (!ssd && w._decoration != null) {
      _destroyDecoration(w);
      w.proxy.useCsd();
    } else if (initial && !ssd) {
      w.proxy.useCsd();
    }
  }

  void _destroyDecoration(RiverWindow w) {
    final _Decoration? decoration = w._decoration;
    if (decoration == null) return;
    w._decoration = null;
    _decorationSurfaces.remove(decoration.surface.id);
    if (decoration.shadowSurface case final WlSurface shadow) {
      _shadowSurfaces.remove(shadow.id);
    }
    decoration.destroy();
  }

  _DecorationLook _lookOf(_Decoration decoration) {
    final RiverWindow w = decoration.window;
    final CustomizationService? customization =
        ServiceManager.getService<CustomizationService>();
    final PreferencesService? prefs =
        ServiceManager.getService<PreferencesService>();
    final String font = prefs?.get<String>(SessionSetting.interfaceFont.key) ?? "";
    return _DecorationLook(
      width: w._width,
      title: w.title,
      focused: w == _focused,
      tiled: w._maximized || w._snap != _Snap.none,
      maximized: w._maximized || w._snap != _Snap.none,
      hover: decoration.hover,
      pressed: decoration.pressed,
      dark: customization?.darkMode ?? false,
      accent: (customization?.accentColor.resolve() ?? const Color(0xFFFF5722))
          .toARGB32(),
      tint: prefs?.get<bool>(SessionSetting.titlebarAccentTint.key) ??
          SessionSetting.titlebarAccentTint.defaultValue,
      font: font.isNotEmpty ? font : "packages/zenit_ui/Inter",
      translucent: decoration.blur != null &&
          (customization?.enableEffects ?? false) &&
          (w == _focused ||
              !(prefs?.get<bool>(SessionSetting.opaqueInactiveWindows.key) ??
                  SessionSetting.opaqueInactiveWindows.defaultValue)),
    );
  }

  /// The title bar's blur, set along with the buffer showing [look].
  void _applyTitleBlur(_Decoration decoration, _DecorationLook look) {
    final RiverBlurV1? blur = decoration.blur;
    if (blur == null) return;
    final int r = look.tiled ? 0 : _DecorationPainter.radius.round();
    final List<int> regions = look.translucent
        ? [0, 0, look.width, _DecorationPainter.height.round(), r, r, 0, 0, 10000]
        : const [];
    if (listEquals(regions, decoration.blurRegions)) return;
    decoration.blurRegions = regions;
    blur.setRegions(_int32Array(regions));
  }

  /// Render sequence: show the title bars that are ready, start drawing
  /// those that changed (they are shown at a later render sequence).
  void _renderDecorations() {
    for (final RiverWindow w in _stack) {
      final _Decoration? decoration = w._decoration;
      if (decoration == null || w._width <= 0) continue;

      _renderShadow(decoration);

      // Fullscreen windows have no title bar.
      if (w._fullscreen) {
        if (!decoration.hidden) {
          decoration.hidden = true;
          decoration.surface.attach(null, 0, 0);
          decoration.role.syncNextCommit();
          decoration.surface.commit();
          decoration.shown = null;
        }
        continue;
      }

      final _DecorationLook look = _lookOf(decoration);
      if (look == decoration.shown && !decoration.hidden) continue;

      final _DecorationBuffer? ready = decoration.ready;
      if (ready != null && ready.look == look) {
        decoration.ready = null;
        _applyTitleBlur(decoration, look);
        decoration.surface
          ..attach(ready.buffer, 0, 0)
          ..setBufferScale(_DecorationPainter.scale)
          ..damageBuffer(0, 0, 1 << 30, 1 << 30);
        decoration.role
          ..setOffset(0, -_DecorationPainter.height.round())
          ..syncNextCommit();
        decoration.surface.commit();
        decoration.attached?.destroy();
        decoration.attached = ready;
        decoration.shown = look;
        decoration.hidden = false;
        continue;
      }
      if (decoration.rendering != look) {
        decoration.rendering = look;
        unawaited(_drawDecoration(decoration, look));
      }
    }
  }

  /// Render sequence: the shadow surface follows the window right away
  /// (stretching the shadow drawn for the previous size until the new one
  /// is ready), as do its resize ring and the corner cutouts.
  void _renderShadow(_Decoration decoration) {
    final WlSurface? surface = decoration.shadowSurface;
    final RiverDecorationV1? role = decoration.shadowRole;
    if (surface == null || role == null) return;
    final RiverWindow w = decoration.window;
    final bool floating =
        !w._fullscreen && !w._maximized && w._snap == _Snap.none;
    final int width = w._width;
    final int height = w._height + _DecorationPainter.height.round();
    final (int, int, bool) geometry = (width, height, floating);

    if (!floating) {
      if (decoration.shadowGeometry?.$3 ?? true) {
        decoration.shadowGeometry = geometry;
        decoration.shadowBlur?.setCutouts(const []);
        surface.attach(null, 0, 0);
        role.syncNextCommit();
        surface.commit();
        decoration.shadowAttached?.destroy();
        decoration.shadowAttached = null;
      }
      return;
    }

    final _ShadowLook look = _ShadowLook(
      width: width,
      height: height,
      focused: w == _focused,
      factor: decoration.shadowViewport != null ? 0.5 : 1,
    );
    final _ShadowBuffer? ready = decoration.shadowReady;
    final bool newBuffer = ready != null;
    if (geometry != decoration.shadowGeometry || newBuffer) {
      // Nothing to show yet: wait for the first shadow.
      final _ShadowBuffer? buffer = ready ?? decoration.shadowAttached;
      if (buffer != null) {
        const int m = _ShadowPainter.margin;
        final int fullWidth = width + 2 * m;
        final int fullHeight = height + 2 * m;
        if (ready != null) {
          decoration.shadowReady = null;
          surface
            ..attach(ready.buffer, 0, 0)
            ..damageBuffer(0, 0, 1 << 30, 1 << 30);
          if (decoration.shadowAttached != ready) {
            decoration.shadowAttached?.destroy();
          }
          decoration.shadowAttached = ready;
        }
        if (decoration.shadowViewport case final WpViewport viewport) {
          viewport.setDestination(fullWidth, fullHeight);
        }
        // Input only in a thin ring around the window: the edges.
        final WlRegion ring = _compositor!.createRegion()
          ..add(
            m - _ShadowPainter.grab,
            m - _ShadowPainter.grab,
            width + 2 * _ShadowPainter.grab,
            height + 2 * _ShadowPainter.grab,
          )
          ..subtract(m, m, width, height);
        surface.setInputRegion(ring);
        ring.destroy();
        decoration.shadowBlur?.setCutouts(_int32Array([
          m,
          m,
          width,
          height,
          _DecorationPainter.radius.round(),
          // Bottom right and bottom left: the title bar rounds the top.
          4 | 8,
        ]));
        role
          ..setOffset(-m, -_DecorationPainter.height.round() - m)
          ..syncNextCommit();
        surface.commit();
        decoration.shadowGeometry = geometry;
      }
    }
    final _ShadowLook? shown = decoration.shadowAttached?.look;
    if (shown != look &&
        decoration.shadowReady?.look != look &&
        decoration.shadowRendering == null) {
      decoration.shadowRendering = look;
      unawaited(_drawShadow(decoration, look));
    }
  }

  Future<void> _drawShadow(_Decoration decoration, _ShadowLook look) async {
    try {
      final ui.Image image = await _ShadowPainter.paint(look);
      final ByteData? rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int width = image.width;
      final int height = image.height;
      image.dispose();
      decoration.shadowRendering = null;
      if (rgba == null || decoration.window._decoration != decoration) return;
      final (WlShmPool, WlBuffer) shm = _shmBuffer(
        rgba.buffer.asUint8List(),
        width,
        height,
        "shadow-${decoration.shadowSurface?.id}",
      );
      decoration.shadowReady?.destroy();
      decoration.shadowReady = _ShadowBuffer(look, shm.$2, shm.$1);
      _requestManage();
    } on Object catch (e) {
      logger.warning("Couldn't draw a window shadow: $e");
      decoration.shadowRendering = null;
    }
  }

  /// A wl_shm buffer holding [rgba] (premultiplied RGBA, converted here to
  /// ARGB8888).
  (WlShmPool, WlBuffer) _shmBuffer(
    Uint8List pixels,
    int width,
    int height,
    String name,
  ) {
    for (int i = 0; i < pixels.length; i += 4) {
      final int r = pixels[i];
      pixels[i] = pixels[i + 2];
      pixels[i + 2] = r;
    }
    final String dir =
        Platform.environment["XDG_RUNTIME_DIR"] ?? Directory.systemTemp.path;
    final File file = File(
      "$dir/pangolin-$name-$pid-${DateTime.now().microsecondsSinceEpoch}",
    );
    file.writeAsBytesSync(pixels, flush: true);
    // Read-write: river maps shared memory for reading and writing.
    final RandomAccessFile fd = file.openSync(mode: FileMode.append);
    file.deleteSync();
    final WlShmPool pool = _shm!.createPool(fd, pixels.length);
    final WlBuffer buffer = pool.createBuffer(0, width, height, width * 4, 0);
    // The fd goes out with the next flush; once it's sent, river holds its
    // own copy and ours can go.
    _connection.flush();
    fd.closeSync();
    return (pool, buffer);
  }

  Future<void> _drawDecoration(
    _Decoration decoration,
    _DecorationLook look,
  ) async {
    try {
      final ui.Image image = await _DecorationPainter.paint(look);
      final ByteData? rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int width = image.width;
      final int height = image.height;
      image.dispose();
      // Outdated while it was painted (or the window went away): another
      // look is being painted already, if any.
      if (rgba == null ||
          decoration.window._decoration != decoration ||
          decoration.rendering != look) {
        if (decoration.rendering == look) decoration.rendering = null;
        return;
      }
      // Premultiplied RGBA to wl_shm ARGB8888 (B, G, R, A in memory).
      final (WlShmPool pool, WlBuffer buffer) = _shmBuffer(
        rgba.buffer.asUint8List(),
        width,
        height,
        "decoration-${decoration.surface.id}",
      );
      decoration.rendering = null;
      decoration.ready?.destroy();
      decoration.ready = _DecorationBuffer(look, buffer, pool);
      _requestManage();
    } on Object catch (e) {
      logger.warning("Couldn't draw a title bar: $e");
      decoration.rendering = null;
    }
  }

  // Pointer input on title bars.

  /// A pointer can only be asked for once the seat has one (it may come and
  /// go, e.g. a mouse plugged in later).
  void _bindDecorationInput() {
    final WlSeat? seat = _wlSeat;
    if (seat == null) return;
    seat.onCapabilities = (capabilities) {
      final bool hasPointer = capabilities & WlSeatCapability.pointer != 0;
      if (hasPointer && _pointer == null) {
        _listenToPointer(seat.getPointer());
      } else if (!hasPointer && _pointer != null) {
        _cursorShape?.destroy();
        _cursorShape = null;
        if (_pointer!.version >= 3) _pointer!.release();
        _pointer = null;
      }
    };
  }

  /// Which edges of the window a point of its shadow surface grabs: the
  /// ring around it, both edges near the corners.
  static int _edgesAt(_Decoration decoration, Offset p) {
    const double m = _ShadowPainter.margin * 1.0;
    const double corner = _ShadowPainter.cornerGrab;
    final RiverWindow w = decoration.window;
    final double width = w._width.toDouble();
    final double height = w._height + _DecorationPainter.height;
    final double x = p.dx - m;
    final double y = p.dy - m;
    final bool outsideX = x < 0 || x > width;
    final bool outsideY = y < 0 || y > height;
    int edges = 0;
    if (x < 0 || (x < corner && outsideY)) edges |= RiverWindowV1Edges.left;
    if (x > width || (x > width - corner && outsideY)) {
      edges |= RiverWindowV1Edges.right;
    }
    if (y < 0 || (y < corner && outsideX)) edges |= RiverWindowV1Edges.top;
    if (y > height || (y > height - corner && outsideX)) {
      edges |= RiverWindowV1Edges.bottom;
    }
    return edges;
  }

  static int _resizeShape(int edges) {
    const int top = RiverWindowV1Edges.top;
    const int bottom = RiverWindowV1Edges.bottom;
    const int left = RiverWindowV1Edges.left;
    const int right = RiverWindowV1Edges.right;
    return switch (edges) {
      _ when edges == top | left => WpCursorShapeDeviceV1Shape.nwResize,
      _ when edges == top | right => WpCursorShapeDeviceV1Shape.neResize,
      _ when edges == bottom | left => WpCursorShapeDeviceV1Shape.swResize,
      _ when edges == bottom | right => WpCursorShapeDeviceV1Shape.seResize,
      _ when edges == top => WpCursorShapeDeviceV1Shape.nResize,
      _ when edges == bottom => WpCursorShapeDeviceV1Shape.sResize,
      _ when edges == left => WpCursorShapeDeviceV1Shape.wResize,
      _ when edges == right => WpCursorShapeDeviceV1Shape.eResize,
      _ => WpCursorShapeDeviceV1Shape.default_,
    };
  }

  void _listenToPointer(WlPointer pointer) {
    _pointer = pointer;
    _cursorShape = _cursorShapeManager?.getPointer(pointer);
    _Decoration? current;
    Offset position = Offset.zero;
    // The shadow (resize ring) under the pointer, and the edges it grabs.
    _Decoration? ring;
    int ringEdges = 0;
    int enterSerial = 0;

    void setHover(_Decoration decoration, _DecorationButton? hover) {
      if (decoration.hover == hover) return;
      decoration.hover = hover;
      _requestManage();
    }

    pointer
      ..onEnter = (serial, surface, x, y) {
        current = _decorationSurfaces[surface.id];
        ring = _shadowSurfaces[surface.id];
        enterSerial = serial;
        position = Offset(x, y);
        final _Decoration? r = ring;
        ringEdges = r == null ? 0 : _edgesAt(r, position);
        _cursorShape?.setShape(serial, _resizeShape(ringEdges));
        final _Decoration? d = current;
        if (d != null) {
          setHover(d, _DecorationPainter.buttonAt(d.window._width, position));
        }
      }
      ..onLeave = (serial, surface) {
        ring = null;
        ringEdges = 0;
        final _Decoration? d = current;
        current = null;
        if (d != null) {
          d.pressed = null;
          setHover(d, null);
        }
      }
      ..onMotion = (time, x, y) {
        position = Offset(x, y);
        if (ring case final _Decoration r) {
          final int edges = _edgesAt(r, position);
          if (edges != ringEdges) {
            ringEdges = edges;
            _cursorShape?.setShape(enterSerial, _resizeShape(edges));
          }
          return;
        }
        final _Decoration? d = current;
        if (d != null) {
          setHover(d, _DecorationPainter.buttonAt(d.window._width, position));
        }
      }
      ..onButton = (serial, time, button, state) {
        // The edges: resize.
        if (ring case final _Decoration r) {
          if (button != 0x110 || state != 1 || ringEdges == 0) return;
          final _Seat? s = _seats.firstOrNull;
          if (s != null) {
            s.interacted = r.window;
            s.pendingOp = _OpRequest.resize(r.window, ringEdges);
            _requestManage();
          }
          return;
        }
        final _Decoration? d = current;
        if (d == null || button != 0x110) return;
        final RiverWindow w = d.window;
        final _DecorationButton? target =
            _DecorationPainter.buttonAt(w._width, position);
        if (state == 1) {
          if (target != null) {
            d.pressed = target;
            _requestManage();
            return;
          }
          // Double click on the title: maximize or restore.
          if (time - d.lastPress < 400) {
            d.lastPress = 0;
            _schedule(() {
              if (w._maximized || w._snap != _Snap.none) {
                _morph(w, () => _restoreFloating(w));
              } else {
                _morph(w, () => _maximize(w));
              }
            });
            return;
          }
          d.lastPress = time;
          // Drag the title bar: move the window (a maximized one is
          // restored once the pointer moves).
          final _Seat? s = _seats.firstOrNull;
          if (s != null) {
            s.interacted = w;
            s.pendingOp = _OpRequest.move(w);
            _requestManage();
          }
        } else {
          final _DecorationButton? pressed = d.pressed;
          d.pressed = null;
          _requestManage();
          if (pressed == null || pressed != target) return;
          _schedule(() {
            switch (pressed) {
              case _DecorationButton.close:
                w.proxy.close();
              case _DecorationButton.minimize:
                _minimize(w);
              case _DecorationButton.maximize:
                if (w._maximized || w._snap != _Snap.none) {
                  _morph(w, () => _restoreFloating(w));
                } else {
                  _morph(w, () => _maximize(w));
                }
            }
          });
        }
      };
  }
}
