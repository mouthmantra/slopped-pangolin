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

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Outcome of a password check.
enum PamResult { success, wrongPassword, unavailable }

/// Checks the user's password with PAM (libpam is loaded at runtime, so
/// Pangolin builds without its headers and runs on any distribution that
/// has it).
abstract final class Pam {
  /// Whether passwords can be checked here at all: without libpam (e.g. a
  /// system without PAM) a locked screen could never be unlocked.
  static final bool available = () {
    try {
      DynamicLibrary.open("libpam.so.0");
      return true;
    } on ArgumentError {
      return false;
    }
  }();

  /// PAM service used to check passwords: Pangolin's own when installed
  /// system-wide (/etc/pam.d/pangolin), the login service otherwise.
  static String get service {
    for (final String name in ["pangolin", "login", "system-auth", "other"]) {
      if (File("/etc/pam.d/$name").existsSync() ||
          File("/usr/lib/pam.d/$name").existsSync() ||
          File("/usr/share/pam.d/$name").existsSync()) {
        return name;
      }
    }
    return "login";
  }

  static String get user {
    final String? name = Platform.environment["USER"] ??
        Platform.environment["LOGNAME"];
    if (name != null && name.isNotEmpty) return name;
    final ProcessResult result = Process.runSync("id", ["-un"]);
    return (result.stdout as String).trim();
  }

  /// Checks [password] for the current user, on a background isolate (PAM
  /// can take seconds, deliberately, after a wrong password).
  static Future<PamResult> authenticate(String password) {
    final String service = Pam.service;
    final String user = Pam.user;
    return Isolate.run(() => _authenticate(service, user, password));
  }
}

const int _pamSuccess = 0;
const int _pamConvErr = 19;
const int _pamPromptEchoOff = 1;
const int _pamPromptEchoOn = 2;

final class _PamMessage extends Struct {
  @Int32()
  external int style;
  external Pointer<Utf8> msg;
}

final class _PamResponse extends Struct {
  external Pointer<Utf8> resp;
  @Int32()
  external int retcode;
}

final class _PamConv extends Struct {
  external Pointer<NativeFunction<_ConvNative>> conv;
  external Pointer<Void> appdata;
}

typedef _ConvNative = Int32 Function(
  Int32 count,
  Pointer<Pointer<_PamMessage>> messages,
  Pointer<Pointer<_PamResponse>> responses,
  Pointer<Void> appdata,
);

typedef _StartNative = Int32 Function(
  Pointer<Utf8> service,
  Pointer<Utf8> user,
  Pointer<_PamConv> conv,
  Pointer<Pointer<Void>> handle,
);
typedef _Start = int Function(
  Pointer<Utf8> service,
  Pointer<Utf8> user,
  Pointer<_PamConv> conv,
  Pointer<Pointer<Void>> handle,
);
typedef _HandleIntNative = Int32 Function(Pointer<Void> handle, Int32 value);
typedef _HandleInt = int Function(Pointer<Void> handle, int value);

PamResult _authenticate(String service, String user, String password) {
  final DynamicLibrary pam;
  try {
    pam = DynamicLibrary.open("libpam.so.0");
  } on ArgumentError {
    return PamResult.unavailable;
  }
  final _Start start = pam.lookupFunction<_StartNative, _Start>("pam_start");
  final _HandleInt authenticate =
      pam.lookupFunction<_HandleIntNative, _HandleInt>("pam_authenticate");
  final _HandleInt accountManagement =
      pam.lookupFunction<_HandleIntNative, _HandleInt>("pam_acct_mgmt");
  final _HandleInt setCredentials =
      pam.lookupFunction<_HandleIntNative, _HandleInt>("pam_setcred");
  final _HandleInt end = pam.lookupFunction<_HandleIntNative, _HandleInt>("pam_end");

  // PAM asks for the password through the conversation function; it frees
  // the answers itself, so they are allocated with the C allocator.
  int converse(
    int count,
    Pointer<Pointer<_PamMessage>> messages,
    Pointer<Pointer<_PamResponse>> responses,
    Pointer<Void> appdata,
  ) {
    if (count <= 0) return _pamConvErr;
    final Pointer<_PamResponse> answers = calloc<_PamResponse>(count);
    for (int i = 0; i < count; i++) {
      final int style = messages[i].ref.style;
      if (style == _pamPromptEchoOff || style == _pamPromptEchoOn) {
        answers[i].resp = password.toNativeUtf8(allocator: calloc);
      }
    }
    responses.value = answers;
    return _pamSuccess;
  }

  final NativeCallable<_ConvNative> callable =
      NativeCallable<_ConvNative>.isolateLocal(
    converse,
    exceptionalReturn: _pamConvErr,
  );
  final Pointer<_PamConv> conversation = calloc<_PamConv>()
    ..ref.conv = callable.nativeFunction
    ..ref.appdata = nullptr;
  final Pointer<Pointer<Void>> handle = calloc<Pointer<Void>>();
  final Pointer<Utf8> serviceName = service.toNativeUtf8();
  final Pointer<Utf8> userName = user.toNativeUtf8();
  try {
    int status = start(serviceName, userName, conversation, handle);
    if (status != _pamSuccess) return PamResult.unavailable;
    status = authenticate(handle.value, 0);
    if (status == _pamSuccess) status = accountManagement(handle.value, 0);
    // Refreshes credentials such as Kerberos tickets, as screen lockers do.
    if (status == _pamSuccess) setCredentials(handle.value, 0x0010);
    end(handle.value, status);
    return status == _pamSuccess ? PamResult.success : PamResult.wrongPassword;
  } finally {
    malloc.free(serviceName);
    malloc.free(userName);
    calloc.free(handle);
    calloc.free(conversation);
    callable.close();
  }
}
