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

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/pam.dart';
import 'package:pangolin/services/session.dart';

enum SessionLockState {
  unlocked,

  /// Asked river to lock, waiting for every monitor to show the lock screen.
  locking,
  locked,
}

/// Pangolin's lock screen: the session is locked through river
/// (ext-session-lock-v1), the lock screen is a Flutter view on every monitor
/// and the password is checked with PAM.
class SessionLock extends ChangeNotifier {
  SessionLock._();

  static final SessionLock instance = SessionLock._();
  static final Logger _logger = Logger("SessionLock");

  bool supported = false;
  SessionLockState state = SessionLockState.unlocked;

  /// Lock screen views, one per monitor.
  List<int> views = const [];

  /// A password check is running.
  bool checking = false;

  /// Shown under the password field after a failed attempt.
  String? error;

  /// Increases at every failed attempt (the field shakes).
  int failures = 0;

  final List<Completer<void>> _lockWaiters = [];

  bool get isLocked => state != SessionLockState.unlocked;

  Future<void> init() async {
    PangolinSession.onNativeCall("lockStateChanged", (arguments) {
      final String? value = (arguments as Map?)?["state"] as String?;
      switch (value) {
        case "locked":
          state = SessionLockState.locked;
          _completeWaiters();
        case "unlocked" || "denied":
          if (value == "denied") {
            _logger.warning("river refused to lock the session");
          }
          state = SessionLockState.unlocked;
          views = const [];
          _completeWaiters();
      }
      notifyListeners();
    });
    PangolinSession.onNativeCall("lockViewsChanged", (arguments) {
      views = [
        for (final Object? id in ((arguments as Map?)?["views"] as List?) ?? const [])
          id! as int,
      ];
      notifyListeners();
    });
    try {
      supported = await PangolinSession.lockSupported();
    } on Object catch (e) {
      _logger.warning("Couldn't check for session lock support: $e");
    }
    if (supported && !Pam.available) {
      // Couldn't unlock: no locking at all.
      _logger.warning("PAM (libpam.so.0) isn't available: the screen won't lock");
      supported = false;
    }
    if (supported) unawaited(_followLogind());
  }

  ResourceHandle? _sleepInhibitor;

  /// Locks before the computer sleeps (lid closed, suspend from anywhere)
  /// and when asked through logind (`loginctl lock-session`).
  Future<void> _followLogind() async {
    try {
      final DBusClient system = DBusClient.system();
      final DBusRemoteObject manager = DBusRemoteObject(
        system,
        name: "org.freedesktop.login1",
        path: DBusObjectPath("/org/freedesktop/login1"),
      );
      await _inhibitSleep(manager);
      DBusRemoteObjectSignalStream(
        object: manager,
        interface: "org.freedesktop.login1.Manager",
        name: "PrepareForSleep",
        signature: DBusSignature("b"),
      ).listen((signal) async {
        final bool sleeping = signal.values.first.asBoolean();
        if (sleeping) {
          await lock();
          // Locked: let the computer sleep now.
          _sleepInhibitor?.toFile().closeSync();
          _sleepInhibitor = null;
        } else {
          await _inhibitSleep(manager);
        }
      });

      final DBusValue sessionPath = await manager
          .callMethod(
            "org.freedesktop.login1.Manager",
            "GetSessionByPID",
            [DBusUint32(pid)],
            replySignature: DBusSignature("o"),
          )
          .then((r) => r.values.first);
      final DBusRemoteObject session = DBusRemoteObject(
        system,
        name: "org.freedesktop.login1",
        path: sessionPath.asObjectPath(),
      );
      DBusRemoteObjectSignalStream(
        object: session,
        interface: "org.freedesktop.login1.Session",
        name: "Lock",
      ).listen((_) => unawaited(lock()));
    } on Object catch (e) {
      _logger.info("logind isn't available, no lock on suspend: $e");
    }
  }

  /// A delay inhibitor gives Pangolin time to lock before sleeping.
  Future<void> _inhibitSleep(DBusRemoteObject manager) async {
    if (_sleepInhibitor != null) return;
    try {
      final DBusMethodSuccessResponse reply = await manager.callMethod(
        "org.freedesktop.login1.Manager",
        "Inhibit",
        [
          const DBusString("sleep"),
          const DBusString("Pangolin"),
          const DBusString("Lock the screen before sleeping"),
          const DBusString("delay"),
        ],
        replySignature: DBusSignature("h"),
      );
      _sleepInhibitor = reply.values.first.asUnixFd();
    } on Object catch (e) {
      _logger.info("Couldn't delay sleep to lock first: $e");
    }
  }

  void _completeWaiters() {
    for (final Completer<void> waiter in _lockWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _lockWaiters.clear();
  }

  /// Locks the session. Completes once every monitor shows the lock screen
  /// (or locking failed), so that it is safe to suspend afterwards.
  Future<void> lock() async {
    if (!supported) return;
    if (state == SessionLockState.locked) return;
    final Completer<void> done = Completer();
    _lockWaiters.add(done);
    if (state == SessionLockState.unlocked) {
      error = null;
      final (bool started, List<int> lockViews) = await PangolinSession.lock();
      if (!started) {
        _completeWaiters();
        return;
      }
      state = SessionLockState.locking;
      views = lockViews;
      notifyListeners();
    }
    await done.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
  }

  /// Checks [password] and unlocks the session when it is right.
  Future<bool> unlock(String password) async {
    if (!isLocked || checking) return false;
    checking = true;
    error = null;
    notifyListeners();
    final PamResult result = await Pam.authenticate(password);
    checking = false;
    switch (result) {
      case PamResult.success:
        await PangolinSession.unlock();
        return true;
      case PamResult.wrongPassword:
        error = "Incorrect password, try again";
      case PamResult.unavailable:
        error = "Passwords can't be checked (PAM is unavailable)";
    }
    failures++;
    notifyListeners();
    return false;
  }

  /// The user's full name from the password database, or their login.
  static String get displayName {
    final String user = Pam.user;
    try {
      for (final String line in File("/etc/passwd").readAsLinesSync()) {
        final List<String> fields = line.split(":");
        if (fields.length > 4 && fields[0] == user) {
          final String gecos = fields[4].split(",").first.trim();
          if (gecos.isNotEmpty) return gecos;
        }
      }
    } on FileSystemException {
      // Fall back to the login.
    }
    return user;
  }
}
