import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/core/services/error_service.dart';

/// Repository for /users/{uid}/projects/{projectId} documents.
///
/// Firestore schema:
///   name         String  — project display name
///   clientName   String  — client / company name
///   location     String  — job-site location
///   type         String  — 'pipeline'|'structural'|'pressure_vessel'|'offshore'|'other'
///   status       String  — 'open' | 'closed'
///   startDate    String  — ISO date string (yyyy-MM-dd)
///   endDate      String? — ISO date string (null while project is open)
///   reportCount  int     — denormalised count for fast list rendering
///   createdAt    Timestamp
///   updatedAt    Timestamp
class ProjectRepository {
  static final ProjectRepository _i = ProjectRepository._();
  ProjectRepository._();
  factory ProjectRepository() => _i;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('projects');

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Live stream of all projects for [userId], optionally filtered by [status]
  /// ('open' | 'closed'). Orders by updatedAt descending.
  Stream<List<Map<String, dynamic>>> listProjectsStream(
    String userId, {
    String? status,
  }) {
    // Single-field orderBy only — no composite index needed.
    // Status filter is applied client-side (users have O(10–100) projects).
    return _col(userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) {
      final all = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
      if (status == null) return all;
      return all.where((p) => p['status'] == status).toList();
    });
  }

  // ---------------------------------------------------------------------------
  // One-shot reads
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listProjects(
    String userId, {
    String? status,
  }) async {
    try {
      // Single-field orderBy only — client-side status filter (no composite index).
      final snap = await _col(userId).orderBy('updatedAt', descending: true).get();
      final all = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
      if (status == null) return all;
      return all.where((p) => p['status'] == status).toList();
    } catch (e, st) {
      AppLogger.error('❌ Failed to list projects', error: e, stackTrace: st);
      await ErrorService.captureException(e,
          stackTrace: st, context: 'ProjectRepository.listProjects');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getProject(
    String userId,
    String projectId,
  ) async {
    try {
      final doc = await _col(userId).doc(projectId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return data;
    } catch (e, st) {
      AppLogger.error('❌ Failed to get project', error: e, stackTrace: st);
      await ErrorService.captureException(e,
          stackTrace: st, context: 'ProjectRepository.getProject');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a new project document. Returns the new [projectId].
  Future<String> createProject(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      final now = FieldValue.serverTimestamp();
      final doc = await _col(userId).add({
        'name': data['name'] ?? '',
        'clientName': data['clientName'] ?? '',
        'location': data['location'] ?? '',
        'type': data['type'] ?? 'other',
        'status': data['status'] ?? 'open',
        'startDate': data['startDate'] ?? '',
        'endDate': data['endDate'],
        'reportCount': 0,
        'createdAt': now,
        'updatedAt': now,
      });
      AppLogger.info('✅ Project created: ${doc.id}');
      return doc.id;
    } catch (e, st) {
      AppLogger.error('❌ Failed to create project', error: e, stackTrace: st);
      await ErrorService.captureException(e,
          stackTrace: st, context: 'ProjectRepository.createProject');
      rethrow;
    }
  }

  /// Partial merge update of a project document.
  Future<void> updateProject(
    String userId,
    String projectId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _col(userId).doc(projectId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.info('✅ Project updated: $projectId');
    } catch (e, st) {
      AppLogger.error('❌ Failed to update project', error: e, stackTrace: st);
      await ErrorService.captureException(e,
          stackTrace: st, context: 'ProjectRepository.updateProject');
      rethrow;
    }
  }

  /// Marks a project as closed (sets status + endDate).
  Future<void> closeProject(String userId, String projectId) async {
    await updateProject(userId, projectId, {
      'status': 'closed',
      'endDate': DateTime.now().toIso8601String().substring(0, 10),
    });
  }

  /// Atomically increments the denormalised [reportCount] field.
  ///
  /// Silently swallows errors — a missing/deleted project document should
  /// never block the report save that triggered the increment.
  Future<void> incrementReportCount(String userId, String projectId) async {
    try {
      await _col(userId).doc(projectId).update({
        'reportCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppLogger.debug('✅ Project $projectId reportCount incremented');
    } catch (e) {
      AppLogger.warning('⚠️ Could not increment reportCount for project $projectId: $e');
    }
  }

  /// Permanently deletes a project document.
  Future<void> deleteProject(String userId, String projectId) async {
    try {
      await _col(userId).doc(projectId).delete();
      AppLogger.info('✅ Project deleted: $projectId');
    } catch (e, st) {
      AppLogger.error('❌ Failed to delete project', error: e, stackTrace: st);
      await ErrorService.captureException(e,
          stackTrace: st, context: 'ProjectRepository.deleteProject');
      rethrow;
    }
  }
}
