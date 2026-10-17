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

import 'package:dahlia_apps/apps/activity_monitor/system_stats.dart';
import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final Map<String, String> _info = {};
  final _Distribution _distribution = _Distribution.load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _load() async {
    final Map<String, String> info = {};
    final String osRelease = _read("/etc/os-release") ?? "";
    info["Operating system"] =
        RegExp(r'^PRETTY_NAME="?([^"\n]*)"?', multiLine: true).firstMatch(osRelease)?.group(1) ?? "Linux";
    info["Kernel"] = _read("/proc/sys/kernel/osrelease") ?? "Unknown";
    info["Device name"] = Platform.localHostname;
    info["Processor"] = "${ProcFs.cpuModel()} × ${Platform.numberOfProcessors}";

    final String meminfo = _read("/proc/meminfo") ?? "";
    final int? memKb = int.tryParse(RegExp(r"MemTotal:\s+(\d+)").firstMatch(meminfo)?.group(1) ?? "");
    if (memKb != null) info["Memory"] = formatBytes(memKb * 1024);

    final List<String> gpus = [];
    final Directory drm = Directory("/sys/class/drm");
    if (drm.existsSync()) {
      for (final FileSystemEntity e in drm.listSync()) {
        final String name = e.path.split("/").last;
        if (!RegExp(r"^card\d+$").hasMatch(name)) continue;
        final String? uevent = _read("${e.path}/device/uevent");
        final String? driver = RegExp(r"^DRIVER=(.*)$", multiLine: true).firstMatch(uevent ?? "")?.group(1);
        if (driver != null) gpus.add(driver);
      }
    }
    if (gpus.isNotEmpty) info["Graphics"] = gpus.toSet().join(", ");

    final Map<String, String> env = Platform.environment;
    info["Desktop"] = "Pangolin (${env["XDG_CURRENT_DESKTOP"] ?? "dahliaOS"})";
    // The river the session runs (Pangolin's own, not necessarily on PATH).
    final String? river =
        (await SystemUtils.run(env["PANGOLIN_RIVER"] ?? "river", ["-version"]))?.trim();
    info["Compositor"] = river != null ? "river $river" : (env["XDG_SESSION_DESKTOP"] ?? "Unknown");
    info["Windowing system"] = env["WAYLAND_DISPLAY"] != null ? "Wayland" : "X11";
    info["Dart"] = Platform.version.split(" ").first;

    if (mounted) setState(() => _info.addAll(info));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageBody(
      children: [
        const _Banner(),
        const SizedBox(height: 24),
        _DistributionCard(distribution: _distribution),
        const SizedBox(height: 8),
        SettingsGroup(
          title: "This device",
          children: [
            for (final MapEntry<String, String> e in _info.entries) InfoRow(label: e.key, value: e.value),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _info.entries.map((e) => "${e.key}: ${e.value}").join("\n")),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("System information copied")),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text("Copy"),
            ),
            TextButton.icon(
              onPressed: () => _showLicenses(context),
              icon: const Icon(Icons.gavel_rounded),
              label: const Text("Licenses"),
            ),
            TextButton.icon(
              onPressed: () => SystemUtils.open("https://dahliaos.io"),
              icon: const Icon(Icons.public_rounded),
              label: const Text("dahliaos.io"),
            ),
          ],
        ),
      ],
    );
  }
}

bool _licensesRegistered = false;

/// The licenses of everything in Pangolin: the Dart packages' (which Flutter
/// bundles) and those of what isn't one (river, the Inter font), from the
/// license files installed with Pangolin (see docs/DISTRIBUTING.md).
void _showLicenses(BuildContext context) {
  if (!_licensesRegistered) {
    _licensesRegistered = true;
    LicenseRegistry.addLicense(_installedLicenses);
  }
  showLicensePage(
    context: context,
    applicationName: "Pangolin",
    applicationLegalese: "Pangolin and the dahliaOS apps: Apache License 2.0. "
        "river (the compositor): GNU GPL version 3.",
  );
}

Stream<LicenseEntry> _installedLicenses() async* {
  // <prefix>/lib/dahlia-apps/dahlia_apps → <prefix>/share/licenses/pangolin
  final String prefix = File(Platform.resolvedExecutable).parent.parent.parent.path;
  String? read(String name) {
    try {
      return File("$prefix/share/licenses/pangolin/$name").readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  yield LicenseEntryWithLineBreaks(
    ["river"],
    "Pangolin's compositor is river (https://codeberg.org/river/river) with "
    "Pangolin's changes. It is free software: you can redistribute it and/or "
    "modify it under the terms of the GNU General Public License, version 3 "
    "only. Its source code, with Pangolin's changes, is part of Pangolin's "
    "source code (river-main/river).\n\n${read("GPL-3.0-only.txt") ?? ""}",
  );
  final String? ofl = read("OFL-1.1-Inter.txt");
  if (ofl != null) yield LicenseEntryWithLineBreaks(["Inter (font)"], ofl);
}

/// The dahliaOS waves in the accent color, with the logo.
class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(theme.colorScheme.primary, BlendMode.color),
              child: Image.asset("assets/images/modern.png", fit: BoxFit.cover),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset("assets/images/dahliaOS-white.png", height: 56),
                  const SizedBox(height: 10),
                  Text(
                    "Pangolin desktop on river",
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Linux distribution Pangolin runs on, from os-release(5).
class _Distribution {
  const _Distribution({
    required this.name,
    this.version,
    this.homeUrl,
    this.logo,
  });

  factory _Distribution.load() {
    String text = "";
    for (final String path in ["/etc/os-release", "/usr/lib/os-release"]) {
      try {
        text = File(path).readAsStringSync();
        break;
      } on FileSystemException {
        continue;
      }
    }
    String? field(String key) {
      final String? value = RegExp('^$key=(.*)\$', multiLine: true)
          .firstMatch(text)
          ?.group(1)
          ?.trim()
          .replaceAll(RegExp(r'^"|"$'), "")
          .replaceAll("'", "");
      return value == null || value.isEmpty ? null : value;
    }

    final String? logoName = field("LOGO");
    return _Distribution(
      name: field("PRETTY_NAME") ?? field("NAME") ?? "Linux",
      version: field("VERSION"),
      homeUrl: field("HOME_URL"),
      logo: logoName == null ? null : _findIcon(logoName),
    );
  }

  final String name;
  final String? version;
  final String? homeUrl;

  /// A PNG of the distribution's logo (os-release LOGO, looked up in the
  /// icon themes as desktops do).
  final File? logo;

  static File? _findIcon(String name) {
    final Map<String, String> env = Platform.environment;
    final String home = env["HOME"] ?? "";
    final List<String> dataDirs = [
      env["XDG_DATA_HOME"] ?? "$home/.local/share",
      ...(env["XDG_DATA_DIRS"] ?? "/usr/local/share:/usr/share")
          .split(":")
          .where((d) => d.isNotEmpty),
    ];
    // Largest bitmap first.
    const List<String> sizes = [
      "512x512", "256x256", "192x192", "128x128", "96x96", "64x64", "48x48",
    ];
    for (final String dir in dataDirs) {
      for (final String size in sizes) {
        final File file = File("$dir/icons/hicolor/$size/apps/$name.png");
        if (file.existsSync()) return file;
      }
    }
    for (final String dir in [...dataDirs.map((d) => "$d/pixmaps"), "/usr/share/pixmaps"]) {
      final File file = File("$dir/$name.png");
      if (file.existsSync()) return file;
    }
    return null;
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.distribution});

  final _Distribution distribution;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final File? logo = distribution.logo;
    return SettingsGroup(
      title: "Operating system",
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: logo != null
                    ? Image.file(logo)
                    : Icon(
                        Icons.computer_rounded,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distribution.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Pangolin desktop from dahliaOS",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (distribution.homeUrl != null)
                TextButton(
                  onPressed: () => SystemUtils.open(distribution.homeUrl!),
                  child: const Text("Website"),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
