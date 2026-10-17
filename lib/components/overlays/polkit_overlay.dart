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
import 'package:pangolin/services/polkit_agent.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';

/// Asks for a password when an app needs permission for something
/// ([PolkitAgent]). Dismissing it cancels the request.
class PolkitOverlay extends ShellOverlay {
  static const String overlayId = "polkit";

  PolkitOverlay({super.key}) : super(id: overlayId);

  @override
  ShellOverlayState<PolkitOverlay> createState() => _PolkitOverlayState();
}

class _PolkitOverlayState extends ShellOverlayState<PolkitOverlay> {
  final TextEditingController _answer = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: "polkit");

  /// Has the keyboard while the field can't (disabled while checking), so
  /// that Escape still cancels.
  final FocusNode _dialogFocus = FocusNode(debugLabel: "polkit dialog");

  PolkitAgent get _agent => PolkitAgent.instance;

  /// The request on screen (kept while the dialog animates out).
  PolkitRequest? _request;

  @override
  void initState() {
    super.initState();
    _agent.current.addListener(_onRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  @override
  void dispose() {
    _agent.current.removeListener(_onRequest);
    _request?.prompt.removeListener(_onPrompt);
    _answer.dispose();
    _focus.dispose();
    _dialogFocus.dispose();
    super.dispose();
  }

  void _onRequest() {
    final PolkitRequest? request = _agent.current.value;
    if (request != null) {
      _show(request);
      ShellService.current.showOverlay(PolkitOverlay.overlayId);
    } else if (controller.showing) {
      ShellService.current.dismissOverlay(PolkitOverlay.overlayId);
    }
  }

  void _show(PolkitRequest request) {
    if (request == _request) return;
    _request?.prompt.removeListener(_onPrompt);
    request.prompt.addListener(_onPrompt);
    _answer.clear();
    setState(() => _request = request);
  }

  void _onPrompt() {
    if (!mounted) return;
    setState(() {});
    _refocus();
  }

  /// The field while it takes answers (it can't while disabled), the dialog
  /// otherwise.
  void _refocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final PolkitPrompt? prompt = _request?.prompt.value;
      if (!mounted || !controller.showing || prompt == null) return;
      if (prompt.prompt != null && !prompt.busy) {
        _focus.requestFocus();
      } else {
        _dialogFocus.requestFocus();
      }
    });
  }

  void _submit() {
    final PolkitRequest? request = _request;
    if (request == null) return;
    final PolkitPrompt prompt = request.prompt.value;
    if (prompt.prompt == null || prompt.busy) return;
    request.respond(_answer.text);
    _answer.clear();
  }

  void _cancel() {
    ShellService.current.dismissOverlay(PolkitOverlay.overlayId);
  }

  @override
  FutureOr<void> requestShow(Map<String, dynamic> args) {
    if (_agent.current.value == null) return null;
    controller.showing = true;
    animationController.forward();
    _refocus();
  }

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) {
    controller.showing = false;
    animationController.reverse();
    // Dismissed by the user (or by another overlay): no permission.
    final PolkitRequest? request = _request;
    if (request != null && _agent.current.value == request) request.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final PolkitRequest? request = _request;
    if (shouldHide || request == null) return const SizedBox();
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final PolkitPrompt prompt = request.prompt.value;
    final String hint = _hintOf(prompt.prompt);

    return Center(
      child: PopupTransition(
        animation: animation,
        showing: controller.showing,
        alignment: FractionalOffset.center,
        child: SurfaceLayer(
          shape: Constants.bigShape,
          child: Material(
            type: MaterialType.transparency,
            child: Focus(
              focusNode: _dialogFocus,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _cancel();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
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
                          Icons.lock_outline_rounded,
                          color: colors.onSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Authentication required",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        request.message.isNotEmpty
                            ? request.message
                            : "An app wants to make changes that need your "
                                "permission.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                colors.onSurface.withValues(alpha: 0.12),
                            child: Text(
                              request.user.displayName
                                  .characters
                                  .first
                                  .toUpperCase(),
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              request.user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _AnswerField(
                        controller: _answer,
                        focus: _focus,
                        hint: hint,
                        echo: prompt.echo,
                        enabled: prompt.prompt != null && !prompt.busy,
                        busy: prompt.busy,
                        onSubmit: _submit,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: prompt.error != null || prompt.info != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  prompt.error ?? prompt.info!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: prompt.error != null
                                        ? colors.error
                                        : colors.onSurface
                                            .withValues(alpha: 0.75),
                                  ),
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _cancel,
                          child: const Text("Cancel"),
                        ),
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

  /// "Password: " → "Password".
  static String _hintOf(String? prompt) {
    final String text = (prompt ?? "Password").trim();
    final String bare =
        text.endsWith(":") ? text.substring(0, text.length - 1).trim() : text;
    return bare.isEmpty ? "Password" : bare;
  }
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.echo,
    required this.enabled,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool echo;
  final bool enabled;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 20, right: 4),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: colors.onSurface.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              obscureText: !echo,
              enabled: enabled,
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
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 40,
            child: Material(
              color: colors.secondary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onSubmit : null,
                child: Center(
                  child: busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onSecondary,
                          ),
                        )
                      : Icon(
                          Icons.arrow_forward_rounded,
                          color: colors.onSecondary,
                          size: 22,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
