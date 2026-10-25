import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/display_manager.dart';
import 'package:pangolin/services/greetd.dart';

// The login screen's side of pangolin-dm's protocol, against a stand-in
// daemon on a socket (dm/tests/run.sh covers the daemon itself).
void main() {
  test("frames round-trip, keys repeat, the type comes first", () {
    final Uint8List frame = PangolinDm.encode("start", [("session", "pangolin"), ("env", "A=1"), ("env", "B=2")]);
    final int length = ByteData.sublistView(frame, 0, 4).getUint32(0, Endian.little);
    expect(length, frame.length - 4);
    final (String type, Map<String, List<String>> fields) = PangolinDm.decode(Uint8List.sublistView(frame, 4));
    expect(type, "start");
    expect(fields["session"], ["pangolin"]);
    expect(fields["env"], ["A=1", "B=2"]);
  });

  test("a login: message, question, a wrong answer, then the right one", () async {
    final Directory dir = Directory.systemTemp.createTempSync("pdm");
    final String path = "${dir.path}/greeter.sock";
    final ServerSocket server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
    final List<(String, Map<String, List<String>>)> requests = [];

    // The daemon's side: one scripted reply per request.
    final List<Uint8List> replies = [
      PangolinDm.encode("message", [("kind", "info"), ("text", "Touch your security key")]),
      PangolinDm.encode("question", [("secret", "1"), ("text", "Password:")]),
      PangolinDm.encode("failed", [("reason", "auth"), ("text", "Authentication failure")]),
      PangolinDm.encode("question", [("secret", "1"), ("text", "Password:")]),
      PangolinDm.encode("verified", []),
      PangolinDm.encode("started", []),
    ];
    server.listen((socket) {
      final BytesBuilder buffer = BytesBuilder();
      socket.listen((data) {
        buffer.add(data);
        Uint8List bytes = buffer.takeBytes();
        while (bytes.length >= 4) {
          final int length = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
          if (bytes.length < 4 + length) break;
          requests.add(PangolinDm.decode(Uint8List.sublistView(bytes, 4, 4 + length)));
          bytes = Uint8List.fromList(bytes.sublist(4 + length));
          socket.add(replies.removeAt(0));
        }
        buffer.add(bytes);
      });
    });

    final PangolinDm dm = await PangolinDm.connectTo(path);

    final LoginReply first = await dm.begin("ada");
    expect(first, isA<LoginInfo>().having((m) => m.text, "text", "Touch your security key"));
    expect(await dm.answer(null), isA<LoginQuestion>().having((q) => q.secret, "secret", isTrue));
    expect(await dm.answer("wrong"), isA<LoginFailed>().having((f) => f.wrongAnswer, "wrong", isTrue));
    expect(await dm.answer("again"), isA<LoginQuestion>());
    expect(await dm.answer("secret123"), isA<LoginVerified>());
    final LoginReply started = await dm.start(
      const LoginSession(id: "pangolin", name: "Pangolin", command: ["pangolin-session"], desktopNames: "Pangolin"),
      const ["PANGOLIN_FROM_GREETER=1"],
    );
    expect(started, isA<LoginStarted>());

    expect(requests.map((r) => r.$1).toList(), ["begin", "answer", "answer", "answer", "answer", "start"]);
    expect(requests[0].$2["user"], ["ada"]);
    expect(requests[1].$2.containsKey("text"), isFalse, reason: "a message is acknowledged without text");
    expect(requests[4].$2["text"], ["secret123"]);
    // The session by id: the daemon reads its command, not the greeter.
    expect(requests[5].$2["session"], ["pangolin"]);
    expect(requests[5].$2["env"], ["PANGOLIN_FROM_GREETER=1"]);

    await dm.close();
    await server.close();
    dir.deleteSync(recursive: true);
  });
}
