import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FirebasePerformance _performance = FirebasePerformance.instance;

  // ============================================
  // USER TRACKING
  // ============================================

  /// Set user properties when they log in
  static Future<void> setUser(
    String userId, {
    String? email,
    String? company,
    String? role,
    String? displayName,
  }) async {
    try {
      await _analytics.setUserId(id: userId);

      if (email != null) {
        await _analytics.setUserProperty(name: 'email', value: email);
      }

      if (company != null) {
        await _analytics.setUserProperty(name: 'company', value: company);
      }

      if (role != null) {
        await _analytics.setUserProperty(name: 'role', value: role);
      }

      if (displayName != null) {
        await _analytics.setUserProperty(name: 'display_name', value: displayName);
      }

      AppLogger.info('✅ Analytics: User set - $userId');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error setting user - $e');
    }
  }

  /// Clear user data on logout
  static Future<void> clearUser() async {
    try {
      await _analytics.setUserId(id: null);
      AppLogger.info('✅ Analytics: User cleared');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error clearing user - $e');
    }
  }

  // ============================================
  // AUTHENTICATION EVENTS
  // ============================================

  static Future<void> logSignIn(String method) async {
    try {
      await _analytics.logLogin(loginMethod: method);
      AppLogger.info('✅ Analytics: Sign in logged - $method');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging sign in - $e');
    }
  }

  static Future<void> logSignUp(String method) async {
    try {
      await _analytics.logSignUp(signUpMethod: method);
      AppLogger.info('✅ Analytics: Sign up logged - $method');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging sign up - $e');
    }
  }

  static Future<void> logSignOut() async {
    try {
      await _analytics.logEvent(name: 'sign_out');
      AppLogger.info('✅ Analytics: Sign out logged');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging sign out - $e');
    }
  }

  // ============================================
  // INSPECTION EVENTS
  // ============================================

  static Future<void> logInspectionCreated({
    required String userId,
    required String inspectionId,
    required String inspectionType,
    String? templateId,
    String? templateName,
    String? workspaceId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'inspection_created',
        parameters: {
          'user_id': userId,
          'inspection_id': inspectionId,
          'inspection_type': inspectionType,
          if (templateId != null) 'template_id': templateId,
          if (templateName != null) 'template_name': templateName,
          if (workspaceId != null) 'workspace_id': workspaceId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Inspection created - $inspectionType');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging inspection creation - $e');
    }
  }

  static Future<void> logInspectionUpdated({
    required String userId,
    required String inspectionId,
    required String inspectionType,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'inspection_updated',
        parameters: {
          'user_id': userId,
          'inspection_id': inspectionId,
          'inspection_type': inspectionType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging inspection update - $e');
    }
  }

  static Future<void> logInspectionDeleted({
    required String userId,
    required String inspectionId,
    required String inspectionType,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'inspection_deleted',
        parameters: {
          'user_id': userId,
          'inspection_id': inspectionId,
          'inspection_type': inspectionType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Inspection deleted - $inspectionId');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging inspection deletion - $e');
    }
  }

  // ============================================
  // PDF GENERATION EVENTS
  // ============================================

  /// Track PDF generation with performance metrics
  static Future<void> trackPDFGeneration({
    required String reportId,
    required String userId,
    required String inspectionType,
    required Future<void> Function() pdfGenerationFunction,
  }) async {
    final trace = _performance.newTrace('pdf_generation');
    await trace.start();

    final startTime = DateTime.now();

    try {
      // Execute PDF generation
      await pdfGenerationFunction();

      final duration = DateTime.now().difference(startTime);

      // Stop performance trace
      trace.setMetric('duration_ms', duration.inMilliseconds);
      await trace.stop();

      // Log analytics event
      await _analytics.logEvent(
        name: 'pdf_generated',
        parameters: {
          'report_id': reportId,
          'user_id': userId,
          'inspection_type': inspectionType,
          'duration_ms': duration.inMilliseconds,
          'success': 1,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      AppLogger.info('✅ Analytics: PDF generated in ${duration.inMilliseconds}ms');
    } catch (e) {
      await trace.stop();

      // Log failure
      await _analytics.logEvent(
        name: 'pdf_generation_failed',
        parameters: {
          'report_id': reportId,
          'user_id': userId,
          'inspection_type': inspectionType,
          'error': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      AppLogger.error('❌ Analytics: PDF generation failed - $e');
      rethrow;
    }
  }

  /// Generic event logging
static Future<void> logEvent({
  required String name,
  Map<String, dynamic>? parameters,
}) async {
  try {
    await _analytics.logEvent(
      name: name,
      parameters: parameters?.cast<String, Object>(),
    );
    AppLogger.info('✅ Analytics: Event logged - $name');
  } catch (e) {
    AppLogger.error('❌ Analytics: Error logging event - $e');
  }
}

  // ============================================
  // PHOTO UPLOAD EVENTS
  // ============================================

  static Future<void> logPhotoUploaded({
    required String userId,
    required String reportId,
    required int photoCount,
    double? fileSizeMB,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'photo_uploaded',
        parameters: {
          'user_id': userId,
          'report_id': reportId,
          'photo_count': photoCount,
          if (fileSizeMB != null) 'file_size_mb': fileSizeMB,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Photo uploaded - $photoCount photo(s)');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging photo upload - $e');
    }
  }

  static Future<void> logPhotoDeleted({
    required String userId,
    required String reportId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'photo_deleted',
        parameters: {
          'user_id': userId,
          'report_id': reportId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging photo deletion - $e');
    }
  }

  // ============================================
  // TEMPLATE EVENTS
  // ============================================

  static Future<void> logTemplateUsed({
    required String userId,
    required String templateId,
    required String templateName,
    required String inspectionType,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'template_used',
        parameters: {
          'user_id': userId,
          'template_id': templateId,
          'template_name': templateName,
          'inspection_type': inspectionType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Template used - $templateName');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging template usage - $e');
    }
  }

  static Future<void> logTemplateUploaded({
    required String userId,
    required String templateName,
    required String fileType, // 'excel', 'pdf', etc.
  }) async {
    try {
      await _analytics.logEvent(
        name: 'template_uploaded',
        parameters: {
          'user_id': userId,
          'template_name': templateName,
          'file_type': fileType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Template uploaded - $templateName');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging template upload - $e');
    }
  }

  // ============================================
  // WORKSPACE EVENTS
  // ============================================

  static Future<void> logWorkspaceCreated({
    required String userId,
    required String workspaceId,
    required String workspaceName,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'workspace_created',
        parameters: {
          'user_id': userId,
          'workspace_id': workspaceId,
          'workspace_name': workspaceName,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Workspace created - $workspaceName');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging workspace creation - $e');
    }
  }

  static Future<void> logWorkspaceSwitched({
    required String userId,
    required String workspaceId,
    required String workspaceName,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'workspace_switched',
        parameters: {
          'user_id': userId,
          'workspace_id': workspaceId,
          'workspace_name': workspaceName,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging workspace switch - $e');
    }
  }

  static Future<void> logMemberInvited({
    required String userId,
    required String workspaceId,
    required String inviteeEmail,
    required String role,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'member_invited',
        parameters: {
          'user_id': userId,
          'workspace_id': workspaceId,
          'invitee_email': inviteeEmail,
          'role': role,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Member invited - $inviteeEmail');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging member invitation - $e');
    }
  }

  // ============================================
  // SYNC EVENTS
  // ============================================

  static Future<void> logOfflineSync({
    required String userId,
    required int reportsCount,
    bool success = true,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'offline_sync',
        parameters: {
          'user_id': userId,
          'reports_count': reportsCount,
          'success': success,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      AppLogger.info('✅ Analytics: Offline sync - $reportsCount report(s)');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging offline sync - $e');
    }
  }

  // ============================================
  // MATERIALS EVENTS
  // ============================================

  static Future<void> logMaterialAdded({
    required String userId,
    required String materialType, // 'base_metal', 'filler_metal', 'consumable'
    required String materialName,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'material_added',
        parameters: {
          'user_id': userId,
          'material_type': materialType,
          'material_name': materialName,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging material addition - $e');
    }
  }

  // ============================================
  // SCREEN VIEW TRACKING
  // ============================================

  static Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
      AppLogger.info('✅ Analytics: Screen view - $screenName');
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging screen view - $e');
    }
  }

  // ============================================
  // PERFORMANCE TRACKING
  // ============================================

  /// Generic performance tracker for any operation
  static Future<T> trackPerformance<T>({
    required String traceName,
    required Future<T> Function() operation,
    Map<String, int>? metrics,
  }) async {
    final trace = _performance.newTrace(traceName);
    await trace.start();

    try {
      final result = await operation();

      if (metrics != null) {
        metrics.forEach((key, value) {
          trace.setMetric(key, value);
        });
      }

      await trace.stop();
      return result;
    } catch (e) {
      await trace.stop();
      rethrow;
    }
  }

  // ============================================
  // ERROR TRACKING
  // ============================================

  static Future<void> logError({
    required String errorType,
    required String errorMessage,
    String? stackTrace,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'error_occurred',
        parameters: {
          'error_type': errorType,
          'error_message': errorMessage,
          if (stackTrace != null) 'stack_trace': stackTrace.substring(0, 100),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging error - $e');
    }
  }

  // ============================================
  // FEATURE USAGE
  // ============================================

  static Future<void> logFeatureUsed({
    required String featureName,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'feature_used',
        parameters: {
          'feature_name': featureName,
          'timestamp': DateTime.now().toIso8601String(),
          ...?additionalParams,
        },
      );
    } catch (e) {
      AppLogger.error('❌ Analytics: Error logging feature usage - $e');
    }
  }
}