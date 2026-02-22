// lib/core/services/logger_service.dart
//
// Centralised structured logger for WeldQAi.
// - In debug builds: pretty-printed, all levels (trace → fatal)
// - In release builds: warnings and above only, no colour / method info
//   (colour codes break crash-reporting log capture)
// - Never use print() or debugPrint() directly in app code.
//   Always go through AppLogger.

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:logger/logger.dart';

class AppLogger {
  AppLogger._();

  static final Logger _log = Logger(
    level: kReleaseMode ? Level.warning : Level.trace,
    printer: kReleaseMode
        ? SimplePrinter(colors: false, printTime: true)
        : PrettyPrinter(
            methodCount: 2,
            errorMethodCount: 8,
            lineLength: 120,
            colors: true,
            printEmojis: true,
            dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
          ),
    output: ConsoleOutput(),
  );

  /// Verbose trace — fine-grained diagnostic info.
  static void trace(String message, {Object? error, StackTrace? stackTrace}) =>
      _log.t(message, error: error, stackTrace: stackTrace);

  /// Debug-level info useful during development.
  static void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _log.d(message, error: error, stackTrace: stackTrace);

  /// Normal operational messages (feature completed, user action, etc.).
  static void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log.i(message, error: error, stackTrace: stackTrace);

  /// Recoverable unexpected states — investigate but not critical.
  static void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _log.w(message, error: error, stackTrace: stackTrace);

  /// Errors that impair a feature; should be captured by ErrorService.
  static void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _log.e(message, error: error, stackTrace: stackTrace);

  /// Fatal / unrecoverable — app cannot continue.
  static void fatal(String message, {Object? error, StackTrace? stackTrace}) =>
      _log.f(message, error: error, stackTrace: stackTrace);
}
