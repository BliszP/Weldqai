// test/helpers/test_helpers.dart
//
// Shared test infrastructure for WeldQAi unit tests.
// Provides pre-seeded FakeFirebaseFirestore instances and mock users.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

class TestHelpers {
  TestHelpers._();

  /// Creates a FakeFirebaseFirestore seeded with a paid monthly subscription
  /// for [userId] at users/{userId}/subscription/info.
  static Future<FakeFirebaseFirestore> createFirestoreWithSubscription(
    String userId, {
    bool hasAccess = true,
    String status = 'active',
    String subscriptionType = 'monthly_individual',
  }) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc(userId)
        .collection('subscription')
        .doc('info')
        .set({
      'hasAccess': hasAccess,
      'status': status,
      'subscriptionType': subscriptionType,
      'role': 'owner',
      'isPayingUser': true,
    });
    return db;
  }

  /// Creates a FakeFirebaseFirestore seeded with a trial subscription
  /// that still has [reportsRemaining] left.
  static Future<FakeFirebaseFirestore> createFirestoreWithTrial(
    String userId, {
    int reportsRemaining = 2,
    int maxReports = 3,
  }) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc(userId)
        .collection('subscription')
        .doc('trial')
        .set({
      'status': 'active',
      'limits': {'completeReports': maxReports},
      'usage': {
        'completeReports': maxReports - reportsRemaining,
        'draftReports': 0,
        'firstReportAt': null,
        'storageUsed': 0,
      },
    });
    return db;
  }

  /// Creates a FakeFirebaseFirestore with pay-per-report credits.
  static Future<FakeFirebaseFirestore> createFirestoreWithCredits(
    String userId, {
    int credits = 5,
  }) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc(userId)
        .collection('subscription')
        .doc('credits')
        .set({'reportCredits': credits});
    return db;
  }

  /// Creates a FakeFirebaseFirestore seeded with report items at the
  /// CORRECT path: users/{userId}/reports/{schemaId}/items/{itemId}.
  static Future<FakeFirebaseFirestore> createFirestoreWithReportItems(
    String userId, {
    String schemaId = 'visual_inspection',
    int itemCount = 3,
  }) async {
    final db = FakeFirebaseFirestore();
    for (int i = 0; i < itemCount; i++) {
      await db
          .collection('users')
          .doc(userId)
          .collection('reports')
          .doc(schemaId)
          .collection('items')
          .add({
        'title': 'Test Report $i',
        'status': 'complete',
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
    return db;
  }

  /// Creates a MockFirebaseAuth with a signed-in mock user.
  static MockFirebaseAuth createMockAuth({
    String uid = 'test-user-123',
    String email = 'test@example.com',
    bool signedIn = true,
  }) {
    final user = MockUser(uid: uid, email: email);
    return MockFirebaseAuth(mockUser: user, signedIn: signedIn);
  }
}
