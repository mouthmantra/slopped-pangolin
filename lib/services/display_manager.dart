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

import 'package:pangolin/services/greetd.dart';

/// What a login step came back with.
sealed class LoginReply {
  const LoginReply();
}

/// The user is verified: the session can start.
class LoginVerified extends LoginReply {
  const LoginVerified();
}

/// The session is on its way (the greeter leaves now).
class LoginStarted extends LoginReply {
  const LoginStarted();
}

/// PAM asks something: a password ([secret]), a PIN, a user name.
class LoginQuestion extends LoginReply {
  const LoginQuestion(this.text, {required this.secret});
  final String text;
  final bool secret;
}

/// PAM tells something ("Touch your security key"; [problem] for errors).
/// Answered with an empty answer.
class LoginInfo extends LoginReply {
  const LoginInfo(this.text, {required this.problem});
  final String text;
  final bool problem;
}

class LoginFailed extends LoginReply {
  const LoginFailed({required this.wrongAnswer, this.text = ""});

  /// The password (or other answer) was wrong: try again.
  final bool wrongAnswer;
  final String text;
}

/// What the login screen talks to: Pangolin's display manager (pangolin-dm,
/// $PANGOLIN_DM_SOCK), or greetd ($GREETD_SOCK) where that still runs it.
abstract class LoginBackend {
  static bool get available => PangolinDm.available || GreetdClient.available;

  static Future<LoginBackend> connect() async =>
      PangolinDm.available ? await PangolinDm.connect() : _Greetd(await GreetdClient.connect());

  /// Starts a login for [user]; the first question (or verified, failed).
  Future<LoginReply> begin(String user);

  /// Answers the last question; null acknowledges a message.
  Future<LoginReply> answer(String? text);

  /// Starts [session] (null: a login shell) once verified, with [env] (only
  /// what the display manager allows reaches it).
  Future<LoginReply> start(LoginSession? session, List<String> env);

  Future<void> cancel();
  Future<void> close();
}

/// Pangolin's display manager (dm/, docs/DISPLAY_MANAGER.md): frames of a
/// little endian 32 bit length and "key NUL value NUL" pairs, "type" first;
/// one reply per request.
class PangolinDm implements LoginBackend {
  PangolinDm._(this._socket) {
    _socket.listen(_onData, onDone: _onDone, onError: (_) => _onDone());
  }

  final Socket _socket;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<Completer<(String, Map<String, List<String>>)>> _pending = [];

  static bool get available => Platform.environment["PANGOLIN_DM_SOCK"]?.isNotEmpty == true;

  static Future<PangolinDm> connect() => connectTo(Platform.environment["PANGOLIN_DM_SOCK"]!);

  static Future<PangolinDm> connectTo(String path) async =>
      PangolinDm._(await Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0));

  /// Encodes a frame; [pairs] in order, keys may repeat.
  static Uint8List encode(String type, List<(String, String)> pairs) {
    final BytesBuilder body = BytesBuilder();
    for (final (String key, String value) in [("type", type), ...pairs]) {
      body
        ..add(utf8.encode(key))
        ..addByte(0)
        ..add(utf8.encode(value))
        ..addByte(0);
    }
    final Uint8List payload = body.takeBytes();
    final ByteData length = ByteData(4)..setUint32(0, payload.length, Endian.little);
    return Uint8List.fromList([...length.buffer.asUint8List(), ...payload]);
  }

  /// Decodes one frame's payload: its type and its values by key.
  static (String, Map<String, List<String>>) decode(Uint8List payload) {
    final List<String> parts = [];
    int start = 0;
    for (int i = 0; i < payload.length; i++) {
      if (payload[i] == 0) {
        parts.add(utf8.decode(payload.sublist(start, i), allowMalformed: true));
        start = i + 1;
      }
    }
    final Map<String, List<String>> fields = {};
    String type = "";
    for (int i = 0; i + 1 < parts.length; i += 2) {
      if (i == 0 && parts[0] == "type") {
        type = parts[1];
        continue;
      }
      fields.putIfAbsent(parts[i], () => []).add(parts[i + 1]);
    }
    return (type, fields);
  }

  Future<LoginReply> _request(String type, [List<(String, String)> pairs = const []]) async {
    final Completer<(String, Map<String, List<String>>)> reply = Completer();
    _pending.add(reply);
    _socket.add(encode(type, pairs));
    final (String kind, Map<String, List<String>> f) = await reply.future;
    String field(String key) => f[key]?.first ?? "";
    return switch (kind) {
      "question" => LoginQuestion(field("text"), secret: field("secret") != "0"),
      "message" => LoginInfo(field("text"), problem: field("kind") == "problem"),
      "verified" => const LoginVerified(),
      "started" || "ok" => const LoginStarted(),
      "failed" => LoginFailed(wrongAnswer: field("reason") == "auth", text: field("text")),
      _ => LoginFailed(wrongAnswer: false, text: field("text").isEmpty ? "The login stopped" : field("text")),
    };
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    Uint8List bytes = _buffer.takeBytes();
    while (bytes.length >= 4) {
      final int length = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
      if (bytes.length < 4 + length) break;
      final (String, Map<String, List<String>>) message = decode(Uint8List.sublistView(bytes, 4, 4 + length));
      bytes = Uint8List.fromList(bytes.sublist(4 + length));
      if (_pending.isNotEmpty) _pending.removeAt(0).complete(message);
    }
    _buffer.add(bytes);
  }

  void _onDone() {
    for (final Completer<(String, Map<String, List<String>>)> reply in _pending) {
      if (!reply.isCompleted) reply.complete(("error", {"text": ["The display manager went away"]}));
    }
    _pending.clear();
  }

  @override
  Future<LoginReply> begin(String user) => _request("begin", [("user", user), ("service", "password")]);

  @override
  Future<LoginReply> answer(String? text) => _request("answer", [if (text != null) ("text", text)]);

  @override
  Future<LoginReply> start(LoginSession? session, List<String> env) => _request("start", [
        // The daemon reads the session's command from its desktop file.
        ("session", session?.id ?? ""),
        for (final String e in env) ("env", e),
      ]);

  @override
  Future<void> cancel() => _request("cancel");

  @override
  Future<void> close() => _socket.close();
}

/// greetd, behind the same steps.
class _Greetd implements LoginBackend {
  _Greetd(this._client);

  final GreetdClient _client;

  static LoginReply _map(GreetdReply reply, {bool started = false}) => switch (reply) {
        GreetdSuccess() => started ? const LoginStarted() : const LoginVerified(),
        GreetdAuthMessage(:final String type, :final String message) => reply.needsAnswer
            ? LoginQuestion(message, secret: type == "secret")
            : LoginInfo(message, problem: type == "error"),
        GreetdError(:final String type, :final String description) =>
          LoginFailed(wrongAnswer: type == "auth_error", text: description),
      };

  @override
  Future<LoginReply> begin(String user) async => _map(await _client.createSession(user));

  @override
  Future<LoginReply> answer(String? text) async => _map(await _client.answer(text));

  @override
  Future<LoginReply> start(LoginSession? session, List<String> env) async => _map(
        await _client.startSession(session?.command ?? ["/bin/sh", "-l"], [
          ...env,
          "XDG_SESSION_TYPE=wayland",
          "XDG_SESSION_CLASS=user",
          if (session != null && session.desktopNames.isNotEmpty) "XDG_CURRENT_DESKTOP=${session.desktopNames}",
          if (session != null) "XDG_SESSION_DESKTOP=${session.id}",
        ]),
        started: true,
      );

  @override
  Future<void> cancel() => _client.cancelSession();

  @override
  Future<void> close() => _client.close();
}
