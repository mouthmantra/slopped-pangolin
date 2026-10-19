import 'package:flutter/material.dart';
import 'package:pangolin/components/shell/shell_popups.dart';
import 'package:pangolin/services/shell_area.dart';
import 'package:pangolin/widgets/input_region.dart';
import 'package:uuid/uuid.dart';
import 'package:zenit_ui/zenit_ui.dart';

class ContextMenu extends StatefulWidget {
  final List<BaseContextMenuItem>? entries;
  final Widget child;
  final bool openOnLongPress;
  final bool openOnSecondaryPress;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  const ContextMenu({
    required this.entries,
    required this.child,
    this.openOnLongPress = true,
    this.openOnSecondaryPress = true,
    this.onOpen,
    this.onClose,
    super.key,
  });

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  late final String controllerId =
      _MenuControllerRegistry.instance.register(MenuController());
  late Offset lastPosition;

  @override
  void dispose() {
    ShellInputRegion.instance.claim(this, false);
    _MenuControllerRegistry.instance.unregister(controllerId);
    super.dispose();
  }

  // An open menu may extend anywhere on the shell surface. Menus on another
  // surface (the desktop) must not claim it: the transparent shell surface
  // would then swallow every click meant for them.
  void _onOpen() {
    if (isOnShellSurface(context)) ShellInputRegion.instance.claim(this, true);
    widget.onOpen?.call();
  }

  void _onClose() {
    ShellInputRegion.instance.claim(this, false);
    widget.onClose?.call();
  }

  /// On the shell surface the menu opens once the surface covers the screen
  /// (it's a strip along the bottom while only the taskbar shows).
  Future<void> _open(Offset position) async {
    if (isOnShellSurface(context)) {
      await ShellSurfaceArea.instance.ensureFull();
      if (!mounted) return;
    }
    _MenuControllerRegistry.instance.open(controllerId, position: position);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries == null || widget.entries!.isEmpty) return widget.child;

    return GestureDetector(
      onSecondaryTapUp: (details) => _open(details.localPosition),
      onLongPressDown: (details) => lastPosition = details.localPosition,
      onLongPress: () => _open(lastPosition),
      child: ListenableBuilder(
        listenable: ZenitBlur.state,
        builder: (context, child) => MenuAnchor(
          onOpen: _onOpen,
          onClose: _onClose,
          style: shellMenuStyle(context),
          controller: _MenuControllerRegistry.instance.get(controllerId),
          anchorTapClosesMenu: true,
          menuChildren: [
            // Frosted glass behind the whole menu panel.
            if (ZenitBlur.active)
              BlurRegion.ancestor(borderRadius: shellMenuRadius),
            ...widget.entries!.map((e) => e.buildWrapper(context)),
          ],
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Corner radius of shell menus.
const BorderRadius shellMenuRadius = BorderRadius.all(Radius.circular(12));

/// Menus of the shell: frosted glass when river blurs, no frame.
MenuStyle shellMenuStyle(BuildContext context) {
  final Color background = Theme.of(context).colorScheme.background;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll<Color>(
      ZenitBlur.active
          ? background.withValues(alpha: ZenitBlur.fillOpacity)
          : background,
    ),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: shellMenuRadius),
    ),
    side: const WidgetStatePropertyAll(BorderSide.none),
  );
}

class _EnabledBuilder extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _EnabledBuilder({
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: child,
      ),
    );
  }
}

abstract class BaseContextMenuItem {
  final Widget? child;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  const BaseContextMenuItem({
    this.child,
    this.enabled = true,
    this.leading,
    this.trailing,
  });

  Widget buildWrapper(BuildContext context) =>
      _EnabledBuilder(enabled: enabled, child: build(context));

  Widget build(BuildContext context);
  Widget? buildLeading(BuildContext context) => leading;
  Widget? buildTrailing(BuildContext context) => trailing;
}

class SubmenuMenuItem extends BaseContextMenuItem {
  final List<BaseContextMenuItem> menuChildren;

  const SubmenuMenuItem({
    required Widget super.child,
    required this.menuChildren,
    super.leading,
    super.enabled,
  }) : super(trailing: null);

  @override
  Widget? buildTrailing(BuildContext context) {
    return const Icon(Icons.chevron_right, size: 16);
  }

  @override
  Widget build(BuildContext context) {
    return SubmenuButton(
      menuStyle: shellMenuStyle(context),
      menuChildren: [
        if (ZenitBlur.active)
          BlurRegion.ancestor(borderRadius: shellMenuRadius),
        ...menuChildren.map((e) => e.buildWrapper(context)),
      ],
      leadingIcon: buildLeading(context),
      trailingIcon: buildTrailing(context),
      style: ButtonStyle(
        backgroundColor: const MaterialStatePropertyAll<Color>(
          Colors.transparent,
        ),
        padding: const MaterialStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      child: child,
    );
  }
}

class ContextMenuItem extends BaseContextMenuItem {
  final VoidCallback? onTap;
  final MenuSerializableShortcut? shortcut;

  const ContextMenuItem({
    required Widget super.child,
    this.onTap,
    super.leading,
    super.trailing,
    this.shortcut,
    super.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final Widget? leading = buildLeading(context);

    return MenuItemButton(
      leadingIcon: leading != null
          ? IconTheme.merge(
              data: Theme.of(context).iconTheme.copyWith(size: 20),
              child: leading,
            )
          : null,
      trailingIcon: buildTrailing(context),
      onPressed: onTap,
      shortcut: shortcut,
      style: ButtonStyle(
        backgroundColor: const MaterialStatePropertyAll<Color>(
          Colors.transparent,
        ),
        padding: const MaterialStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      child: child,
    );
  }
}

class RadioMenuItem<T> extends ContextMenuItem {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool toggleable;

  const RadioMenuItem({
    required this.value,
    required this.groupValue,
    this.onChanged,
    this.toggleable = false,
    required super.child,
    super.trailing,
    super.shortcut,
    super.enabled,
  }) : super(leading: null, onTap: null);

  @override
  VoidCallback? get onTap => onChanged == null
      ? null
      : () {
          if (toggleable && groupValue == value) {
            onChanged!.call(null);
            return;
          }
          onChanged!.call(value);
        };

  @override
  Widget? buildTrailing(BuildContext context) {
    return ExcludeFocus(
      child: IgnorePointer(
        child: Radio<T>(
          groupValue: groupValue,
          value: value,
          onChanged: onChanged,
          toggleable: toggleable,
        ),
      ),
    );
  }
}

class CheckboxMenuItem extends ContextMenuItem {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;

  const CheckboxMenuItem({
    required this.value,
    this.onChanged,
    this.tristate = false,
    required super.child,
    super.trailing,
    super.shortcut,
    super.enabled,
  }) : super(leading: null, onTap: null);

  @override
  VoidCallback? get onTap => onChanged == null
      ? null
      : () {
          onChanged!.call(
            switch (value) {
              false => true,
              true => tristate ? null : false,
              null => false,
            },
          );
        };

  @override
  Widget? buildTrailing(BuildContext context) {
    return ExcludeFocus(
      child: IgnorePointer(
        child: Checkbox(
          value: value,
          onChanged: onChanged,
          tristate: tristate,
        ),
      ),
    );
  }
}

class ContextMenuDivider extends BaseContextMenuItem {
  const ContextMenuDivider();

  @override
  Widget build(BuildContext context) => const Divider();
}

final class _MenuControllerRegistry {
  static final _MenuControllerRegistry instance = _MenuControllerRegistry._();

  _MenuControllerRegistry._();

  final Map<String, MenuController> _registeredControllers = {};

  String register(MenuController controller) {
    if (_registeredControllers.containsValue(controller)) {
      throw Exception("Controller already registered.");
    }

    final id = const Uuid().v4();
    _registeredControllers[id] = controller;
    return id;
  }

  void unregister(String id) {
    if (!_registeredControllers.containsKey(id)) {
      throw Exception("Controller $id not registered.");
    }

    _registeredControllers.remove(id);
  }

  MenuController get(String id) {
    if (!_registeredControllers.containsKey(id)) {
      throw Exception("Controller $id not registered.");
    }

    return _registeredControllers[id]!;
  }

  MenuController? maybeGet(String id) {
    return _registeredControllers[id];
  }

  void open(String id, {Offset? position}) {
    if (!_registeredControllers.containsKey(id)) {
      throw Exception("Controller $id not registered.");
    }

    closeAll();
    _registeredControllers[id]!.open(position: position);
  }

  void closeAll() {
    for (final controller in _registeredControllers.values) {
      controller.close();
    }
  }

  bool anyOpen() {
    return _registeredControllers.values.any((e) => e.isOpen);
  }
}
