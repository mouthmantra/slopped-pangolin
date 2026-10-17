/*
Copyright 2021 The dahliaOS Authors

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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/search.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/utils/extensions/extensions.dart';
import 'package:pangolin/widgets/resource/auto_image.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:xdg_desktop/xdg_desktop.dart';
import 'package:yatl_flutter/yatl_flutter.dart';

/// Spotlight style search (Super+Space): a search field in the middle of the
/// screen, the best matches listed below it as you type. Up/Down pick a
/// result, Enter opens it, Escape closes.
class SearchOverlay extends ShellOverlay {
  static const String overlayId = "search";

  SearchOverlay({super.key}) : super(id: overlayId);

  @override
  _SearchOverlayState createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ShellOverlayState<SearchOverlay>
    with StateServiceListener<CustomizationService, SearchOverlay> {
  static const double _width = 680;
  static const int _maxResults = 7;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: "search");
  List<DesktopEntry> _results = const [];
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Future<void> requestShow(Map<String, Object?> args) async {
    _controller.text = args['searchQuery'] as String? ?? "";
    _update(_controller.text);
    controller.showing = true;
    _focusNode.requestFocus();
    await animationController.forward();
  }

  @override
  Future<void> requestDismiss(Map<String, dynamic> args) async {
    controller.showing = false;
    _focusNode.unfocus();
    await animationController.reverse();
  }

  void _dismiss() => ShellService.current.dismissOverlay(SearchOverlay.overlayId);

  /// Best matches first: names starting with the text, then names containing
  /// it, then matches on descriptions and keywords.
  void _update(String text) {
    final String query = text.trim().toLowerCase();
    final List<DesktopEntry> results;
    if (query.isEmpty) {
      results = [
        for (final String id
            in CustomizationService.current.recentSearchResults.reversed
                .toSet())
          if (ApplicationService.current.getApp(id) case final DesktopEntry app)
            app,
      ];
    } else {
      final Locale locale = context.locale;
      int rank(DesktopEntry app) {
        final String name = app.getLocalizedName(locale).toLowerCase();
        if (name.startsWith(query)) return 0;
        if (name.split(RegExp(r"\s+")).any((w) => w.startsWith(query))) {
          return 1;
        }
        if (name.contains(query)) return 2;
        return 3;
      }

      final List<DesktopEntry> found = [
        ...SearchService.current.search(text.trim(), locale)
            as List<DesktopEntry>,
      ];
      found.sort((a, b) {
        final int byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return a
            .getLocalizedName(locale)
            .toLowerCase()
            .compareTo(b.getLocalizedName(locale).toLowerCase());
      });
      results = found;
    }
    setState(() {
      _results = results.take(_maxResults).toList();
      _selected = 0;
    });
  }

  Future<void> _open(DesktopEntry app) async {
    final CustomizationService service = CustomizationService.current;
    service.recentSearchResults = [
      ...service.recentSearchResults.where((id) => id != app.id),
      app.id,
    ].reversed.take(20).toList().reversed.toList();
    ShellService.current.dismissEverything();
    await ApplicationService.current.startApp(app.id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    if (_results.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % _results.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected = (_selected - 1 + _results.length) % _results.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _open(_results[_selected.clamp(0, _results.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    if (shouldHide) return const SizedBox();
    final ThemeData theme = Theme.of(context);
    final Size screen = MediaQuery.sizeOf(context);
    final double width = (screen.width - 32).clamp(0.0, _width);
    final bool recent = _controller.text.trim().isEmpty;

    // Clicking anywhere else closes the search (the shell dismisses overlays
    // on clicks nothing else takes), the taskbar stays usable.
    return Stack(
      children: [
        Positioned(
          top: screen.height * 0.2,
          left: (screen.width - width) / 2,
          width: width,
          child: PopupTransition(
            animation: animation,
            showing: controller.showing,
            alignment: Alignment.topCenter,
            child: SurfaceLayer(
              dropShadow: true,
              shape: Constants.bigShape,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Focus(
                      onKeyEvent: _onKey,
                      child: _SearchField(
                        controller: _controller,
                        focusNode: _focusNode,
                        onChanged: _update,
                      ),
                    ),
                    if (_results.isNotEmpty) ...[
                      if (recent)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                          child: Text(
                            "Recent",
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < _results.length; i++)
                              _ResultTile(
                                app: _results[i],
                                selected: i == _selected,
                                onHover: () => setState(() => _selected = i),
                                onTap: () => _open(_results[i]),
                              ),
                          ],
                        ),
                      ),
                    ] else if (!recent)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        child: Text(
                          "No results",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 22),
          Icon(Icons.search_rounded, size: 26, color: muted),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onChanged: onChanged,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w400,
              ),
              cursorColor: theme.colorScheme.secondary,
              decoration: InputDecoration(
                hintText: "Search apps",
                hintStyle: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: muted,
                ),
                filled: false,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(width: 22)
                : IconButton(
                    tooltip: "Clear",
                    icon: Icon(Icons.close_rounded, color: muted),
                    onPressed: () {
                      controller.clear();
                      onChanged("");
                      focusNode.requestFocus();
                    },
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.app,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final DesktopEntry app;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color foreground = selected ? colors.onSecondary : colors.onSurface;
    final String? comment = app.getLocalizedComment(context.locale);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) {
        if (!selected) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            shape: Constants.mediumShape,
            color: selected ? colors.secondary : Colors.transparent,
          ),
          child: Row(
            children: [
              if (app.icon != null)
                AutoVisualResource(resource: app.icon!.main, size: 32)
              else
                Icon(Icons.apps_rounded, size: 32, color: foreground),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.getLocalizedName(context.locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (comment != null && comment.isNotEmpty)
                      Text(
                        comment,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                strings.searchOverlay.app,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
