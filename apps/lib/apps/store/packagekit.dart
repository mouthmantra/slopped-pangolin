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

import 'package:dahlia_apps/kit/system.dart';
import 'package:dbus/dbus.dart';

/// A package of the distribution, as PackageKit names it.
class SystemPackage {
  const SystemPackage({
    required this.id,
    required this.summary,
    required this.info,
  });

  /// "name;version;arch;data" (data: the repository, or "installed").
  final String id;
  final String summary;

  /// PackageKit's info: installed, available, or for updates how important.
  final int info;

  List<String> get _fields => id.split(";");
  String get name => _fields.first;
  String get version => _fields.length > 1 ? _fields[1] : "";
  String get arch => _fields.length > 2 ? _fields[2] : "";
  String get origin => _fields.length > 3 ? _fields[3] : "";

  bool get installed =>
      info == PackageKitClient._infoInstalled || origin.startsWith("installed");

  bool get securityUpdate =>
      info == PackageKitClient._infoSecurity ||
      info == PackageKitClient._infoCritical;
}

class SystemPackageDetails {
  const SystemPackageDetails({
    required this.package,
    required this.description,
    this.url,
    this.license,
    this.size,
    this.downloadSize,
  });

  final SystemPackage package;
  final String description;
  final String? url;
  final String? license;
  final int? size;
  final int? downloadSize;
}

/// How a transaction is going.
class PackageProgress {
  const PackageProgress(this.status, this.percent);

  final String status;

  /// 0-100, null when unknown.
  final int? percent;
}

class PackageKitException implements Exception {
  const PackageKitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The distribution's packages through PackageKit (system bus), whatever
/// the package manager (dnf, apt, pacman, zypper, apk, ...). Installing,
/// removing and updating ask for permission through the session's polkit
/// agent.
class PackageKitClient {
  PackageKitClient._(this._client, this._root, {required this.backend});

  final DBusClient _client;
  final DBusRemoteObject _root;

  /// The package manager PackageKit runs (e.g. "dnf").
  final String backend;

  static const String _name = "org.freedesktop.PackageKit";
  static const String _transaction = "org.freedesktop.PackageKit.Transaction";

  // PackageKit 1.x enums (stable across 1.x; 2.x renumbers them).
  static const int _filterNone = 1 << 1;
  static const int _filterInstalled = 1 << 2;
  static const int _filterNotDevelopment = 1 << 5;
  static const int _filterNewest = 1 << 16;
  static const int _filterArch = 1 << 18;
  static const int _filterNotSource = 1 << 21;
  static const int _flagOnlyTrusted = 1 << 1;
  static const int _infoInstalled = 1;
  static const int _infoSecurity = 8;
  static const int _infoCritical = 26;
  static const int _exitSuccess = 1;
  static const int _exitCancelled = 3;

  /// Connects when PackageKit is there (running or startable) and speaks
  /// the protocol this client knows (1.x).
  static Future<PackageKitClient?> connect() async {
    if (!SystemUtils.systemBusAvailable) return null;
    final DBusClient client = DBusClient.system();
    try {
      final List<String> activatable = await client.listActivatableNames();
      final List<String> running = await client.listNames();
      if (!activatable.contains(_name) && !running.contains(_name)) {
        await client.close();
        return null;
      }
      final DBusRemoteObject root = DBusRemoteObject(
        client,
        name: _name,
        path: DBusObjectPath("/org/freedesktop/PackageKit"),
      );
      final int major = (await root.getProperty(
        _name,
        "VersionMajor",
        signature: DBusSignature("u"),
      ))
          .asUint32();
      if (major != 1) {
        await client.close();
        return null;
      }
      final String backend = (await root.getProperty(
        _name,
        "BackendName",
        signature: DBusSignature("s"),
      ))
          .asString();
      return PackageKitClient._(client, root, backend: backend);
    } on Object {
      await client.close();
      return null;
    }
  }

  Future<void> close() => _client.close();

  /// Packages whose name matches [query], one per name (the installed one
  /// when it is), without development, debug and source packages.
  Future<List<SystemPackage>> search(String query) async {
    final List<String> terms =
        query.trim().split(RegExp(r"\s+")).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return [];
    final List<SystemPackage> found = [];
    await _run(
      "SearchNames",
      [
        const DBusUint64(
          _filterNotDevelopment | _filterNewest | _filterArch | _filterNotSource,
        ),
        DBusArray.string(terms),
      ],
      onPackage: found.add,
    );
    final Map<String, SystemPackage> byName = {};
    for (final SystemPackage package in found) {
      if (package.name.endsWith("-debuginfo") ||
          package.name.endsWith("-debugsource") ||
          package.name.endsWith("-dbgsym")) {
        continue;
      }
      final SystemPackage? seen = byName[package.name];
      if (seen == null || (package.installed && !seen.installed)) {
        byName[package.name] = package;
      }
    }
    final String lower = query.trim().toLowerCase();
    // Exact matches first, then the shortest names (the main package before
    // its plugins and translations).
    return byName.values.toList()
      ..sort((a, b) {
        final bool ea = a.name.toLowerCase() == lower;
        final bool eb = b.name.toLowerCase() == lower;
        if (ea != eb) return ea ? -1 : 1;
        final int length = a.name.length.compareTo(b.name.length);
        return length != 0 ? length : a.name.compareTo(b.name);
      });
  }

  /// The installed (or else newest) package called [name].
  Future<SystemPackage?> resolve(String name) async {
    final List<SystemPackage> found = [];
    await _run(
      "Resolve",
      [
        const DBusUint64(_filterNewest | _filterArch | _filterNotSource),
        DBusArray.string([name]),
      ],
      onPackage: found.add,
    );
    return found.where((p) => p.installed).firstOrNull ?? found.firstOrNull;
  }

  Future<SystemPackageDetails?> details(SystemPackage package) async {
    SystemPackageDetails? details;
    await _run(
      "GetDetails",
      [
        DBusArray.string([package.id]),
      ],
      onDetails: (data) {
        int? number(String key) => switch (data[key]) {
              final DBusUint64 v => v.value,
              final DBusUint32 v => v.value,
              _ => null,
            };
        String? text(String key) {
          final DBusValue? v = data[key];
          if (v is! DBusString || v.value.isEmpty) return null;
          return v.value;
        }

        details = SystemPackageDetails(
          package: package,
          description: text("description") ?? package.summary,
          url: text("url"),
          license: text("license"),
          size: number("size"),
          downloadSize: number("download-size"),
        );
      },
    );
    return details;
  }

  /// Updates waiting to be installed.
  Future<List<SystemPackage>> updates() async {
    final List<SystemPackage> found = [];
    await _run(
      "GetUpdates",
      [const DBusUint64(_filterNone)],
      onPackage: found.add,
    );
    return found;
  }

  /// Installed packages (used to tell which search results are installed
  /// cheaply, by name).
  Future<Set<String>> installedNames() async {
    final Set<String> names = {};
    await _run(
      "GetPackages",
      [const DBusUint64(_filterInstalled)],
      onPackage: (p) => names.add(p.name),
    );
    return names;
  }

  Future<void> install(
    SystemPackage package,
    void Function(PackageProgress progress) onProgress,
  ) =>
      _run(
        "InstallPackages",
        [
          const DBusUint64(_flagOnlyTrusted),
          DBusArray.string([package.id]),
        ],
        onProgress: onProgress,
      );

  Future<void> remove(
    SystemPackage package,
    void Function(PackageProgress progress) onProgress,
  ) =>
      _run(
        "RemovePackages",
        [
          const DBusUint64(_flagOnlyTrusted),
          DBusArray.string([package.id]),
          // What needs it goes too (as when removed with the package
          // manager), what it needed stays.
          const DBusBoolean(true),
          const DBusBoolean(false),
        ],
        onProgress: onProgress,
      );

  Future<void> update(
    List<SystemPackage> packages,
    void Function(PackageProgress progress) onProgress,
  ) =>
      _run(
        "UpdatePackages",
        [
          const DBusUint64(_flagOnlyTrusted),
          DBusArray.string([for (final SystemPackage p in packages) p.id]),
        ],
        onProgress: onProgress,
      );

  /// Runs one transaction to its end. Throws [PackageKitException] when it
  /// fails (not when cancelled, e.g. permission not given: that's
  /// [PackageKitException] too, with a message saying so).
  Future<void> _run(
    String method,
    List<DBusValue> args, {
    void Function(SystemPackage package)? onPackage,
    void Function(Map<String, DBusValue> data)? onDetails,
    void Function(PackageProgress progress)? onProgress,
  }) async {
    final DBusObjectPath path = (await _root.callMethod(
      _name,
      "CreateTransaction",
      [],
      replySignature: DBusSignature("o"),
    ))
        .returnValues
        .first
        .asObjectPath();
    final DBusRemoteObject transaction =
        DBusRemoteObject(_client, name: _name, path: path);

    final Completer<int> finished = Completer();
    String? error;
    int status = 0;
    int? percent;
    // One stream for everything the transaction says, so that it all comes
    // in order (Finished last).
    final StreamSubscription<DBusSignal> subscription =
        DBusSignalStream(_client, sender: _name, path: path).listen((signal) {
      final List<DBusValue> v = signal.values;
      if (signal.interface == "org.freedesktop.DBus.Properties" &&
          signal.name == "PropertiesChanged" &&
          signal.signature == DBusSignature("sa{sv}as")) {
        if (v[0].asString() != _transaction) return;
        final Map<String, DBusValue> changed = v[1].asStringVariantDict();
        final DBusValue? newStatus = changed["Status"];
        final DBusValue? newPercent = changed["Percentage"];
        if (newStatus is DBusUint32) status = newStatus.value;
        if (newPercent is DBusUint32) {
          // 101: unknown.
          percent = newPercent.value <= 100 ? newPercent.value : null;
        }
        if (!finished.isCompleted) {
          onProgress?.call(PackageProgress(_statusText(status), percent));
        }
        return;
      }
      if (signal.interface != _transaction) return;
      switch (signal.name) {
        case "Package" when signal.signature == DBusSignature("uss"):
          onPackage?.call(
            SystemPackage(
              info: v[0].asUint32(),
              id: v[1].asString(),
              summary: v[2].asString(),
            ),
          );
        case "Details" when signal.signature == DBusSignature("a{sv}"):
          onDetails?.call(v[0].asStringVariantDict());
        case "ErrorCode" when signal.signature == DBusSignature("us"):
          error = v[1].asString();
        case "Finished" when signal.signature == DBusSignature("uu"):
          if (!finished.isCompleted) finished.complete(v[0].asUint32());
      }
    });

    try {
      await transaction.callMethod(
        _transaction,
        "SetHints",
        [
          DBusArray.string([
            "locale=${_locale()}",
            // Asking for a password is fine.
            "interactive=true",
            "background=false",
          ]),
        ],
        replySignature: DBusSignature(""),
      );
      await transaction.callMethod(
        _transaction,
        method,
        args,
        replySignature: DBusSignature(""),
      );
      final int exit = await finished.future;
      if (exit == _exitSuccess) return;
      if (exit == _exitCancelled) {
        throw PackageKitException(error ?? "Cancelled");
      }
      throw PackageKitException(error ?? "Something went wrong");
    } on DBusMethodResponseException catch (e) {
      throw PackageKitException(_describe(e));
    } finally {
      unawaited(subscription.cancel());
    }
  }

  static String _describe(DBusMethodResponseException e) {
    final String name = e.errorName;
    if (name.endsWith("RefusedByPolicy") || name.endsWith("NotAuthorized")) {
      return "Permission wasn't given";
    }
    final List<DBusValue> values = e.response.values;
    if (values.isNotEmpty && values.first is DBusString) {
      return values.first.asString();
    }
    return name;
  }

  static String _locale() {
    final String locale = Platform.environment["LC_ALL"] ??
        Platform.environment["LC_MESSAGES"] ??
        Platform.environment["LANG"] ??
        "C";
    return locale.isEmpty ? "C" : locale;
  }

  // PackageKit 1.x statuses (the later ones differ between versions).
  static String _statusText(int status) => switch (status) {
        1 => "Waiting…",
        2 => "Getting ready…",
        4 || 5 => "Looking things up…",
        6 => "Removing…",
        7 || 20 || 21 || 22 || 23 || 24 || 25 => "Updating sources…",
        8 => "Downloading…",
        9 => "Installing…",
        10 => "Updating…",
        11 => "Cleaning up…",
        13 => "Resolving dependencies…",
        14 => "Checking signatures…",
        15 => "Testing changes…",
        16 => "Applying changes…",
        17 => "Requesting data…",
        18 => "Finished",
        19 => "Cancelling…",
        27 => "Loading cache…",
        30 => "Waiting for another package manager…",
        31 => "Waiting for permission…",
        _ => "Working…",
      };
}
