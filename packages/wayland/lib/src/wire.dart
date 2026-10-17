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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Size in bytes of a Wayland message header (object id + size/opcode word).
const int kHeaderSize = 8;

/// Converts a `wl_fixed_t` (24.8 signed fixed point) to a double.
double fixedToDouble(int fixed) => fixed.toSigned(32) / 256.0;

/// Converts a double to a `wl_fixed_t` (24.8 signed fixed point).
int doubleToFixed(double value) => (value * 256.0).round().toSigned(32);

int _pad4(int length) => (length + 3) & ~3;

/// Serializes the arguments of a single request.
///
/// The header is written by [finish] once the final size is known, matching
/// the layout described in the "Wire Format" section of the Wayland spec.
class WireWriter {
  WireWriter(this.objectId, this.opcode);

  final int objectId;
  final int opcode;

  final BytesBuilder _body = BytesBuilder(copy: false);
  final List<RandomAccessFile> fds = [];

  void int32(int value) {
    final ByteData data = ByteData(4)..setInt32(0, value, Endian.host);
    _body.add(data.buffer.asUint8List());
  }

  void uint32(int value) {
    final ByteData data = ByteData(4)..setUint32(0, value, Endian.host);
    _body.add(data.buffer.asUint8List());
  }

  void fixed(double value) => int32(doubleToFixed(value));

  void string(String? value) {
    if (value == null) {
      uint32(0);
      return;
    }

    final List<int> encoded = utf8.encode(value);
    // Length includes the terminating NUL byte.
    uint32(encoded.length + 1);
    final Uint8List padded = Uint8List(_pad4(encoded.length + 1));
    padded.setRange(0, encoded.length, encoded);
    _body.add(padded);
  }

  void array(List<int>? value) {
    final List<int> bytes = value ?? const [];
    uint32(bytes.length);
    final Uint8List padded = Uint8List(_pad4(bytes.length));
    padded.setRange(0, bytes.length, bytes);
    _body.add(padded);
  }

  void fd(RandomAccessFile file) => fds.add(file);

  Uint8List finish() {
    final int size = kHeaderSize + _body.length;
    if (size > 0xffff) {
      throw ArgumentError('Wayland message too large ($size bytes)');
    }

    final ByteData header = ByteData(kHeaderSize)
      ..setUint32(0, objectId, Endian.host)
      ..setUint32(4, (size << 16) | (opcode & 0xffff), Endian.host);

    final BytesBuilder message = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(_body.takeBytes());
    return message.takeBytes();
  }
}

/// Source of file descriptors received out of band alongside messages.
abstract interface class FdSource {
  RandomAccessFile takeFd();
}

/// Deserializes the arguments of a single event.
class WireReader {
  WireReader(this._data, this._fds);

  final ByteData _data;
  final FdSource _fds;
  int _offset = 0;

  int int32() {
    final int value = _data.getInt32(_offset, Endian.host);
    _offset += 4;
    return value;
  }

  int uint32() {
    final int value = _data.getUint32(_offset, Endian.host);
    _offset += 4;
    return value;
  }

  double fixed() => fixedToDouble(int32());

  String? string() {
    final int length = uint32();
    if (length == 0) return null;

    final Uint8List bytes = _data.buffer.asUint8List(
      _data.offsetInBytes + _offset,
      length - 1, // strip the terminating NUL byte
    );
    _offset += _pad4(length);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Uint8List array() {
    final int length = uint32();
    final Uint8List bytes = Uint8List.fromList(
      _data.buffer.asUint8List(_data.offsetInBytes + _offset, length),
    );
    _offset += _pad4(length);
    return bytes;
  }

  RandomAccessFile fd() => _fds.takeFd();
}
