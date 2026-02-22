// lib/core/services/subscription_service.dart
// ✅ UPDATED: Added watchStatus() for real-time subscription updates

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SubscriptionService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  SubscriptionService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  /// Get current subscription status (one-time fetch)
  Future<SubscriptionStatus> getStatus() async {
    if (_uid == null) {
      return SubscriptionStatus.notAuthenticated();
    }

    // Check for paid subscription first
    final subDoc = await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('info')
        .get();

    if (subDoc.exists) {
      final data = subDoc.data()!;
      final hasAccess = data['hasAccess'] == true;
      final status = data['status'] as String?;
      final type = data['subscriptionType'] as String?;

      if (hasAccess && status == 'active') {
        if (type == 'monthly_individual') {
          // ✅ UPDATED - Extract billing period info
          final currentPeriodEnd = (data['currentPeriodEnd'] as Timestamp?)?.toDate();
          final cancelAtPeriodEnd = data['cancelAtPeriodEnd'] as bool?;
          
          return SubscriptionStatus.monthlyIndividual(
            currentPeriodEnd: currentPeriodEnd,
            cancelAtPeriodEnd: cancelAtPeriodEnd,
          );
        } else if (type == 'team') {
          return SubscriptionStatus.team(
            isOwner: data['role'] == 'owner',
            teamOwnerId: data['teamOwnerId'] as String?,
          );
        }
      }
    }

    // Check for pay-per-report credits
    final creditsDoc = await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('credits')
        .get();

    if (creditsDoc.exists) {
      final credits = (creditsDoc.data()?['reportCredits'] as num?)?.toInt() ?? 0;
      if (credits > 0) {
        return SubscriptionStatus.payPerReport(creditsRemaining: credits);
      }
    }

    // Check trial status
    final trialDoc = await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('trial')
        .get();

    if (!trialDoc.exists) {
      // Initialize trial for new user
      await _initializeTrial();
      return SubscriptionStatus.trial(reportsRemaining: 3, daysRemaining: 7);
    }

    final trialData = trialDoc.data()!;
    final trialStatus = trialData['status'] as String;

    if (trialStatus == 'expired') {
      return SubscriptionStatus.trialExpired();
    }

    final completeReports = (trialData['usage']['completeReports'] as num?)?.toInt() ?? 0;
    final maxReports = (trialData['limits']['completeReports'] as num?)?.toInt() ?? 3;
    final firstReportAt = (trialData['usage']['firstReportAt'] as Timestamp?)?.toDate();

    int? daysRemaining;
    if (firstReportAt != null) {
      final expiryDate = firstReportAt.add(Duration(days: 7));
      final diff = expiryDate.difference(DateTime.now());
      daysRemaining = diff.inDays;

      if (daysRemaining <= 0) {
        await _markTrialExpired();
        return SubscriptionStatus.trialExpired();
      }
    }

    final reportsRemaining = maxReports - completeReports;
    if (reportsRemaining <= 0) {
      await _markTrialExpired();
      return SubscriptionStatus.trialExpired();
    }

    return SubscriptionStatus.trial(
      reportsRemaining: reportsRemaining,
      daysRemaining: daysRemaining,
      totalReports: maxReports,
    );
  }

  /// ✅ NEW: Watch subscription status in real-time
  /// Use this in StreamBuilder for auto-updating UI
  Stream<SubscriptionStatus> watchStatus() {
    if (_uid == null) {
      return Stream.value(SubscriptionStatus.notAuthenticated());
    }

    // Watch subscription info document for changes
    return _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('info')
        .snapshots()
        .asyncMap((infoDoc) async {
      // Check for paid subscription first
      if (infoDoc.exists) {
        final data = infoDoc.data()!;
        final hasAccess = data['hasAccess'] == true;
        final status = data['status'] as String?;
        final type = data['subscriptionType'] as String?;

        if (hasAccess && status == 'active') {
          if (type == 'monthly_individual') {
            // ✅ UPDATED - Extract billing period info
            final currentPeriodEnd = (data['currentPeriodEnd'] as Timestamp?)?.toDate();
            final cancelAtPeriodEnd = data['cancelAtPeriodEnd'] as bool?;
            
            return SubscriptionStatus.monthlyIndividual(
              currentPeriodEnd: currentPeriodEnd,
              cancelAtPeriodEnd: cancelAtPeriodEnd,
            );
          } else if (type == 'team') {
            return SubscriptionStatus.team(
              isOwner: data['role'] == 'owner',
              teamOwnerId: data['teamOwnerId'] as String?,
            );
          }
        }
      }

      // Check for pay-per-report credits
      final creditsDoc = await _db
          .collection('users')
          .doc(_uid)
          .collection('subscription')
          .doc('credits')
          .get();

      if (creditsDoc.exists) {
        final credits = (creditsDoc.data()?['reportCredits'] as num?)?.toInt() ?? 0;
        if (credits > 0) {
          return SubscriptionStatus.payPerReport(creditsRemaining: credits);
        }
      }

      // Check trial status
      final trialDoc = await _db
          .collection('users')
          .doc(_uid)
          .collection('subscription')
          .doc('trial')
          .get();

      if (!trialDoc.exists) {
        // Initialize trial for new user
        await _initializeTrial();
        return SubscriptionStatus.trial(reportsRemaining: 3, daysRemaining: 7);
      }

      final trialData = trialDoc.data()!;
      final trialStatus = trialData['status'] as String;

      if (trialStatus == 'expired') {
        return SubscriptionStatus.trialExpired();
      }

      final completeReports = (trialData['usage']['completeReports'] as num?)?.toInt() ?? 0;
      final maxReports = (trialData['limits']['completeReports'] as num?)?.toInt() ?? 3;
      final firstReportAt = (trialData['usage']['firstReportAt'] as Timestamp?)?.toDate();

      int? daysRemaining;
      if (firstReportAt != null) {
        final expiryDate = firstReportAt.add(Duration(days: 7));
        final diff = expiryDate.difference(DateTime.now());
        daysRemaining = diff.inDays;

        if (daysRemaining <= 0) {
          await _markTrialExpired();
          return SubscriptionStatus.trialExpired();
        }
      }

      final reportsRemaining = maxReports - completeReports;
      if (reportsRemaining <= 0) {
        await _markTrialExpired();
        return SubscriptionStatus.trialExpired();
      }

      return SubscriptionStatus.trial(
        reportsRemaining: reportsRemaining,
        daysRemaining: daysRemaining,
        totalReports: maxReports,
      );
    });
  }

  /// ✅ UPDATED: Check if user can create a NEW report
  /// Call this BEFORE saveReport() when reportId is null (new report)
  Future<ReportCheckResult> canCreateReport() async {
    final status = await getStatus();

    // Monthly subscribers can always create
    if (status.type == SubscriptionType.monthlyIndividual ||
        status.type == SubscriptionType.team) {
      return ReportCheckResult.allowed();
    }

    // Pay-per-report users need credits
    if (status.type == SubscriptionType.payPerReport) {
      if (status.creditsRemaining! > 0) {
        return ReportCheckResult.allowed(
          willUseCredit: true,
          creditsRemaining: status.creditsRemaining! - 1,
        );
      } else {
        return ReportCheckResult.needsPayment(
          reason: 'No report credits remaining. Purchase more to continue.',
        );
      }
    }

    // Trial users need remaining reports
    if (status.type == SubscriptionType.trial) {
      if (status.reportsRemaining! > 0) {
        return ReportCheckResult.allowed(
          isTrialUser: true,
          reportsRemaining: status.reportsRemaining! - 1,
        );
      } else {
        return ReportCheckResult.trialExpired();
      }
    }

    return ReportCheckResult.trialExpired();
  }

  /// ✅ UPDATED: Track report creation
  /// Call this AFTER saveReport() succeeds when creating NEW report (reportId was null)
  Future<void> trackReportCreation() async {
    if (_uid == null) return;

    final status = await getStatus();

    if (status.type == SubscriptionType.payPerReport) {
      // Deduct credit
      await _db
          .collection('users')
          .doc(_uid)
          .collection('subscription')
          .doc('credits')
          .update({
        'reportCredits': FieldValue.increment(-1),
        'lastUsed': FieldValue.serverTimestamp(),
      });
    } else if (status.type == SubscriptionType.trial) {
      // Increment trial usage
      final trialRef = _db
          .collection('users')
          .doc(_uid)
          .collection('subscription')
          .doc('trial');

      final trialDoc = await trialRef.get();
      final firstReportAt = trialDoc.data()?['usage']?['firstReportAt'];

      final Map<String, dynamic> updates = {
        'usage.completeReports': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Set trial start time on first report
      if (firstReportAt == null) {
        updates['usage.firstReportAt'] = FieldValue.serverTimestamp();
        updates['startedAt'] = FieldValue.serverTimestamp();
        
        final now = DateTime.now();
        final expires = now.add(Duration(days: 7));
        updates['expiresAt'] = Timestamp.fromDate(expires);
      }

      await trialRef.update(updates);

      // Check if we should send reminder
      final completeReports = (trialDoc.data()?['usage']?['completeReports'] as num?)?.toInt() ?? 0;
      if (completeReports + 1 == 2) {
        await _sendTrialReminder('last_report');
      }
    }
  }

  /// Initialize trial for new user
  Future<void> _initializeTrial() async {
    if (_uid == null) return;

    await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('trial')
        .set({
      'status': 'active',
      'startedAt': null, // Will be set on first report
      'expiresAt': null, // Will be set on first report

      'limits': {
        'completeReports': 3,
        'daysFromFirstReport': 7,
        'storage': 524288000, // 500MB
      },

      'usage': {
        'completeReports': 0,
        'draftReports': 0,
        'firstReportAt': null,
        'storageUsed': 0,
      },

      'features': {
        'canCreateDrafts': true,
        'canCompleteReports': true,
        'canExportPDF': true,
        'hasWatermark': true,
        'canCollaborate': false,
        'canEnableOffline': false,
      },

      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mark trial as expired
  Future<void> _markTrialExpired() async {
    if (_uid == null) return;

    await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('trial')
        .update({
      'status': 'expired',
      'expiredAt': FieldValue.serverTimestamp(),
    });
  }

  /// Send trial reminder notification
  Future<void> _sendTrialReminder(String reminderType) async {
    if (_uid == null) return;

    String title;
    String body;

    switch (reminderType) {
      case 'last_report':
        title = 'Last Free Report!';
        body = 'You have 1 report remaining in your trial. Upgrade now to continue!';
        break;
      default:
        return;
    }

    await _db.collection('users').doc(_uid).collection('inbox').add({
      'title': title,
      'body': body,
      'type': 'trial_reminder',
      'reminderType': reminderType,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Add credits (after payment)
  Future<void> addCredits(int credits, String paymentId) async {
    if (_uid == null) return;

    final creditsRef = _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('credits');

    await creditsRef.set({
      'reportCredits': FieldValue.increment(credits),
      'purchaseHistory': FieldValue.arrayUnion([
        {
          'credits': credits,
          'paymentId': paymentId,
          'purchasedAt': FieldValue.serverTimestamp(),
        }
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Create monthly subscription
  Future<void> createMonthlySubscription({
    required String stripeSubscriptionId,
    required String stripeCustomerId,
  }) async {
    if (_uid == null) return;

    await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('info')
        .set({
      // hasAccess is set server-side by the Stripe webhook (customer.subscription.created).
      // Do NOT write it from the client — any authenticated user could grant themselves access.
      'status': 'active',
      'subscriptionType': 'monthly_individual',
      'role': 'owner',
      'isPayingUser': true,
      'stripeSubscriptionId': stripeSubscriptionId,
      'stripeCustomerId': stripeCustomerId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Mark trial as converted
    await _db
        .collection('users')
        .doc(_uid)
        .collection('subscription')
        .doc('trial')
        .update({
      'status': 'converted',
      'convertedAt': FieldValue.serverTimestamp(),
      'convertedTo': 'monthly_individual',
    });
  }
}

/// Subscription status
class SubscriptionStatus {
  final SubscriptionType type;
  final int? reportsRemaining;
  final int? daysRemaining;
  final int? creditsRemaining;
  final bool? isTeamOwner;
  final String? teamOwnerId;
  final int? totalReports;
  final DateTime? currentPeriodEnd;  // ✅ NEW - When subscription renews
  final bool? cancelAtPeriodEnd;      // ✅ NEW - If user cancelled

  const SubscriptionStatus({
    required this.type,
    this.reportsRemaining,
    this.daysRemaining,
    this.creditsRemaining,
    this.isTeamOwner,
    this.teamOwnerId,
    this.totalReports,
    this.currentPeriodEnd,   // ✅ NEW
    this.cancelAtPeriodEnd,  // ✅ NEW
  });

  factory SubscriptionStatus.trial({
    required int reportsRemaining,
    int? daysRemaining,
    int totalReports = 3,
  }) {
    return SubscriptionStatus(
      type: SubscriptionType.trial,
      reportsRemaining: reportsRemaining,
      daysRemaining: daysRemaining,
      totalReports: totalReports,
    );
  }

  factory SubscriptionStatus.trialExpired() {
    return const SubscriptionStatus(
      type: SubscriptionType.trialExpired,
      reportsRemaining: 0,
    );
  }

  factory SubscriptionStatus.payPerReport({required int creditsRemaining}) {
    return SubscriptionStatus(
      type: SubscriptionType.payPerReport,
      creditsRemaining: creditsRemaining,
    );
  }

  factory SubscriptionStatus.monthlyIndividual({
    DateTime? currentPeriodEnd,
    bool? cancelAtPeriodEnd,
  }) {
    return SubscriptionStatus(
      type: SubscriptionType.monthlyIndividual,
      currentPeriodEnd: currentPeriodEnd,      // ✅ NEW
      cancelAtPeriodEnd: cancelAtPeriodEnd,    // ✅ NEW
    );
  }

  factory SubscriptionStatus.team({
    required bool isOwner,
    String? teamOwnerId,
  }) {
    return SubscriptionStatus(
      type: SubscriptionType.team,
      isTeamOwner: isOwner,
      teamOwnerId: teamOwnerId,
    );
  }

  factory SubscriptionStatus.notAuthenticated() {
    return const SubscriptionStatus(
      type: SubscriptionType.notAuthenticated,
    );
  }

  bool get hasUnlimitedReports =>
      type == SubscriptionType.monthlyIndividual ||
      type == SubscriptionType.team;

  bool get needsPayment =>
      type == SubscriptionType.trialExpired ||
      (type == SubscriptionType.payPerReport && creditsRemaining == 0);
}

enum SubscriptionType {
  trial,
  trialExpired,
  payPerReport,
  monthlyIndividual,
  team,
  notAuthenticated,
}

/// Result of report creation check
class ReportCheckResult {
  final bool allowed;
  final bool isTrialUser;
  final bool willUseCredit;
  final int? reportsRemaining;
  final int? creditsRemaining;
  final String? blockReason;

  const ReportCheckResult({
    required this.allowed,
    this.isTrialUser = false,
    this.willUseCredit = false,
    this.reportsRemaining,
    this.creditsRemaining,
    this.blockReason,
  });

  factory ReportCheckResult.allowed({
    bool isTrialUser = false,
    bool willUseCredit = false,
    int? reportsRemaining,
    int? creditsRemaining,
  }) {
    return ReportCheckResult(
      allowed: true,
      isTrialUser: isTrialUser,
      willUseCredit: willUseCredit,
      reportsRemaining: reportsRemaining,
      creditsRemaining: creditsRemaining,
    );
  }

  factory ReportCheckResult.trialExpired() {
    return const ReportCheckResult(
      allowed: false,
      blockReason: 'Your trial has ended. Choose a plan to continue!',
    );
  }

  factory ReportCheckResult.needsPayment({required String reason}) {
    return ReportCheckResult(
      allowed: false,
      blockReason: reason,
    );
  }
}