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

import 'package:dahlia_apps/apps/store/flathub.dart';
import 'package:dahlia_apps/apps/store/packagekit.dart';
import 'package:dahlia_apps/kit/kit.dart';

final DahliaAppSpec storeApp = DahliaAppSpec(
  name: "store",
  title: "App Store",
  builder: (context, args) => StorePage(openApp: args.isNotEmpty ? args.first : null),
);

/// What the store is currently showing.
sealed class _View {
  const _View();
}

class _HomeView extends _View {
  const _HomeView();
}

class _CategoryView extends _View {
  const _CategoryView(this.category);
  final StoreCategory category;
}

class _SearchView extends _View {
  const _SearchView(this.query);
  final String query;
}

class _InstalledView extends _View {
  const _InstalledView();
}

class _AppView extends _View {
  const _AppView(this.id);
  final String id;
}

class _PackageView extends _View {
  const _PackageView(this.package);
  final SystemPackage package;
}

class StorePage extends StatefulWidget {
  const StorePage({this.openApp, super.key});

  /// Flathub id to show first (e.g. `dahlia_apps store org.gnome.Maps`), or
  /// `search:QUERY` to search.
  final String? openApp;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final FlathubClient _flathub = FlathubClient();
  final FlatpakManager _flatpak = FlatpakManager();
  final List<_View> _history = [const _HomeView()];
  final TextEditingController _search = TextEditingController();

  Map<String, InstallScope> _installed = {};
  final Map<String, String> _operations = {};

  /// The distribution's packages, when PackageKit is there.
  PackageKitClient? _packageKit;

  /// Packages installed or removed here since PackageKit last said (by
  /// name), and those being worked on.
  final Map<String, bool> _packageInstalled = {};
  final Map<String, PackageProgress> _packageOperations = {};

  _View get _view => _history.last;

  @override
  void initState() {
    super.initState();
    final String? open = widget.openApp;
    if (open != null && open.startsWith("search:")) {
      // `dahlia_apps store search:QUERY`: straight to the results.
      final String query = open.substring(7).trim();
      if (query.isNotEmpty) {
        _search.text = query;
        _history.add(_SearchView(query));
      }
    } else if (open != null) {
      _history.add(_AppView(open));
    }
    _refreshInstalled();
    PackageKitClient.connect().then((client) {
      if (!mounted) {
        client?.close();
        return;
      }
      setState(() => _packageKit = client);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _packageKit?.close();
    super.dispose();
  }

  bool _isInstalled(SystemPackage package) =>
      _packageInstalled[package.name] ?? package.installed;

  Future<void> _changePackage(SystemPackage package, {required bool install}) async {
    final PackageKitClient? client = _packageKit;
    if (client == null) return;
    setState(() => _packageOperations[package.name] =
        PackageProgress(install ? "Starting…" : "Removing…", null));
    void onProgress(PackageProgress progress) {
      if (mounted) setState(() => _packageOperations[package.name] = progress);
    }

    String? error;
    try {
      // Removing the installed package, not an available one of the same name.
      final SystemPackage target = install
          ? package
          : (package.installed ? package : await client.resolve(package.name)) ?? package;
      if (install) {
        await client.install(target, onProgress);
      } else {
        await client.remove(target, onProgress);
      }
    } on PackageKitException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() {
      _packageOperations.remove(package.name);
      if (error == null) _packageInstalled[package.name] = install;
    });
    _toast(
      error == null
          ? "${package.name} ${install ? "is installed" : "was removed"}"
          : "Couldn't ${install ? "install" : "remove"} ${package.name}: $error",
    );
  }

  Widget _packageAction(SystemPackage package, {bool large = false}) {
    final PackageProgress? operation = _packageOperations[package.name];
    if (operation != null) {
      return SizedBox(
        width: large ? 220 : 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: operation.percent == null ? null : operation.percent! / 100,
            ),
            const SizedBox(height: 4),
            Text(
              operation.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }
    if (_isInstalled(package)) {
      return large
          ? OutlinedButton(
              onPressed: () => _changePackage(package, install: false),
              child: const Text("Remove"),
            )
          : const Chip(label: Text("Installed"));
    }
    return FilledButton(
      onPressed: () => _changePackage(package, install: true),
      child: const Text("Install"),
    );
  }

  Future<void> _refreshInstalled() async {
    if (!_flatpak.available) return;
    final Map<String, InstallScope> installed = await _flatpak.installed();
    if (mounted) setState(() => _installed = installed);
  }

  void _push(_View view) => setState(() => _history.add(view));

  void _back() {
    if (_history.length > 1) setState(_history.removeLast);
  }

  Future<void> _install(StoreApp app) async {
    setState(() => _operations[app.id] = "Starting…");
    final bool ok = await _flatpak.install(app.id, (line) {
      if (mounted && line.trim().isNotEmpty) setState(() => _operations[app.id] = line.trim());
    });
    if (!mounted) return;
    setState(() => _operations.remove(app.id));
    _toast(ok ? "${app.name} is installed" : "Couldn't install ${app.name}");
    await _refreshInstalled();
  }

  Future<void> _uninstall(StoreApp app) async {
    final InstallScope? scope = _installed[app.id];
    if (scope == null) return;
    setState(() => _operations[app.id] = "Removing…");
    final bool ok = await _flatpak.uninstall(app.id, scope, (line) {
      if (mounted && line.trim().isNotEmpty) setState(() => _operations[app.id] = line.trim());
    });
    if (!mounted) return;
    setState(() => _operations.remove(app.id));
    _toast(ok ? "${app.name} was removed" : "Couldn't remove ${app.name}");
    await _refreshInstalled();
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Widget _actionButton(StoreApp app, {bool large = false}) {
    final String? operation = _operations[app.id];
    if (operation != null) {
      return SizedBox(
        width: large ? 220 : 90,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LinearProgressIndicator(),
            if (large) ...[
              const SizedBox(height: 4),
              Text(operation, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
      );
    }
    if (!_flatpak.available) {
      return const Tooltip(message: "Flatpak is not installed", child: FilledButton(onPressed: null, child: Text("Install")));
    }
    if (_installed.containsKey(app.id)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(onPressed: () => _flatpak.launch(app.id), child: const Text("Open")),
          if (large) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _uninstall(app), child: const Text("Uninstall")),
          ],
        ],
      );
    }
    return FilledButton(onPressed: () => _install(app), child: const Text("Install"));
  }

  @override
  Widget build(BuildContext context) {
    final _View view = _view;
    return DahliaScaffold(
      titlebarLeading: [
        if (_history.length > 1)
          IconButton(tooltip: "Back", icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
      ],
      titlebarActions: [
        SearchField(
          controller: _search,
          width: 260,
          hint: _packageKit != null ? "Search apps and packages" : "Search Flathub",
          onSubmitted: (q) {
            if (q.trim().isNotEmpty) _push(_SearchView(q.trim()));
          },
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: view is _InstalledView ? null : () => _push(const _InstalledView()),
          icon: const Icon(Icons.download_done_rounded),
          label: Text("Installed${_installed.isEmpty ? "" : " (${_installed.length})"}"),
        ),
      ],
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(_history.length),
          child: switch (view) {
            _HomeView() => _HomeTab(
                flathub: _flathub,
                onOpen: (app) => _push(_AppView(app.id)),
                onCategory: (c) => _push(_CategoryView(c)),
                action: _actionButton,
              ),
            _CategoryView(:final category) => _AppGrid(
                title: category.label,
                load: () => _flathub.category(category.id),
                onOpen: (app) => _push(_AppView(app.id)),
                action: _actionButton,
              ),
            _SearchView(:final query) => _SearchResults(
                query: query,
                flathub: _flathub,
                packageKit: _packageKit,
                onOpen: (app) => _push(_AppView(app.id)),
                onOpenPackage: (p) => _push(_PackageView(p)),
                action: _actionButton,
                packageAction: _packageAction,
              ),
            _InstalledView() => _InstalledTab(
                installed: _installed,
                flatpak: _flatpak,
                packageKit: _packageKit,
                onOpen: (id) => _push(_AppView(id)),
                onChanged: _refreshInstalled,
              ),
            _PackageView(:final package) => _PackageDetails(
                packageKit: _packageKit,
                package: package,
                action: (p) => _packageAction(p, large: true),
              ),
            _AppView(:final id) => _AppDetails(
                flathub: _flathub,
                id: id,
                action: (app) => _actionButton(app, large: true),
              ),
          },
        ),
      ),
    );
  }
}

typedef _ActionBuilder = Widget Function(StoreApp app);
typedef _PackageActionBuilder = Widget Function(SystemPackage package);

class _AppIcon extends StatelessWidget {
  const _AppIcon(this.url, {this.size = 64});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? url = this.url;
    return SizedBox.square(
      dimension: size,
      child: url == null
          ? Icon(Icons.apps_rounded, size: size * 0.8)
          : Image.network(
              url,
              fit: BoxFit.contain,
              cacheWidth: (size * 2).round(),
              errorBuilder: (context, _, __) => Icon(Icons.apps_rounded, size: size * 0.8),
            ),
    );
  }
}

/// Loads a list and shows a spinner / error / content.
class _Loader<T> extends StatefulWidget {
  const _Loader({required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't reach Flathub",
            subtitle: "Check your internet connection.",
            action: OutlinedButton(
              onPressed: () => setState(() => _future = widget.load()),
              child: const Text("Try again"),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.flathub,
    required this.onOpen,
    required this.onCategory,
    required this.action,
  });

  final FlathubClient flathub;
  final ValueChanged<StoreApp> onOpen;
  final ValueChanged<StoreCategory> onCategory;
  final _ActionBuilder action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _Loader<List<List<StoreApp>>>(
      load: () => Future.wait([
        flathub.collection("popular", perPage: 12),
        flathub.collection("trending", perPage: 12),
        flathub.collection("recently-updated", perPage: 12),
      ]),
      builder: (context, data) {
        final StoreApp? featured = data[1].isNotEmpty ? data[1].first : data[0].firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (featured != null)
              Material(
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                child: InkWell(
                  onTap: () => onOpen(featured),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        _AppIcon(featured.icon, size: 96),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("TRENDING ON FLATHUB",
                                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                              Text(featured.name, style: theme.textTheme.headlineMedium),
                              Text(featured.summary, style: theme.textTheme.titleMedium),
                            ],
                          ),
                        ),
                        action(featured),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final StoreCategory c in storeCategories)
                  ActionChip(label: Text(c.label), onPressed: () => onCategory(c)),
              ],
            ),
            for (final (String title, List<StoreApp> apps) in [
              ("Popular", data[0]),
              ("Trending", data[1]),
              ("New & Updated", data[2]),
            ]) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              _CardGrid(apps: apps, onOpen: onOpen, action: action),
            ],
          ],
        );
      },
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.apps, required this.onOpen, required this.action});

  final List<StoreApp> apps;
  final ValueChanged<StoreApp> onOpen;
  final _ActionBuilder action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 96,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final StoreApp app = apps[i];
        return ZenitSection(
          child: InkWell(
            onTap: () => onOpen(app),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _AppIcon(app.icon, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(app.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                            ),
                            if (app.verified)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.verified_rounded, size: 14, color: theme.colorScheme.primary),
                              ),
                          ],
                        ),
                        Text(app.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  action(app),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({required this.title, required this.load, required this.onOpen, required this.action});

  final String title;
  final Future<List<StoreApp>> Function() load;
  final ValueChanged<StoreApp> onOpen;
  final _ActionBuilder action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _Loader<List<StoreApp>>(
      load: load,
      builder: (context, apps) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (apps.isEmpty)
            const EmptyState(icon: Icons.search_off_rounded, title: "Nothing found")
          else
            _CardGrid(apps: apps, onOpen: onOpen, action: action),
        ],
      ),
    );
  }
}

/// Flathub's apps, then the distribution's packages.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.flathub,
    required this.packageKit,
    required this.onOpen,
    required this.onOpenPackage,
    required this.action,
    required this.packageAction,
  });

  final String query;
  final FlathubClient flathub;
  final PackageKitClient? packageKit;
  final ValueChanged<StoreApp> onOpen;
  final ValueChanged<SystemPackage> onOpenPackage;
  final _ActionBuilder action;
  final _PackageActionBuilder packageAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PackageKitClient? packageKit = this.packageKit;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text("Results for “$query”", style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        _InlineLoader<List<StoreApp>>(
          load: () => flathub.search(query),
          errorTitle: "Couldn't reach Flathub",
          builder: (context, apps) => apps.isEmpty
              ? const _Note("No apps on Flathub")
              : _CardGrid(apps: apps, onOpen: onOpen, action: action),
        ),
        if (packageKit != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
            child: Text("System packages", style: theme.textTheme.titleLarge),
          ),
          _InlineLoader<List<SystemPackage>>(
            load: () => packageKit.search(query),
            errorTitle: "Couldn't search the system's packages",
            builder: (context, packages) => packages.isEmpty
                ? const _Note("No packages")
                : SettingsGroup(
                    children: [
                      for (final SystemPackage p in packages.take(30))
                        SettingsRow(
                          icon: Icons.inventory_2_outlined,
                          title: p.name,
                          subtitle: p.summary,
                          onTap: () => onOpenPackage(p),
                          trailing: packageAction(p),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

/// Loads within a list: a spinner, a short error, then the content.
class _InlineLoader<T> extends StatefulWidget {
  const _InlineLoader({
    required this.load,
    required this.builder,
    required this.errorTitle,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final String errorTitle;

  @override
  State<_InlineLoader<T>> createState() => _InlineLoaderState<T>();
}

class _InlineLoaderState<T> extends State<_InlineLoader<T>> {
  late Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Row(
            children: [
              Expanded(child: _Note("${widget.errorTitle}: ${snapshot.error}")),
              TextButton(
                onPressed: () => setState(() => _future = widget.load()),
                child: const Text("Try again"),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _PackageDetails extends StatelessWidget {
  const _PackageDetails({
    required this.packageKit,
    required this.package,
    required this.action,
  });

  final PackageKitClient? packageKit;
  final SystemPackage package;
  final _PackageActionBuilder action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PackageKitClient? packageKit = this.packageKit;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: ShapeDecoration(
                shape: const CircleBorder(),
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package.name, style: theme.textTheme.headlineMedium),
                  Text(
                    "System package${packageKit != null ? " (${packageKit.backend})" : ""}",
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(package.summary, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            action(package),
          ],
        ),
        const SizedBox(height: 24),
        if (packageKit != null)
          _InlineLoader<SystemPackageDetails?>(
            load: () => packageKit.details(package),
            errorTitle: "Couldn't get the details",
            builder: (context, d) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d != null && d.description.isNotEmpty) ...[
                  SelectableText(
                    d.description,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                ],
                SettingsGroup(
                  title: "Information",
                  children: [
                    if (package.version.isNotEmpty)
                      InfoRow(label: "Version", value: package.version),
                    if (package.arch.isNotEmpty)
                      InfoRow(label: "Architecture", value: package.arch),
                    if (package.origin.isNotEmpty)
                      InfoRow(
                        label: "Source",
                        value: package.origin.replaceFirst("installed:", ""),
                      ),
                    if (d?.license != null)
                      InfoRow(label: "License", value: d!.license!),
                    if (d?.downloadSize != null && d!.downloadSize! > 0)
                      InfoRow(
                        label: "Download size",
                        value: formatBytes(d.downloadSize!),
                      ),
                    if (d?.size != null && d!.size! > 0)
                      InfoRow(
                        label: "Installed size",
                        value: formatBytes(d.size!),
                      ),
                    if (d?.url != null)
                      SettingsRow(
                        icon: Icons.public_rounded,
                        title: "Website",
                        subtitle: d!.url,
                        onTap: () => SystemUtils.open(d.url!),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Updates of the distribution's packages.
class _SystemUpdates extends StatefulWidget {
  const _SystemUpdates({required this.packageKit});

  final PackageKitClient packageKit;

  @override
  State<_SystemUpdates> createState() => _SystemUpdatesState();
}

class _SystemUpdatesState extends State<_SystemUpdates> {
  late Future<List<SystemPackage>> _updates = widget.packageKit.updates();
  PackageProgress? _progress;

  Future<void> _install(List<SystemPackage> updates) async {
    setState(() => _progress = const PackageProgress("Starting…", null));
    String? error;
    try {
      await widget.packageKit.update(updates, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
    } on PackageKitException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() {
      _progress = null;
      _updates = widget.packageKit.updates();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null ? "The system is up to date" : "Couldn't update: $error",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<List<SystemPackage>>(
      future: _updates,
      builder: (context, snapshot) {
        final List<SystemPackage>? updates = snapshot.data;
        final PackageProgress? progress = _progress;
        final int security =
            updates?.where((u) => u.securityUpdate).length ?? 0;
        return SettingsGroup(
          title: "System updates",
          children: [
            SettingsRow(
              icon: Icons.system_update_alt_rounded,
              title: snapshot.hasError
                  ? "Couldn't check for updates"
                  : updates == null
                      ? "Checking for updates…"
                      : updates.isEmpty
                          ? "Your system is up to date"
                          : "${updates.length} update${updates.length == 1 ? "" : "s"} available",
              subtitle: progress?.status ??
                  (security > 0
                      ? "$security security update${security == 1 ? "" : "s"}"
                      : null),
              trailing: progress != null
                  ? SizedBox(
                      width: 140,
                      child: LinearProgressIndicator(
                        value: progress.percent == null
                            ? null
                            : progress.percent! / 100,
                      ),
                    )
                  : updates != null && updates.isNotEmpty
                      ? FilledButton(
                          onPressed: () => _install(updates),
                          child: const Text("Update system"),
                        )
                      : snapshot.hasError
                          ? TextButton(
                              onPressed: () => setState(
                                () => _updates = widget.packageKit.updates(),
                              ),
                              child: const Text("Try again"),
                            )
                          : null,
            ),
            if (updates != null && updates.isNotEmpty && progress == null)
              for (final SystemPackage u in updates.take(8))
                SettingsRow(
                  title: u.name,
                  subtitle: "${u.version}${u.summary.isNotEmpty ? " · ${u.summary}" : ""}",
                ),
            if (updates != null && updates.length > 8 && progress == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  "and ${updates.length - 8} more",
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppDetails extends StatelessWidget {
  const _AppDetails({required this.flathub, required this.id, required this.action});

  final FlathubClient flathub;
  final String id;
  final _ActionBuilder action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _Loader<StoreAppDetails>(
      load: () => flathub.details(id),
      builder: (context, d) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Row(
            children: [
              _AppIcon(d.app.icon, size: 112),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.app.name, style: theme.textTheme.headlineMedium),
                    if (d.app.developer != null) Text(d.app.developer!, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(d.app.summary, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              action(d.app),
            ],
          ),
          if (d.screenshots.isNotEmpty) ...[
            const SizedBox(height: 24),
            _Screenshots(urls: d.screenshots),
          ],
          const SizedBox(height: 24),
          SelectableText(d.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: 24),
          SettingsGroup(
            title: "Information",
            children: [
              if (d.version != null) InfoRow(label: "Version", value: d.version!),
              if (d.license != null) InfoRow(label: "License", value: d.license!),
              if (d.downloadSize != null) InfoRow(label: "Download size", value: formatBytes(d.downloadSize!)),
              if (d.installedSize != null) InfoRow(label: "Installed size", value: formatBytes(d.installedSize!)),
              InfoRow(label: "Flathub ID", value: d.app.id),
              if (d.homepage != null)
                SettingsRow(
                  icon: Icons.public_rounded,
                  title: "Website",
                  subtitle: d.homepage,
                  onTap: () => SystemUtils.open(d.homepage!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Screenshots extends StatefulWidget {
  const _Screenshots({required this.urls});
  final List<String> urls;

  @override
  State<_Screenshots> createState() => _ScreenshotsState();
}

class _ScreenshotsState extends State<_Screenshots> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 360,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.urls[i],
                      fit: BoxFit.contain,
                      errorBuilder: (context, _, __) => const Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              ),
              if (_page > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  ),
                ),
              if (_page < widget.urls.length - 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < widget.urls.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? theme.colorScheme.primary : theme.dividerColor,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _InstalledTab extends StatefulWidget {
  const _InstalledTab({
    required this.installed,
    required this.flatpak,
    required this.packageKit,
    required this.onOpen,
    required this.onChanged,
  });

  final Map<String, InstallScope> installed;
  final FlatpakManager flatpak;
  final PackageKitClient? packageKit;
  final ValueChanged<String> onOpen;
  final Future<void> Function() onChanged;

  @override
  State<_InstalledTab> createState() => _InstalledTabState();
}

class _InstalledTabState extends State<_InstalledTab> {
  String? _updating;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PackageKitClient? packageKit = widget.packageKit;
    if (!widget.flatpak.available) {
      if (packageKit != null) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [_SystemUpdates(packageKit: packageKit)],
        );
      }
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: "Flatpak isn't installed",
        subtitle: "The App Store installs applications from Flathub with Flatpak.",
      );
    }
    final List<String> ids = widget.installed.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (packageKit != null) ...[
          _SystemUpdates(packageKit: packageKit),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            Text("Installed apps", style: theme.textTheme.headlineSmall),
            const Spacer(),
            if (_updating != null)
              SizedBox(
                width: 260,
                child: Text(_updating!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _updating != null || ids.isEmpty
                  ? null
                  : () async {
                      setState(() => _updating = "Checking for updates…");
                      await widget.flatpak.updateAll((line) {
                        if (mounted && line.trim().isNotEmpty) setState(() => _updating = line.trim());
                      });
                      if (mounted) setState(() => _updating = null);
                      await widget.onChanged();
                    },
              icon: const Icon(Icons.system_update_alt_rounded),
              label: const Text("Update all"),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (ids.isEmpty)
          const EmptyState(icon: Icons.inbox_outlined, title: "No apps installed from Flathub yet")
        else
          SettingsGroup(
            children: [
              for (final String id in ids)
                SettingsRow(
                  icon: Icons.inventory_2_outlined,
                  title: id,
                  subtitle: widget.installed[id] == InstallScope.user ? "Installed for you" : "Installed system-wide",
                  onTap: () => widget.onOpen(id),
                  trailing: TextButton(onPressed: () => widget.flatpak.launch(id), child: const Text("Open")),
                ),
            ],
          ),
      ],
    );
  }
}
