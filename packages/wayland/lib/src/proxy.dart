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

import 'package:meta/meta.dart';
import 'package:wayland/src/connection.dart';
import 'package:wayland/src/wire.dart';

typedef ProxyFactory<T extends Proxy> = T Function(
  WaylandConnection connection,
  int id,
  int version,
);

/// Static description of a Wayland interface, used to bind globals and to
/// construct proxies for objects created by the server.
class WaylandInterface<T extends Proxy> {
  const WaylandInterface(this.name, this.version, this.factory);

  /// Interface name as advertised by `wl_registry.global`.
  final String name;

  /// Highest version of the interface this library knows how to speak.
  final int version;

  final ProxyFactory<T> factory;
}

/// Client side representation of a Wayland object.
abstract class Proxy {
  Proxy(this.connection, this.id, this.version);

  final WaylandConnection connection;
  final int id;
  final int version;

  bool _destroyed = false;

  /// Whether a destructor request has been sent for this object. Events that
  /// are still in flight are parsed but no longer delivered to listeners.
  bool get destroyed => _destroyed;

  String get interfaceName;

  /// Arbitrary data attached by users of the proxy, akin to
  /// `wl_proxy_set_user_data`.
  Object? userData;

  @internal
  void dispatchEvent(int opcode, WireReader reader);

  @protected
  void markDestroyed() {
    _destroyed = true;
    connection.releaseProxy(this);
  }

  @protected
  void send(WireWriter writer) {
    if (_destroyed) {
      throw StateError('Request sent on destroyed object $this');
    }
    connection.queueRequest(writer);
  }

  @override
  String toString() => '$interfaceName@$id';
}
