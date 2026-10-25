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

import 'package:pangolin/services/tray/dbusmenu.dart';
import 'package:pangolin/services/tray/item.dart';
import 'package:pangolin/widgets/context_menu.dart';
import 'package:pangolin/widgets/tray/tray_icon.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// The entries of a tray item's menu below [parent], drawn like the
/// shell's context menus.
List<Widget> trayMenuEntries(
  BuildContext context, {
  required DBusMenuClient client,
  required DBusMenuNode parent,
  required VoidCallback onActivated,
  String? themePath,
}) {
  final List<DBusMenuNode> children = parent.shownChildren;
  // Labels line up when some entries have icons.
  final bool icons = children.any((e) => !e.isSeparator && e.hasIcon);
  return [
    if (ZenitBlur.active) const BlurRegion.ancestor(borderRadius: shellMenuRadius),
    for (final DBusMenuNode node in children)
      _entry(context, client, node, icons, themePath, onActivated),
  ];
}

const ButtonStyle _style = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll<Color>(Colors.transparent),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
);

Widget _entry(
  BuildContext context,
  DBusMenuClient client,
  DBusMenuNode node,
  bool icons,
  String? themePath,
  VoidCallback onActivated,
) {
  // Like Zenit's context menus: the theme's dividers are invisible, a
  // separator is a gap.
  if (node.isSeparator) {
    return Padding(
      key: ValueKey(node.id),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: const Divider(thickness: 1, indent: 8, endIndent: 8),
    );
  }

  final Widget label = ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Text(
      node.displayLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: switch (node.disposition) {
        DBusMenuDisposition.alert =>
          TextStyle(color: Theme.of(context).colorScheme.error),
        DBusMenuDisposition.warning => const TextStyle(color: Colors.orange),
        _ => null,
      },
    ),
  );
  final Widget? leading = icons
      ? SizedBox.square(
          dimension: 20,
          child: node.hasIcon ? _icon(node, themePath) : null,
        )
      : null;

  if (node.isSubmenu) {
    final List<Widget> entries;
    if (!node.enabled) {
      // A submenu without entries can't open.
      entries = const [];
    } else if (node.shownChildren.isEmpty) {
      // Qt fills submenus once they are about to show (opening this asks
      // for that): something must be there to open it.
      entries = [
        if (ZenitBlur.active)
          const BlurRegion.ancestor(borderRadius: shellMenuRadius),
        const MenuItemButton(style: _style, child: Text("Empty")),
      ];
    } else {
      entries = trayMenuEntries(
        context,
        client: client,
        parent: node,
        onActivated: onActivated,
        themePath: themePath,
      );
    }
    return SubmenuButton(
      key: ValueKey(node.id),
      menuStyle: shellMenuStyle(context),
      menuChildren: entries,
      leadingIcon: leading,
      submenuIcon: const WidgetStatePropertyAll(
        Icon(Icons.chevron_right, size: 16),
      ),
      onOpen: () => client.opened(node.id),
      onClose: () => client.closed(node.id),
      style: _style,
      child: label,
    );
  }

  return MenuItemButton(
    key: ValueKey(node.id),
    leadingIcon: leading,
    trailingIcon: _toggle(context, node),
    style: _style,
    onPressed: node.enabled
        ? () {
            client.clicked(node.id);
            onActivated();
          }
        : null,
    child: label,
  );
}

Widget _icon(DBusMenuNode node, String? themePath) {
  final data = node.iconData;
  if (data != null) {
    return Image.memory(
      data,
      width: 20,
      height: 20,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  // Like GTK and Qt: no icon rather than a generic one.
  return TrayIconImage(
    source: TrayIconSource(name: node.iconName),
    themePath: themePath,
    size: 20,
    fallback: const SizedBox.shrink(),
  );
}

Widget? _toggle(BuildContext context, DBusMenuNode node) {
  final bool? state = node.toggleState;
  final Color accent = Theme.of(context).colorScheme.secondary;
  return switch (node.toggleType) {
    DBusMenuToggleType.checkmark => Icon(
        switch (state) {
          true => Icons.check_box_rounded,
          false => Icons.check_box_outline_blank_rounded,
          null => Icons.indeterminate_check_box_rounded,
        },
        size: 20,
        color: state != false ? accent : null,
      ),
    DBusMenuToggleType.radio => Icon(
        state == true
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: state == true ? accent : null,
      ),
    DBusMenuToggleType.none => null,
  };
}
