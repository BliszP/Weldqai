// test/unit/services/subscription_service_test.dart
//
// Tests SubscriptionService using FakeFirebaseFirestore + MockFirebaseAuth
// so no real Firebase project is required.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';
import '../../helpers/test_helpers.dart';

void main() {
  const testUid = 'test-user-123';

  group('SubscriptionService.getStatus', () {
    test('returns notAuthenticated when no user is signed in', () async {
      final db = FakeFirebaseFirestore();
      final auth = TestHelpers.createMockAuth(signedIn: false);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.getStatus();
      expect(status.type, SubscriptionType.notAuthenticated);
    });

    test('returns monthlyIndividual when hasAccess is true', () async {
      final db = await TestHelpers.createFirestoreWithSubscription(testUid);
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.getStatus();
      expect(status.type, SubscriptionType.monthlyIndividual);
    });

    test('returns payPerReport when credits > 0 and no subscription', () async {
      final db = await TestHelpers.createFirestoreWithCredits(testUid, credits: 3);
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.getStatus();
      expect(status.type, SubscriptionType.payPerReport);
      expect(status.creditsRemaining, 3);
    });

    test('initialises trial for brand-new user', () async {
      final db = FakeFirebaseFirestore();
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.getStatus();
      expect(status.type, SubscriptionType.trial);
      expect(status.reportsRemaining, 3);
    });

    test('returns trial with reduced count after usage', () async {
      final db = await TestHelpers.createFirestoreWithTrial(
        testUid,
        reportsRemaining: 2,
      );
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.getStatus();
      expect(status.type, SubscriptionType.trial);
      expect(status.reportsRemaining, 2);
    });

    test('returns trialExpired when trial status is expired', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('users')
          .doc(testUid)
          .collection('subscription')
          .doc('trial')
          .set({'status': 'expired'});
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.getStatus();
      expect(status.type, SubscriptionType.trialExpired);
    });
  });

  group('SubscriptionService.canCreateReport', () {
    test('allowed for monthly subscriber', () async {
      final db = await TestHelpers.createFirestoreWithSubscription(testUid);
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final result = await service.canCreateReport();
      expect(result.allowed, isTrue);
    });

    test('allowed for trial user with reports remaining', () async {
      final db = await TestHelpers.createFirestoreWithTrial(testUid, reportsRemaining: 2);
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final result = await service.canCreateReport();
      expect(result.allowed, isTrue);
      expect(result.isTrialUser, isTrue);
    });

    test('blocked for expired trial', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('users')
          .doc(testUid)
          .collection('subscription')
          .doc('trial')
          .set({'status': 'expired'});
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final result = await service.canCreateReport();
      expect(result.allowed, isFalse);
      expect(result.blockReason, isNotNull);
    });

    test('blocked when 0 credits AND trial is expired', () async {
      // When credits=0 the service falls through to check trial.
      // We must expire the trial too for the user to be fully blocked.
      final db = await TestHelpers.createFirestoreWithCredits(testUid, credits: 0);
      await db
          .collection('users')
          .doc(testUid)
          .collection('subscription')
          .doc('trial')
          .set({'status': 'expired'});
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final result = await service.canCreateReport();
      expect(result.allowed, isFalse);
    });
  });

  group('SubscriptionService.watchStatus', () {
    test('emits notAuthenticated when not signed in', () async {
      final db = FakeFirebaseFirestore();
      final auth = TestHelpers.createMockAuth(signedIn: false);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.watchStatus().first;
      expect(status.type, SubscriptionType.notAuthenticated);
    });

    test('emits monthlyIndividual for paid user', () async {
      final db = await TestHelpers.createFirestoreWithSubscription(testUid);
      final auth = TestHelpers.createMockAuth(uid: testUid);
      final service = SubscriptionService(firestore: db, auth: auth);
      final status = await service.watchStatus().first;
      expect(status.type, SubscriptionType.monthlyIndividual);
    });
  });
}
