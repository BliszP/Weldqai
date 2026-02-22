// ignore_for_file: unused_local_variable

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/user_data_repository.dart'; // ✅ Changed
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/core/services/error_service.dart';

class SyncService {
  static final SyncService _i = SyncService._();
  SyncService._();
  factory SyncService() => _i;

  bool _configured = false;

  /// Call ONCE at app start, before any Firestore use (very important on Web).
  Future<void> init() async {
    if (_configured) return;
    final sp = await SharedPreferences.getInstance();
    final enable = sp.getBool('prefs.offline') ?? true; // default ON
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: enable,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    _configured = true;
  }

  Future<void> enableOffline(bool enable) async {
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: enable,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('prefs.offline', enable);
  }

  /// Forces fresh reads to hydrate cache + stamps lastSync.
  /// Syncs data for the current authenticated user
  Future<int> syncForCurrentUser() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception('No authenticated user');
    }

    final repo = UserDataRepository(); // ✅ Changed to UserDataRepository
    int count = 0;

    try {
      // Sync reports (force server read to cache)
      count += await _syncReports(userId);
      
      // Sync templates/schemas
      count += await _syncTemplates(userId);
      
      // Sync dashboard data (activity, queue, alerts)
      count += await _syncDashboard(userId);
      
      // Sync profile
      count += await _syncProfile(userId);

      // Save last sync timestamp
      final sp = await SharedPreferences.getInstance();
      await sp.setString('sync.$userId.last', DateTime.now().toIso8601String());

      return count;
    } catch (e, st) {
      AppLogger.error('❌ Sync failed', error: e, stackTrace: st);
      await ErrorService.captureException(e, stackTrace: st, context: 'SyncService.syncForCurrentUser');
      rethrow;
    }
  }

  /// Sync report items for offline use.
  ///
  /// Real report data lives at:
  ///   users/{userId}/reports/{schemaId}/items/{itemId}
  ///
  /// The top-level `users/{userId}/reports` collection contains schema
  /// metadata documents — not report items. We first fetch the schema list,
  /// then hydrate the `items` subcollection for each schema.
  Future<int> _syncReports(String userId) async {
    try {
      // Step 1: enumerate schemas (the parent docs, not the items themselves).
      final schemasSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('reports')
          .get(const GetOptions(source: Source.server));

      int count = 0;

      // Step 2: for each schema, hydrate its items into the local cache.
      for (final schemaDoc in schemasSnap.docs) {
        final itemsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('reports')
            .doc(schemaDoc.id)
            .collection('items')
            .orderBy('updatedAt', descending: true)
            .limit(100)
            .get(const GetOptions(source: Source.server));
        count += itemsSnap.docs.length;
      }

      AppLogger.info('✅ Synced $count report items '
          'across ${schemasSnap.docs.length} schemas');
      return count;
    } catch (e) {
      AppLogger.error('❌ Failed to sync reports: $e');
      return 0;
    }
  }

  /// Sync templates/schemas for offline use.
  /// Custom schemas live at users/{userId}/custom_schemas/{schemaId}.
  Future<int> _syncTemplates(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('custom_schemas')
          .get(const GetOptions(source: Source.server));

      AppLogger.info('✅ Synced ${snapshot.docs.length} custom schemas');
      return snapshot.docs.length;
    } catch (e) {
      AppLogger.error('❌ Failed to sync templates: $e');
      return 0;
    }
  }

  /// Sync dashboard data (activity, queue, alerts) for offline use
  Future<int> _syncDashboard(String userId) async {
    int count = 0;
    try {
      // Sync activity stream
      final activitySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('activity')
          .orderBy('time', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));
      count += activitySnapshot.docs.length;

      // Sync work queue
      final queueSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('queue')
          .orderBy('time', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));
      count += queueSnapshot.docs.length;

      // Sync alerts
      final alertsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('alerts')
          .orderBy('time', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));
      count += alertsSnapshot.docs.length;

      AppLogger.info('✅ Synced $count dashboard items');
      return count;
    } catch (e) {
      AppLogger.error('❌ Failed to sync dashboard: $e');
      return count;
    }
  }

  /// Sync user profile for offline use.
  /// Profile is the top-level users/{userId} document.
  Future<int> _syncProfile(String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server));

      AppLogger.info('✅ Synced profile');
      return 1;
    } catch (e) {
      AppLogger.error('❌ Failed to sync profile: $e');
      return 0;
    }
  }

  /// Get last sync time for current user
  Future<String?> lastSyncedAt() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return null;

    final sp = await SharedPreferences.getInstance();
    return sp.getString('sync.$userId.last');
  }

  /// Check if offline mode is enabled
  Future<bool> offlineEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool('prefs.offline') ?? true;
  }

  /// Clear sync timestamp (useful for testing)
  Future<void> clearSyncTimestamp() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final sp = await SharedPreferences.getInstance();
    await sp.remove('sync.$userId.last');
  }
}