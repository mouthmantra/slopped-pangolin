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
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:wayland/src/protocols/wayland.dart';
import 'package:wayland/src/proxy.dart';
import 'package:wayland/src/wire.dart';

/// First object id the server allocates from (`WL_SERVER_ID_START`).
const int kServerIdStart = 0xff000000;

/// Raised when the compositor sends `wl_display.error`. The connection is
/// unusable afterwards.
class WaylandProtocolError implements Exception {
  const WaylandProtocolError(this.object, this.code, this.message);

  final String object;
  final int code;
  final String message;

  @override
  String toString() => 'Wayland protocol error on $object (code $code): $message';
}

/// A connection to a Wayland compositor over its Unix domain socket.
///
/// The connection owns the object table. Events are dispatched on the Dart
/// event loop in the order they are received, and requests issued in the same
/// synchronous block are flushed together in a single `sendmsg`, which keeps
/// multi-request transactions (such as a river manage sequence) atomic on the
/// wire.
class WaylandConnection implements FdSource {
  WaylandConnection._(this._socket, this.socketPath) {
    final String? trace = Platform.environment['DART_WAYLAND_DEBUG'];
    if (trace != null && trace.isNotEmpty && trace != '0') {
      final RandomAccessFile? sink = trace == '1'
          ? null
          : File(trace).openSync(mode: FileMode.append);
      debugLog = (line) {
        final String stamped =
            '[${(DateTime.now().microsecondsSinceEpoch % 100000000) / 1000.0}] $line\n';
        if (sink != null) {
          sink.writeStringSync(stamped);
        } else {
          stderr.write(stamped);
        }
      };
    }

    display = WlDisplay(this, 1, 1);
    _objects[1] = display;

    display.onError = (object, code, message) {
      _fail(WaylandProtocolError(object?.toString() ?? 'unknown', code, message));
    };
    display.onDeleteId = _deleteId;

    _subscription = _socket.listen(
      _onSocketEvent,
      onError: (Object e, StackTrace s) => _fail(e, s),
      onDone: () => _fail(const SocketException('Wayland socket closed')),
    );
  }

  /// Connects to the compositor named by [name], or by `$WAYLAND_DISPLAY`.
  ///
  /// Relative names are resolved against `$XDG_RUNTIME_DIR` as libwayland does.
  static Future<WaylandConnection> connect({String? name}) async {
    final Map<String, String> env = Platform.environment;
    final String display = name ?? env['WAYLAND_DISPLAY'] ?? 'wayland-0';

    final String path;
    if (display.startsWith('/')) {
      path = display;
    } else {
      final String? runtimeDir = env['XDG_RUNTIME_DIR'];
      if (runtimeDir == null) {
        throw StateError('XDG_RUNTIME_DIR is not set, cannot locate $display');
      }
      path = '$runtimeDir/$display';
    }

    final RawSocket socket = await RawSocket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return WaylandConnection._(socket, path);
  }

  final RawSocket _socket;
  final String socketPath;
  late final StreamSubscription<RawSocketEvent> _subscription;

  late final WlDisplay display;

  final Map<int, Proxy> _objects = {};
  final Queue<int> _freeIds = Queue();
  int _nextId = 2;

  final BytesBuilder _incoming = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  final Queue<RandomAccessFile> _incomingFds = Queue();

  final BytesBuilder _outgoing = BytesBuilder(copy: false);
  final List<RandomAccessFile> _outgoingFds = [];
  Uint8List? _unsent;
  bool _flushScheduled = false;

  final Completer<void> _done = Completer();
  bool _closed = false;

  /// Completes when the connection is closed, with an error if it was closed
  /// because of a protocol or socket error.
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  /// When set, every request and event is logged here, similar to
  /// `WAYLAND_DEBUG=1` in libwayland. Enabled by `DART_WAYLAND_DEBUG=1` (to
  /// stderr) or `DART_WAYLAND_DEBUG=<path>` (synchronously to a file).
  void Function(String line)? debugLog;

  /// Invoked when a listener throws while an event is being dispatched. The
  /// connection keeps processing further events.
  void Function(Object error, StackTrace stack)? onListenerError;

  /// Creates a new `wl_registry` for this connection.
  WlRegistry getRegistry() => display.getRegistry();

  /// Waits until the compositor has processed every request sent so far and
  /// all events it generated in response were dispatched.
  Future<void> roundtrip() {
    final Completer<void> completer = Completer();
    final WlCallback callback = display.sync();
    callback.onDone = (_) {
      if (!completer.isCompleted) completer.complete();
    };
    done.then(
      (_) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('connection closed'));
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    return completer.future;
  }

  /// Allocates a client side object id and registers a proxy for it.
  T createProxy<T extends Proxy>(ProxyFactory<T> factory, int version) {
    final int id = _freeIds.isNotEmpty ? _freeIds.removeFirst() : _nextId++;
    final T proxy = factory(this, id, version);
    _objects[id] = proxy;
    return proxy;
  }

  /// Registers a proxy for an object the server created through a `new_id`
  /// event argument.
  T adoptServerObject<T extends Proxy>(
    ProxyFactory<T> factory,
    int id,
    int version,
  ) {
    final T proxy = factory(this, id, version);
    _objects[id] = proxy;
    return proxy;
  }

  /// Looks up the proxy for an object id received in an event.
  Proxy? lookup(int id) => id == 0 ? null : _objects[id];

  /// Called once a destructor request has been queued for [proxy].
  void releaseProxy(Proxy proxy) {
    // Server allocated ids never receive wl_display.delete_id, so they can be
    // forgotten immediately. Client ids stay reserved (as zombies) until the
    // server acknowledges the destruction.
    if (proxy.id >= kServerIdStart && identical(_objects[proxy.id], proxy)) {
      _objects.remove(proxy.id);
    }
  }

  void _deleteId(int id) {
    _objects.remove(id);
    if (id < kServerIdStart) _freeIds.addLast(id);
  }

  /// Queues a serialized request. Requests are flushed at the end of the
  /// current microtask so that requests issued together share a write.
  void queueRequest(WireWriter writer) {
    if (_closed) return;
    final Uint8List message = writer.finish();
    if (debugLog != null) {
      final ByteData data = ByteData.sublistView(message);
      final List<int> words = [
        for (int i = kHeaderSize; i + 4 <= message.length; i += 4)
          data.getInt32(i, Endian.host),
      ];
      debugLog!(' -> ${_objects[writer.objectId] ?? writer.objectId}#${writer.opcode} $words');
    }
    _outgoing.add(message);
    _outgoingFds.addAll(writer.fds);
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(flush);
    }
  }

  /// Writes all queued requests to the socket immediately.
  void flush() {
    _flushScheduled = false;
    if (_closed) return;

    if (_outgoing.isNotEmpty) {
      final Uint8List data = _outgoing.takeBytes();
      _unsent = _unsent == null ? data : Uint8List.fromList([..._unsent!, ...data]);
    }

    final Uint8List? unsent = _unsent;
    if (unsent == null || unsent.isEmpty) return;

    try {
      final int written;
      if (_outgoingFds.isNotEmpty) {
        // File descriptors travel with the first chunk of data; the server
        // consumes them in order as it parses the requests that need them.
        written = _socket.sendMessage(
          [
            SocketControlMessage.fromHandles(
              _outgoingFds.map(ResourceHandle.fromFile).toList(),
            ),
          ],
          unsent,
        );
        _outgoingFds.clear();
      } else {
        written = _socket.write(unsent);
      }

      _unsent = written >= unsent.length ? null : Uint8List.sublistView(unsent, written);
      _socket.writeEventsEnabled = _unsent != null;
    } catch (e, s) {
      _fail(e, s);
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        _readAvailable();
      case RawSocketEvent.write:
        flush();
      case RawSocketEvent.readClosed:
      case RawSocketEvent.closed:
        _fail(const SocketException('Wayland compositor closed the connection'));
    }
  }

  void _readAvailable() {
    // readMessage() returns an empty message rather than null once the socket
    // is drained. File descriptors always arrive with at least one data byte
    // on a stream socket, so an empty message means there is nothing left.
    while (!_closed) {
      final SocketMessage? message = _socket.readMessage();
      if (message == null || message.data.isEmpty) break;
      _incoming.add(message.data);
      for (final SocketControlMessage control in message.controlMessages) {
        for (final ResourceHandle handle in control.extractHandles()) {
          _incomingFds.addLast(handle.toFile());
        }
      }
    }

    if (_incoming.isNotEmpty) {
      final Uint8List fresh = _incoming.takeBytes();
      _pending = _pending.isEmpty ? fresh : Uint8List.fromList([..._pending, ...fresh]);
    }
    _dispatchPending();
  }

  void _dispatchPending() {
    int offset = 0;
    final ByteData view = ByteData.sublistView(_pending);

    while (!_closed && _pending.length - offset >= kHeaderSize) {
      final int objectId = view.getUint32(offset, Endian.host);
      final int word = view.getUint32(offset + 4, Endian.host);
      final int size = word >> 16;
      final int opcode = word & 0xffff;

      if (size < kHeaderSize) {
        _fail(StateError('Malformed Wayland message (size $size)'));
        return;
      }
      if (_pending.length - offset < size) break;

      final Proxy? proxy = _objects[objectId];
      debugLog?.call('<-  ${proxy ?? 'unknown@$objectId'}#$opcode (${size - kHeaderSize} bytes)');
      if (proxy != null) {
        final WireReader reader = WireReader(
          ByteData.sublistView(_pending, offset + kHeaderSize, offset + size),
          this,
        );
        try {
          proxy.dispatchEvent(opcode, reader);
        } catch (e, s) {
          final handler = onListenerError;
          if (handler != null) {
            handler(e, s);
          } else {
            Zone.current.handleUncaughtError(e, s);
          }
        }
      }

      offset += size;
    }

    _pending = offset == 0 ? _pending : Uint8List.fromList(_pending.sublist(offset));
  }

  @override
  RandomAccessFile takeFd() {
    if (_incomingFds.isEmpty) {
      throw StateError('Event expected a file descriptor but none was received');
    }
    return _incomingFds.removeFirst();
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_closed) return;
    debugLog?.call('connection closed: $error');
    _closed = true;
    _subscription.cancel();
    _socket.close();
    if (!_done.isCompleted) {
      if (error is SocketException) {
        _done.complete();
      } else {
        _done.completeError(error, stack);
      }
    }
  }

  /// Flushes pending requests and closes the socket.
  Future<void> close() async {
    if (_closed) return;
    flush();
    _closed = true;
    await _subscription.cancel();
    await _socket.close();
    if (!_done.isCompleted) _done.complete();
  }
}
