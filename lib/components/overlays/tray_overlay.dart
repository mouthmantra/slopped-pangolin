import 'dart:async';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/tray.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:pangolin/widgets/tray/tray_icon.dart';
import 'package:pangolin/widgets/tray/tray_item_area.dart';

class TrayMenuOverlay extends ShellOverlay {
  static const String overlayId = "tray";

  TrayMenuOverlay({super.key}) : super(id: overlayId);

  @override
  ShellOverlayState<TrayMenuOverlay> createState() => _TrayMenuOverlayState();
}

class _TrayMenuOverlayState extends ShellOverlayState<TrayMenuOverlay>
    with StateServiceListener<TrayService, TrayMenuOverlay> {
  static const double _itemSize = 40.0;
  static const double _itemPadding = 8.0;
  static const double _sidePadding = 12.0;
  static const int _itemRowCount = 4;
  static const double _layoutWidth = _itemSize * _itemRowCount +
      _itemPadding * (_itemRowCount - 1) +
      _sidePadding * 2;
  Offset? origin;

  @override
  Widget buildChild(BuildContext context, TrayService service) {
    if (shouldHide) return const SizedBox();

    // Passive items (the item says it has nothing to show) come last.
    final List<TrayItem> items = [
      ...service.shownItems,
      ...service.hiddenItems,
    ];
    final origin = this.origin ??
        Offset(
          MediaQuery.of(context).size.width / 2,
          WindowManagerService.current.controller.wmBounds.bottom,
        );
    final rowCount = items.isNotEmpty ? (items.length / 4).ceil() : 1;
    final layoutHeight =
        _itemSize * rowCount + _itemPadding * (rowCount - 1) + _sidePadding * 2;

    return Positioned(
      left: origin.dx - _layoutWidth / 2,
      top: origin.dy - layoutHeight - 8.0,
      child: PopupTransition(
        animation: animation,
        showing: controller.showing,
        alignment: FractionalOffset.bottomCenter,
        margin: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _layoutWidth),
          child: Center(
            child: SurfaceLayer(
              outline: true,
              dropShadow: true,
              shape: Constants.bigShape,
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.all(_sidePadding),
                  child: items.isNotEmpty
                      ? Wrap(
                          spacing: _itemPadding,
                          runSpacing: _itemPadding,
                          children: items
                              .map((e) => _TrayMenuItem(key: ObjectKey(e), item: e))
                              .toList(),
                        )
                      : const SizedBox(
                          height: _itemSize,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12.0),
                            child: IntrinsicWidth(
                              child: Center(
                                child: Text("Empty"),
                              ),
                            ),
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

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) async {
    controller.showing = false;
    await animationController.reverse();
  }

  @override
  FutureOr<void> requestShow(Map<String, dynamic> args) async {
    origin = args["origin"] as Offset?;
    controller.showing = true;
    await animationController.forward();
  }
}

/// A tray item in the panel: clicks, the wheel and its menu go through
/// [TrayItemArea].
class _TrayMenuItem extends StatelessWidget {
  final TrayItem item;

  const _TrayMenuItem({required this.item, super.key});

  @override
  Widget build(BuildContext context) {
    return TrayItemArea(
      item: item,
      inPopup: true,
      builder: (context, menuOpen, actions) => SizedBox.square(
        dimension: _TrayMenuOverlayState._itemSize,
        child: Material(
          shape: Constants.smallShape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTapUp: (details) => actions.primary(details.globalPosition),
            onSecondaryTapUp: (details) =>
                actions.secondary(details.globalPosition),
            child: Center(
              child: ListenableBuilder(
                listenable: item,
                builder: (context, _) => TrayIconImage.item(item, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
