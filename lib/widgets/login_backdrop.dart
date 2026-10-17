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

import 'package:flutter/material.dart';

/// Shadow under the white text of the lock and login screens: keeps it
/// readable on any wallpaper, also bright ones, without blurring the
/// wallpaper.
///
/// Small: blurred shadows are drawn again with every frame (the text
/// field's cursor blinking), and the veil below does most of the work.
const List<Shadow> loginTextShadows = [
  Shadow(color: Color(0x73000000), blurRadius: 3, offset: Offset(0, 1)),
];

/// The wallpaper behind the lock and login screens, sharp (as on the
/// desktop) and darkened where the text sits: a light veil over all of it,
/// deeper at the top (the clock) and around the middle (the user and the
/// password field).
class LoginBackdrop extends StatelessWidget {
  const LoginBackdrop({
    required this.wallpaper,
    this.veil = kAlwaysCompleteAnimation,
    super.key,
  });

  final Widget wallpaper;

  /// How much of the darkening shows: the login screen takes it away when
  /// it hands over to the desktop, which starts on the plain wallpaper.
  final Animation<double> veil;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Repainted only when the wallpaper changes, not with the text
        // field's cursor above it.
        RepaintBoundary(child: wallpaper),
        FadeTransition(
          opacity: veil,
          child: const _Veil(),
        ),
      ],
    );
  }
}

class _Veil extends StatelessWidget {
  const _Veil();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x8C000000),
                Color(0x4D000000),
                Color(0x66000000),
                Color(0x59000000),
              ],
              stops: [0, 0.35, 0.62, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 0.25),
              radius: 0.75,
              colors: [Color(0x40000000), Color(0x00000000)],
            ),
          ),
        ),
      ],
    );
  }
}
