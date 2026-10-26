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

import 'dart:io';

import 'package:flutter/material.dart';

/// A user's picture, or their initial in a circle of [color] (the accent by
/// default), as the login and lock screens show accounts.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.name,
    required this.size,
    this.color,
    this.picture,
    super.key,
  });

  final String name;
  final double size;
  final Color? color;

  /// The account's picture (AccountsService, as GNOME sets it), if any.
  final File? picture;

  /// [user]'s picture as GNOME's Settings and GDM keep it, or for a
  /// systemd-homed user, the one in homed's blob folder (readable while the
  /// home is locked).
  static File? pictureOf(String user) {
    if (user.isEmpty || user.contains("/")) return null;
    for (final String path in [
      "/var/lib/AccountsService/icons/$user",
      "/var/cache/systemd/home/$user/avatar",
    ]) {
      final File file = File(path);
      try {
        if (file.statSync().type == FileSystemEntityType.file) return file;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final File? picture = this.picture;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.secondary,
        shape: BoxShape.circle,
      ),
      child: picture != null
          ? Image.file(
              picture,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth:
                  (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
              errorBuilder: (context, _, __) => _initial(),
            )
          : _initial(),
    );
  }

  Widget _initial() {
    return Text(
      name.isNotEmpty ? name.characters.first.toUpperCase() : "?",
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.45,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
