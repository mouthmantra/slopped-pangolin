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
import 'dart:typed_data';

/// A message greetd sends back.
sealed class GreetdReply {
  const GreetdReply();

  static GreetdReply fromJson(Map<String, Object?> json) {
    switch (json["type"]) {
      case "success":
        return const GreetdSuccess();
      case "auth_message":
        return GreetdAuthMessage(
          type: json["auth_message_type"] as String? ?? "secret",
          message: json["auth_message"] as String? ?? "",
        );
      default:
        return GreetdError(
          type: json["error_type"] as String? ?? "error",
          description: json["description"] as String? ?? "",
        );
    }
  }
}

class GreetdSuccess extends GreetdReply {
  const GreetdSuccess();
}

/// greetd asks something (a password: "secret", a login code: "visible")
/// or tells something ("info", "error").
class GreetdAuthMessage extends GreetdReply {
  const GreetdAuthMessage({required this.type, required this.message});

  final String type;
  final String message;

  bool get needsAnswer => type == "secret" || type == "visible";
}

class GreetdError extends GreetdReply {
  const GreetdError({required this.type, required this.description});

  /// "auth_error" for a wrong password.
  final String type;
  final String description;
}

/// Client of greetd's IPC ($GREETD_SOCK): JSON messages, each preceded by
/// its length as a native endian 32 bit integer.
class GreetdClient {
  GreetdClient._(this._socket) {
    _socket.listen(_onData, onDone: _onDone, onError: (_) => _onDone());
  }

  final Socket _socket;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<Completer<GreetdReply>> _pending = [];

  /// Whether greetd runs this greeter.
  static bool get available =>
      Platform.environment["GREETD_SOCK"]?.isNotEmpty == true;

  static Future<GreetdClient> connect() async {
    final String path = Platform.environment["GREETD_SOCK"]!;
    final Socket socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return GreetdClient._(socket);
  }

  Future<GreetdReply> _request(Map<String, Object?> message) {
    final Uint8List body = utf8.encode(jsonEncode(message));
    final ByteData length = ByteData(4)..setUint32(0, body.length, Endian.host);
    final Completer<GreetdReply> reply = Completer();
    _pending.add(reply);
    _socket
      ..add(length.buffer.asUint8List())
      ..add(body);
    return reply.future;
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    Uint8List bytes = _buffer.takeBytes();
    while (bytes.length >= 4) {
      final int length =
          ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.host);
      if (bytes.length < 4 + length) break;
      final Object? json = jsonDecode(utf8.decode(bytes.sublist(4, 4 + length)));
      bytes = bytes.sublist(4 + length);
      if (_pending.isEmpty) continue;
      final Completer<GreetdReply> reply = _pending.removeAt(0);
      reply.complete(
        json is Map<String, Object?>
            ? GreetdReply.fromJson(json)
            : const GreetdError(type: "error", description: "Bad reply"),
      );
    }
    _buffer.add(bytes);
  }

  void _onDone() {
    for (final Completer<GreetdReply> reply in _pending) {
      if (!reply.isCompleted) {
        reply.complete(
          const GreetdError(type: "error", description: "greetd went away"),
        );
      }
    }
    _pending.clear();
  }

  Future<GreetdReply> createSession(String username) =>
      _request({"type": "create_session", "username": username});

  Future<GreetdReply> answer(String? response) => _request({
        "type": "post_auth_message_response",
        if (response != null) "response": response,
      });

  Future<GreetdReply> startSession(List<String> command, List<String> env) =>
      _request({"type": "start_session", "cmd": command, "env": env});

  Future<GreetdReply> cancelSession() =>
      _request({"type": "cancel_session"});

  Future<void> close() => _socket.close();
}

/// A user who can log in.
class LoginUser {
  const LoginUser({required this.name, required this.fullName});

  final String name;
  final String fullName;

  String get displayName => fullName.isNotEmpty ? fullName : name;

  /// Regular accounts from the password database.
  static List<LoginUser> all() {
    final List<LoginUser> users = [];
    try {
      for (final String line in File("/etc/passwd").readAsLinesSync()) {
        final List<String> f = line.split(":");
        if (f.length < 7) continue;
        final int uid = int.tryParse(f[2]) ?? -1;
        if (uid < 1000 || uid >= 60000) continue;
        if (f[6].endsWith("nologin") || f[6].endsWith("false")) continue;
        users.add(LoginUser(name: f[0], fullName: f[4].split(",").first.trim()));
      }
    } on FileSystemException {
      // No users to show: the greeter asks for a user name.
    }
    return users;
  }
}

/// A desktop session (wayland-sessions/*.desktop).
class LoginSession {
  const LoginSession({
    required this.id,
    required this.name,
    required this.command,
    required this.desktopNames,
  });

  final String id;
  final String name;
  final List<String> command;
  final String desktopNames;

  static List<LoginSession> all() {
    final Map<String, LoginSession> sessions = {};
    final List<String> dirs = [
      for (final String d in (Platform.environment["XDG_DATA_DIRS"] ??
              "/usr/local/share:/usr/share")
          .split(":"))
        if (d.isNotEmpty) "$d/wayland-sessions",
    ];
    for (final String dir in dirs) {
      final Directory directory = Directory(dir);
      if (!directory.existsSync()) continue;
      for (final FileSystemEntity entry in directory.listSync()) {
        if (!entry.path.endsWith(".desktop")) continue;
        final String id = entry.uri.pathSegments.last.replaceAll(".desktop", "");
        if (sessions.containsKey(id)) continue;
        final LoginSession? session = _parse(id, File(entry.path));
        if (session != null) sessions[id] = session;
      }
    }
    final List<LoginSession> list = sessions.values.toList()
      ..sort((a, b) {
        // Pangolin first.
        if (a.id == "pangolin") return -1;
        if (b.id == "pangolin") return 1;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  static LoginSession? _parse(String id, File file) {
    String? name;
    String? exec;
    String desktopNames = "";
    bool inEntry = false;
    try {
      for (final String line in file.readAsLinesSync()) {
        if (line.startsWith("[")) {
          inEntry = line.trim() == "[Desktop Entry]";
          continue;
        }
        if (!inEntry) continue;
        if (line.startsWith("Name=")) name ??= line.substring(5);
        if (line.startsWith("Exec=")) exec ??= line.substring(5);
        if (line.startsWith("DesktopNames=")) {
          desktopNames = line.substring(13).replaceAll(";", ":");
        }
        if (line.trim() == "Hidden=true" || line.trim() == "NoDisplay=true") {
          return null;
        }
      }
    } on FileSystemException {
      return null;
    }
    if (name == null || exec == null) return null;
    return LoginSession(
      id: id,
      name: name,
      command: _split(exec),
      desktopNames: desktopNames.endsWith(":")
          ? desktopNames.substring(0, desktopNames.length - 1)
          : desktopNames,
    );
  }

  /// Splits an Exec line into arguments (desktop entry quoting rules).
  static List<String> _split(String exec) {
    final List<String> args = [];
    final StringBuffer current = StringBuffer();
    bool quoted = false;
    bool escaped = false;
    for (final int c in exec.runes) {
      final String ch = String.fromCharCode(c);
      if (escaped) {
        current.write(ch);
        escaped = false;
      } else if (ch == "\\") {
        escaped = true;
      } else if (ch == '"') {
        quoted = !quoted;
      } else if (ch == " " && !quoted) {
        if (current.isNotEmpty) args.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    if (current.isNotEmpty) args.add(current.toString());
    // Field codes (%f, %u, ...) don't apply to sessions.
    return args.where((a) => !RegExp(r"^%[a-zA-Z]$").hasMatch(a)).toList();
  }
}
