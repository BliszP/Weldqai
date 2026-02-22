// lib/core/services/error_service.dart
//
// Thin wrapper that delegates to AppLogger AND (in release builds) to Sentry.
// All captured exceptions are logged locally regardless of build mode.
//
// Usage:
//   try {
//     await riskyOp();
//   } catch (e, st) {
//     AppLogger.error('❌ riskyOp failed', error: e, stackTrace: st);
//     await ErrorService.captureException(e, stackTrace: st, context: 'RiskyOp');
//     rethrow;
//   }

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class ErrorService {
  ErrorService._();

  /// Capture a non-fatal exception.
  /// [context] is a short label that appears in the Sentry breadcrumb/issue title.
  static Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? extras,
  }) async {
    AppLogger.error(
      '❌ ${context ?? 'Exception'}: $exception',
      error: exception,
      stackTrace: stackTrace,
    );

    if (!kReleaseMode) return; // Sentry only in release

    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      withScope: (scope) async {
        if (context != null) await scope.setTag('context', context);
        if (extras != null) await scope.setContexts('extras', extras);
      },
    );
  }

  /// Add a navigation / event breadcrumb (no exception captured).
  static Future<void> addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) async {
    AppLogger.debug('[breadcrumb] $message');
    if (!kReleaseMode) return;
    await Sentry.addBreadcrumb(
      Breadcrumb(message: message, category: category ?? 'app', data: data),
    );
  }

  /// Set the authenticated user context for Sentry.
  static Future<void> setUser(String userId, {String? email, String? displayName}) async {
    if (!kReleaseMode) return;
    await Sentry.configureScope((scope) async {
      await scope.setUser(SentryUser(id: userId, email: email, name: displayName));
    });
  }

  /// Clear user context on sign-out.
  static Future<void> clearUser() async {
    if (!kReleaseMode) return;
    await Sentry.configureScope((scope) => scope.setUser(null));
  }
}
