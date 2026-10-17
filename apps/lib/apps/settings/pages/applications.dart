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

import 'dart:io';

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

class _App {
  _App(this.id, this.path, this.name, this.comment, this.exec, this.flatpak);
  final String id;
  final String path;
  final String name;
  final String comment;
  final String exec;
  final String? flatpak;
  bool get dahlia => id.startsWith("io.dahliaos.");
}

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key});

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  List<_App> _apps = [];
  String _query = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final Map<String, _App> apps = {};
    final List<String> dirs = [
      p.join(xdg.dataHome.path, "applications"),
      ...xdg.dataDirs.map((d) => p.join(d.path, "applications")),
    ];
    for (final String dir in dirs) {
      final Directory d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final FileSystemEntity e in d.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith(".desktop")) continue;
        final String id = p.basenameWithoutExtension(e.path);
        if (apps.containsKey(id)) continue; // earlier dirs take precedence
        final Map<String, String> fields = {};
        bool inEntry = false;
        try {
          for (final String line in e.readAsLinesSync()) {
            if (line.startsWith("[")) inEntry = line.trim() == "[Desktop Entry]";
            if (!inEntry) continue;
            final int eq = line.indexOf("=");
            if (eq > 0) fields.putIfAbsent(line.substring(0, eq).trim(), () => line.substring(eq + 1).trim());
          }
        } on FileSystemException {
          continue;
        }
        if (fields["Type"] != "Application" || fields["NoDisplay"] == "true" || fields["Hidden"] == "true") {
          continue;
        }
        apps[id] = _App(
          id,
          e.path,
          fields["Name"] ?? id,
          fields["Comment"] ?? "",
          fields["Exec"] ?? "",
          fields["X-Flatpak"],
        );
      }
    }
    setState(() {
      _apps = apps.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  Future<void> _uninstall(_App app) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Uninstall ${app.name}?"),
        content: const Text("The application and its data will be removed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Uninstall")),
        ],
      ),
    );
    if (ok != true) return;
    final bool user = app.path.startsWith(xdg.dataHome.path);
    final String? out = await SystemUtils.run(
      "flatpak",
      ["uninstall", user ? "--user" : "--system", "-y", "--noninteractive", app.flatpak!],
      timeout: const Duration(minutes: 5),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(out != null ? "${app.name} was uninstalled" : "Couldn't uninstall ${app.name}")),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final String q = _query.toLowerCase();
    final List<_App> apps = _apps
        .where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.id.toLowerCase().contains(q))
        .toList();

    return SettingsPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: SearchField(hint: "Search ${_apps.length} apps", onChanged: (v) => setState(() => _query = v))),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => SystemUtils.launchApp("store"),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text("Get more apps"),
              ),
            ],
          ),
        ),
        SettingsGroup(
          children: [
            for (final _App app in apps)
              SettingsRow(
                title: app.name,
                subtitle: app.comment.isNotEmpty ? app.comment : app.id,
                icon: app.dahlia
                    ? Icons.auto_awesome_rounded
                    : app.flatpak != null
                        ? Icons.inventory_2_outlined
                        : Icons.apps_rounded,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (app.flatpak != null)
                      TextButton(onPressed: () => _uninstall(app), child: const Text("Uninstall")),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
