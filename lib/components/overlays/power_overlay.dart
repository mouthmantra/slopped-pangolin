/*
Copyright 2021 The dahliaOS Authors

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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/widgets/power_account_button.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:zenit_ui/zenit_ui.dart';

class PowerOverlay extends ShellOverlay {
  static const String overlayId = "power";

  PowerOverlay({super.key}) : super(id: overlayId);

  @override
  _PowerOverlayState createState() => _PowerOverlayState();
}

class _PowerOverlayState extends ShellOverlayState<PowerOverlay> {
  @override
  FutureOr<void> requestShow(Map<String, dynamic> args) async {
    controller.showing = true;
    animationController.forward();
  }

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) async {
    animationController.reverse();
    controller.showing = false;
  }

  @override
  Widget build(BuildContext context) {
    if (shouldHide) return const SizedBox();

    return Stack(
      children: [
        // Clicks outside the panel reach the shell, which dismisses it.
        // Sized by its content so every action fits, centered in the work area.
        Center(
          child: PopupTransition(
            animation: animation,
            showing: controller.showing,
            alignment: FractionalOffset.center,
            child: SurfaceLayer(
              outline: true,
              shape: Constants.bigShape,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 328,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).surfaceColor,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.powerOverlay.title,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(strings.powerOverlay.subtitle),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          PowerAccountMenuButton(
                            title: strings.powerOverlay.poweroff,
                            icon: Icons.power_settings_new_rounded,
                            context: context,
                            onPressed: ActionManager.powerOff,
                          ),
                          PowerAccountMenuButton(
                            title: strings.powerOverlay.sleep,
                            icon: Icons.brightness_4_outlined,
                            context: context,
                            onPressed: ActionManager.suspend,
                          ),
                          PowerAccountMenuButton(
                            title: strings.powerOverlay.restart,
                            icon: Icons.replay_rounded,
                            context: context,
                            onPressed: ActionManager.reboot,
                          ),
                          PowerAccountMenuButton(
                            title: "Sign out",
                            icon: Icons.logout_rounded,
                            context: context,
                            onPressed: ActionManager.logout,
                          ),
                          if (ActionManager.canLock)
                            PowerAccountMenuButton(
                              title: "Lock",
                              icon: Icons.lock_outline,
                              context: context,
                              onPressed: ActionManager.lock,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
