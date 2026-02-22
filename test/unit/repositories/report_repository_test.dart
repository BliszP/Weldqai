// test/unit/repositories/report_repository_test.dart
//
// Tests ReportRepository using FakeFirebaseFirestore.
// No real Firebase project required.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weldqai_app/core/repositories/report_repository.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';

void main() {
  const testUid = 'test-user-456';
  const schemaId = 'visual_inspection';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late ReportRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: testUid, email: 'welder@example.com'),
      signedIn: true,
    );
    // Inject SubscriptionService with the same fake Firestore so it never
    // touches FirebaseFirestore.instance (which requires Firebase.initializeApp).
    final subscriptionService = SubscriptionService(firestore: db, auth: auth);
    repo = ReportRepository(
      firestore: db,
      auth: auth,
      subscriptionService: subscriptionService,
    );
  });

  group('ReportRepository.saveReport', () {
    test('creates a new report and returns a non-empty id', () async {
      final id = await repo.saveReport(
        userId: testUid,
        schemaId: schemaId,
        payload: {'title': 'Test Inspection', 'status': 'draft'},
        skipSubscriptionCheck: true,
      );
      expect(id, isNotEmpty);
    });

    test('updating an existing report preserves the same id', () async {
      // Create first
      final id = await repo.saveReport(
        userId: testUid,
        schemaId: schemaId,
        payload: {'title': 'Initial', 'status': 'draft'},
        skipSubscriptionCheck: true,
      );

      // Update with same id
      final updatedId = await repo.saveReport(
        userId: testUid,
        schemaId: schemaId,
        payload: {'title': 'Updated', 'status': 'complete'},
        reportId: id,
        skipSubscriptionCheck: true,
      );

      expect(updatedId, id);
    });

    test('report is written to users/{uid}/reports/{schemaId}/items/{id}', () async {
      final id = await repo.saveReport(
        userId: testUid,
        schemaId: schemaId,
        payload: {'title': 'Path Test'},
        skipSubscriptionCheck: true,
      );

      final doc = await db
          .collection('users')
          .doc(testUid)
          .collection('reports')
          .doc(schemaId)
          .collection('items')
          .doc(id)
          .get();

      expect(doc.exists, isTrue);
      // saveReport wraps the caller's payload inside a 'payload' field
      final payload = doc.data()?['payload'] as Map<String, dynamic>?;
      expect(payload?['title'], 'Path Test');
    });

    test('throws StateError for empty userId', () async {
      expect(
        () => repo.saveReport(
          userId: '',
          schemaId: schemaId,
          payload: {'title': 'Bad'},
          skipSubscriptionCheck: true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ReportRepository — Firestore path correctness', () {
    test(
      'REGRESSION: saved items are NOT visible at the direct reports collection '
      '(confirms correct subcollection nesting)',
      () async {
        await repo.saveReport(
          userId: testUid,
          schemaId: schemaId,
          payload: {'title': 'Nested Item'},
          skipSubscriptionCheck: true,
        );

        // Top-level reports collection should NOT contain documents directly
        // (they are nested inside reports/{schemaId}/items)
        final topLevel = await db
            .collection('users')
            .doc(testUid)
            .collection('reports')
            .get();

        // Sub-collections appear as implicit docs in FakeFirestore,
        // but the doc itself has no fields
        for (final doc in topLevel.docs) {
          expect(doc.data().containsKey('title'), isFalse,
              reason: 'Report data should only exist in the items subcollection');
        }
      },
    );
  });
}
