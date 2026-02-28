import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// Writes immutable audit entries to /users/{uid}/audit_log/{id}.
///
/// Firestore rules: create = owner; update/delete = false.
/// Once written an audit entry cannot be modified or deleted from the client.
class AuditLogService {
  static final AuditLogService _i = AuditLogService._();
  AuditLogService._();
  factory AuditLogService() => _i;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Action constants ───────────────────────────────────────────────────────
  static const String actionCreate = 'create';
  static const String actionUpdate = 'update';
  static const String actionLock   = 'lock';
  static const String actionDelete = 'delete';
  static const String actionExport = 'export';

  // ── Entity type constants ──────────────────────────────────────────────────
  static const String entityReport   = 'report';
  static const String entityProject  = 'project';
  static const String entityTemplate = 'template';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Record an audit event. Silently swallows errors — audit logging must never
  /// block the primary operation that triggered it.
  Future<void> log({
    required String userId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final actorUid = FirebaseAuth.instance.currentUser?.uid ?? userId;
      final actorEmail = FirebaseAuth.instance.currentUser?.email;

      await _db
          .collection('users')
          .doc(userId)
          .collection('audit_log')
          .add({
        'action':     action,
        'entityType': entityType,
        'entityId':   entityId,
        'actorUid':   actorUid,
        'actorEmail': actorEmail,
        'metadata':   metadata,
        'timestamp':  FieldValue.serverTimestamp(),
      });

      AppLogger.debug(
          '📋 Audit: $action $entityType $entityId by $actorEmail');
    } catch (e) {
      // Never rethrow — audit log failure must not interrupt the primary flow.
      AppLogger.warning('⚠️ Audit log failed for $action $entityType $entityId: $e');
    }
  }

  // ── Convenience wrappers ───────────────────────────────────────────────────

  Future<void> logReportCreate(String userId, String reportId,
      {String? schemaId, String? projectId}) =>
      log(
        userId: userId,
        action: actionCreate,
        entityType: entityReport,
        entityId: reportId,
        metadata: {
          if (schemaId  != null) 'schemaId':  schemaId,
          if (projectId != null) 'projectId': projectId,
        },
      );

  Future<void> logReportUpdate(String userId, String reportId,
      {String? schemaId}) =>
      log(
        userId: userId,
        action: actionUpdate,
        entityType: entityReport,
        entityId: reportId,
        metadata: {if (schemaId != null) 'schemaId': schemaId},
      );

  Future<void> logReportLock(String userId, String reportId,
      {String? schemaId}) =>
      log(
        userId: userId,
        action: actionLock,
        entityType: entityReport,
        entityId: reportId,
        metadata: {if (schemaId != null) 'schemaId': schemaId},
      );

  Future<void> logReportDelete(String userId, String reportId,
      {String? schemaId}) =>
      log(
        userId: userId,
        action: actionDelete,
        entityType: entityReport,
        entityId: reportId,
        metadata: {if (schemaId != null) 'schemaId': schemaId},
      );

  Future<void> logExport(String userId, String reportId,
      {String? format, String? schemaId}) =>
      log(
        userId: userId,
        action: actionExport,
        entityType: entityReport,
        entityId: reportId,
        metadata: {
          if (format   != null) 'format':   format,
          if (schemaId != null) 'schemaId': schemaId,
        },
      );

  // ── Read (for future audit viewer screen) ─────────────────────────────────

  /// Stream the most recent [limit] audit entries for a user, newest first.
  Stream<List<Map<String, dynamic>>> watchAuditLog(
    String userId, {
    int limit = 50,
    String? entityType,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .doc(userId)
        .collection('audit_log')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (entityType != null) {
      q = q.where('entityType', isEqualTo: entityType);
    }

    return q.snapshots().map(
      (snap) => snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList(),
    );
  }
}
