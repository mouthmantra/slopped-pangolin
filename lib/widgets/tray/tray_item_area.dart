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

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pangolin/components/shell/shell_popups.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/shell_area.dart';
import 'package:pangolin/services/tray/dbusmenu.dart';
import 'package:pangolin/services/tray/item.dart';
import 'package:pangolin/widgets/context_menu.dart';
import 'package:pangolin/widgets/input_region.dart';
import 'package:pangolin/widgets/tray/tray_menu.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// Clicks that [TrayItemArea.builder]'s widget takes itself (an InkWell,
/// whose tap would otherwise win over the area's), handed on to the item.
abstract interface class TrayItemActions {
  /// A left click at [position] (global): activates the item, or opens its
  /// menu.
  void primary(Offset position);

  /// A right click at [position]: opens the item's menu.
  void secondary(Offset position);
}

/// Where a tray item takes input: left click activates it (or opens its
/// menu), middle click is its secondary action, the wheel scrolls it and
/// right click opens its menu, anchored to [builder]'s widget.
class TrayItemArea extends StatefulWidget {
  final TrayItem item;

  /// In a popup (the tray's overflow, quick settings) that should stay
  /// open while the item's menu is.
  final bool inPopup;

  final Widget Function(
    BuildContext context,
    bool menuOpen,
    TrayItemActions actions,
  ) builder;

  const TrayItemArea({
    required this.item,
    required this.builder,
    this.inPopup = false,
    super.key,
  });

  @override
  State<TrayItemArea> createState() => _TrayItemAreaState();
}

class _TrayItemAreaState extends State<TrayItemArea>
    implements TrayItemActions {
  /// Pixels of touchpad scrolling that make one step.
  static const double _step = 50;

  final MenuController _menu = MenuController();
  final FocusNode _focus = FocusNode(debugLabel: "Tray item");

  /// The menu shown, kept while it is open even if the item gets another.
  DBusMenuClient? _client;
  bool _menuOpen = false;
  bool _opening = false;

  double _scrollDown = 0;
  double _scrollRight = 0;

  @override
  void dispose() {
    _focus.dispose();
    ShellInputRegion.instance.claim(this, false);
    if (_menuOpen) _client?.closed(0);
    super.dispose();
  }

  TrayItem get _item => widget.item;

  @override
  void primary(Offset position) => unawaited(_primary(position));

  @override
  void secondary(Offset position) => unawaited(_secondary(position));

  Future<void> _primary(Offset position) async {
    if (_menuOpen) {
      _menu.close();
      return;
    }
    if (_item.itemIsMenu && await _openMenu()) return;
    if (await _item.activate(position.dx.round(), position.dy.round())) {
      ShellService.current.dismissEverything();
      return;
    }
    // Appindicators have no Activate: a click shows their menu.
    if (mounted) await _openMenu();
  }

  Future<void> _middle(Offset position) async {
    if (_menuOpen) {
      _menu.close();
      return;
    }
    await _item.secondaryActivate(position.dx.round(), position.dy.round());
  }

  Future<void> _secondary(Offset position) async {
    if (_menuOpen) {
      _menu.close();
      return;
    }
    if (await _openMenu()) return;
    // No dbusmenu: the item may show a menu of its own.
    if (await _item.contextMenu(position.dx.round(), position.dy.round())) {
      ShellService.current.dismissEverything();
    }
  }

  Future<bool> _openMenu() async {
    final DBusMenuClient? client = _item.menu;
    if (client == null || client.isClosed) return false;
    if (_opening) return true;
    _opening = true;
    try {
      final DBusMenuNode? root = await client.prepare();
      if (!mounted || root == null) return false;
      if (!widget.inPopup) ShellService.current.dismissEverything();
      // The menu draws over the whole shell surface.
      if (isOnShellSurface(context)) {
        await ShellSurfaceArea.instance.ensureFull();
        if (!mounted) return false;
      }
      setState(() => _client = client);
      _menu.open();
      return true;
    } finally {
      _opening = false;
    }
  }

  void _onOpen() {
    if (isOnShellSurface(context)) ShellInputRegion.instance.claim(this, true);
    _client?.opened(0);
    _focus.requestFocus();
    setState(() => _menuOpen = true);
  }

  void _onClose() {
    ShellInputRegion.instance.claim(this, false);
    _client?.closed(0);
    if (mounted) setState(() => _menuOpen = false);
  }

  /// An entry of the menu was clicked: whatever it does happens elsewhere.
  void _onActivated() {
    if (widget.inPopup) ShellService.current.dismissEverything();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final PointerScrollEvent scroll = event as PointerScrollEvent;
      _scroll(scroll.scrollDelta, wheel: scroll.kind == PointerDeviceKind.mouse);
    });
  }

  // Touchpads: the content follows the fingers.
  void _onPanZoom(PointerPanZoomUpdateEvent event) =>
      _scroll(-event.panDelta, wheel: false);

  /// A wheel click is one event, of whatever size the embedder makes it:
  /// one step each. Touchpads (and high resolution wheels) scroll in small
  /// amounts: a step every [_step] pixels, so that items that step (volume)
  /// don't race.
  void _scroll(Offset delta, {required bool wheel}) {
    if (wheel && delta.distance >= 20) {
      _scrollDown = 0;
      _scrollRight = 0;
      if (delta.dy != 0) _send(delta.dy.sign.toInt(), TrayScrollOrientation.vertical);
      if (delta.dx != 0) _send(delta.dx.sign.toInt(), TrayScrollOrientation.horizontal);
      return;
    }
    _scrollDown += delta.dy;
    _scrollRight += delta.dx;
    final int down = (_scrollDown / _step).truncate();
    final int right = (_scrollRight / _step).truncate();
    if (down != 0) {
      _scrollDown -= down * _step;
      _send(down, TrayScrollOrientation.vertical);
    }
    if (right != 0) {
      _scrollRight -= right * _step;
      _send(right, TrayScrollOrientation.horizontal);
    }
  }

  void _send(int steps, TrayScrollOrientation orientation) =>
      unawaited(_item.scroll(steps, orientation));

  /// Escape closes the menu (focus is on the anchor, not in the menu).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_menuOpen &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _menu.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<Widget> _entries(BuildContext context) {
    final DBusMenuClient? client = _client;
    final DBusMenuNode? root = client?.root;
    if (client == null || root == null || root.shownChildren.isEmpty) {
      // The menu emptied while open.
      if (_menuOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _menu.close();
        });
      }
      return const [];
    }
    return trayMenuEntries(
      context,
      client: client,
      parent: root,
      onActivated: _onActivated,
      themePath: _item.iconThemePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget area = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => unawaited(_primary(d.globalPosition)),
      onTertiaryTapUp: (d) => unawaited(_middle(d.globalPosition)),
      onSecondaryTapUp: (d) => unawaited(_secondary(d.globalPosition)),
      onLongPressStart: (d) => unawaited(_secondary(d.globalPosition)),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomUpdate: _onPanZoom,
        child: widget.builder(context, _menuOpen, this),
      ),
    );

    return ListenableBuilder(
      listenable: Listenable.merge([
        ZenitBlur.state,
        _item,
        if (_client != null) _client!,
      ]),
      builder: (context, child) => MenuAnchor(
        controller: _menu,
        childFocusNode: _focus,
        style: shellMenuStyle(context),
        onOpen: _onOpen,
        onClose: _onClose,
        menuChildren: _entries(context),
        // Hidden, not removed, while the menu is open: the tree under the
        // anchor must not change.
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: TooltipVisibility(
            visible: !_menuOpen,
            child: Tooltip(
              message: _item.toolTipText,
              waitDuration: const Duration(seconds: 1),
              child: child,
            ),
          ),
        ),
      ),
      child: area,
    );
  }
}
