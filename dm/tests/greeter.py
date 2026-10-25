#!/usr/bin/env python3
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
"""A scripted greeter for pangolin-dm's test (tests/run.sh): talks to the
daemon on $PANGOLIN_DM_SOCK as Pangolin's greeter does, checks each reply,
then leaves so the session can start. Writes what it saw to $1."""

import getpass
import os
import socket
import struct
import sys


def send(sock, kind, *pairs):
    data = b""
    for key, value in (("type", kind),) + pairs:
        data += key.encode() + b"\0" + value.encode() + b"\0"
    sock.sendall(struct.pack("<I", len(data)) + data)


def recv(sock):
    def exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise EOFError
            buf += chunk
        return buf

    (length,) = struct.unpack("<I", exact(4))
    parts = exact(length).split(b"\0")[:-1]
    pairs = [(parts[i].decode(), parts[i + 1].decode()) for i in range(0, len(parts), 2)]
    return pairs[0][1], dict(pairs[1:])


def main():
    log = open(sys.argv[1], "w")
    failures = []

    def expect(what, got, want, check=lambda fields: True):
        kind, fields = got
        ok = kind == want and check(fields)
        log.write(f"{'ok' if ok else 'FAIL'} {what}: {kind} {fields}\n")
        if not ok:
            failures.append(what)
        return fields

    sock = socket.socket(socket.AF_UNIX)
    sock.connect(os.environ["PANGOLIN_DM_SOCK"])
    user = getpass.getuser()

    # A wrong password: the module's message, its question, then failed.
    send(sock, "begin", ("user", user))
    expect("info message", recv(sock), "message",
           lambda f: f.get("kind") == "info" and f.get("text") == "Testing pangolin-dm")
    send(sock, "answer")
    expect("password question", recv(sock), "question",
           lambda f: f.get("secret") == "1" and f.get("text") == "Password:")
    send(sock, "answer", ("text", "wrong"))
    expect("wrong password", recv(sock), "failed", lambda f: f.get("reason") == "auth")

    # The right one.
    send(sock, "begin", ("user", user))
    expect("info again", recv(sock), "message")
    send(sock, "answer")
    expect("question again", recv(sock), "question")
    send(sock, "answer", ("text", "secret123"))
    expect("verified", recv(sock), "verified")

    # A session that doesn't exist, then the test one; only allowed
    # variables reach it.
    send(sock, "start", ("session", "../etc/passwd"))
    expect("unknown session", recv(sock), "error")
    send(sock, "start", ("session", "test"), ("env", "PANGOLIN_FROM_GREETER=1"),
         ("env", "LD_PRELOAD=/tmp/evil.so"))
    expect("started", recv(sock), "started")

    log.write("failures: %d\n" % len(failures))
    log.close()
    sock.close()
    # Leaving lets the session take the screen.
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
