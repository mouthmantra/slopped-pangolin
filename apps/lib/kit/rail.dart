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

import 'package:dahlia_apps/kit/titlebar.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// A page shown in a [DahliaRail].
class RailDestination {
  const RailDestination(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;
}

/// Navigation rail of the dahliaOS design (Settings, Activity Monitor): round
/// accent buttons on an accent tinted pane, the current page highlighted
/// around its button.
class DahliaRail extends StatelessWidget {
  const DahliaRail({
    required this.destinations,
    required this.current,
    required this.onSelected,
    this.leading = const [],
    super.key,
  });

  /// The pages; a null leaves a gap between two groups.
  final List<RailDestination?> destinations;
  final String? current;
  final ValueChanged<String> onSelected;

  /// [RailItem]s above the pages, e.g. Settings' search.
  final List<Widget> leading;

  /// Continues the title bar (same tint, translucent over river's blur). Pass
  /// it as the scaffold's titlebarColor, and rebuild on [ZenitBlur.state].
  static Color colorOf(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color base = DahliaTitlebar.accentTint
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: dark ? 0.16 : 0.09),
            theme.scaffoldBackgroundColor,
          )
        : theme.colorScheme.surface.themedLightness(context, 0.05);
    return ZenitBlur.active ? base.withValues(alpha: ZenitBlur.fillOpacity) : base;
  }

  @override
  Widget build(BuildContext context) {
    final Widget rail = ColoredBox(
      color: colorOf(context),
      child: SizedBox(
        width: 88,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            if (leading.isNotEmpty) ...[...leading, const SizedBox(height: 14)],
            for (final RailDestination? dest in destinations)
              if (dest == null)
                const SizedBox(height: 14)
              else
                RailItem(
                  tooltip: dest.title,
                  selected: dest.id == current,
                  onTap: () => onSelected(dest.id),
                  child: RailIcon(icon: dest.icon, size: 40),
                ),
          ],
        ),
      ),
    );
    if (!ZenitBlur.active) return rail;
    return BlurRegion(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(DahliaTitlebar.windowRadius),
      ),
      child: rail,
    );
  }
}

/// One entry of a [DahliaRail].
class RailItem extends StatelessWidget {
  const RailItem({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: dark ? 0.32 : 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 56,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page's icon on an accent circle.
class RailIcon extends StatelessWidget {
  const RailIcon({required this.icon, required this.size, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size / 2, color: theme.colorScheme.onPrimary),
    );
  }
}
