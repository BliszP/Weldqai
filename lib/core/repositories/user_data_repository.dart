// ignore_for_file: unused_element

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserDataRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  UserDataRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  // ===== Auth Helpers =====
  String? get currentUserId => _auth.currentUser?.uid;
  bool get isAuthenticated => _auth.currentUser != null;

  // ===== Profile =====
  Future<void> initializeUserProfile({
    required String userId,
    required String email,
    String? displayName,
  }) async {
    final profileDoc =
        _db.collection('users').doc(userId).collection('profile').doc('info');

    final exists = await profileDoc.get().then((doc) => doc.exists);

    if (!exists) {
      await profileDoc.set({
        'userId': userId,
        'email': email,
        'displayName': displayName ?? email.split('@')[0],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Ensure /directory/{uid} exists for email -> uid lookup (invite by email)
    final dirDoc = _db.collection('directory').doc(userId);
    final dirExists = await dirDoc.get().then((d) => d.exists);
    if (!dirExists) {
      await dirDoc.set({
        'email': email,
        'emailLower': email.toLowerCase(),
        'displayName': displayName ?? email.split('@')[0],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // keep it up to date if changed
      await dirDoc.set({
        'email': email,
        'emailLower': email.toLowerCase(),
        'displayName': displayName ?? email.split('@')[0],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Stream<DocumentSnapshot> getUserProfile(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('info')
        .snapshots();
  }

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('info')
        .update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Keep directory in sync if email/displayName updated
    final dirUpdate = <String, dynamic>{};
    if (data.containsKey('email') && data['email'] is String) {
      dirUpdate['email'] = data['email'];
      dirUpdate['emailLower'] = (data['email'] as String).toLowerCase();
    }
    if (data.containsKey('displayName')) {
      dirUpdate['displayName'] = data['displayName'];
    }
    if (dirUpdate.isNotEmpty) {
      dirUpdate['updatedAt'] = FieldValue.serverTimestamp();
      await _db.collection('directory').doc(userId).set(dirUpdate, SetOptions(merge: true));
    }
  }

  // ===== KPI Methods =====
  Stream<QuerySnapshot> getKPIs(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('kpis')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> createKPI(String userId, Map<String, dynamic> kpiData) async {
    await _db.collection('users').doc(userId).collection('kpis').add({
      ...kpiData,
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateKPI(
    String userId,
    String kpiId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('kpis')
        .doc(kpiId)
        .update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteKPI(String userId, String kpiId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('kpis')
        .doc(kpiId)
        .delete();
  }

// ===== Report Item Methods (schema-scoped; matches ReportRepository) =====

// Stream all items under a schema (newest first)
Stream<QuerySnapshot<Map<String, dynamic>>> getReportItems(
  String userId,
  String schemaId,
) {
  return _db
      .collection('users').doc(userId)
      .collection('reports').doc(schemaId)
      .collection('items')
      .orderBy('createdAt', descending: true)
      .snapshots();
}

// Create one report item under a schema
Future<String> createReportItem(
  String userId,
  String schemaId,
  Map<String, dynamic> item,
) async {
  final currentUser = _auth.currentUser;
  
  final doc = await _db
      .collection('users').doc(userId)
      .collection('reports').doc(schemaId)
      .collection('items')
      .add({
        ...item,
        'userId': userId,
        'schemaId': schemaId,
        'createdBy': currentUser?.uid,
        'createdByEmail': currentUser?.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
  return doc.id;
}
// Update one report item
Future<void> updateReportItem(
  String userId,
  String schemaId,
  String itemId,
  Map<String, dynamic> data,
) async {
  final currentUser = _auth.currentUser;
  
  await _db
      .collection('users').doc(userId)
      .collection('reports').doc(schemaId)
      .collection('items').doc(itemId)
      .update({
        ...data,
        'updatedBy': currentUser?.uid,
        'updatedByEmail': currentUser?.email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

// Delete one report item
Future<void> deleteReportItem(
  String userId,
  String schemaId,
  String itemId,
) async {
  await _db
      .collection('users').doc(userId)
      .collection('reports').doc(schemaId)
      .collection('items').doc(itemId)
      .delete();
}

// Read one report item (live)
Stream<DocumentSnapshot<Map<String, dynamic>>> getReportItem(
  String userId,
  String schemaId,
  String itemId,
) {
  return _db
      .collection('users').doc(userId)
      .collection('reports').doc(schemaId)
      .collection('items').doc(itemId)
      .snapshots();
}

  // ===== Stream Methods =====
  Stream<QuerySnapshot> getStreams(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('streams')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> createStream(
    String userId,
    Map<String, dynamic> streamData,
  ) async {
    await _db.collection('users').doc(userId).collection('streams').add({
      ...streamData,
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateStream(
    String userId,
    String streamId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('streams')
        .doc(streamId)
        .update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteStream(String userId, String streamId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('streams')
        .doc(streamId)
        .delete();
  }

  // ===== Visualization Methods =====
  Stream<QuerySnapshot> getVisualizations(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('visualizations')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> createVisualization(
    String userId,
    Map<String, dynamic> vizData,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('visualizations')
        .add({
      ...vizData,
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateVisualization(
    String userId,
    String vizId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('visualizations')
        .doc(vizId)
        .update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteVisualization(String userId, String vizId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('visualizations')
        .doc(vizId)
        .delete();
  }

  // ===== Chat Methods =====
  Stream<QuerySnapshot> getChatMessages(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('chat')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> sendChatMessage(
    String userId,
    Map<String, dynamic> messageData,
  ) async {
    await _db.collection('users').doc(userId).collection('chat').add({
      ...messageData,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ===== Collaboration (UID-based) =====
Future<void> shareWith(
  String ownerId,
  String collaboratorId, {
  List<String> permissions = const ['read'],
}) async {
  // 1. Write to owner's sharedWith collection
  await _db
      .collection('users')
      .doc(ownerId)
      .collection('sharedWith')
      .doc(collaboratorId)
      .set({
    'collaboratorId': collaboratorId,
    'sharedAt': FieldValue.serverTimestamp(),
    'permissions': permissions,
  }, SetOptions(merge: true));

  // 2. Write to collaborator's sharedAccess collection (reverse lookup)
  await _db
      .collection('users')
      .doc(collaboratorId)
      .collection('sharedAccess')
      .doc(ownerId)
      .set({
    'ownerId': ownerId,
    'sharedAt': FieldValue.serverTimestamp(),
    'permissions': permissions,
  }, SetOptions(merge: true));
}

  Stream<QuerySnapshot> getCollaborators(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('sharedWith')
        .orderBy('sharedAt', descending: true)
        .snapshots();
  }
  Future<bool> hasAccessTo(String targetUserId) async {
    if (currentUserId == targetUserId) return true;

    final doc = await _db
        .collection('users')
        .doc(targetUserId)
        .collection('sharedWith')
        .doc(currentUserId)
        .get();

    return doc.exists;
  }

  // ===== Dashboard-specific (unchanged) =====
 Future<Map<String, num>> loadSummary(String userId) async {
  final ref = _db.collection('users').doc(userId).collection('stats').doc('summary');
  final doc = await ref.get(const GetOptions(source: Source.server));
  final m = doc.data() ?? const <String, dynamic>{};
  num n(v) => (v is num) ? v : (num.tryParse('$v') ?? 0);
  return {
    'openWelds' : n(m['openWelds']),
    'ndtPending': n(m['ndtPending']),
    'repairs'   : n(m['repairsOpen'] ?? m['repairs']),
    'completed' : n(m['completed']),
    'rejectRows': n(m['rejectRows']),
  };
}

Future<List<Map<String, dynamic>>> loadAlerts(String userId) async {
  final snapshot = await _db
      .collection('users')
      .doc(userId)
      .collection('alerts')
      .orderBy('time', descending: true)        // 🔁 was 'timestamp'
      .limit(10)
      .get();

  return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
}

Future<List<Map<String, dynamic>>> loadActivity(String userId) async {
  final snapshot = await _db
      .collection('users')
      .doc(userId)
      .collection('activity')
      .orderBy('time', descending: true)        // 🔁 was 'timestamp'
      .limit(20)
      .get();

  return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
}

Stream<List<Map<String, dynamic>>> alertsStream(String userId) {
  return _db
      .collection('users')
      .doc(userId)
      .collection('alerts')
      .orderBy('time', descending: true)        // 🔁 was 'timestamp'
      .limit(10)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
}

Stream<List<Map<String, dynamic>>> activityStream(String userId) {
  return _db
      .collection('users')
      .doc(userId)
      .collection('activity')
      .orderBy('time', descending: true)        // 🔁 was 'timestamp'
      .limit(20)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
}


  Future<List<Map<String, dynamic>>> loadQueuePage(String userId) async {
    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('queue')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();

    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }
 Future<Map<String, num>> loadWeldingKpis(String userId) async {
  final stats = await _db.collection('users').doc(userId).collection('stats').doc('welds').get();
  final m = stats.data() ?? const <String, dynamic>{};
  num n(v) => (v is num) ? v : (num.tryParse('$v') ?? 0);
  return {
    'today': n(m['today'] ?? m['dailyToday']),
    'week': n(m['week'] ?? m['last7Total']),
    'top': n(m['topWelder7d'] ?? m['top']),
  };
}

Future<Map<String, num>> loadVisualKpis(String userId) async {
  final insp = await _db.collection('users').doc(userId).collection('stats').doc('inspector_7d').get();
  final defects = await _db.collection('users').doc(userId).collection('stats').doc('defects_30d').get();
  num n(v) => (v is num) ? v : (num.tryParse('$v') ?? 0);

  num inspected = 0;
  for (final v in (insp.data() ?? const <String, dynamic>{}).values) {
    inspected += n(v);
  }
  final dm = defects.data() ?? const <String, dynamic>{};

  return {
    'inspected': inspected,
    'rejects30d': n(dm['Reject']),
  };
}

Future<Map<String, num>> loadNdtKpis(String userId) async {
  final summary = await _db.collection('users').doc(userId).collection('stats').doc('summary').get();
  final m = summary.data() ?? const <String, dynamic>{};
  num n(v) => (v is num) ? v : (num.tryParse('$v') ?? 0);
  final pass = n(m['__ndtPassCnt']);
  final total = n(m['__ndtTotalCnt']);
  final passPct = (total > 0) ? (pass * 100.0 / total) : 0.0;
  return {'passPct': passPct, 'pending': n(m['ndtPending']), 'total': total};
}

Future<Map<String, num>> loadRepairsKpis(String userId) async {
  final summary = await _db.collection('users').doc(userId).collection('stats').doc('repairs_summary').get();
  final metrics = await _db.collection('users').doc(userId).collection('stats').doc('repairs_metrics').get();
  num n(v) => (v is num) ? v : (num.tryParse('$v') ?? 0);
  return {
    'open': n(summary.data()?['open']),
    'closed': n(summary.data()?['closed']),
    'avgDaysToClose': n(metrics.data()?['avgDaysToClose']),
  };
}

  Map<String, dynamic> _aggregateKpis(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return {'count': 0, 'total': 0, 'average': 0};
    }
    return {
      'count': docs.length,
      'items': docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return <String, dynamic>{
          'id': doc.id,
          if (data != null) ...data,
        };
      }).toList(),
    };
  }

  // ===== Realtime Dashboard Streams =====
 // Replace your existing summaryStream with this:
Stream<Map<String, dynamic>> summaryStream(String userId) {
  return _db
      .collection('users')
      .doc(userId)
      .collection('stats')
      .doc('summary')
      .snapshots()
      .map((s) => (s.data() ?? const {}));
}

// (Optional) add more stats streams you can bind in the UI:

/// Visual defects over last 30 days (document of counters)
Stream<Map<String, dynamic>> defects30dStream(String userId) {
  return _db
      .collection('users')
      .doc(userId)
      .collection('stats')
      .doc('defects_30d')
      .snapshots()
      .map((s) => (s.data() ?? const {}));
}

/// Welder 7-day activity counters
Stream<Map<String, dynamic>> welder7dStream(String userId) {
  return _db
      .collection('users')
      .doc(userId)
      .collection('stats')
      .doc('welder_7d')
      .snapshots()
      .map((s) => (s.data() ?? const {}));
}

/// Inspector 7-day activity counters (visual + NDT)
Stream<Map<String, dynamic>> inspector7dStream(String userId) {
  return _db
      .collection('users')
      .doc(userId)
      .collection('stats')
      .doc('inspector_7d')
      .snapshots()
      .map((s) => (s.data() ?? const {}));
}

  Stream<List<Map<String, dynamic>>> queueStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('queue')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  // === LIVE KPI STREAMS FOR DASHBOARD TILES ================================

  // Generic helper to build the 7d/avg/total map from a QuerySnapshot
  Map<String, dynamic> _kpiFromSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final docs = snap.docs;
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    int count7 = 0;
    for (final d in docs) {
      final data = d.data();
      final ts = data['createdAt'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        if (!dt.isBefore(sevenDaysAgo)) count7++;
      }
    }

    final avg = count7 / 7.0;
    return <String, dynamic>{
      'average': avg.isFinite ? double.parse(avg.toStringAsFixed(1)) : 0.0,
      'count': count7,
      'total': docs.length,
    };
  }

  /// Welding tile: /users/{uid}/reports/welding_operation/items/*
  Stream<Map<String, dynamic>> weldingKpisStream(String userId) {
    return _db
        .collection('users').doc(userId)
        .collection('reports').doc('welding_operation')
        .collection('items')
        .snapshots()
        .map(_kpiFromSnapshot);
  }

  /// Visual Inspection tile: /users/{uid}/reports/visual_inspection/items/*
  Stream<Map<String, dynamic>> visualKpisStream(String userId) {
    return _db
        .collection('users').doc(userId)
        .collection('reports').doc('visual_inspection')
        .collection('items')
        .snapshots()
        .map(_kpiFromSnapshot);
  }

  /// NDT tile: merges RT/UT/MPI by using a collectionGroup on 'items'
  /// We rely on ReportRepository writing 'userId' and 'schemaId' into each item.
  Stream<Map<String, dynamic>> ndtKpisStream(String userId) {
    return _db
        .collectionGroup('items')
        .where('userId', isEqualTo: userId)
        .where('schemaId', whereIn: ['ndt_rt', 'ndt_ut', 'ndt_mpi'])
        .snapshots()
        .map(_kpiFromSnapshot);
  }

  /// Repairs tile: /users/{uid}/reports/repairs_log/items/*
  Stream<Map<String, dynamic>> repairsKpisStream(String userId) {
    return _db
        .collection('users').doc(userId)
        .collection('reports').doc('repairs_log')
        .collection('items')
        .snapshots()
        .map(_kpiFromSnapshot);
  }
// ============================================================================
// ADD THESE METHODS TO YOUR user_data_repository.dart FILE
// Location: Add them AFTER line 731 (at the end of the class, before the closing brace)
// ============================================================================

  // ===== SHARING & COLLABORATION METHODS =====
  
  /// Invite a user by email to collaborate on your workspace
  /// Creates BIDIRECTIONAL relationship with 3 documents
  Future<void> inviteByEmail(
    String ownerId,
    String inviteeEmail, {
    List<String> permissions = const ['read'],
  }) async {
    try {
      // Step 1: Look up the invitee's UID from the directory
      final directoryQuery = await _db
          .collection('directory')
          .where('emailLower', isEqualTo: inviteeEmail.toLowerCase())
          .limit(1)
          .get();

      if (directoryQuery.docs.isEmpty) {
        throw Exception(
          'User with email $inviteeEmail not found. They may need to sign in first.',
        );
      }

      final inviteeUid = directoryQuery.docs.first.id;
      final inviteeData = directoryQuery.docs.first.data();
      final inviteeDisplayName = inviteeData['displayName'] as String? ?? inviteeEmail;

      // Prevent inviting yourself
      if (inviteeUid == ownerId) {
        throw Exception('You cannot share with yourself.');
      }

      // Step 2: Create the bidirectional sharing relationship
      final batch = _db.batch();

      // A) Owner's side: /users/{ownerId}/sharedWith/{inviteeUid}
      // This grants the invitee access to the owner's workspace
      final sharedWithRef = _db
          .collection('users')
          .doc(ownerId)
          .collection('sharedWith')
          .doc(inviteeUid);

      batch.set(sharedWithRef, {
        'collaboratorId': inviteeUid,
        'collaboratorEmail': inviteeEmail,
        'collaboratorDisplayName': inviteeDisplayName,
        'permissions': permissions,
        'sharedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // B) Invitee's side: /users/{inviteeUid}/sharedAccess/{ownerId}
      // This shows the invitee that the owner shared their workspace
      final sharedAccessRef = _db
          .collection('users')
          .doc(inviteeUid)
          .collection('sharedAccess')
          .doc(ownerId);

      batch.set(sharedAccessRef, {
        'ownerId': ownerId,
        'permissions': permissions,
        'sharedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // C) ✨ NEW: Owner's tracking of who they invited
      // /users/{ownerId}/myCollaborators/{inviteeUid}
      // This is used by the UI to show "My collaborators" tab
      final myCollaboratorsRef = _db
          .collection('users')
          .doc(ownerId)
          .collection('myCollaborators')
          .doc(inviteeUid);

      batch.set(myCollaboratorsRef, {
        'collaboratorId': inviteeUid,
        'collaboratorEmail': inviteeEmail,
        'collaboratorDisplayName': inviteeDisplayName,
        'permissions': permissions,
        'invitedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to invite collaborator: $e');
    }
  }

  /// Remove a collaborator's access to your workspace
  /// Deletes all 3 documents to clean up the bidirectional relationship
  Future<void> removeSharedAccess(String ownerId, String collaboratorId) async {
    final batch = _db.batch();

    // Remove from owner's sharedWith
    final sharedWithRef = _db
        .collection('users')
        .doc(ownerId)
        .collection('sharedWith')
        .doc(collaboratorId);
    batch.delete(sharedWithRef);

    // Remove from collaborator's sharedAccess
    final sharedAccessRef = _db
        .collection('users')
        .doc(collaboratorId)
        .collection('sharedAccess')
        .doc(ownerId);
    batch.delete(sharedAccessRef);

    // Remove from owner's myCollaborators
    final myCollaboratorsRef = _db
        .collection('users')
        .doc(ownerId)
        .collection('myCollaborators')
        .doc(collaboratorId);
    batch.delete(myCollaboratorsRef);

    await batch.commit();
  }

  /// Watch list of users who can access YOUR workspace
  /// This is the "My collaborators" tab - people YOU invited
  Stream<QuerySnapshot> watchMyCollaborators(String ownerId) {
    return _db
        .collection('users')
        .doc(ownerId)
        .collection('myCollaborators')
        .orderBy('invitedAt', descending: true)
        .snapshots();
  }

  /// Watch list of workspaces shared WITH YOU
  /// This is the "Shared with me" tab - workspaces YOU can access
  Stream<QuerySnapshot> watchSharedWithMe(String myUid) {
    return _db
        .collection('users')
        .doc(myUid)
        .collection('sharedAccess')
        .orderBy('sharedAt', descending: true)
        .snapshots();
  }

  /// Look up UID by email (for inviting users)
  Future<String?> lookupUidByEmail(String email) async {
    final query = await _db
        .collection('directory')
        .where('emailLower', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }

  /// Update sharing permissions for an existing collaborator
  Future<void> updateCollaboratorPermissions(
    String ownerId,
    String collaboratorId,
    List<String> newPermissions,
  ) async {
    final batch = _db.batch();

    // Update sharedWith
    final sharedWithRef = _db
        .collection('users')
        .doc(ownerId)
        .collection('sharedWith')
        .doc(collaboratorId);
    batch.update(sharedWithRef, {
      'permissions': newPermissions,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update sharedAccess
    final sharedAccessRef = _db
        .collection('users')
        .doc(collaboratorId)
        .collection('sharedAccess')
        .doc(ownerId);
    batch.update(sharedAccessRef, {
      'permissions': newPermissions,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update myCollaborators
    final myCollaboratorsRef = _db
        .collection('users')
        .doc(ownerId)
        .collection('myCollaborators')
        .doc(collaboratorId);
    batch.update(myCollaboratorsRef, {
      'permissions': newPermissions,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}
