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
import 'dart:convert';
import 'dart:io';

import 'package:dahlia_apps/kit/system.dart';
import 'package:http/http.dart' as http;

/// An application listed on Flathub.
class StoreApp {
  StoreApp({
    required this.id,
    required this.name,
    required this.summary,
    this.icon,
    this.developer,
    this.verified = false,
    this.installsLastMonth,
  });

  factory StoreApp.fromHit(Map<String, Object?> json) => StoreApp(
        id: json["app_id"]! as String,
        name: json["name"] as String? ?? json["app_id"]! as String,
        summary: json["summary"] as String? ?? "",
        icon: json["icon"] as String?,
        developer: json["developer_name"] as String?,
        verified: json["verification_verified"] == true || json["verification_verified"] == "true",
        installsLastMonth: json["installs_last_month"] as int?,
      );

  final String id;
  final String name;
  final String summary;
  final String? icon;
  final String? developer;
  final bool verified;
  final int? installsLastMonth;
}

class StoreAppDetails {
  StoreAppDetails({
    required this.app,
    required this.description,
    required this.screenshots,
    this.version,
    this.license,
    this.homepage,
    this.downloadSize,
    this.installedSize,
  });

  final StoreApp app;
  final String description;
  final List<String> screenshots;
  final String? version;
  final String? license;
  final String? homepage;
  final int? downloadSize;
  final int? installedSize;
}

class StoreCategory {
  const StoreCategory(this.id, this.label);
  final String id;
  final String label;
}

const List<StoreCategory> storeCategories = [
  StoreCategory("Office", "Productivity"),
  StoreCategory("Graphics", "Graphics & Photography"),
  StoreCategory("AudioVideo", "Audio & Video"),
  StoreCategory("Development", "Developer Tools"),
  StoreCategory("Game", "Games"),
  StoreCategory("Education", "Education"),
  StoreCategory("Network", "Networking"),
  StoreCategory("Science", "Science"),
  StoreCategory("Utility", "Utilities"),
  StoreCategory("System", "System"),
];

/// Read-only access to the Flathub catalog.
class FlathubClient {
  static const String _base = "https://flathub.org/api/v2";
  final http.Client _http = http.Client();

  Future<Object?> _get(String path) async {
    final http.Response response = await _http
        .get(Uri.parse("$_base$path"), headers: {"Accept": "application/json"})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException("Flathub returned ${response.statusCode}", uri: Uri.parse("$_base$path"));
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  List<StoreApp> _hits(Object? json) => ((json! as Map)["hits"] as List)
      .cast<Map>()
      .map((e) => StoreApp.fromHit(e.cast<String, Object?>()))
      .toList();

  Future<List<StoreApp>> collection(String name, {int perPage = 24}) async =>
      _hits(await _get("/collection/$name?page=1&per_page=$perPage"));

  Future<List<StoreApp>> category(String category, {int perPage = 48}) async =>
      _hits(await _get("/collection/category/$category?page=1&per_page=$perPage"));

  Future<List<StoreApp>> search(String query) async {
    final http.Response response = await _http
        .post(
          Uri.parse("$_base/search"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"query": query}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw HttpException("Search failed (${response.statusCode})");
    return _hits(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<StoreAppDetails> details(String id) async {
    final Map<String, Object?> json = ((await _get("/appstream/$id"))! as Map).cast<String, Object?>();
    Map<String, Object?> summary = {};
    try {
      summary = ((await _get("/summary/$id"))! as Map).cast<String, Object?>();
    } on Object {
      // Sizes are optional.
    }

    final List<String> screenshots = [];
    for (final Map shot in (json["screenshots"] as List? ?? const []).cast<Map>()) {
      final List<Map> sizes = (shot["sizes"] as List? ?? const []).cast<Map>();
      if (sizes.isEmpty) continue;
      // Pick the largest rendition no wider than ~1200 px.
      sizes.sort((a, b) => int.parse("${a["width"]}").compareTo(int.parse("${b["width"]}")));
      final Map best = sizes.lastWhere(
        (s) => int.parse("${s["width"]}") <= 1248,
        orElse: () => sizes.first,
      );
      screenshots.add(best["src"] as String);
    }
    final List releases = json["releases"] as List? ?? const [];
    final Map urls = json["urls"] as Map? ?? const {};

    return StoreAppDetails(
      app: StoreApp(
        id: id,
        name: json["name"] as String? ?? id,
        summary: json["summary"] as String? ?? "",
        icon: json["icon"] as String?,
        developer: json["developer_name"] as String?,
      ),
      description: htmlToText(json["description"] as String? ?? ""),
      screenshots: screenshots,
      version: releases.isNotEmpty ? (releases.first as Map)["version"] as String? : null,
      license: json["project_license"] as String?,
      homepage: urls["homepage"] as String?,
      downloadSize: summary["download_size"] as int?,
      installedSize: summary["installed_size"] as int?,
    );
  }

  /// AppStream descriptions are a small HTML subset.
  static String htmlToText(String html) {
    return html
        .replaceAll(RegExp(r"<li>\s*"), "• ")
        .replaceAll(RegExp(r"</(p|li|ul|ol)>"), "\n")
        .replaceAll(RegExp("<[^>]+>"), "")
        .replaceAll("&amp;", "&")
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", '"')
        .replaceAll("&#39;", "'")
        .split("\n")
        .map((l) => l.trim())
        .join("\n")
        .replaceAll(RegExp(r"\n{3,}"), "\n\n")
        .trim();
  }
}

enum InstallScope { user, system }

/// Local flatpak installation management.
class FlatpakManager {
  bool get available => SystemUtils.which("flatpak") != null;

  /// Installed applications, mapped to their installation.
  Future<Map<String, InstallScope>> installed() async {
    final String? out =
        await SystemUtils.run("flatpak", ["list", "--app", "--columns=application,installation"]);
    final Map<String, InstallScope> apps = {};
    for (final String line in (out ?? "").split("\n")) {
      final List<String> parts = line.trim().split(RegExp(r"\s+"));
      if (parts.length < 2) continue;
      apps[parts[0]] = parts[1] == "user" ? InstallScope.user : InstallScope.system;
    }
    return apps;
  }

  Future<void> _ensureRemote() async {
    await SystemUtils.run(
      "flatpak",
      ["remote-add", "--user", "--if-not-exists", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo"],
      timeout: const Duration(minutes: 1),
    );
  }

  /// Installs [id] for the current user, reporting output lines as progress.
  Future<bool> install(String id, void Function(String line) onProgress) async {
    await _ensureRemote();
    return _stream(["install", "--user", "--noninteractive", "-y", "flathub", id], onProgress);
  }

  Future<bool> uninstall(String id, InstallScope scope, void Function(String line) onProgress) {
    return _stream(
      ["uninstall", scope == InstallScope.user ? "--user" : "--system", "--noninteractive", "-y", id],
      onProgress,
    );
  }

  Future<bool> updateAll(void Function(String line) onProgress) =>
      _stream(["update", "--user", "--noninteractive", "-y"], onProgress);

  Future<bool> _stream(List<String> args, void Function(String) onProgress) async {
    final Process process = await Process.start("flatpak", args);
    final StreamSubscription<String> out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onProgress);
    final StreamSubscription<String> err = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onProgress);
    final int code = await process.exitCode;
    await out.cancel();
    await err.cancel();
    return code == 0;
  }

  Future<void> launch(String id) async {
    await Process.start("flatpak", ["run", id], mode: ProcessStartMode.detached);
  }
}
