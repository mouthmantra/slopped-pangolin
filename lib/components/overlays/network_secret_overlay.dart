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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/vpn.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';

/// Asks for the password a VPN (or a Wi-Fi network) needs to connect, for
/// NetworkManager ([VpnService]'s secret agent). Dismissing it cancels.
class NetworkSecretOverlay extends ShellOverlay {
  static const String overlayId = "network-secret";

  NetworkSecretOverlay({super.key}) : super(id: overlayId);

  @override
  ShellOverlayState<NetworkSecretOverlay> createState() =>
      _NetworkSecretOverlayState();
}

class _NetworkSecretOverlayState
    extends ShellOverlayState<NetworkSecretOverlay> {
  final Map<String, TextEditingController> _fields = {};
  final Map<String, FocusNode> _focus = {};
  bool _remember = true;

  VpnService get _vpn => VpnService.instance;

  /// The request on screen (kept while the dialog animates out).
  NetworkSecretRequest? _request;

  @override
  void initState() {
    super.initState();
    _vpn.secretRequest.addListener(_onRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  @override
  void dispose() {
    _vpn.secretRequest.removeListener(_onRequest);
    _disposeFields();
    super.dispose();
  }

  void _disposeFields() {
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    for (final FocusNode f in _focus.values) {
      f.dispose();
    }
    _fields.clear();
    _focus.clear();
  }

  void _onRequest() {
    final NetworkSecretRequest? request = _vpn.secretRequest.value;
    if (request != null) {
      if (request != _request) {
        _disposeFields();
        for (final String key in request.keys) {
          _fields[key] = TextEditingController();
          _focus[key] = FocusNode(debugLabel: "network secret $key");
        }
        setState(() {
          _request = request;
          _remember = request.remember;
        });
      }
      ShellService.current.showOverlay(NetworkSecretOverlay.overlayId);
    } else if (controller.showing) {
      ShellService.current.dismissOverlay(NetworkSecretOverlay.overlayId);
    }
  }

  void _refocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.showing) return;
      _focus.values.firstOrNull?.requestFocus();
    });
  }

  void _submit() {
    final NetworkSecretRequest? request = _request;
    if (request == null || request.done) return;
    request
      ..remember = _remember
      ..respond({
        for (final MapEntry<String, TextEditingController> e
            in _fields.entries)
          e.key: e.value.text,
      });
  }

  void _cancel() {
    ShellService.current.dismissOverlay(NetworkSecretOverlay.overlayId);
  }

  @override
  FutureOr<void> requestShow(Map<String, dynamic> args) {
    if (_vpn.secretRequest.value == null) return null;
    controller.showing = true;
    animationController.forward();
    _refocus();
  }

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) {
    controller.showing = false;
    animationController.reverse();
    // Dismissed by the user (or by another overlay): not connecting.
    final NetworkSecretRequest? request = _request;
    if (request != null && _vpn.secretRequest.value == request) {
      request.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final NetworkSecretRequest? request = _request;
    if (shouldHide || request == null) return const SizedBox();
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String what = request.isVpn ? "the VPN" : "the network";
    final String message = request.message?.trim().isNotEmpty == true
        ? request.message!.trim()
        : request.retry
            ? "That didn't work. Enter the password of $what "
                "“${request.name}” again."
            : "A password is needed to connect to $what “${request.name}”.";

    return Center(
      child: PopupTransition(
        animation: animation,
        showing: controller.showing,
        alignment: FractionalOffset.center,
        child: SurfaceLayer(
          shape: Constants.bigShape,
          child: Material(
            type: MaterialType.transparency,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              },
              child: SizedBox(
                width: 400,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color: colors.secondary,
                        ),
                        child: Icon(
                          request.isVpn
                              ? Icons.vpn_key_rounded
                              : Icons.wifi_password_rounded,
                          color: colors.onSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        request.isVpn ? "Connect to VPN" : "Connect to Wi-Fi",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final String key in request.keys) ...[
                        _SecretField(
                          controller: _fields[key]!,
                          focus: _focus[key]!,
                          hint: NetworkSecretRequest.label(key),
                          secret: key != "username",
                          onSubmit: key == request.keys.last
                              ? _submit
                              : () => _focus[request.keys[
                                          request.keys.indexOf(key) + 1]]
                                      ?.requestFocus(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _remember = !_remember),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _remember,
                              onChanged: (v) =>
                                  setState(() => _remember = v ?? true),
                            ),
                            const Text("Remember the password"),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _cancel,
                            child: const Text("Cancel"),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _submit,
                            child: const Text("Connect"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.secret,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool secret;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: colors.onSurface.withValues(alpha: 0.08),
      ),
      child: TextField(
        controller: controller,
        focusNode: focus,
        obscureText: secret,
        onSubmitted: (_) => onSubmit(),
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          filled: false,
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}
