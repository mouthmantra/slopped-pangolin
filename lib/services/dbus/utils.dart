import 'dart:async';
import 'dart:io';

Future<T?> callAsNullable<T>(FutureOr<T> Function() method) async {
  try {
    final T value = await method();
    return value;
  } catch (e) {
    return null;
  }
}

T? callAsNullableSync<T>(T Function() method) {
  try {
    final T value = method();
    return value;
  } catch (e) {
    return null;
  }
}

/// Whether a system bus socket exists. Connecting to a missing bus makes
/// package:dbus raise errors from inside signal subscriptions, where callers
/// can't catch them, so check first.
bool systemBusAvailable() {
  final String address = Platform.environment["DBUS_SYSTEM_BUS_ADDRESS"] ??
      "unix:path=/run/dbus/system_bus_socket";
  for (final String part in address.split(";")) {
    if (!part.startsWith("unix:")) return true; // tcp etc.: can't tell, try it
    final RegExpMatch? path = RegExp("path=([^,]+)").firstMatch(part);
    if (path == null) return true; // abstract socket
    if (FileSystemEntity.typeSync(path.group(1)!) !=
        FileSystemEntityType.notFound) {
      return true;
    }
  }
  return false;
}
