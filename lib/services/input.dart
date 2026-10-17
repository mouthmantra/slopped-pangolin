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
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:ffi/ffi.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:wayland/wayland.dart';

class InputServiceFactory extends ServiceFactory<InputService> {
  const InputServiceFactory();

  @override
  InputService build() {
    if (!PangolinSession.isSession) throw StateError("Not in a river session");
    return _RiverInputService();
  }

  @override
  InputService fallback() => _NoopInputService();
}

/// Applies the session's keyboard and pointer settings (stored in the shared
/// preferences, edited by the Settings app) to river's input devices.
abstract class InputService extends Service {
  static InputService get current => ServiceManager.getService<InputService>()!;
}

class _NoopInputService extends InputService {
  @override
  void start() {}

  @override
  void stop() {}
}

class _RiverInputService extends InputService {
  late final WaylandConnection _connection;
  RiverInputManagerV1? _inputManager;
  RiverXkbConfigV1? _xkbConfig;
  RiverLibinputConfigV1? _libinput;

  final List<RiverInputDeviceV1> _keyboards = [];
  final List<RiverXkbKeyboardV1> _xkbKeyboards = [];
  final List<RiverLibinputDeviceV1> _pointers = [];
  final Set<RiverLibinputDeviceV1> _touchpads = {};

  RiverXkbKeymapV1? _keymap;
  String? _keymapSource;
  Timer? _applyDebounce;

  PreferencesService get _prefs => PreferencesService.current;

  T _get<T extends Object>(SessionSetting<T> setting) =>
      _prefs.get<T>(setting.key) ?? setting.defaultValue;

  @override
  Future<void> start() async {
    await ServiceManager.waitForService<PreferencesService>();
    _connection = await WaylandConnection.connect();
    final GlobalRegistry globals = await GlobalRegistry.create(_connection);

    _inputManager = globals.bind(RiverInputManagerV1.interface);
    _xkbConfig = globals.bind(RiverXkbConfigV1.interface);
    _libinput = globals.bind(RiverLibinputConfigV1.interface);

    _inputManager?.onInputDevice = (device) {
      device
        ..onType = (type) {
          if (type == RiverInputDeviceV1Type.keyboard) {
            _keyboards.add(device);
            _applyRepeat(device);
          }
        }
        ..onRemoved = () {
          _keyboards.remove(device);
          device.destroy();
        };
    };

    _xkbConfig?.onXkbKeyboard = (keyboard) {
      _xkbKeyboards.add(keyboard);
      keyboard.onRemoved = () {
        _xkbKeyboards.remove(keyboard);
        keyboard.destroy();
      };
      final RiverXkbKeymapV1? keymap = _keymap;
      if (keymap != null) keyboard.setKeymap(keymap);
    };

    _libinput?.onLibinputDevice = (device) {
      // Touchpads support tapping, mice don't: the settings that apply are
      // known once river has described the device (done).
      bool described = false;
      void describe() {
        if (described || !_pointers.contains(device)) return;
        described = true;
        _applyPointer(device);
      }

      device
        ..onTapSupport = (fingers) {
          if (fingers > 0) _touchpads.add(device);
        }
        ..onDone = describe
        ..onRemoved = () {
          _pointers.remove(device);
          _touchpads.remove(device);
          device.destroy();
        };
      _pointers.add(device);
      // river versions without the done event.
      Timer(const Duration(milliseconds: 100), describe);
    };

    await _connection.roundtrip();
    _applyKeymap();

    _prefs.addListener(_onPreferencesChanged);
    logger.info(
      "Input configuration ready (keyboards: ${_keyboards.length}, "
      "pointers: ${_pointers.length}, xkb: ${_xkbConfig != null})",
    );
  }

  @override
  Future<void> stop() async {
    _prefs.removeListener(_onPreferencesChanged);
    await _connection.close();
  }

  void _onPreferencesChanged() {
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 150), () {
      _applyKeymap();
      _keyboards.forEach(_applyRepeat);
      _pointers.forEach(_applyPointer);
    });
  }

  void _applyRepeat(RiverInputDeviceV1 device) {
    device.setRepeatInfo(
      _get(SessionSetting.keyRepeatRate).clamp(1, 100),
      _get(SessionSetting.keyRepeatDelay).clamp(100, 2000),
    );
  }

  /// Mice and touchpads have settings of their own (Settings > Mouse,
  /// Touchpad); requests a device doesn't support just report "unsupported".
  void _applyPointer(RiverLibinputDeviceV1 device) {
    device.setLeftHanded(_get(SessionSetting.leftHanded) ? 1 : 0);
    if (_touchpads.contains(device)) {
      device.setTap(_get(SessionSetting.tapToClick) ? 1 : 0);
      // Two fingers: the physical click (clickfinger) and the tap both give
      // a right click; otherwise the bottom right corner does.
      device.setClickMethod(
        _get(SessionSetting.twoFingerRightClick)
            ? RiverLibinputDeviceV1ClickMethod.clickfinger
            : RiverLibinputDeviceV1ClickMethod.buttonAreas,
      );
      device.setNaturalScroll(_get(SessionSetting.naturalScroll) ? 1 : 0);
      device.setDwt(_get(SessionSetting.disableWhileTyping) ? 1 : 0);
      device.setSendEvents(switch (_get(SessionSetting.touchpadMode)) {
        "disabled" => RiverLibinputDeviceV1SendEventsModes.disabled,
        "external_mouse" =>
          RiverLibinputDeviceV1SendEventsModes.disabledOnExternalMouse,
        _ => RiverLibinputDeviceV1SendEventsModes.enabled,
      });
      device.setAccelProfile(
        _get(SessionSetting.touchpadAcceleration)
            ? RiverLibinputDeviceV1AccelProfile.adaptive
            : RiverLibinputDeviceV1AccelProfile.flat,
      );
      _setSpeed(device, _get(SessionSetting.touchpadSpeed));
    } else {
      device.setNaturalScroll(_get(SessionSetting.mouseNaturalScroll) ? 1 : 0);
      device.setAccelProfile(
        _get(SessionSetting.mouseAcceleration)
            ? RiverLibinputDeviceV1AccelProfile.adaptive
            : RiverLibinputDeviceV1AccelProfile.flat,
      );
      _setSpeed(device, _get(SessionSetting.pointerSpeed));
    }
  }

  static void _setSpeed(RiverLibinputDeviceV1 device, double speed) {
    final ByteData encoded = ByteData(8)
      ..setFloat64(0, speed.clamp(-1.0, 1.0), Endian.host);
    device.setAccelSpeed(encoded.buffer.asUint8List());
  }

  void _applyKeymap() {
    final RiverXkbConfigV1? config = _xkbConfig;
    if (config == null) return;

    final String layouts = _get(SessionSetting.keyboardLayouts);
    final String variants = _get(SessionSetting.keyboardVariants);
    final String options = _get(SessionSetting.keyboardOptions);
    final String source = "$layouts|$variants|$options";
    if (source == _keymapSource) return;

    final String? text = XkbKeymapCompiler.compile(
      layout: layouts,
      variant: variants,
      options: options,
    );
    if (text == null) {
      logger.warning("Could not compile keymap for layouts '$layouts'");
      return;
    }
    _keymapSource = source;

    final File file = File(
      "${Platform.environment["XDG_RUNTIME_DIR"] ?? Directory.systemTemp.path}"
      "/pangolin-keymap-$pid",
    );
    file.writeAsStringSync("$text\u0000", flush: true);
    final RandomAccessFile handle = file.openSync();
    file.deleteSync();

    final RiverXkbKeymapV1 keymap =
        config.createKeymap(handle, RiverXkbConfigV1KeymapFormat.textV1);
    keymap
      ..onSuccess = () {
        _keymap?.destroy();
        _keymap = keymap;
        for (final RiverXkbKeyboardV1 keyboard in _xkbKeyboards) {
          keyboard.setKeymap(keymap);
        }
        logger.info("Keyboard layout set to $layouts");
      }
      ..onFailure = (error) {
        logger.warning("river rejected the keymap: $error");
        keymap.destroy();
      };
    _connection.flush();
    handle.closeSync();
  }
}

final class _XkbRuleNames extends Struct {
  external Pointer<Utf8> rules;
  external Pointer<Utf8> model;
  external Pointer<Utf8> layout;
  external Pointer<Utf8> variant;
  external Pointer<Utf8> options;
}

/// Compiles RMLVO names into a keymap string with libxkbcommon.
abstract final class XkbKeymapCompiler {
  static DynamicLibrary? _lib;

  static DynamicLibrary? get _xkb {
    if (_lib != null) return _lib;
    for (final String name in ["libxkbcommon.so.0", "libxkbcommon.so"]) {
      try {
        return _lib = DynamicLibrary.open(name);
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  static String? compile({
    required String layout,
    String variant = "",
    String options = "",
  }) {
    final DynamicLibrary? xkb = _xkb;
    if (xkb == null) return null;

    final Pointer<Void> Function(int) contextNew = xkb
        .lookupFunction<Pointer<Void> Function(Int32), Pointer<Void> Function(int)>(
      "xkb_context_new",
    );
    final void Function(Pointer<Void>) contextUnref = xkb
        .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      "xkb_context_unref",
    );
    final Pointer<Void> Function(Pointer<Void>, Pointer<_XkbRuleNames>, int) keymapNew =
        xkb.lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<_XkbRuleNames>, Int32),
            Pointer<Void> Function(Pointer<Void>, Pointer<_XkbRuleNames>, int)>(
      "xkb_keymap_new_from_names",
    );
    final void Function(Pointer<Void>) keymapUnref = xkb
        .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      "xkb_keymap_unref",
    );
    final Pointer<Utf8> Function(Pointer<Void>, int) keymapString = xkb.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)>("xkb_keymap_get_as_string");

    final Pointer<Void> context = contextNew(0);
    if (context == nullptr) return null;
    final Pointer<_XkbRuleNames> names = calloc<_XkbRuleNames>();
    final List<Pointer<Utf8>> strings = [
      layout.toNativeUtf8(),
      variant.toNativeUtf8(),
      options.toNativeUtf8(),
    ];
    try {
      names.ref
        ..layout = strings[0]
        ..variant = strings[1]
        ..options = strings[2];
      final Pointer<Void> keymap = keymapNew(context, names, 0);
      if (keymap == nullptr) return null;
      final Pointer<Utf8> text = keymapString(keymap, 1 /* XKB_KEYMAP_FORMAT_TEXT_V1 */);
      final String? result = text == nullptr ? null : text.toDartString();
      if (text != nullptr) malloc.free(text);
      keymapUnref(keymap);
      return result;
    } finally {
      for (final Pointer<Utf8> s in strings) {
        calloc.free(s);
      }
      calloc.free(names);
      contextUnref(context);
    }
  }
}
