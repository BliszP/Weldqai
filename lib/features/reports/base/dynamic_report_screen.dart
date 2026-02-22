// lib/features/reports/base/dynamic_report_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:weldqai_app/core/services/scan_service.dart';
import 'package:weldqai_app/core/repositories/report_repository.dart';
import 'package:weldqai_app/features/reports/base/multi_report_accordion.dart';
// ❌ REMOVE THIS: import 'package:weldqai_app/features/reports/widgets/template_upload_button.dart';

class DynamicReportScreen extends StatefulWidget {
  const DynamicReportScreen({
    super.key,
    required this.userId,
    required this.schemaId,
    required this.schemaTitle,
    this.defaultMinRowsOverride,
    this.reportId,
  });

  final String userId;
  final String schemaId;
  final String schemaTitle;
  final int? defaultMinRowsOverride;
  final String? reportId;

  @override
  State<DynamicReportScreen> createState() => _DynamicReportScreenState();
}

class _DynamicReportScreenState extends State<DynamicReportScreen> {
  late final ScanService _scan;
  late final ReportRepository _repo;
  late Future<Map<String, dynamic>> _futureSchema;

  @override
  void initState() {
    super.initState();
    _scan = ScanService();
    _repo = ReportRepository();
    _futureSchema = _loadSchema(widget.schemaId, widget.schemaTitle);
  }

  Future<Map<String, dynamic>> _loadSchema(String id, String fallbackTitle) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('custom_schemas')
            .doc(id)
            .get();

        if (doc.exists) {
          final data = doc.data();
          final schemaAny = data?['schema'];
          if (schemaAny is Map<String, dynamic>) {
            return _ensureValid(schemaAny, fallbackTitle);
          }
          if (schemaAny is Map) {
            return _ensureValid(Map<String, dynamic>.from(schemaAny), fallbackTitle);
          }
        }
      }
    } catch (_) {}

    final path = 'assets/schemas/$id.json';
    try {
      final raw = await rootBundle.loadString(path);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return _ensureValid(decoded, fallbackTitle);
      if (decoded is Map) return _ensureValid(Map<String, dynamic>.from(decoded), fallbackTitle);
    } catch (_) {}

    return _fallback(fallbackTitle);
  }

  Map<String, dynamic> _ensureValid(Map<String, dynamic> s, String title) {
    final m = Map<String, dynamic>.from(s);
    if (m['details'] is! List) {
      m['details'] = [
        {'key': 'date', 'label': 'Date', 'type': 'date'},
        {'key': 'shift', 'label': 'Shift', 'type': 'dropdown', 'options': ['Day', 'Night']},
        {'key': 'document_no', 'label': 'Document No.'},
      ];
    }
    if (m['tables'] is! List || (m['tables'] as List).isEmpty) {
      m['tables'] = [
        {
          'columns': [
            {'key': 'col1', 'label': 'Col 1', 'type': 'text', 'width': 140},
            {'key': 'col2', 'label': 'Col 2', 'type': 'number', 'width': 140},
          ],
          'minRows': 5,
        }
      ];
    }
    m['title'] ??= title;
    return m;
  }

  Map<String, dynamic> _fallback(String title) => {
        'title': title,
        'details': [
          {'key': 'date', 'label': 'Date', 'type': 'date'},
          {'key': 'shift', 'label': 'Shift', 'type': 'dropdown', 'options': ['Day', 'Night']},
          {'key': 'document_no', 'label': 'Document No.'},
        ],
        'tables': [
          {
            'columns': [
              {'key': 'col1', 'label': 'Col 1', 'type': 'text', 'width': 140},
              {'key': 'col2', 'label': 'Col 2', 'type': 'number', 'width': 140},
            ],
            'minRows': 5,
          }
        ],
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _futureSchema,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final schema = snap.data ?? _fallback(widget.schemaTitle);

        return Scaffold(
          appBar: AppBar(title: Text(widget.schemaTitle)),
          body: MultiReportAccordion(
            userId: widget.userId,
            reportType: widget.schemaId,
            reportTypeLabel: widget.schemaTitle,
            schema: schema,
            defaultMinRowsOverride: widget.defaultMinRowsOverride,
            scanService: _scan,
            repo: _repo,
            reportId: widget.reportId,
          ),
          // ❌ REMOVED: floatingActionButton
          // ❌ REMOVED: floatingActionButtonLocation
        );
      },
    );
  }
}