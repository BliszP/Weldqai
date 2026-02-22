// lib/core/repositories/metrics_repository.dart
// ignore_for_file: unintended_html_in_doc_comment, duplicate_ignore, invalid_return_type_for_catch_error, no_leading_underscores_for_local_identifiers

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Firestore-driven metrics that back Visualization & Dashboard screens.
/// - Primary scope: users/{userId}/stats/*
/// - Legacy fallback: projects/{projectId}/stats/* (using the same userId value)
/// - Server-first with cache fallback
/// - Streams includeMetadataChanges for fast cache -> server flips
/// - Robust number parsing
class MetricsRepository {
  final FirebaseFirestore _db;
  MetricsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ===========================
  // Home KPIs (VisualizationHomeScreen)
  // ===========================

  Future<Map<String, num>> loadOverviewKpis(String userId, DateTimeRange? range) {
    return kpis(userId, range);
  }

  Stream<Map<String, num>> overviewKpisStream(String userId, DateTimeRange? range) {
    return kpisStream(userId, range);
  }

  /// One-shot KPIs for the home screen (derived from /stats/summary + welds/daily).
  /// We compute:
  ///  - ndtPassPercent from __ndtPassCnt/__ndtTotalCnt (if needed)
  ///  - totalWelds by summing last 30 daily weld counts when not present
  Future<Map<String, num>> kpis(String userId, DateTimeRange? range) async {
    final usersRef = _summaryRefUsers(userId);

    // Try users/
    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    Map<String, dynamic> data = usersDoc?.data() ?? const <String, dynamic>{};

    // Fallback to legacy projects/{userId} if empty
    if (data.isEmpty) {
      final legacyDoc = await _serverFirstDoc(_summaryRefProjects(userId)).catchError((_) => null);
      data = legacyDoc?.data() ?? const <String, dynamic>{};
    }

    // Derive pass %
    final passCnt = _toNum(data['__ndtPassCnt']);
    final totalCnt = _toNum(data['__ndtTotalCnt']);
    final ndtPassPercent = (totalCnt > 0)
        ? (passCnt * 100.0 / totalCnt)
        : _toNum(data['ndtPassPercent']); // fallback if present

    // Derive totalWelds (sum last 30 daily docs) if not present
    num totalWelds = _toNum(data['totalWelds']);
    if (totalWelds == 0) {
      totalWelds = await _sumDailyWelds(userId, days: 30);
    }

    return <String, num>{
      'totalWelds': totalWelds,
      'ndtPassPercent': ndtPassPercent,
      'repairsOpen': _toNum(data['repairsOpen']),
    };
  }

  /// Live KPIs stream (summary doc).
  /// Emits a fully-keyed map every time. If the users/ doc is empty, it backfills
  /// once from legacy and still keeps listening to users/.
  Stream<Map<String, num>> kpisStream(String userId, DateTimeRange? range) {
    final usersRef = _summaryRefUsers(userId);
    final legacyRef = _summaryRefProjects(userId);

    return usersRef
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snap) async {
          Map<String, dynamic> chosen = snap.data() ?? const <String, dynamic>{};

          // If users/ is empty, try legacy once
          if (chosen.isEmpty) {
            final legacyDoc = await _serverFirstDoc(legacyRef).catchError((_) => null);
            chosen = legacyDoc?.data() ?? const <String, dynamic>{};
          }

          // Derive pass %
          final passCnt = _toNum(chosen['__ndtPassCnt']);
          final totalCnt = _toNum(chosen['__ndtTotalCnt']);
          final ndtPassPercent = (totalCnt > 0)
              ? (passCnt * 100.0 / totalCnt)
              : _toNum(chosen['ndtPassPercent']);

          // Derive totalWelds from daily if missing/zero
          num totalWelds = _toNum(chosen['totalWelds']);
          if (totalWelds == 0) {
            totalWelds = await _sumDailyWelds(userId, days: 30);
          }

          return _ensureKpiKeys(<String, num>{
            'totalWelds': totalWelds,
            'ndtPassPercent': ndtPassPercent,
            'repairsOpen': _toNum(chosen['repairsOpen']),
          });
        })
        .map(_ensureKpiKeys);
  }

  Map<String, num> _ensureKpiKeys(Map<String, num> m) => {
        'totalWelds': m['totalWelds'] ?? 0,
        'ndtPassPercent': m['ndtPassPercent'] ?? 0,
        'repairsOpen': m['repairsOpen'] ?? 0,
      };

  DocumentReference<Map<String, dynamic>> _summaryRefUsers(String userId) =>
      _db.collection('users').doc(userId).collection('stats').doc('summary');

  DocumentReference<Map<String, dynamic>> _summaryRefProjects(String projectIdCompat) =>
      _db.collection('projects').doc(projectIdCompat).collection('stats').doc('summary');

  // ===========================
  // Charts (VisualizationKpiScreen)
  // ===========================

  /// Last 6 months NDT pass rate (%).
  /// Accepts docs with { month:'YYYY-MM', passPercent:<num> } or { passPct:<num> }.
  Future<List<double>> ndtPassRateLast6Months(String userId) async {
    final usersQ = _db
        .collection('users').doc(userId)
        .collection('stats').doc('ndt').collection('monthly')
        .orderBy('month', descending: true)
        .limit(6);

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _serverFirstQuery(usersQ);
      if (snap.docs.isEmpty) {
        final legacyQ = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('ndt').collection('monthly')
            .orderBy('month', descending: true)
            .limit(6);
        snap = await _serverFirstQuery(legacyQ);
      }
    } catch (_) {
      final legacyQ = _db
          .collection('projects').doc(userId)
          .collection('stats').doc('ndt').collection('monthly')
          .orderBy('month', descending: true)
          .limit(6);
      snap = await _serverFirstQuery(legacyQ);
    }

    final valsDesc = snap.docs.map((d) {
      final m = d.data();
      final pp = _toDouble(m['passPercent']);
      if (pp > 0) return pp;
      return _toDouble(m['passPct']);
    }).toList(growable: false);

    final vals = valsDesc.reversed.toList();
    return _paddedDoubles(vals, 6);
  }

  /// Welds per day — last 7 days.
  /// Primary path: users/{userId}/stats/welds/daily { day:'YYYY-MM-DD', count:<num> }.
  /// Fallback path A: projects/{id}/stats/welds/daily
  /// Fallback path B: projects/{id}/stats/welds_daily/days (legacy 'date' field)
  Future<List<int>> weldsPerDayLast7(String userId) async {
    final usersBase = _db
        .collection('users').doc(userId)
        .collection('stats').doc('welds').collection('daily');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _serverFirstQuery(
        usersBase.orderBy('day', descending: true).limit(7),
      );
      if (snap.docs.isEmpty) {
        final baseA = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('welds').collection('daily');
        snap = await _serverFirstQuery(
          baseA.orderBy('day', descending: true).limit(7),
        );
        if (snap.docs.isEmpty) {
          final baseB = _db
              .collection('projects').doc(userId)
              .collection('stats').doc('welds_daily').collection('days');
          snap = await _serverFirstQuery(
            baseB.orderBy('date', descending: true).limit(7), // legacy uses 'date'
          );
        }
      }
    } catch (_) {
      try {
        final baseA = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('welds').collection('daily');
        snap = await _serverFirstQuery(
          baseA.orderBy('day', descending: true).limit(7),
        );
      } catch (_) {
        final baseB = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('welds_daily').collection('days');
        snap = await _serverFirstQuery(
          baseB.orderBy('date', descending: true).limit(7), // legacy uses 'date'
        );
      }
    }

    final valsDesc = snap.docs.map((d) => _toInt(d.data()['count'])).toList(growable: false);
    final vals = valsDesc.reversed.toList();
    return _paddedInts(vals, 7);
  }

  /// Repairs open vs closed.
  /// Path: users/{userId}/stats/repairs_summary { open:<num>, closed:<num> }.
  Future<Map<String, int>> repairsOpenClosed(
    String userId, {
    DateTime? start,
    DateTime? end,
  }) async {
    final usersRef = _db
        .collection('users').doc(userId)
        .collection('stats').doc('repairs_summary');

    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    Map<String, dynamic> m = const <String, dynamic>{};

    if (usersDoc?.data() != null) {
      m = usersDoc!.data()!;
    } else {
      final legacyDoc = await _serverFirstDoc(
        _db.collection('projects').doc(userId).collection('stats').doc('repairs_summary'),
      ).catchError((_) => null);
      if (legacyDoc?.data() != null) {
        m = legacyDoc!.data()!;
      }
    }

    return <String, int>{
      'Open': _toInt(m['open']),
      'Closed': _toInt(m['closed']),
    };
  }

  /// Average days to close repairs.
  /// Path: users/{userId}/stats/repairs_metrics { avgDaysToClose:<num> }.
  Future<double> avgRepairDaysToClose(
    String userId, {
    DateTime? start,
    DateTime? end,
  }) async {
    final usersRef = _db
        .collection('users').doc(userId)
        .collection('stats').doc('repairs_metrics');

    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    if (usersDoc?.data() != null) {
      return _toDouble(usersDoc!.data()!['avgDaysToClose']);
    }

    final legacyDoc = await _serverFirstDoc(
      _db.collection('projects').doc(userId).collection('stats').doc('repairs_metrics'),
    ).catchError((_) => null);

    return _toDouble(legacyDoc?.data()?['avgDaysToClose']);
  }

  /// Top defects — last 30 days.
  /// Path: users/{userId}/stats/defects_30d { '<defect>': <num> }.
  Future<Map<String, int>> defectBreakdown30d(String userId) async {
    final usersRef = _db
        .collection('users').doc(userId)
        .collection('stats').doc('defects_30d');

    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    if (usersDoc?.data() != null) {
      return _stringIntMap(usersDoc!.data());
    }

    final legacyDoc = await _serverFirstDoc(
      _db.collection('projects').doc(userId).collection('stats').doc('defects_30d'),
    ).catchError((_) => null);

    return _stringIntMap(legacyDoc?.data());
  }

  /// Inspector throughput — last 7 days.
  /// Path: users/{userId}/stats/inspector_7d { '<name>': <num> }.
  Future<Map<String, int>> inspectorThroughput7(String userId) async {
    final usersRef = _db
        .collection('users').doc(userId)
        .collection('stats').doc('inspector_7d');

    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    if (usersDoc?.data() != null) {
      return _stringIntMap(usersDoc!.data());
    }

    final legacyDoc = await _serverFirstDoc(
      _db.collection('projects').doc(userId).collection('stats').doc('inspector_7d'),
    ).catchError((_) => null);

    return _stringIntMap(legacyDoc?.data());
  }

  /// Welder productivity — last 7 days.
  /// Path: users/{userId}/stats/welder_7d { '<name>': <num> }.
  Future<Map<String, int>> welderProductivity7(String userId) async {
    final usersRef = _db
        .collection('users').doc(userId)
        .collection('stats').doc('welder_7d');

    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    if (usersDoc?.data() != null) {
      return _stringIntMap(usersDoc!.data());
    }

    final legacyDoc = await _serverFirstDoc(
      _db.collection('projects').doc(userId).collection('stats').doc('welder_7d'),
    ).catchError((_) => null);

    return _stringIntMap(legacyDoc?.data());
  }

  /// Heat input distribution — last 30 days.
  /// Path: users/{userId}/stats/heat_30d { '<bucket>': <num> }.
  Future<Map<String, int>> heatInputDistribution30d(String userId) async {
    final usersRef = _db
        .collection('users').doc(userId)
        .collection('stats').doc('heat_30d');

    final usersDoc = await _serverFirstDoc(usersRef).catchError((_) => null);
    if (usersDoc?.data() != null) {
      return _stringIntMap(usersDoc!.data());
    }

    final legacyDoc = await _serverFirstDoc(
      _db.collection('projects').doc(userId).collection('stats').doc('heat_30d'),
    ).catchError((_) => null);

    return _stringIntMap(legacyDoc?.data());
  }

  /// Visual inspection accept rate per day — last 30 days (%).
  /// Path: users/{userId}/stats/visual/daily; doc may have:
  ///   - passPercent:<num> OR
  ///   - accepted:<num>, total:<num> (we compute accepted/total*100).
  Future<List<double>> visualAcceptRateLast30d(String userId) async {
    final usersQ = _db
        .collection('users').doc(userId)
        .collection('stats').doc('visual').collection('daily')
        .orderBy('day', descending: true)
        .limit(30);

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _serverFirstQuery(usersQ);
      if (snap.docs.isEmpty) {
        final legacyQ = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('visual').collection('daily')
            .orderBy('day', descending: true)
            .limit(30);
        snap = await _serverFirstQuery(legacyQ);
      }
    } catch (_) {
      final legacyQ = _db
          .collection('projects').doc(userId)
          .collection('stats').doc('visual').collection('daily')
          .orderBy('day', descending: true)
          .limit(30);
      snap = await _serverFirstQuery(legacyQ);
    }

    final valsDesc = snap.docs.map((d) {
      final m = d.data();
      final pp = _toDouble(m['passPercent']);
      if (pp > 0) return pp;
      final acc = _toDouble(m['accepted']);
      final tot = _toDouble(m['total']);
      return (tot > 0) ? (acc / tot) * 100.0 : 0.0;
    }).toList(growable: false);

    final vals = valsDesc.reversed.toList();
    return _paddedDoubles(vals, 30);
  }

  /// Visual inspection accept rate series for last [days] or a custom [range].
  /// Prefers timestamp field 'dayTs'; falls back to string 'day' ('YYYY-MM-DD').
  Future<List<double>> visualAcceptRateSeries(
    String userId, {
    int days = 30,
    DateTimeRange? range,
  }) async {
    final base = _db
        .collection('users').doc(userId)
        .collection('stats').doc('visual').collection('daily');

    Query<Map<String, dynamic>> q;

    if (range != null) {
      q = base
          .where('dayTs', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(range.start)))
          .where('dayTs', isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(range.end)))
          .orderBy('dayTs', descending: true);
    } else {
      q = base.orderBy('dayTs', descending: true).limit(days);
    }

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _serverFirstQuery(q);
    } catch (_) {
      // legacy: projects/{id}/stats/visual/daily
      final legacyBase = _db
          .collection('projects').doc(userId)
          .collection('stats').doc('visual').collection('daily');

      final q2 = (range == null)
          ? legacyBase.orderBy('day', descending: true).limit(days)
          : legacyBase
              .where('day', isGreaterThanOrEqualTo: _fmtDay(range.start))
              .where('day', isLessThanOrEqualTo: _fmtDay(range.end))
              .orderBy('day', descending: true);

      snap = await _serverFirstQuery(q2);
    }

    final valsDesc = snap.docs.map((d) {
      final m = d.data();
      final pp = _toDouble(m['passPercent']);
      if (pp > 0) return pp;
      final acc = _toDouble(m['accepted']);
      final tot = _toDouble(m['total']);
      return (tot > 0) ? (acc / tot) * 100.0 : 0.0;
    }).toList(growable: false);

    final vals = valsDesc.reversed.toList(); // chronological
    final targetLen = range == null ? days : _daysBetweenInclusive(range.start, range.end);
    return _paddedDoubles(vals, targetLen);
  }

  /// Optional: single average accept rate (%) over last [days] or [range].
  Future<double> visualAcceptRateAvg(
    String userId, {
    int days = 30,
    DateTimeRange? range,
  }) async {
    final series = await visualAcceptRateSeries(userId, days: days, range: range);
    if (series.isEmpty) return 0.0;
    final sum = series.fold<double>(0.0, (s, v) => s + v);
    return sum / series.length;
  }

  // ---------- Dashboard helpers (aligned with ReportRepository rollups) ----------

  Future<Map<String, num>> dashboardWeldingKpis(String userId) async {
    // week = sum last 7 daily, today = last point in 7-day series
    final week = await _sumDailyWelds(userId, days: 7);
    final series7 = await weldsPerDayLast7(userId);
    final today = series7.isNotEmpty ? series7.last : 0;

    // top welder from /stats/welder_7d
    num top = 0;
    try {
      final d = await _db
          .collection('users').doc(userId)
          .collection('stats').doc('welder_7d')
          .get(const GetOptions(source: Source.server));
      final m = d.data() ?? const <String, dynamic>{};
      for (final v in m.values) {
        final n = _toNum(v);
        if (n > top) top = n;
      }
    } catch (_) {}

    return {'today': today, 'week': week, 'top': top};
  }

  Future<Map<String, num>> dashboardVisualKpis(String userId) async {
    // inspected = sum of inspector_7d buckets
    num inspected = 0, rejects = 0, topPorosity = 0;
    try {
      final insp = await _db
          .collection('users').doc(userId)
          .collection('stats').doc('inspector_7d')
          .get(const GetOptions(source: Source.server));
      final data = insp.data() ?? const <String, dynamic>{};
      for (final v in data.values) {
        inspected += _toNum(v);
      }
    } catch (_) {}

    try {
      final defects = await _db
          .collection('users').doc(userId)
          .collection('stats').doc('defects_30d')
          .get(const GetOptions(source: Source.server));
      final m = defects.data() ?? const <String, dynamic>{};
      rejects = _toNum(m['Reject']);
      topPorosity = _toNum(m['Porosity']);
    } catch (_) {}

    return {'inspected': inspected, 'rejects': rejects, 'topPorosity': topPorosity};
  }

  Future<Map<String, num>> dashboardNdtKpis(String userId) async {
    final d = await _db
        .collection('users').doc(userId)
        .collection('stats').doc('summary')
        .get(const GetOptions(source: Source.server))
        .catchError((_) => null);

    final m = d.data() ?? const <String, dynamic>{};
    final pass = _toNum(m['__ndtPassCnt']);
    final total = _toNum(m['__ndtTotalCnt']);
    final passPct = (total > 0) ? (pass * 100.0 / total) : 0.0;
    return {'passPct': passPct, 'pending': _toNum(m['ndtPending']), 'total': total};
  }

  Future<Map<String, num>> dashboardRepairsKpis(String userId) async {
    num open = 0, closed = 0, avgDays = 0;
    try {
      final s = await _db
          .collection('users').doc(userId)
          .collection('stats').doc('repairs_summary')
          .get(const GetOptions(source: Source.server));
      final m = s.data() ?? const <String, dynamic>{};
      open = _toNum(m['open']);
      closed = _toNum(m['closed']);
    } catch (_) {}
    try {
      final m = await _db
          .collection('users').doc(userId)
          .collection('stats').doc('repairs_metrics')
          .get(const GetOptions(source: Source.server));
      avgDays = _toNum(m.data()?['avgDaysToClose']);
    } catch (_) {}
    return {'open': open, 'closed': closed, 'avgDays': avgDays};
  }

// Add near other helpers
DocumentReference<Map<String, dynamic>> _weldsDailyDoc(String userId, String day) =>
  _db.collection('users').doc(userId).collection('stats').doc('welds').collection('daily').doc(day);

Stream<Map<String, num>> dashboardWeldingKpisStream(String userId) {
  final summaryRef = _summaryRefUsers(userId);
  final welder7dRef = _db.collection('users').doc(userId).collection('stats').doc('welder_7d');

  return summaryRef.snapshots(includeMetadataChanges: true).asyncMap((_) async {
    // today
    final now = DateTime.now();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final todayId = '$yyyy-$mm-$dd';

    num today = 0, week = 0, top = 0;

    try {
      final td = await _weldsDailyDoc(userId, todayId).get(const GetOptions(source: Source.server));
      today = _toNum(td.data()?['count']);
    } catch (_) {
      final td = await _weldsDailyDoc(userId, todayId).get(const GetOptions(source: Source.cache));
      today = _toNum(td.data()?['count']);
    }

    // sum last 7
    try {
      final q = _db.collection('users').doc(userId)
        .collection('stats').doc('welds').collection('daily')
        .orderBy('day', descending: true).limit(7);
      final snap = await _serverFirstQuery(q);
      for (final d in snap.docs) {
        week += _toNum(d.data()['count']);
      }
    } catch (_) {}

    // top welder
    try {
      final wd = await _serverFirstDoc(welder7dRef);
      final m = wd?.data() ?? const <String, dynamic>{};
      for (final v in m.values) {
        final n = _toNum(v);
        if (n > top) top = n;
      }
    } catch (_) {}

    return <String, num>{'today': today, 'week': week, 'top': top};
  });
}

  // ---------- NEW: visual KPIs STREAM (inspected + top repair reason) ----------
  Stream<Map<String, dynamic>> dashboardVisualKpisStream(String userId) {
    final inspRef =
        _db.collection('users').doc(userId).collection('stats').doc('inspector_7d');
    final reasonsRef =
        _db.collection('users').doc(userId).collection('stats').doc('repairs_reasons_30d');

    // We combine 2 snapshot streams without extra deps by manually listening to both.
    return Stream<Map<String, dynamic>>.multi((controller) {
      Map<String, dynamic>? _lastInsp;
      Map<String, dynamic>? _lastReasons;
      bool _closed = false;

      void emit() {
        if (_closed) return;

        // inspected = sum(instructor_7d values)
        num inspected = 0;
        final insp = _lastInsp ?? const <String, dynamic>{};
        for (final v in insp.values) {
          inspected += _toNum(v);
        }

        // topReason from repairs_reasons_30d (label + count)
        String topReason = '';
        num topCount = 0;
        final reasons = _lastReasons ?? const <String, dynamic>{};
        reasons.forEach((k, v) {
          final n = _toNum(v);
          if (n > topCount) {
            topCount = n;
            topReason = k.toString();
          }
        });

        // rejects (optional): if you track a dedicated 'Reject' bucket in reasons, map it here.
        // Otherwise keep 0; the tile will still show inspected + top reason nicely.
        final rejects = _toNum(reasons['Reject']);

        controller.add(<String, dynamic>{
          'inspected': inspected,
          'rejects': rejects,
          'topReason': topReason,       // label (e.g., Porosity)
          'topReasonCount': topCount,   // how many
        });
      }

      final sub1 = inspRef
          .snapshots(includeMetadataChanges: true)
          .listen((snap) {
        _lastInsp = snap.data();
        emit();
      });

      final sub2 = reasonsRef
          .snapshots(includeMetadataChanges: true)
          .listen((snap) {
        _lastReasons = snap.data();
        emit();
      });

      controller.onCancel = () async {
        _closed = true;
        await sub1.cancel();
        await sub2.cancel();
      };
    });
  }


Stream<Map<String, num>> dashboardNdtKpisStream(String userId) {
  final ref = _summaryRefUsers(userId);
  return ref.snapshots(includeMetadataChanges: true).map((snap) {
    final m = snap.data() ?? const <String, dynamic>{};
    return <String, num>{
      'passPct': _toNum(m['ndtPassPercent'] ?? m['ndtPassPct']),
      'pending': _toNum(m['ndtPending']),
      'total'  : _toNum(m['__ndtTotalCnt'] ?? m['total']),
    };
  });
}

Stream<Map<String, num>> dashboardRepairsKpisStream(String userId) {
  final summaryRef = _db.collection('users').doc(userId).collection('stats').doc('repairs_summary');
  final metricsRef = _db.collection('users').doc(userId).collection('stats').doc('repairs_metrics');

  return summaryRef.snapshots(includeMetadataChanges: true).asyncMap((_) async {
    num open = 0, closed = 0, avgDays = 0;

    try {
      final s = await _serverFirstDoc(summaryRef);
      final m = s?.data() ?? const <String, dynamic>{};
      open   = _toNum(m['open']);
      closed = _toNum(m['closed']);
    } catch (_) {}

    try {
      final m = await _serverFirstDoc(metricsRef);
      avgDays = _toNum(m?.data()?['avgDaysToClose']);
    } catch (_) {}

    return <String, num>{'open': open, 'closed': closed, 'avgDays': avgDays};
  });
}

  // ===========================
  // Helpers (robust + offline-first)
  // ===========================

  Future<DocumentSnapshot<Map<String, dynamic>>?> _serverFirstDoc(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      try {
        return await ref.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _serverFirstQuery(
      Query<Map<String, dynamic>> query) async {
    try {
      return await query.get(const GetOptions(source: Source.server));
    } catch (_) {
      return query.get(const GetOptions(source: Source.cache));
    }
  }

  Map<String, int> _stringIntMap(Map<String, dynamic>? m) {
    if (m == null) return const {};
    final out = <String, int>{};
    m.forEach((k, v) => out[k] = _toInt(v));
    return out;
  }

  // Sum last [days] weld counts from users/{uid}/stats/welds/daily (fallback to legacy).
  Future<int> _sumDailyWelds(String userId, {int days = 30}) async {
    final baseUsers = _db
        .collection('users').doc(userId)
        .collection('stats').doc('welds').collection('daily');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _serverFirstQuery(
        baseUsers.orderBy('day', descending: true).limit(days),
      );
    } catch (_) {
      // legacy A
      try {
        final baseA = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('welds').collection('daily');
        snap = await _serverFirstQuery(
          baseA.orderBy('day', descending: true).limit(days),
        );
      } catch (_) {
        // legacy B (older field name was 'date')
        final baseB = _db
            .collection('projects').doc(userId)
            .collection('stats').doc('welds_daily').collection('days');
        snap = await _serverFirstQuery(
          baseB.orderBy('date', descending: true).limit(days),
        );
      }
    }

    int sum = 0;
    for (final d in snap.docs) {
      sum += _toInt(d.data()['count']);
    }
    return sum;
  }

  // Safe numeric parsing
  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is String) {
      final n = num.tryParse(v.trim());
      return n ?? 0;
    }
    return 0;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    if (v is String) {
      final n = num.tryParse(v.trim());
      return n?.toInt() ?? 0;
    }
    return 0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) {
      final n = num.tryParse(v.trim());
      return (n ?? 0).toDouble();
    }
    return 0.0;
  }

  // Ensure fixed-length series (pads on the left with zeros)
  List<double> _paddedDoubles(List<double> values, int len) {
    if (values.length == len) return values;
    if (values.length > len) return values.sublist(values.length - len);
    return List<double>.filled(len - values.length, 0)..addAll(values);
  }

  List<int> _paddedInts(List<int> values, int len) {
    if (values.length == len) return values;
    if (values.length > len) return values.sublist(values.length - len);
    return List<int>.filled(len - values.length, 0)..addAll(values);
  }

  // Date helpers
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  String _fmtDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  int _daysBetweenInclusive(DateTime a, DateTime b) {
    final start = DateTime(a.year, a.month, a.day);
    final end = DateTime(b.year, b.month, b.day);
    return end.difference(start).inDays + 1;
  }
}
