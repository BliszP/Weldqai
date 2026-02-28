// lib/core/repositories/report_repository.dart
// ignore_for_file: no_leading_underscores_for_local_identifiers, unused_element

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';  // ✅ ADD THIS LINE
import 'package:weldqai_app/core/repositories/project_repository.dart';
import 'package:weldqai_app/core/services/analytics_service.dart';
import 'package:weldqai_app/core/services/audit_log_service.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// ReportRepository (user-scoped)
/// - Primary scope:   /users/{userId}/reports/{schemaId}/items/{autoId}
/// - Rollups:         /users/{userId}/stats/*
/// - Aux feeds:       /users/{userId}/activity | alerts | queue
/// - Optional legacy dual-write (kept while migrating): /projects/{id}/...
class ReportRepository {
  ReportRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SubscriptionService? subscriptionService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _subscriptionService = subscriptionService ?? SubscriptionService();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final SubscriptionService _subscriptionService;

  /// Set true ONLY if you still need to mirror writes to `/projects/{userId}` during migration.
  static const bool _dualWriteLegacy = false;

  // ---------------------------------------------------------------------------
  // Root helpers
  // ---------------------------------------------------------------------------

  /// Primary: users/{userId}
  DocumentReference<Map<String, dynamic>> _userRoot(String userId) =>
      _db.collection('users').doc(_requireUid(userId));

  /// Legacy: projects/{projectIdCompat} (using userId as the doc id)
  DocumentReference<Map<String, dynamic>> _legacyRoot(String id) =>
      _db.collection('projects').doc(_requireUid(id));

  /// Return the set of roots to write to (primary + optional legacy).
  Iterable<DocumentReference<Map<String, dynamic>>> _roots(String userId) sync* {
    final uid = _requireUid(userId);
    yield _userRoot(uid);
    if (_dualWriteLegacy) yield _legacyRoot(uid);
  }

  String _requireUid(String? uid) {
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Missing userId. Ensure the user is signed in and a valid userId is provided.');
    }
    return uid;
  }

  // ===========================================================================
  // Public writes
  // ===========================================================================

  /// Create or update a single report item (user-scoped).
  Future<String> saveReport({
    required String userId,
    required String schemaId,
    required Map<String, dynamic> payload,
    String? reportId,
    bool skipSubscriptionCheck = false,  // ✅ NEW: Bypass subscription if true
  }) async {
    final uid = _requireUid(userId);
    final col = _itemsCol(uid, schemaId);

      // ✅ ADD THIS CHECK BEFORE "If updating, load previous"
  // ✅ CHECK SUBSCRIPTION (unless skipSubscriptionCheck = true)
final isNewReport = reportId == null || reportId.isEmpty;

if (isNewReport && !skipSubscriptionCheck) {  // ✅ ADDED && !skipSubscriptionCheck
  final checkResult = await _subscriptionService.canCreateReport();
  
  if (!checkResult.allowed) {
    throw Exception(checkResult.blockReason ?? 'Cannot create report');
  }
}
  // ✅ END OF NEW CODE

    // If updating, load previous for delta rollups
    Map<String, dynamic>? oldDoc;
    final isUpdate = reportId != null && reportId.isNotEmpty;
    if (isUpdate) {
      final prev = await col.doc(reportId).get();
      if (prev.exists) {
        final data = prev.data() ?? <String, dynamic>{};
        oldDoc = {'id': prev.id, ...data};
      }
    }

    final status = _deriveStatus(schemaId, payload); // accept/reject/pending/open/closed
    final nowTs = FieldValue.serverTimestamp();
    final nowIso = _isoNow();

    final body = <String, dynamic>{
      'userId': uid,
      'schemaId': schemaId,
      'status': status,
      'payload': Map<String, dynamic>.from(payload),
      'updatedAt': nowTs,
      'updatedBy': _auth.currentUser?.uid,
      'updatedAtText': nowIso,
    };

    late String id;
    if (isUpdate) {
      id = reportId;
      await col.doc(id).set(body, SetOptions(merge: true));
    } else {
      final doc = await col.add({
        ...body,
        'createdAt': nowTs,
        'createdAtText': nowIso,
        'createdBy': _auth.currentUser?.uid,
      });
      id = doc.id;
    }

    // Rollups (delta-aware) — user scope + optional legacy
    await _applyRollups(
      userId: uid,
      schemaId: schemaId,
      oldItem: oldDoc,
      newItem: {'id': id, ...body},
    );

     // ✅ ADD ANALYTICS TRACKING HERE
  if (isUpdate) {
    await AnalyticsService.logInspectionUpdated(
      userId: uid,
      inspectionId: id,
      inspectionType: schemaId,
    );
  } else {
    await AnalyticsService.logInspectionCreated(
      userId: uid,
      inspectionId: id,
      inspectionType: schemaId,
      templateId: payload['templateId']?.toString(),
      templateName: payload['reportTypeLabel']?.toString(),
    );
  }

    // Auxiliary collections (activity / alerts / queue) — user scope + optional legacy
    await _writeActivity(
      userId: uid,
      schemaId: schemaId,
      reportId: id,
      action: isUpdate ? 'updated' : 'created',
      status: status,
    );

    await _maybeWriteAlert(
      userId: uid,
      schemaId: schemaId,
      reportId: id,
      status: status,
      payload: payload,
    );

    await _maybeWriteQueue(
      userId: uid,
      schemaId: schemaId,
      reportId: id,
      status: status,
      payload: payload,
    );

    // If resolved (accept/yes/no/closed/complete), clear activity rows for this report
    if (_isResolvedStatus(status)) {
      await _deleteActivityForReport(
        userId: uid,
        schemaId: schemaId,
        reportId: id,
      );
    }

  // ✅ TRACK REPORT CREATION (unless skipSubscriptionCheck = true)
if (isNewReport && !skipSubscriptionCheck) {  // ✅ ADDED && !skipSubscriptionCheck
  await _subscriptionService.trackReportCreation();
}

    // Increment denormalised reportCount on the linked project (fire-and-forget;
    // errors are swallowed inside incrementReportCount so they never block saves).
    if (isNewReport) {
      final projectId = payload['projectId'] as String?;
      if (projectId != null && projectId.isNotEmpty) {
        await ProjectRepository().incrementReportCount(uid, projectId);
      }
    }

    // Audit log (fire-and-forget — never blocks the save).
    if (isNewReport) {
      await AuditLogService().logReportCreate(uid, id,
          schemaId: schemaId,
          projectId: payload['projectId'] as String?);
    } else {
      await AuditLogService().logReportUpdate(uid, id, schemaId: schemaId);
    }

    return id;
  }

  // ---------------------------------------------------------------------------
  // Report lock
  // ---------------------------------------------------------------------------

  /// Marks a report as submitted/locked. Once locked, Firestore rules prevent
  /// further updates from the client. The lock is also recorded in the audit log.
  ///
  /// Pass [certNumber] and [certBody] to stamp the inspector's credential on
  /// the report document (used by export_service when generating PDFs).
  Future<void> lockReport({
    required String userId,
    required String schemaId,
    required String reportId,
    String? certNumber,
    String? certBody,
  }) async {
    final uid = _requireUid(userId);
    final ref = _itemsCol(uid, schemaId).doc(reportId);

    await ref.update({
      'lockedAt':    FieldValue.serverTimestamp(),
      'lockedBy':    _auth.currentUser?.uid,
      'lockedByEmail': _auth.currentUser?.email,
      'reportStatus': 'submitted',
      if (certNumber != null && certNumber.isNotEmpty) 'certNumber': certNumber,
      if (certBody   != null && certBody.isNotEmpty)   'certBody':   certBody,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    AppLogger.info('🔒 Report locked: $reportId (schema: $schemaId)');

    await AuditLogService().logReportLock(uid, reportId, schemaId: schemaId);
  }

/// Delete one saved item (and clean up rollups + photos + signatures + aux collections).
Future<void> deleteItem({
  required String userId,
  required String schemaId,
  required String itemId,
}) async {
  final uid = _requireUid(userId);
  final ref = _itemsCol(uid, schemaId).doc(itemId);
  final snap = await ref.get();
  final oldDoc = snap.exists ? {'id': snap.id, ...?snap.data()} : null;

  // 1. Delete photos from Firebase Storage
  await _deleteAllPhotos(userId: uid, schemaId: schemaId, reportId: itemId);

  // 2. Delete signature images from Firebase Storage
  await _deleteAllSignatures(userId: uid, schemaId: schemaId, reportId: itemId);

  // 3. Delete the report document from Firestore
  await ref.delete();

  // 4. Rollups (subtract old)
  await _applyRollups(
    userId: uid,
    schemaId: schemaId,
    oldItem: oldDoc,
    newItem: null,
  );

  // 5. Remove aux docs for this report (alerts/queue/activity)
  await _deleteAuxForReport(
    userId: uid,
    schemaId: schemaId,
    reportId: itemId,
  );

  // 6. Audit log (fire-and-forget).
  await AuditLogService().logReportDelete(uid, itemId, schemaId: schemaId);
}

/// Delete all photos for a report from Firebase Storage
Future<void> _deleteAllPhotos({
  required String userId,
  required String schemaId,
  required String reportId,
}) async {
  try {
    final path = 'reports/$userId/$schemaId/$reportId';
    final ref = FirebaseStorage.instance.ref(path);
    
    // List all files in the report's photo directory
    final result = await ref.listAll();
    
    // Delete each photo
    for (final item in result.items) {
      try {
        await item.delete();
        AppLogger.debug('Deleted photo: ${item.fullPath}');
      } catch (e) {
        AppLogger.debug('Failed to delete photo ${item.fullPath}: $e');
      }
    }
    
    AppLogger.info('✅ Deleted ${result.items.length} photos for report $reportId');
  } catch (e) {
    AppLogger.warning('⚠️ Error deleting photos: $e');
    // Continue with deletion even if photo cleanup fails
  }
}

/// Delete all signature images for a report from Firebase Storage
Future<void> _deleteAllSignatures({
  required String userId,
  required String schemaId,
  required String reportId,
}) async {
  try {
    // Delete contractor signature
    try {
      final contractorRef = FirebaseStorage.instance
          .ref('reports/$userId/$schemaId/$reportId/contractor_sig.png');
      await contractorRef.delete();
      AppLogger.debug('Deleted contractor signature');
    } catch (_) {
      // File might not exist
    }
    
    // Delete client signature
    try {
      final clientRef = FirebaseStorage.instance
          .ref('reports/$userId/$schemaId/$reportId/client_sig.png');
      await clientRef.delete();
      AppLogger.debug('Deleted client signature');
    } catch (_) {
      // File might not exist
    }
    
    AppLogger.info('✅ Deleted signatures for report $reportId');
  } catch (e) {
    AppLogger.warning('⚠️ Error deleting signatures: $e');
    // Continue with deletion even if signature cleanup fails
  }
}

// Add this import at the top of report_repository.dart if not already there:
// import 'package:firebase_storage/firebase_storage.dart';
  // ===========================================================================
  // Reads (used by forms / exports)
  // ===========================================================================

  /// Latest saved item for a schema (by createdAt desc; tolerant fallback).
  Future<Map<String, dynamic>?> loadLatestItem({
    required String userId,
    required String schemaId,
  }) async {
    final uid = _requireUid(userId);
    final col = _itemsCol(uid, schemaId);
    QuerySnapshot<Map<String, dynamic>> q;
    try {
      q = await col.orderBy('createdAt', descending: true).limit(1).get();
    } catch (_) {
      q = await col.limit(1).get();
    }
    if (q.docs.isEmpty) return null;
    final d = q.docs.first;
    return {'id': d.id, ...d.data()};
  }

  /// List recent items (newest first).
  Future<List<Map<String, dynamic>>> listItems({
    required String userId,
    required String schemaId,
    int limit = 50,
  }) async {
    final uid = _requireUid(userId);
    final col = _itemsCol(uid, schemaId);
    QuerySnapshot<Map<String, dynamic>> q;
    try {
      q = await col.orderBy('createdAt', descending: true).limit(limit).get();
    } catch (_) {
      q = await col.limit(limit).get();
    }
    return q.docs.map((d) => {'id': d.id, ...d.data()}).toList(growable: false);
  }

  // ===========================================================================
  // Live streams (opt-in for UIs that want instant updates)
  // ===========================================================================

  /// Stream a single report document.
  Stream<Map<String, dynamic>?> watchItem({
    required String userId,
    required String schemaId,
    required String itemId,
  }) {
    final uid = _requireUid(userId);
    return _itemsCol(uid, schemaId)
        .doc(itemId)
        .snapshots(includeMetadataChanges: true)
        .map((d) => d.exists ? {'id': d.id, ...?d.data()} : null);
  }

  /// Stream recent items for a schema (ordered newest first).
  Stream<List<Map<String, dynamic>>> watchItems({
    required String userId,
    required String schemaId,
    int limit = 50,
  }) {
    final uid = _requireUid(userId);
    final q = _itemsCol(uid, schemaId)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    return q.snapshots(includeMetadataChanges: true).map((snap) {
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(growable: false);
    });
  }

  /// Stream just the current status for a report item.
  Stream<String?> watchStatus({
    required String userId,
    required String schemaId,
    required String itemId,
  }) {
    final uid = _requireUid(userId);
    return _itemsCol(uid, schemaId)
        .doc(itemId)
        .snapshots(includeMetadataChanges: true)
        .map((d) => d.data()?['status']?.toString());
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  CollectionReference<Map<String, dynamic>> _itemsCol(
    String userId,
    String schemaId,
  ) =>
      _userRoot(userId)
          .collection('reports')
          .doc(schemaId)
          .collection('items');

  String _yyyyMmDd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  num _n(dynamic v) => (v is num) ? v : (num.tryParse('$v') ?? 0);

  String _isoNow() => DateTime.now().toIso8601String();

  Map<String, dynamic> _detailsOf(Map<String, dynamic>? item) {
    final payload =
        (item?['payload'] is Map) ? Map<String, dynamic>.from(item!['payload']) : const {};
    return (payload['details'] is Map)
        ? Map<String, dynamic>.from(payload['details'])
        : const {};
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic>? item) {
    final payload =
        (item?['payload'] is Map) ? Map<String, dynamic>.from(item!['payload']) : const {};
    final raw = payload['rows'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  // --- normalized status detection (supports Yes/No/OK/Pass/Accept/Reject/Fail/etc.)
  bool _isRejectWord(String v) {
    final s = v.trim().toLowerCase();
    return s == 'reject' ||
        s == 'rejected' ||
        s == 'fail' ||
        s == 'failed' ||
        s == 'repair' ||
        s == 'rework' ||
        s == 'recoat' ||
        s == 'hold';
      
    // NOTE: deliberately NOT treating "no" as reject.
  }

  bool _isAcceptWord(String v) {
    final s = v.trim().toLowerCase();
    return s == 'accept' ||
        s == 'accepted' ||
        s == 'pass' ||
        s == 'passed' ||
        s == 'ok' ||
        s == 'no' ||  // treat "no" as resolved (do not raise alerts/queue)
        s == 'complete' ||
        s == 'completed';
  }

  bool _isResolvedStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'accept' ||
        s == 'yes' ||
        s == 'no' ||
        s == 'closed' ||
        s == 'complete' ||
        s == 'completed';
  }

  /// Status derivation for fast counts.
  String _deriveStatus(String schemaId, Map<String, dynamic> payload) {
    final sid = schemaId.toLowerCase();
    final details =
        (payload['details'] is Map) ? Map<String, dynamic>.from(payload['details']) : const {};
    final rows = (payload['rows'] is List)
        ? List<Map<String, dynamic>>.from(
            (payload['rows'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : const <Map<String, dynamic>>[];

    bool hasRejectRow() {
      for (final r in rows) {
        final res = (r['result'] ?? r['status'] ?? '').toString();
        if (_isRejectWord(res)) return true;
      }
      return false;
    }

    bool hasAcceptRow() {
      if (rows.isEmpty) return false;
      bool any = false;
      for (final r in rows) {
        final res = (r['result'] ?? r['status'] ?? '').toString();
        if (res.trim().isEmpty) continue;
        any = true;
        if (!_isAcceptWord(res)) return false;
      }
      return any;
    }

    // GLOBAL decision from rows first
    if (hasRejectRow()) return 'reject';
    if (hasAcceptRow()) return 'accept';

    // Additional signals from details
    final detStatus =
        (details['status'] ?? details['overall'] ?? details['conform'] ?? details['ok'] ?? '')
            .toString();
    if (_isRejectWord(detStatus)) return 'reject';
    if (_isAcceptWord(detStatus)) return 'accept';

    // Generic resolved/accept scan across details fields
    bool anyAcceptInDetails = false;
    for (final entry in details.entries) {
      final v = entry.value;
      final asStr = (v ?? '').toString();
      if (_isRejectWord(asStr)) return 'reject';
      if (v is bool) {
        anyAcceptInDetails = true;
        continue;
      }
      if (v is num && (v == 1 || v == 0)) {
        anyAcceptInDetails = true;
        continue;
      }
      final s = asStr.trim().toLowerCase();
      if (s == 'true' || s == 'false' || s == 'y' || s == 'n' || s == '1' || s == '0') {
        anyAcceptInDetails = true;
        continue;
      }
      if (_isAcceptWord(asStr)) {
        anyAcceptInDetails = true;
      }
    }
    if (anyAcceptInDetails) return 'accept';

    // Schema-specific fallbacks
    if (sid.contains('repairs')) {
      final s =
          (details['status'] ?? details['repair_status'] ?? '').toString().trim().toLowerCase();
      if (s == 'closed' || s == 'complete' || s == 'completed') return 'closed';
      return 'open';
    }
    if (sid.startsWith('ndt')) return 'pending';
    if (sid.contains('visual')) return 'pending';
    return 'pending';
  }

  // ===========================================================================
  // Activity / Alerts / Queue (user scope + optional legacy)
  // ===========================================================================

  Future<void> _writeActivity({
    required String userId,
    required String schemaId,
    required String reportId,
    required String action,
    required String status,
  }) async {
    final det = await _readDetailsSafe(userId, schemaId, reportId);
    final nowTs = FieldValue.serverTimestamp();
    final nowText = _isoNow();
    final String activityId = '${schemaId}_$reportId'; // deterministic

    for (final root in _roots(userId)) {
      try {
        await root.collection('activity').doc(activityId).set({
          'schema': schemaId,
          'reportId': reportId,
          'title': det['title'],
          'line1': det['line1'],
          'line2': det['line2'],
          'action': action,
          'reportStatus': status,
          'status': status,
          'actor': _auth.currentUser?.uid,
          'time': nowTs,
          'timeText': nowText,
          'createdAt': nowTs,
          'createdAtText': nowText,
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> _maybeWriteAlert({
    required String userId,
    required String schemaId,
    required String reportId,
    required String status,
    required Map<String, dynamic> payload,
  }) async {
    final alertId = '${schemaId}_$reportId';
    final nowTs = FieldValue.serverTimestamp();
    final nowText = _isoNow();
    final det = _briefFromPayload(schemaId, payload);
    final reason = _extractRejectReason(payload);

    for (final root in _roots(userId)) {
      if (status == 'reject') {
        await root.collection('alerts').doc(alertId).set({
          'schema': schemaId,
          'reportId': reportId,
          'status': 'active', // ✅ NEW: Always start as 'active', user can change manually
          'reportStatus': status, // ✅ NEW: Keep original report status separate
          'title': '${det['title']} — REJECT',
          'subtitle': [
            if ((det['line1'] ?? '').toString().trim().isNotEmpty) det['line1'],
            if (reason.isNotEmpty) reason,
          ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' • '),
          'rejectReason': reason.isNotEmpty ? reason : null,
          'time': nowTs,
          'timeText': nowText,
        }, SetOptions(merge: true));
      } else {
        try {
          await root.collection('alerts').doc(alertId).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _maybeWriteQueue({
    required String userId,
    required String schemaId,
    required String reportId,
    required String status,
    required Map<String, dynamic> payload,
  }) async {
    final qId = '${schemaId}_$reportId';

    if (_isResolvedStatus(status)) {
      for (final root in _roots(userId)) {
        try {
          await root.collection('queue').doc(qId).delete();
        } catch (_) {}
      }
      return;
    }

    final nowTs = FieldValue.serverTimestamp();
    final nowText = _isoNow();
    final det = _briefFromPayload(schemaId, payload);
    final details =
        (payload['details'] is Map) ? Map<String, dynamic>.from(payload['details']) : const <String, dynamic>{};

    final assignedTo = (details['assignedTo'] ?? details['assignee'] ?? '').toString();
    final dueDateString = (details['dueDate'] ?? details['due_date'] ?? '').toString();
    Timestamp? dueTs;
    if (dueDateString.isNotEmpty) {
      final parsed = DateTime.tryParse(dueDateString);
      if (parsed != null) {
        dueTs = Timestamp.fromDate(parsed);
      }
    }

    if (status == 'open' || status == 'pending' || assignedTo.isNotEmpty || dueTs != null) {
      for (final root in _roots(userId)) {
        await root.collection('queue').doc(qId).set({
          'schema': schemaId,
          'reportId': reportId,
          'title': det['title'],
          'line1': det['line1'],
          'line2': det['line2'],
          'reportStatus': status,
          'status': status,
          'assignedTo': assignedTo.isNotEmpty ? assignedTo : null,
          'dueDate': dueTs,
          'createdAt': nowTs,
          'createdAtText': nowText,
          'time': nowTs,
          'timeText': nowText,
        }, SetOptions(merge: true));
      }
    } else {
      for (final root in _roots(userId)) {
        try {
          await root.collection('queue').doc(qId).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _deleteActivityForReport({
    required String userId,
    required String schemaId,
    required String reportId,
  }) async {
    final deterministicId = '${schemaId}_$reportId';
    for (final root in _roots(userId)) {
      try {
        await root.collection('activity').doc(deterministicId).delete();
        continue;
      } catch (_) {}
      try {
        final q = await root
            .collection('activity')
            .where('schema', isEqualTo: schemaId)
            .where('reportId', isEqualTo: reportId)
            .get();
        final batch = _db.batch();
        for (final d in q.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      } catch (_) {}
    }
  }

  Future<void> _deleteAuxForReport({
    required String userId,
    required String schemaId,
    required String reportId,
  }) async {
    for (final root in _roots(userId)) {
      try {
        await root.collection('alerts').doc('${schemaId}_$reportId').delete();
      } catch (_) {}
      try {
        await root.collection('queue').doc('${schemaId}_$reportId').delete();
      } catch (_) {}
      await _deleteActivityForReport(
        userId: userId,
        schemaId: schemaId,
        reportId: reportId,
      );
    }
  }

  Map<String, String> _briefFromPayload(String schemaId, Map<String, dynamic> payload) {
    final title = (payload['reportTypeLabel'] ?? payload['reportType'] ?? schemaId).toString();
    final details =
        (payload['details'] is Map) ? Map<String, dynamic>.from(payload['details']) : const <String, dynamic>{};
    final joint = (details['jointId'] ??
            details['joint_id'] ??
            details['weld_no'] ??
            details['weldNo'] ??
            details['serial'] ??
            '')
        .toString();
    final line1 = joint.isNotEmpty ? joint : (details['location'] ?? details['line'] ?? '').toString();
    final line2 =
        (details['document_no'] ?? details['documentNo'] ?? details['inspector'] ?? details['welder'] ?? '')
            .toString();
    return {
      'title': title,
      'line1': line1,
      'line2': line2,
    };
  }

  String _extractRejectReason(Map<String, dynamic> payload) {
    final details =
        (payload['details'] is Map) ? Map<String, dynamic>.from(payload['details']) : const <String, dynamic>{};
    final rows = (payload['rows'] is List)
        ? (payload['rows'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];

    final fromDetails =
        (details['rejectReason'] ?? details['rejection_reason'] ?? details['reason'] ?? details['remarks'] ?? '')
            .toString()
            .trim();
    if (fromDetails.isNotEmpty) return fromDetails;

    for (final r in rows) {
      final v = (r['rejectReason'] ??
              r['rejection_reason'] ??
              r['defect'] ??
              r['defect_code'] ??
              r['remarks'] ??
              r['comment'] ??
              '')
          .toString()
          .trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Future<Map<String, String>> _readDetailsSafe(
      String userId, String schemaId, String reportId) async {
    try {
      final d = await _itemsCol(userId, schemaId).doc(reportId).get();
      if (!d.exists) return {'title': schemaId, 'line1': '', 'line2': ''};
      final m = d.data() ?? <String, dynamic>{};
      final payload = (m['payload'] is Map) ? Map<String, dynamic>.from(m['payload']) : m;
      return _briefFromPayload(schemaId, payload);
    } catch (_) {
      return {'title': schemaId, 'line1': '', 'line2': ''};
    }
  }

  // ===========================================================================
  // Rollups (Delta-aware) -> /users/{userId}/stats/* (+ optional legacy)
  // ===========================================================================

  Future<void> _applyRollups({
    required String userId,
    required String schemaId,
    required Map<String, dynamic>? oldItem,
    required Map<String, dynamic>? newItem,
  }) async {
    // Build all deltas once
    final summaryDelta = _summaryDelta(schemaId, oldItem, newItem);
    final rejectRowsDelta = _rejectRowsDelta(schemaId, oldItem, newItem);
    final weldsDaily = _weldsDailyDelta(schemaId, oldItem, newItem);
    final welder7d = _welder7dDelta(schemaId, oldItem, newItem);
    final inspector7d = _inspector7dDelta(schemaId, oldItem, newItem);
    final defects30d = _defects30dDelta(schemaId, oldItem, newItem);
    final ndtTotals = _ndtPassTotalsDelta(schemaId, oldItem, newItem);
    final repairsSummary = _repairsSummaryDelta(schemaId, oldItem, newItem);
    final repairsMetrics = await _repairsMetricsDelta(schemaId, oldItem, newItem);
    final repairsReasons30d = _repairsReasons30dDelta(schemaId, oldItem, newItem);


    // Apply to each root (users/* and optionally projects/*)
    for (final root in _roots(userId)) {
      final batch = _db.batch();

      // /stats/repairs_reasons_30d
if (repairsReasons30d.isNotEmpty) {
  final ref = root.collection('stats').doc('repairs_reasons_30d');
  batch.set(ref, {
    for (final e in repairsReasons30d.entries)
      e.key: FieldValue.increment(e.value),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
      // /stats/summary
      if (summaryDelta.isNotEmpty || ndtTotals.isNotEmpty || rejectRowsDelta.isNotEmpty) {
        final ref = root.collection('stats').doc('summary');
        batch.set(
          ref,
          {
            for (final e in summaryDelta.entries) e.key: FieldValue.increment(e.value),
            for (final e in ndtTotals.entries) e.key: FieldValue.increment(e.value),
            for (final e in rejectRowsDelta.entries) e.key: FieldValue.increment(e.value),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      // /stats/welds/daily/{yyyy-mm-dd}
      if (weldsDaily.isNotEmpty) {
        for (final e in weldsDaily.entries) {
          final ref = root.collection('stats').doc('welds').collection('daily').doc(e.key);
          batch.set(ref, {
            'day': e.key,
            'count': FieldValue.increment(e.value),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      // /stats/welder_7d
      if (welder7d.isNotEmpty) {
        final ref = root.collection('stats').doc('welder_7d');
        batch.set(ref, {
          for (final e in welder7d.entries) e.key: FieldValue.increment(e.value),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // /stats/inspector_7d
      if (inspector7d.isNotEmpty) {
        final ref = root.collection('stats').doc('inspector_7d');
        batch.set(ref, {
          for (final e in inspector7d.entries) e.key: FieldValue.increment(e.value),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // /stats/defects_30d
      if (defects30d.isNotEmpty) {
        final ref = root.collection('stats').doc('defects_30d');
        batch.set(ref, {
          for (final e in defects30d.entries) e.key: FieldValue.increment(e.value),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // /stats/repairs_summary
      if (repairsSummary.isNotEmpty) {
        final ref = root.collection('stats').doc('repairs_summary');
        batch.set(ref, {
          for (final e in repairsSummary.entries) e.key: FieldValue.increment(e.value),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // /stats/repairs_metrics
      if (repairsMetrics.isNotEmpty) {
        final ref = root.collection('stats').doc('repairs_metrics');
        batch.set(ref, {
          for (final e in repairsMetrics.entries) e.key: FieldValue.increment(e.value),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    }
  }

  // ---- summary delta (openWelds, ndtPending, repairsOpen, completed) ----
  Map<String, int> _summaryDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    final sid = schemaId;
    int _contrib(Map<String, dynamic>? it, String key) {
      if (it == null) return 0;
      final s = (it['status'] ?? '').toString().toLowerCase();

      if (sid == 'welding_operation' && key == 'openWelds') return 1;

      final isNdt = sid.startsWith('ndt_');
      if (isNdt) {
        if (key == 'ndtPending') return s == 'pending' ? 1 : 0;
        if (key == 'completed') return s == 'accept' ? 1 : 0;
      }

      if (sid == 'repairs_log' && key == 'repairsOpen') return s == 'open' ? 1 : 0;

      return 0;
    }

    final m = <String, int>{};
    for (final k in const ['openWelds', 'ndtPending', 'repairsOpen', 'completed']) {
      final delta = _contrib(newItem, k) - _contrib(oldItem, k);
      if (delta != 0) m[k] = delta;
    }
    return m;
  }

  // ---- per-row reject counter (cross-schema) ----
  Map<String, int> _rejectRowsDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    int countRejectedRows(Map<String, dynamic>? it) {
      if (it == null) return 0;
      int c = 0;
      for (final r in _rowsOf(it)) {
        final res = (r['result'] ?? r['status'] ?? '').toString();
        if (_isRejectWord(res)) c++;
      }
      return c;
    }

    final o = countRejectedRows(oldItem);
    final n = countRejectedRows(newItem);
    final delta = n - o;

    if (delta == 0) return const {};
    // Single field in /stats/summary to be picked up by dashboard
    return {'rejectRows': delta};
  }

  // ---- welds daily ----
  Map<String, int> _weldsDailyDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    if (schemaId != 'welding_operation') return const {};
    String dayOf(Map<String, dynamic>? it) {
      final d = _detailsOf(it);
      final s = (d['date'] ?? '').toString();
      if (s.length >= 10) return s.substring(0, 10);
      return _yyyyMmDd(DateTime.now());
    }

    final o = oldItem == null ? null : dayOf(oldItem);
    final n = newItem == null ? null : dayOf(newItem);
    if (o == n) return const {};
    final m = <String, int>{};
    if (o != null) m[o] = (m[o] ?? 0) - 1;
    if (n != null) m[n] = (m[n] ?? 0) + 1;
    return m;
  }

  // ---- welder 7d ----
  Map<String, int> _welder7dDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    if (schemaId != 'welding_operation') return const {};
    String? w(Map<String, dynamic>? it) {
      final d = _detailsOf(it);
      final s = (d['welder'] ?? d['welder_id'] ?? d['welderId'] ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    final o = w(oldItem);
    final n = w(newItem);
    if (o == n) return const {};
    final m = <String, int>{};
    if (o != null) m[o] = (m[o] ?? 0) - 1;
    if (n != null) m[n] = (m[n] ?? 0) + 1;
    return m;
  }

  // ---- inspector 7d ----
  Map<String, int> _inspector7dDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    if (!(schemaId.contains('visual') || schemaId.startsWith('ndt_'))) return const {};
    String? i(Map<String, dynamic>? it) {
      final d = _detailsOf(it);
      final s = (d['inspector'] ?? d['inspector_id'] ?? d['inspectorId'] ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    final o = i(oldItem);
    final n = i(newItem);
    if (o == n) return const {};
    final m = <String, int>{};
    if (o != null) m[o] = (m[o] ?? 0) - 1;
    if (n != null) m[n] = (m[n] ?? 0) + 1;
    return m;
  }

// ---- repairs reasons 30d (from repairs_log.details.reason) ----
Map<String, int> _repairsReasons30dDelta(
  String schemaId,
  Map<String, dynamic>? oldItem,
  Map<String, dynamic>? newItem,
) {
  if (schemaId != 'repairs_log') return const {};

  String? reasonOf(Map<String, dynamic>? it) {
    if (it == null) return null;
    final det = _detailsOf(it);
    // look in common fields
    final r = (det['reason'] ??
               det['repair_reason'] ??
               det['repairReason'] ??
               det['defect'] ??            // allow legacy naming
               det['defect_code'])
        ?.toString()
        .trim();
    if (r == null || r.isEmpty) return null;
    return r;
  }

  final oldR = reasonOf(oldItem);
  final newR = reasonOf(newItem);
  if (oldR == newR) return const {};

  final m = <String, int>{};
  if (oldR != null) m[oldR] = (m[oldR] ?? 0) - 1;
  if (newR != null) m[newR] = (m[newR] ?? 0) + 1;
  return m;
}


  // ---- defects 30d (visual) ----
  Map<String, int> _defects30dDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    if (!schemaId.toLowerCase().contains('visual')) return const {};
    bool rejected(Map<String, dynamic>? it) {
      final rows = _rowsOf(it);
      for (final r in rows) {
        final res = (r['result'] ?? r['status'] ?? '').toString();
        if (_isRejectWord(res)) return true; // do NOT treat "no" as reject
      }
      return false;
    }

    String? code(Map<String, dynamic>? it) {
      final rows = _rowsOf(it);
      for (final r in rows) {
        final c =
            (r['defect'] ?? r['defect_code'] ?? r['defectCode'] ?? r['code'] ?? '').toString().trim();
        if (c.isNotEmpty) return c;
      }
      return null;
    }

    final m = <String, int>{};
    final oRej = rejected(oldItem);
    final nRej = rejected(newItem);
    if (oRej != nRej) m['Reject'] = (m['Reject'] ?? 0) + (nRej ? 1 : -1);

    final oc = code(oldItem);
    final nc = code(newItem);
    if (oc != nc) {
      if (oc != null) m[oc] = (m[oc] ?? 0) - 1;
      if (nc != null) m[nc] = (m[nc] ?? 0) + 1;
    }
    return m;
  }

  // ---- NDT pass/total counters (derive % elsewhere) ----
  Map<String, int> _ndtPassTotalsDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    if (!schemaId.startsWith('ndt_')) return const {};
    int passOf(Map<String, dynamic>? it) {
      if (it == null) return 0;
      int p = 0;
      for (final r in _rowsOf(it)) {
        final res = (r['result'] ?? r['status'] ?? '').toString().toLowerCase();
        if (_isAcceptWord(res)) p++;
      }
      return p;
    }

    int totalOf(Map<String, dynamic>? it) {
      if (it == null) return 0;
      int t = 0;
      for (final r in _rowsOf(it)) {
        final res = (r['result'] ?? r['status'] ?? '').toString().trim();
        if (res.isNotEmpty) t++;
      }
      return t;
    }

    final m = <String, int>{};
    final dp = passOf(newItem) - passOf(oldItem);
    final dt = totalOf(newItem) - totalOf(oldItem);
    if (dp != 0) m['__ndtPassCnt'] = dp;
    if (dt != 0) m['__ndtTotalCnt'] = dt;
    return m;
  }

  // ---- repairs summary open/closed ----
  Map<String, int> _repairsSummaryDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) {
    if (schemaId != 'repairs_log') return const {};
    String st(Map<String, dynamic>? it) => (it?['status'] ?? '').toString().toLowerCase();
    final o = st(oldItem);
    final n = st(newItem);
    if (o == n) return const {};
    final m = <String, int>{};
    if (o == 'open') m['open'] = (m['open'] ?? 0) - 1;
    if (o == 'closed') m['closed'] = (m['closed'] ?? 0) - 1;
    if (n == 'open') m['open'] = (m['open'] ?? 0) + 1;
    if (n == 'closed') m['closed'] = (m['closed'] ?? 0) + 1;
    return m;
  }

  // ---- repairs metrics (sumDaysClosed / closedCountForAvg) ----
  Future<Map<String, int>> _repairsMetricsDelta(
    String schemaId,
    Map<String, dynamic>? oldItem,
    Map<String, dynamic>? newItem,
  ) async {
    if (schemaId != 'repairs_log') return const {};
    String st(Map<String, dynamic>? it) => (it?['status'] ?? '').toString().toLowerCase();

    DateTime? dFrom(Map<String, dynamic>? it, String key) {
      final d = _detailsOf(it);
      final s = (d[key] ?? '').toString().trim();
      if (s.isEmpty) return null;
      try {
        return DateTime.tryParse(s);
      } catch (_) {
        return null;
      }
    }

    int? days(Map<String, dynamic>? it) {
      final opened = dFrom(it, 'date') ?? dFrom(it, 'openedAt') ?? dFrom(it, 'opened_at');
      final closed = dFrom(it, 'closedAt') ?? dFrom(it, 'closed_at');
      if (opened == null || closed == null) return null;
      return closed.difference(opened).inDays.abs();
    }

    final o = st(oldItem);
    final n = st(newItem);
    final m = <String, int>{};

    if (o != 'closed' && n == 'closed') {
      final d = days(newItem);
      if (d != null) m['sumDaysClosed'] = (m['sumDaysClosed'] ?? 0) + d;
      m['closedCountForAvg'] = (m['closedCountForAvg'] ?? 0) + 1;
    } else if (o == 'closed' && n != 'closed') {
      final d = days(oldItem);
      if (d != null) m['sumDaysClosed'] = (m['sumDaysClosed'] ?? 0) - d;
      m['closedCountForAvg'] = (m['closedCountForAvg'] ?? 0) - 1;
    }

    return m;
  }
}
