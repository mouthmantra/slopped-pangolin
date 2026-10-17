import 'dart:developer';
import 'dart:io' show stderr;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show PlatformDispatcher;
import 'package:logging/logging.dart';
import 'package:pangolin/services/notifications.dart';
import 'package:pangolin/services/shell.dart';
import 'package:stack_trace/stack_trace.dart';

void setupLogger([
  Level baseLoggingLevel = Level.ALL,
  Level notificationLoggingLevel = Level.WARNING,
]) {
  // Framework errors (build/layout/paint) and uncaught async errors must not
  // vanish: the shell has no console to show them on.
  final Logger flutterLogger = Logger("Flutter");
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    flutterLogger.severe(
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    flutterLogger.severe("Uncaught error", error, stack);
    return true;
  };

  Logger.root.level = baseLoggingLevel;
  Logger.root.onRecord.listen((record) {
    // Pangolin is a session component: always leave a trace on stderr so
    // problems end up in the session log / journal, even in release builds.
    if (!kIsWeb && record.level >= Level.INFO) {
      stderr.writeln(
        "[${record.level.name}] ${record.loggerName}: ${record.message}"
        "${record.error != null ? " (${record.error})" : ""}",
      );
      if (record.stackTrace != null && record.level >= Level.SEVERE) {
        stderr.writeln(record.stackTrace);
      }
    }

    if (kDebugMode) {
      if (record.level.value >= notificationLoggingLevel.value) {
        Future.wait([
          ServiceManager.waitForService<ShellService>(),
          ServiceManager.waitForService<NotificationService>(),
        ]).then((value) {
          ShellService.current.onShellReadyCallback(() {
            _pushShellNotification(record);
          });
        });
      }

      log(
        record.message,
        time: record.time,
        sequenceNumber: record.sequenceNumber,
        level: record.level.value,
        name: record.loggerName,
        zone: record.zone,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    }
  });
}

void _pushShellNotification(LogRecord record) {
  NotificationService.current.pushNotification(
    ShellNotification(
      appName: record.loggerName,
      summary:
          "Logged a ${record.level.name.toLowerCase()} for ${record.loggerName}",
      body: record.message,
      actions: [
        if (record.error != null)
          const NotificationAction("error", "Show error"),
        if (record.stackTrace != null &&
            record.stackTrace.toString().isNotEmpty)
          const NotificationAction("stackTrace", "Show stack trace"),
      ],
      onAction: (action) {
        switch (action) {
          case "error":
            ShellService.current.showInformativeDialog(
              "Error",
              record.error.toString(),
            );
          case "stackTrace":
            ShellService.current.showInformativeDialog(
              "Stack trace",
              Trace.from(record.stackTrace!).terse.toString(),
            );
        }
      },
    ),
  );
}
