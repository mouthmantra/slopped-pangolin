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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:display_config/display_config.dart' show SharedUserFiles;
import 'package:pangolin_settings/pangolin_settings.dart';

/// The interface font each user chose, for the login screen, which can't
/// read their settings: its family name in SharedUserFiles ("" for
/// Pangolin's default, Inter). The login screen uses it for that user when
/// the font is installed for everyone (a font in someone's home folder
/// isn't readable there).
abstract final class FontShare {
  static const String sharedName = "font";

  static String? _shared;

  /// In a session: shares the font now and whenever it changes.
  static void follow() {
    final PreferencesService prefs = PreferencesService.current;
    void update() {
      final String font = prefs.get<String>(SessionSetting.interfaceFont.key) ?? "";
      if (font == _shared) return;
      _shared = font;
      unawaited(SharedUserFiles.publish(sharedName, utf8.encode(font)));
    }

    prefs.addListener(update);
    // Once startup is over.
    Timer(const Duration(seconds: 6), update);
  }

  /// The family [user] shared ("" for the default), null when there's none.
  static String? of(String user) {
    try {
      final String? font = SharedUserFiles.published(user, sharedName)?.readAsStringSync().trim();
      return font != null && font.length <= 128 && !font.contains("\n") ? font : null;
    } on Object {
      return null;
    }
  }
}
