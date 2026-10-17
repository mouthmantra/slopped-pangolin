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
import 'dart:math' as math;

import 'package:dahlia_apps/kit/desktop_apps.dart';
import 'package:dahlia_apps/kit/themed_icon.dart';
import 'package:dahlia_apps/kit/widgets.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:zenit_ui/zenit_ui.dart';

export 'package:dahlia_apps/kit/desktop_apps.dart';

class OpenWithResult {
  const OpenWithResult(this.app, {this.makeDefault = false});

  final DesktopApp app;

  /// "Always use for …" was checked.
  final bool makeDefault;
}

/// Picks the app to open something with: the apps that handle its type
/// first (the default one marked), every other app on request. With
/// [choices] (the desktop portal's list), only those.
class OpenWithChooser extends StatefulWidget {
  const OpenWithChooser({
    required this.contentType,
    required this.subject,
    required this.onDone,
    this.choices,
    this.lastChoice,
    this.allowDefault = true,
    this.showTitle = true,
    super.key,
  });

  /// MIME type of what is opened.
  final String contentType;

  /// What is opened, as the user knows it (a file name, a link).
  final String subject;
  final List<String>? choices;
  final String? lastChoice;

  /// Offers to make the choice the default for [contentType].
  final bool allowDefault;
  final bool showTitle;
  final ValueChanged<OpenWithResult?> onDone;

  @override
  State<OpenWithChooser> createState() => _OpenWithChooserState();
}

class _OpenWithChooserState extends State<OpenWithChooser> {
  final DesktopApps _apps = DesktopApps.load();
  late List<DesktopApp> _recommended;
  late List<DesktopApp> _others;
  DesktopApp? _default;
  String? _selected;
  bool _showAll = false;
  bool _makeDefault = false;
  String _query = "";
  final FocusNode _listFocus = FocusNode(debugLabel: "open with list");

  @override
  void initState() {
    super.initState();
    _index();
    _selected = widget.lastChoice != null &&
            [..._recommended, ..._others].any((a) => a.id == widget.lastChoice)
        ? widget.lastChoice
        : _recommended.firstOrNull?.id;
  }

  @override
  void dispose() {
    _listFocus.dispose();
    super.dispose();
  }

  void _index() {
    final List<String>? choices = widget.choices;
    if (choices != null) {
      _recommended = [
        for (final String id in choices)
          if (_apps.apps[id.replaceFirst(RegExp(r"\.desktop$"), "")] case final DesktopApp app) app,
      ];
      _others = const [];
      _default = null;
      return;
    }
    _recommended = _apps.appsFor(widget.contentType);
    _default = _apps.defaultFor(widget.contentType);
    final Set<String> seen = {for (final DesktopApp a in _recommended) a.id};
    _others = [
      for (final DesktopApp app in _apps.apps.values)
        if (!seen.contains(app.id) && app.takesFiles && !_isNoDisplay(app)) app,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Apps meant to stay out of menus are only offered for their types.
  static bool _isNoDisplay(DesktopApp app) {
    try {
      return File(app.path)
          .readAsLinesSync()
          .any((l) => l.trim() == "NoDisplay=true");
    } on FileSystemException {
      return true;
    }
  }

  bool _matches(DesktopApp app) {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return app.name.toLowerCase().contains(q) ||
        (app.genericName?.toLowerCase().contains(q) ?? false) ||
        app.id.toLowerCase().contains(q);
  }

  DesktopApp? get _selectedApp => [..._recommended, ..._others]
      .where((a) => a.id == _selected)
      .firstOrNull;

  void _accept([DesktopApp? app]) {
    final DesktopApp? chosen = app ?? _selectedApp;
    if (chosen == null) return;
    widget.onDone(OpenWithResult(chosen, makeDefault: _makeDefault));
  }

  void _openStore() {
    unawaited(DesktopApps.spawnDetached([Platform.resolvedExecutable, "store"]));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<DesktopApp> recommended = _recommended.where(_matches).toList();
    final bool searching = _query.trim().isNotEmpty;
    final List<DesktopApp> others =
        _showAll || searching ? _others.where(_matches).toList() : const [];
    final String typeName = DesktopApps.describe(_apps.canonical(widget.contentType));
    final List<DesktopApp> shown = [...recommended, ...others];

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        );

    Widget tile(DesktopApp app) => _AppTile(
          app: app,
          selected: app.id == _selected,
          isDefault: app.id == _default?.id,
          onTap: () {
            setState(() => _selected = app.id);
            _listFocus.requestFocus();
          },
          onDoubleTap: () => _accept(app),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => widget.onDone(null),
        const SingleActivator(LogicalKeyboardKey.enter): _accept,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _accept,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(shown, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(shown, -1),
      },
      child: Material(
        color: theme.colorScheme.surface.themedLightness(context, 0.02),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showTitle)
                    Text(
                      "Open “${widget.subject}” with",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  if (widget.showTitle) const SizedBox(height: 2),
                  Text(
                    typeName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SearchField(
                    autofocus: true,
                    hint: "Search apps",
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (_) {
                      if (_selectedApp == null || !shown.contains(_selectedApp)) {
                        setState(() => _selected = shown.firstOrNull?.id);
                      }
                      _accept();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _listFocus,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    if (recommended.isNotEmpty) ...[
                      if (others.isNotEmpty || widget.choices == null)
                        heading(widget.choices == null ? "Apps for $typeName" : "Apps"),
                      for (final DesktopApp app in recommended) tile(app),
                    ],
                    if (others.isNotEmpty) ...[
                      heading("Other apps"),
                      for (final DesktopApp app in others) tile(app),
                    ],
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: EmptyState(
                          icon: Icons.apps_outage_rounded,
                          title: searching
                              ? "No apps match “$_query”"
                              : "No installed app opens $typeName",
                          action: FilledButton.tonal(
                            onPressed: _openStore,
                            child: const Text("Find one in the App Store"),
                          ),
                        ),
                      ),
                    if (!_showAll && !searching && _others.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: TextButton.icon(
                            icon: const Icon(Icons.expand_more_rounded),
                            label: Text("Show all apps (${_others.length})"),
                            onPressed: () => setState(() => _showAll = true),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
              child: Row(
                children: [
                  if (widget.allowDefault && widget.choices == null)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _makeDefault = !_makeDefault),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _makeDefault,
                              onChanged: (v) => setState(() => _makeDefault = v ?? false),
                            ),
                            Flexible(
                              child: Text(
                                "Always use for $typeName",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  TextButton(onPressed: () => widget.onDone(null), child: const Text("Cancel")),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedApp == null ? null : _accept,
                    child: const Text("Open"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _move(List<DesktopApp> shown, int delta) {
    if (shown.isEmpty) return;
    final int current = shown.indexWhere((a) => a.id == _selected);
    final int next = (current < 0 ? 0 : current + delta).clamp(0, shown.length - 1);
    setState(() => _selected = shown[next].id);
  }
}

class _AppTile extends StatefulWidget {
  const _AppTile({
    required this.app,
    required this.selected,
    required this.isDefault,
    required this.onTap,
    required this.onDoubleTap,
  });

  final DesktopApp app;
  final bool selected;
  final bool isDefault;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? foreground = widget.selected ? theme.colorScheme.onPrimary : null;
    final DesktopApp app = widget.app;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.colorScheme.primary
                : _hovered
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ThemedIcon(name: app.icon, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w500, color: foreground),
                    ),
                    if (app.genericName != null && app.genericName != app.name)
                      Text(
                        app.genericName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: (foreground ?? theme.colorScheme.onSurface).withValues(alpha: 0.65),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (foreground ?? theme.colorScheme.primary).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "Default",
                    style: TextStyle(fontSize: 11, color: foreground ?? theme.colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks which app opens [paths] (the type of the first one decides the
/// apps offered) and opens them with it. Completes with whether they were
/// opened.
Future<bool> showOpenWithDialog(BuildContext context, List<String> paths) async {
  if (paths.isEmpty) return false;
  final String type = DesktopApps.typeOf(paths.first);
  final OpenWithResult? result = await showDialog<OpenWithResult>(
    context: context,
    builder: (context) {
      final Size screen = MediaQuery.sizeOf(context);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(460, screen.width - 48),
          height: math.min(560, screen.height - 48),
          child: OpenWithChooser(
            contentType: type,
            subject: paths.length == 1 ? p.basename(paths.first) : "${paths.length} files",
            onDone: (result) => Navigator.pop(context, result),
          ),
        ),
      );
    },
  );
  if (result == null) return false;
  return openWith(result, paths, type);
}

/// Opens [paths] with the chosen app (and makes it the default if asked).
Future<bool> openWith(OpenWithResult result, List<String> paths, String type) async {
  if (result.makeDefault) {
    try {
      DesktopApps.setDefault(DesktopApps.load().canonical(type), result.app);
    } on FileSystemException {
      // Opened all the same.
    }
  }
  return DesktopApps.launch(result.app, paths: paths);
}

/// Opens [path] with its default app, else asks which one ([showOpenWithDialog]).
Future<void> openFile(BuildContext context, String path) async {
  final DesktopApps apps = DesktopApps.load();
  final DesktopApp? app = apps.defaultFor(DesktopApps.typeOf(path));
  if (app != null && await DesktopApps.launch(app, paths: [path])) return;
  if (!context.mounted) return;
  await showOpenWithDialog(context, [path]);
}
