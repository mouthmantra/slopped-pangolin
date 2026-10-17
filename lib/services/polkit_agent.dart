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

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/dbus/utils.dart';

/// Pangolin's polkit authentication agent: when an app asks for something
/// that needs a password (installing software, changing system settings,
/// ...), polkit asks the agent of the session, which shows the shell's own
/// dialog ([PolkitAgent.current]) and checks the password with polkit's
/// helper.
class PolkitAgent {
  PolkitAgent._();

  static final PolkitAgent instance = PolkitAgent._();

  static final Logger _logger = Logger("PolkitAgent");

  static const String _path = "/io/dahliaos/Pangolin/PolkitAgent";
  static const String _agentInterface =
      "org.freedesktop.PolicyKit1.AuthenticationAgent";

  DBusClient? _client;
  String? _polkitOwner;

  /// The authentication being asked for, if any (one at a time).
  final ValueNotifier<PolkitRequest?> current = ValueNotifier(null);
  final List<PolkitRequest> _queue = [];

  /// Registers the agent for this session. Another agent may already have
  /// (Pangolin nested in another desktop): it then stays out of the way.
  Future<void> start() async {
    if (!systemBusAvailable()) return;
    final DBusClient client = DBusClient.system();
    try {
      _polkitOwner = await client.getNameOwner("org.freedesktop.PolicyKit1");
      await client.registerObject(_AgentObject(this));
      final DBusRemoteObject authority = DBusRemoteObject(
        client,
        name: "org.freedesktop.PolicyKit1",
        path: DBusObjectPath("/org/freedesktop/PolicyKit1/Authority"),
      );
      await authority.callMethod(
        "org.freedesktop.PolicyKit1.Authority",
        "RegisterAuthenticationAgent",
        [
          await _subject(client),
          DBusString(_locale()),
          const DBusString(_path),
        ],
        replySignature: DBusSignature(""),
      );
      _client = client;
      _logger.info("Registered as the session's authentication agent");
    } on Object catch (e) {
      _logger.info("Not the authentication agent: $e");
      await client.close();
    }
  }

  /// This session (logind's), or this process when there is none.
  static Future<DBusValue> _subject(DBusClient client) async {
    String? session = Platform.environment["XDG_SESSION_ID"];
    if (session == null || session.isEmpty) {
      try {
        final DBusMethodSuccessResponse reply = await client.callMethod(
          destination: "org.freedesktop.login1",
          path: DBusObjectPath("/org/freedesktop/login1"),
          interface: "org.freedesktop.login1.Manager",
          name: "GetSessionByPID",
          values: [DBusUint32(pid)],
          replySignature: DBusSignature("o"),
        );
        final DBusRemoteObject object = DBusRemoteObject(
          client,
          name: "org.freedesktop.login1",
          path: reply.returnValues.first.asObjectPath(),
        );
        session = (await object.getProperty(
          "org.freedesktop.login1.Session",
          "Id",
          signature: DBusSignature("s"),
        ))
            .asString();
      } on Object {
        session = null;
      }
    }
    if (session != null && session.isNotEmpty) {
      return DBusStruct([
        const DBusString("unix-session"),
        DBusDict.stringVariant({"session-id": DBusString(session)}),
      ]);
    }
    // Field 22 of /proc/self/stat: when the process started.
    final String stat = File("/proc/self/stat").readAsStringSync();
    final List<String> fields =
        stat.substring(stat.lastIndexOf(")") + 2).split(" ");
    return DBusStruct([
      const DBusString("unix-process"),
      DBusDict.stringVariant({
        "pid": DBusUint32(pid),
        "start-time": DBusUint64(int.parse(fields[19])),
      }),
    ]);
  }

  static String _locale() {
    final String locale = Platform.environment["LC_ALL"] ??
        Platform.environment["LC_MESSAGES"] ??
        Platform.environment["LANG"] ??
        "C";
    return locale.isEmpty ? "C" : locale;
  }

  Future<DBusMethodResponse> _begin(DBusMethodCall call) async {
    final List<DBusValue> args = call.values;
    final String actionId = args[0].asString();
    final String message = args[1].asString();
    final String cookie = args[4].asString();
    final PolkitUser? user = await PolkitUser.choose(args[5].asArray());
    if (user == null) {
      return DBusMethodErrorResponse(
        "org.freedesktop.PolicyKit1.Error.Failed",
        [const DBusString("No identity to authenticate as")],
      );
    }

    final PolkitRequest request = PolkitRequest._(
      this,
      actionId: actionId,
      message: message,
      cookie: cookie,
      user: user,
    );
    _queue.add(request);
    _next();
    final bool authenticated = await request._result.future;
    return authenticated
        ? DBusMethodSuccessResponse()
        : DBusMethodErrorResponse(
            "org.freedesktop.PolicyKit1.Error.Cancelled",
            [const DBusString("Authentication was cancelled")],
          );
  }

  DBusMethodResponse _cancel(DBusMethodCall call) {
    final String cookie = call.values.first.asString();
    for (final PolkitRequest request in [..._queue]) {
      if (request.cookie == cookie) request.cancel();
    }
    return DBusMethodSuccessResponse();
  }

  void _next() {
    if (current.value != null || _queue.isEmpty) return;
    final PolkitRequest request = _queue.first;
    current.value = request;
    request._attempt();
  }

  void _finished(PolkitRequest request) {
    _queue.remove(request);
    if (current.value == request) current.value = null;
    _next();
  }

  bool _fromPolkit(DBusMethodCall call) =>
      _polkitOwner != null && call.sender == _polkitOwner;

  Future<void> stop() async {
    for (final PolkitRequest request in [..._queue]) {
      request.cancel();
    }
    await _client?.close();
    _client = null;
  }
}

class _AgentObject extends DBusObject {
  _AgentObject(this._agent) : super(DBusObjectPath(PolkitAgent._path));

  final PolkitAgent _agent;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != PolkitAgent._agentInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    // Only polkit itself may ask (anyone else could fake a dialog).
    if (!_agent._fromPolkit(call)) return DBusMethodErrorResponse.accessDenied();
    switch (call.name) {
      case "BeginAuthentication":
        if (call.signature != DBusSignature("sssa{ss}sa(sa{sv})")) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return await _agent._begin(call);
      case "CancelAuthentication":
        if (call.signature != DBusSignature("s")) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return _agent._cancel(call);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

/// Who authenticates.
class PolkitUser {
  const PolkitUser({
    required this.uid,
    required this.name,
    required this.fullName,
  });

  final int uid;
  final String name;
  final String fullName;

  String get displayName => fullName.isNotEmpty ? fullName : name;

  /// Of the identities polkit accepts: the user of the session if it's one
  /// of them (or in one of the groups), the first other user otherwise.
  static Future<PolkitUser?> choose(List<DBusValue> identities) async {
    final int me = await _uid();
    final List<int> users = [];
    final List<int> groups = [];
    for (final DBusValue identity in identities) {
      final List<DBusValue> parts = identity.asStruct();
      final String kind = parts[0].asString();
      final Map<String, DBusValue> details = parts[1].asStringVariantDict();
      if (kind == "unix-user" && details["uid"] != null) {
        users.add(details["uid"]!.asUint32());
      } else if (kind == "unix-group" && details["gid"] != null) {
        groups.add(details["gid"]!.asUint32());
      }
    }
    if (users.contains(me) || (await _groups()).any(groups.contains)) {
      return await lookup(me);
    }
    for (final int uid in users) {
      final PolkitUser? user = await lookup(uid);
      if (user != null) return user;
    }
    return null;
  }

  static Future<int> _uid() async {
    final ProcessResult result = await Process.run("id", ["-u"]);
    return int.tryParse((result.stdout as String).trim()) ?? -1;
  }

  static Future<List<int>> _groups() async {
    final ProcessResult result = await Process.run("id", ["-G"]);
    return [
      for (final String g in (result.stdout as String).trim().split(" "))
        if (int.tryParse(g) case final int gid) gid,
    ];
  }

  /// From the user database: getent, so that network accounts work too,
  /// or /etc/passwd where there's no getent (busybox systems).
  static Future<PolkitUser?> lookup(int uid) async {
    List<String>? fields;
    try {
      final ProcessResult result = await Process.run("getent", ["passwd", "$uid"]);
      if (result.exitCode == 0) fields = (result.stdout as String).trim().split(":");
    } on ProcessException {
      try {
        fields = File("/etc/passwd")
            .readAsLinesSync()
            .map((line) => line.split(":"))
            .where((f) => f.length > 4 && f[2] == "$uid")
            .firstOrNull;
      } on FileSystemException {
        fields = null;
      }
    }
    if (fields == null || fields.length < 5) return null;
    return PolkitUser(
      uid: uid,
      name: fields[0],
      fullName: fields[4].split(",").first.trim(),
    );
  }
}

/// What the dialog shows for a request.
@immutable
class PolkitPrompt {
  const PolkitPrompt({
    this.prompt,
    this.echo = false,
    this.busy = false,
    this.error,
    this.info,
  });

  /// What PAM asks for ("Password: "), null while there's nothing to answer.
  final String? prompt;

  /// Whether the answer may be shown as typed (not a password).
  final bool echo;

  /// Checking an answer.
  final bool busy;
  final String? error;
  final String? info;

  PolkitPrompt copyWith({
    String? prompt,
    bool? echo,
    bool? busy,
    String? error,
    String? info,
    bool clearPrompt = false,
    bool clearError = false,
  }) =>
      PolkitPrompt(
        prompt: clearPrompt ? null : prompt ?? this.prompt,
        echo: echo ?? this.echo,
        busy: busy ?? this.busy,
        error: clearError ? null : error ?? this.error,
        info: info ?? this.info,
      );
}

/// One authentication: talks to polkit's helper (PAM) until it succeeds or
/// is cancelled; a wrong password starts another attempt.
class PolkitRequest {
  PolkitRequest._(
    this._agent, {
    required this.actionId,
    required this.message,
    required this.cookie,
    required this.user,
  });

  final PolkitAgent _agent;
  final String actionId;
  final String message;
  final String cookie;
  final PolkitUser user;

  final ValueNotifier<PolkitPrompt> prompt =
      ValueNotifier(const PolkitPrompt(busy: true));
  final Completer<bool> _result = Completer();

  _HelperConnection? _helper;
  bool _done = false;

  /// Answers what the helper asked ([PolkitPrompt.prompt]).
  void respond(String answer) {
    final _HelperConnection? helper = _helper;
    if (helper == null || _done) return;
    prompt.value = prompt.value.copyWith(busy: true, clearPrompt: true);
    // One line each.
    helper.write(answer.replaceAll(RegExp(r"[\r\n]"), ""));
  }

  void cancel() => _finish(false);

  void _finish(bool authenticated) {
    if (_done) return;
    _done = true;
    _helper?.close();
    _helper = null;
    if (!_result.isCompleted) _result.complete(authenticated);
    _agent._finished(this);
  }

  Future<void> _attempt() async {
    if (_done) return;
    final _HelperConnection? helper =
        await _HelperConnection.open(user.name, cookie);
    if (_done) {
      helper?.close();
      return;
    }
    if (helper == null) {
      PolkitAgent._logger.warning("Couldn't start polkit's helper");
      prompt.value = const PolkitPrompt(
        error: "Authentication isn't available on this system",
      );
      return;
    }
    _helper = helper;
    helper.lines.listen(
      _onLine,
      onDone: () {
        // Gone without a verdict: a failed attempt.
        if (_helper == helper) _failed();
      },
    );
  }

  void _onLine(String line) {
    if (_done) return;
    if (line.startsWith("PAM_PROMPT_ECHO_OFF ")) {
      prompt.value = prompt.value.copyWith(
        prompt: line.substring(20),
        echo: false,
        busy: false,
      );
    } else if (line.startsWith("PAM_PROMPT_ECHO_ON ")) {
      prompt.value = prompt.value.copyWith(
        prompt: line.substring(19),
        echo: true,
        busy: false,
      );
    } else if (line.startsWith("PAM_ERROR_MSG ")) {
      prompt.value = prompt.value.copyWith(error: line.substring(14));
    } else if (line.startsWith("PAM_TEXT_INFO ")) {
      prompt.value = prompt.value.copyWith(info: line.substring(14));
    } else if (line.startsWith("SUCCESS")) {
      _finish(true);
    } else {
      // FAILURE, or something unexpected.
      _failed();
    }
  }

  void _failed() {
    _helper?.close();
    _helper = null;
    if (_done) return;
    prompt.value = const PolkitPrompt(
      busy: true,
      error: "That didn't work. Please try again.",
    );
    // A short pause, as after a wrong password anywhere else.
    Future.delayed(const Duration(milliseconds: 600), _attempt);
  }
}

/// polkit's helper, which runs PAM as root: through its socket where the
/// system has one (systemd), started setuid otherwise. Lines are C-escaped.
class _HelperConnection {
  _HelperConnection._(this._sink, this.lines, this._close);

  final IOSink _sink;
  final Stream<String> lines;
  final void Function() _close;

  static const String _socket = "/run/polkit/agent-helper.socket";
  /// Where distributions put it (NixOS: its setuid wrapper), or
  /// PANGOLIN_POLKIT_HELPER.
  static List<String> get _helpers => [
        if (Platform.environment["PANGOLIN_POLKIT_HELPER"] case final String path)
          path,
        "/usr/lib/polkit-1/polkit-agent-helper-1",
        "/usr/libexec/polkit-agent-helper-1",
        "/usr/lib/policykit-1/polkit-agent-helper-1",
        "/usr/local/lib/polkit-1/polkit-agent-helper-1",
        "/run/wrappers/bin/polkit-agent-helper-1",
      ];

  static Future<_HelperConnection?> open(String user, String cookie) async {
    if (Platform.environment["PANGOLIN_POLKIT_HELPER"] == null &&
        FileSystemEntity.typeSync(_socket) != FileSystemEntityType.notFound) {
      try {
        final Socket socket = await Socket.connect(
          InternetAddress(_socket, type: InternetAddressType.unix),
          0,
        );
        final _HelperConnection helper = _HelperConnection._(
          socket,
          _linesOf(socket),
          socket.destroy,
        );
        helper
          ..write(user)
          ..write(cookie);
        return helper;
      } on SocketException catch (e) {
        PolkitAgent._logger.info("Helper socket unavailable ($e), trying the helper");
      }
    }
    for (final String path in _helpers) {
      if (!File(path).existsSync()) continue;
      try {
        final Process process = await Process.start(path, [user]);
        unawaited(process.stderr.drain<void>());
        final _HelperConnection helper = _HelperConnection._(
          process.stdin,
          _linesOf(process.stdout),
          () => process.kill(),
        );
        // On stdin, so that other processes can't see it.
        helper.write(cookie);
        return helper;
      } on ProcessException catch (e) {
        PolkitAgent._logger.warning("Couldn't run $path: $e");
      }
    }
    return null;
  }

  static Stream<String> _linesOf(Stream<List<int>> stream) => stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map(_unescape);

  void write(String line) {
    try {
      _sink.write("$line\n");
    } on Object {
      // Gone: its lines end, which fails the attempt.
    }
  }

  void close() {
    try {
      _close();
    } on Object {
      // Already gone.
    }
  }

  /// Undoes g_strescape (as g_strcompress): it escapes bytes, non-ASCII
  /// ones (UTF-8) as octal.
  static String _unescape(String line) {
    if (!line.contains(r"\")) return line;
    final List<int> bytes = [];
    final List<int> units = utf8.encode(line);
    for (int i = 0; i < units.length; i++) {
      final int c = units[i];
      if (c != 0x5c || i + 1 >= units.length) {
        bytes.add(c);
        continue;
      }
      final int next = units[++i];
      const Map<int, int> simple = {
        0x6e: 0x0a, // n
        0x74: 0x09, // t
        0x72: 0x0d, // r
        0x62: 0x08, // b
        0x66: 0x0c, // f
        0x76: 0x0b, // v
      };
      if (simple[next] case final int value) {
        bytes.add(value);
      } else if (next >= 0x30 && next <= 0x37) {
        int value = next - 0x30;
        for (int n = 0;
            n < 2 &&
                i + 1 < units.length &&
                units[i + 1] >= 0x30 &&
                units[i + 1] <= 0x37;
            n++) {
          value = value * 8 + units[++i] - 0x30;
        }
        bytes.add(value & 0xff);
      } else {
        bytes.add(next);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
