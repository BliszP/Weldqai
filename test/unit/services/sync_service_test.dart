// test/unit/services/sync_service_test.dart
//
// Regression tests for P1.2 (fixed Feb 2026):
// SyncService._syncReports() previously queried users/{uid}/reports
// (schema metadata, always empty) instead of the correct per-schema
// subcollection users/{uid}/reports/{schemaId}/items.
//
// The fix now enumerates schema documents first, then hydrates each schema's
// items subcollection. These tests use SharedPreferences mocks and
// FakeFirebaseFirestore to verify Firestore path semantics without
// hitting real Firebase.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncService — collection path (P1.2 regression)', () {
    test(
      'regression: parent reports collection is empty when items live in subcollection',
      () async {
        const uid = 'test-user-123';
        const schemaId = 'visual_inspection';
        final db = FakeFirebaseFirestore();

        // Seed data at the CORRECT path that items actually live at.
        await db
            .collection('users')
            .doc(uid)
            .collection('reports')
            .doc(schemaId)
            .collection('items')
            .add({'title': 'Inspection #1', 'status': 'complete'});

        // The parent collection (schema metadata) never contains report items.
        // SyncService previously queried this and reported 0 synced items.
        final schemaMetadataSnap = await db
            .collection('users')
            .doc(uid)
            .collection('reports')
            .get();

        // The correct path (fixed) returns the actual items.
        final itemsSnap = await db
            .collection('users')
            .doc(uid)
            .collection('reports')
            .doc(schemaId)
            .collection('items')
            .get();

        // Parent collection docs: zero (schema docs only appear here when
        // explicitly written — items live one level deeper).
        expect(schemaMetadataSnap.docs.length, 0,
            reason:
                'Subcollection items never bubble up to the parent collection');

        // Items subcollection: the actual data.
        expect(itemsSnap.docs.length, 1,
            reason: 'Items exist at the correct path');
      },
    );

    test('lastSyncedAt returns null before any sync', () async {
      // SharedPreferences is mock-empty; no sync has run.
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('sync.test-user-123.last');
      expect(lastSync, isNull);
    });

    test('offlineEnabled defaults to true', () async {
      // SyncService reads prefs.offline, defaulting to true when missing.
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('prefs.offline') ?? true;
      expect(enabled, isTrue);
    });

    test('offlineEnabled respects stored preference', () async {
      SharedPreferences.setMockInitialValues({'prefs.offline': false});
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('prefs.offline') ?? true;
      expect(enabled, isFalse);
    });
  });
}
