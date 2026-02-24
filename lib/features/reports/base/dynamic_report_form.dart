// lib/features/reports/base/dynamic_report_form.dart
// FIXED: Properly handles custom fields and labels for export
// ADDED: Photo and Signature management

import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:weldqai_app/core/repositories/report_repository.dart';
import 'package:weldqai_app/core/services/export_service.dart' as exports;
import 'package:weldqai_app/core/services/scan_service.dart';
import 'package:weldqai_app/core/services/formula_engine.dart';
import 'package:weldqai_app/widgets/photo_manager_modal.dart';
import 'package:weldqai_app/widgets/signature_manager_modal.dart';
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/features/reports/widgets/report_action_bar.dart';
import 'package:weldqai_app/features/reports/widgets/report_details_grid.dart';
import 'package:weldqai_app/features/reports/widgets/report_entry_table.dart';

class ReportSnapshot {
  ReportSnapshot({
    required this.reportType,
    required this.reportTypeLabel,
    required this.details,
    required this.rows,
    this.docId,
    this.savedAt,
  });

  final String reportType;
  final String reportTypeLabel;
  final Map<String, String> details;
  final List<Map<String, String>> rows;
  final String? docId;
  final DateTime? savedAt;

  Map<String, dynamic> toJson() => {
        'reportType': reportType,
        'reportTypeLabel': reportTypeLabel,
        'details': details,
        'rows': rows,
        'docId': docId,
        'savedAt': savedAt?.toIso8601String(),
      };

  static ReportSnapshot fromPayload({
    required String reportType,
    required String reportTypeLabel,
    required Map<String, dynamic> payload,
    String? docId,
    DateTime? savedAt,
  }) {
    final det = Map<String, String>.from(payload['details'] ?? const <String, String>{});
    final rows = <Map<String, String>>[];
    final rawRows = payload['rows'];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is Map) {
          rows.add(Map<String, String>.from(r.map((k, v) => MapEntry('$k', '$v'))));
        }
      }
    }
    return ReportSnapshot(
      reportType: reportType,
      reportTypeLabel: reportTypeLabel,
      details: det,
      rows: rows,
      docId: docId,
      savedAt: savedAt,
    );
  }
}

class DynamicReportForm extends StatefulWidget {
  const DynamicReportForm({
    super.key,
    required this.userId,
    required this.reportType,
    required this.reportTypeLabel,
    required this.schema,
    this.defaultMinRows = 5,
    this.scanService,
    this.repo,
    this.onNewReport,
    this.onDetailsChanged,
    this.existingDocId,
    this.initialPayload,
    required reportId,
    this.skipSubscriptionCheck = false,
    this.onSaved,
  });

  final String userId;
  final String reportType;
  final String reportTypeLabel;
  final Map<String, dynamic> schema;
  final int defaultMinRows;

  final ScanService? scanService;
  final ReportRepository? repo;

  final VoidCallback? onNewReport;
  final ValueChanged<Map<String, String>>? onDetailsChanged;

  final String? existingDocId;
  final Map<String, dynamic>? initialPayload;
  final bool skipSubscriptionCheck;
  final void Function(String)? onSaved;

  @override
  State<DynamicReportForm> createState() => DynamicReportFormState();
}

class DynamicReportFormState extends State<DynamicReportForm> {
  final Map<String, TextEditingController> _detailCtrls = {};
  final List<Map<String, TextEditingController>> _rowCtrls = [];
  TextEditingController? _lastFocusedController;
  final _formulaEngine = FormulaEngine();

  String? _docId;
  DateTime? _lastSavedAt;

  int _photoCount = 0;
  bool _hasSignatures = false;

  static const String kStdKey = '__standard';
  String? _selectedStandard;

  List<Map<String, dynamic>> _effectiveDetails = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _effectiveColumns = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    AppLogger.debug('🔍 DynamicReportForm INIT:');
    AppLogger.debug('  Schema details: ${(widget.schema['details'] as List?)?.map((f) => '${f['key']}:${f['label']}').join(', ')}');
    AppLogger.debug('  Schema columns: ${_getColumnsFromSchema().map((c) => '${c['key']}:${c['label']}').join(', ')}');

    _selectedStandard = _initialSelectedStandard();
    _rebuildEffectiveSchema();

    for (final f in _effectiveDetails) {
      final key = (f['key'] ?? '').toString().trim();
      if (key.isNotEmpty) {
        _detailCtrls.putIfAbsent(key, () => TextEditingController());
      }
    }

    _ensureMinRows();
    _docId = widget.existingDocId;

    if (widget.initialPayload != null) {
      _applyPayload(widget.initialPayload!);
    }

    if (_docId != null && widget.initialPayload == null) {
      _loadById(_docId!);
      _loadMediaCounts();
    }
  }

  @override
  void dispose() {
    for (final c in _detailCtrls.values) {
      c.dispose();
    }
    for (final row in _rowCtrls) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  // --- Pure helpers (also used by child widgets via duplication) ------------

  List<String> _uniqueChoices(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in raw.map((e) => e.toString())) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  String? _coerceDropdownValue(String? current, List<String> items) {
    if (current == null || current.isEmpty) return null;
    if (items.contains(current)) return current;
    final i = items.indexWhere((e) => e.toLowerCase() == current.toLowerCase());
    return i >= 0 ? items[i] : null;
  }

  String? _matchStandardKey(String? value, Map standardsMap) {
    if (value == null) return null;
    if (standardsMap.containsKey(value)) return value;
    final lc = value.toLowerCase();
    for (final k in standardsMap.keys) {
      if (k.toString().toLowerCase() == lc) return k.toString();
    }
    return null;
  }

  // --- Schema helpers -------------------------------------------------------

  List<Map<String, dynamic>> _baseDetails() {
    final list = (widget.schema['details'] as List?) ?? const [];
    final allDetails = [for (final f in list.whereType<Map>()) Map<String, dynamic>.from(f)];

    AppLogger.debug('🔍 _baseDetails: Found ${allDetails.length} details in schema');
    for (final d in allDetails) {
      AppLogger.debug('  - ${d['key']}: ${d['label']} (type: ${d['type']}, required: ${d['required']})');
    }

    return allDetails;
  }

  Map<String, dynamic> get _firstTableBase {
    final tables = (widget.schema['tables'] as List?) ?? const [];
    if (tables.isEmpty) return const <String, dynamic>{};
    final t = tables.first;
    return (t is Map) ? Map<String, dynamic>.from(t) : const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _getColumnsFromSchema() {
    final cols = (_firstTableBase['columns'] as List?) ?? const [];
    return [for (final c in cols.whereType<Map>()) Map<String, dynamic>.from(c)];
  }

  String? _initialSelectedStandard() {
    final det = Map<String, dynamic>.from(widget.initialPayload?['details'] ?? const {});
    final fromPayload = det[kStdKey]?.toString().trim();
    if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;
    return null;
  }

  void _rebuildEffectiveSchema() {
    final baseDetails = _baseDetails();
    final baseColumns = _getColumnsFromSchema();

    final stdListRaw = widget.schema['standard'];
    final stdChoices = (stdListRaw is List)
        ? _uniqueChoices(stdListRaw.map((e) => e.toString()).toList())
        : const <String>[];

    _selectedStandard = _coerceDropdownValue(_selectedStandard, stdChoices);

    final effectiveDetails = <Map<String, dynamic>>[];
    if (stdChoices.isNotEmpty) {
      effectiveDetails.add({
        'key': kStdKey,
        'label': 'Standard',
        'type': 'choice',
        'choices': stdChoices,
      });
    }
    effectiveDetails.addAll(baseDetails);

    var effectiveColumns = List<Map<String, dynamic>>.from(baseColumns);

    final standardsMap = (widget.schema['standards'] is Map)
        ? Map<String, dynamic>.from(widget.schema['standards'])
        : const <String, dynamic>{};

    final selectedKey = _matchStandardKey(_selectedStandard, standardsMap);
    if (selectedKey != null) {
      final stdBlock = Map<String, dynamic>.from(standardsMap[selectedKey] ?? const {});
      final stdDetails = (stdBlock['details'] as List?) ?? const [];
      for (final d in stdDetails.whereType<Map>()) {
        effectiveDetails.add(Map<String, dynamic>.from(d));
      }
      final stdTables = (stdBlock['tables'] as List?) ?? const [];
      if (stdTables.isNotEmpty && stdTables.first is Map) {
        final t0 = Map<String, dynamic>.from(stdTables.first as Map);
        final overrides = (t0['columns_overrides'] as Map?) ?? const {};
        if (overrides.isNotEmpty) {
          final patch = Map<String, dynamic>.from(overrides);
          for (int i = 0; i < effectiveColumns.length; i++) {
            final colKey = (effectiveColumns[i]['key'] ?? '').toString();
            if (colKey.isEmpty) continue;
            final colPatchAny = patch[colKey];
            if (colPatchAny is Map) {
              final col = Map<String, dynamic>.from(effectiveColumns[i]);
              col.addAll(Map<String, dynamic>.from(colPatchAny));
              effectiveColumns[i] = col;
            }
          }
        }
      }
    }

    _effectiveDetails = effectiveDetails;
    _effectiveColumns = effectiveColumns;

    AppLogger.debug('🔍 Effective schema rebuilt:');
    AppLogger.debug('  Details: ${_effectiveDetails.map((f) => '${f['key']}:${f['label']}').join(', ')}');
    AppLogger.debug('  Columns: ${_effectiveColumns.map((c) => '${c['key']}:${c['label']}').join(', ')}');
  }

  void _ensureMinRows() {
    final schemaMin = (_firstTableBase['minRows'] is int) ? _firstTableBase['minRows'] as int : null;
    final target = schemaMin ?? widget.defaultMinRows;
    while (_rowCtrls.length < target) {
      _rowCtrls.add({});
    }
  }

  // --- Data loading ---------------------------------------------------------

  void _applyPayload(Map<String, dynamic> payload) {
    final det = Map<String, String>.from(payload['details'] ?? const <String, String>{});

    final stdInPayload = det[kStdKey]?.trim();
    if ((stdInPayload ?? '').isNotEmpty && stdInPayload != _selectedStandard) {
      _selectedStandard = stdInPayload;
      _rebuildEffectiveSchema();

      for (final f in _effectiveDetails) {
        final key = (f['key'] ?? '').toString().trim();
        if (key.isNotEmpty && !_detailCtrls.containsKey(key)) {
          _detailCtrls[key] = TextEditingController();
        }
      }
    }

    det.forEach((k, v) {
      _detailCtrls[k]?.text = v;
    });

    _rowCtrls.clear();
    final rawRows = payload['rows'];
    if (rawRows is List) {
      for (final r in rawRows) {
        final row = <String, TextEditingController>{};
        if (r is Map) {
          for (final c in _effectiveColumns) {
            final key = (c['key'] ?? '').toString();
            if (key.isEmpty) continue;
            row[key] = TextEditingController(text: '${r[key] ?? ''}');
          }
        }
        _rowCtrls.add(row);
      }
    }

    if (_rowCtrls.isEmpty) _ensureMinRows();
    if (mounted) setState(() {});
  }

  // --- Formula engine -------------------------------------------------------

  void _calculateFormulas() {
    for (final field in _effectiveDetails) {
      final key = (field['key'] ?? '').toString();
      final type = (field['type'] ?? '').toString();

      if (type == 'calculated' && field['formula'] != null) {
        final formula = field['formula'].toString();
        final dependencies = (field['dependencies'] as List?)?.cast<String>() ?? [];

        final data = <String, dynamic>{};
        for (final dep in dependencies) {
          final ctrl = _detailCtrls[dep];
          if (ctrl != null) {
            final value = double.tryParse(ctrl.text);
            if (value != null) {
              data[dep] = value;
            }
          }
        }

        final result = _formulaEngine.evaluate(formula, data);
        if (result != null && result.isFinite) {
          final decimals = field['decimals'] as int?;
          final formatted = decimals != null
              ? result.toStringAsFixed(decimals)
              : _fmt(result);
          _detailCtrls[key]?.text = formatted;
        }
      }
    }

    for (int r = 0; r < _rowCtrls.length; r++) {
      _calculateRowFormulas(r);
    }
  }

  void _calculateRowFormulas(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rowCtrls.length) return;
    final row = _rowCtrls[rowIndex];

    for (final col in _effectiveColumns) {
      final key = (col['key'] ?? '').toString();
      final type = (col['type'] ?? '').toString();

      if (type == 'calculated' && col['formula'] != null) {
        final formula = col['formula'].toString();
        final dependencies = (col['dependencies'] as List?)?.cast<String>() ?? [];

        final data = <String, dynamic>{};
        for (final dep in dependencies) {
          final ctrl = row[dep];
          if (ctrl != null) {
            final value = double.tryParse(ctrl.text);
            if (value != null) {
              data[dep] = value;
            }
          }
        }

        final result = _formulaEngine.evaluate(formula, data);
        if (result != null && result.isFinite) {
          final decimals = col['decimals'] as int?;
          final formatted = decimals != null
              ? result.toStringAsFixed(decimals)
              : _fmt(result);
          row[key]?.text = formatted;
        }
      }
    }
  }

  String _fmt(num v) {
    final s = v.toStringAsFixed(3);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  // --- Branding & export helpers --------------------------------------------

  Future<exports.ExportServiceBrandingConfig> _loadBranding() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final db = FirebaseFirestore.instance;

      String companyName = '';
      String companyLogoUrl = '';
      String clientName = '';
      String clientLogoUrl = '';

      if (uid != null) {
        final u = await db.collection('users').doc(uid).collection('profile').doc('info').get();
        final d = u.data() ?? <String, dynamic>{};
        companyName = (d['company'] ?? '').toString();
        companyLogoUrl = (d['companyLogoUrl'] ?? '').toString();
        clientName = (d['clientName'] ?? '').toString();
        clientLogoUrl = (d['clientLogoUrl'] ?? '').toString();
      }

      Future<Uint8List?> bytes(String url) async {
        if (url.isEmpty) return null;
        try {
          return await FirebaseStorage.instance.refFromURL(url).getData(8 * 1024 * 1024);
        } catch (_) {
          try {
            return await FirebaseStorage.instance.ref(url).getData(8 * 1024 * 1024);
          } catch (_) {
            return null;
          }
        }
      }

      final leftBytes = await bytes(companyLogoUrl);
      final rightBytes = await bytes(clientLogoUrl);

      final s = snapshot();
      final metaRows = <List<String>>[];
      void addKV(String k, String? v) {
        final val = (v ?? '').trim();
        if (val.isNotEmpty) metaRows.add([k, val]);
      }
      addKV('Project', s.details['project'] ?? s.details['project_title'] ?? s.details['projectTitle']);
      addKV('Client', clientName.isNotEmpty ? clientName : s.details['client']);
      addKV('Document/Spec', s.details['document_spec'] ?? s.details['document_no'] ?? s.details['doc_no']);
      addKV('Date', s.details['date']);
      addKV('Shift', s.details['shift']);

      return exports.ExportServiceBrandingConfig(
        leftLogoBytes: leftBytes,
        rightLogoBytes: rightBytes,
        leftLogoUrl: companyLogoUrl,
        rightLogoUrl: clientLogoUrl,
        headerTitle: widget.reportTypeLabel,
        headerSubtitle: companyName,
        footerLeft: companyName.trim().isNotEmpty ? companyName : 'Generated by WeldQAi',
        footerRight: 'Page',
        metaRows: metaRows.take(8).toList(),
      );
    } catch (_) {
      return const exports.ExportServiceBrandingConfig(metaRows: <List<String>>[]);
    }
  }

  Future<void> _loadById(String docId) async {
    final repo = widget.repo;
    if (repo == null) return;
    try {
      final items = await repo.listItems(
        userId: widget.userId,
        schemaId: widget.reportType,
        limit: 50,
      );
      final one = items.firstWhere((e) => (e['id'] ?? '') == docId, orElse: () => const {});
      if (one.isEmpty) return;
      final payload = (one['payload'] is Map)
          ? Map<String, dynamic>.from(one['payload'])
          : <String, dynamic>{};
      if (!mounted) return;
      _applyPayload(payload);
    } catch (_) {}
  }

  Future<void> _loadMediaCounts() async {
    if (_docId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('reports')
          .doc(widget.reportType)
          .collection('items')
          .doc(_docId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        final photos = (data['photos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _photoCount = photos.length;

        final sigs = data['signatures'] as Map<String, dynamic>?;
        _hasSignatures = sigs != null &&
            (sigs['contractor']?['imageUrl'] != null ||
             sigs['client']?['imageUrl'] != null);

        if (mounted) setState(() {});
      }
    } catch (e) {
      AppLogger.error('Error loading media counts: $e');
    }
  }

  // --- Snapshot / export data -----------------------------------------------

  ReportSnapshot snapshot() {
    final det = <String, String>{};
    _detailCtrls.forEach((k, v) => det[k] = v.text);

    final rows = <Map<String, String>>[];
    for (final row in _rowCtrls) {
      final m = <String, String>{};
      for (final c in _effectiveColumns) {
        final k = (c['key'] ?? '').toString();
        if (k.isEmpty) continue;
        m[k] = row[k]?.text ?? '';
      }
      rows.add(m);
    }

    return ReportSnapshot(
      reportType: widget.reportType,
      reportTypeLabel: widget.reportTypeLabel,
      details: det,
      rows: rows,
      docId: _docId,
      savedAt: _lastSavedAt,
    );
  }

  Map<String, dynamic> snapshotWithLabels() {
    final det = <String, String>{};
    final detailLabels = <String, String>{};

    _detailCtrls.forEach((k, v) {
      det[k] = v.text;

      String? foundLabel;
      for (final field in _effectiveDetails) {
        if ((field['key'] ?? '').toString() == k) {
          foundLabel = (field['label'] ?? k).toString();
          break;
        }
      }

      detailLabels[k] = foundLabel ?? k;
    });

    final rows = <Map<String, String>>[];
    final columnLabels = <String, String>{};

    for (final c in _effectiveColumns) {
      final k = (c['key'] ?? '').toString();
      if (k.isEmpty) continue;
      columnLabels[k] = (c['label'] ?? k).toString();
    }

    for (final row in _rowCtrls) {
      final m = <String, String>{};
      for (final c in _effectiveColumns) {
        final k = (c['key'] ?? '').toString();
        if (k.isEmpty) continue;
        m[k] = row[k]?.text ?? '';
      }
      rows.add(m);
    }

    AppLogger.debug('📊 Export snapshot created:');
    AppLogger.debug('  Detail labels: ${detailLabels.length} (${detailLabels.keys.take(5).join(', ')}...)');
    AppLogger.debug('  Column labels: ${columnLabels.length} (${columnLabels.keys.take(5).join(', ')}...)');

    return {
      'reportType': widget.reportType,
      'reportTypeLabel': widget.reportTypeLabel,
      'userId': widget.userId,
      'details': det,
      'detailLabels': detailLabels,
      'rows': rows,
      'columnLabels': columnLabels,
      'docId': _docId,
      'savedAt': _lastSavedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _excelConfig() {
    final detailsOrder = <String>[
      for (final f in _effectiveDetails)
        if ((f['key'] ?? '').toString().trim().isNotEmpty)
          (f['key'] as Object).toString().trim(),
    ];

    final cols = [
      for (final c in _effectiveColumns)
        {
          'key': (c['key'] ?? '').toString(),
          'label': (c['label'] ?? c['key'] ?? '').toString(),
          if (c['width'] is num) 'width': (c['width'] as num).toDouble(),
        }
    ];

    const standardKeys = [
      'document_no',
      'job_no',
      'report_no',
      'date',
      'shift',
      'project',
      'client',
      'location',
      'worksite',
      'wps_no',
      'weld_no',
    ];

    return {
      'detailsOrder': detailsOrder,
      'detailsPairsPerRow': widget.reportType.toLowerCase().contains('welding') ? 3 : 2,
      'detailsPairWidths': [14, 18, 14, 18, 14, 18],
      'table': {'columns': cols},
      'standardKeys': standardKeys,
    };
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _handleSave() async {
    final missingRequired = <String>[];

    for (final field in _effectiveDetails) {
      final key = (field['key'] ?? '').toString();
      final label = (field['label'] ?? key).toString();
      final isRequired = field['required'] == true;

      if (isRequired) {
        final value = _detailCtrls[key]?.text ?? '';
        if (value.trim().isEmpty) {
          missingRequired.add(label);
        }
      }
    }

    if (missingRequired.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Required fields missing: ${missingRequired.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final repo = widget.repo;
    final s = snapshot();

    if (repo == null) {
      _lastSavedAt = DateTime.now();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved locally @ ${_lastSavedAt!.toLocal()}')),
        );
        setState(() {});
      }
      return;
    }

    final id = await repo.saveReport(
      userId: widget.userId,
      schemaId: widget.reportType,
      payload: {'details': s.details, 'rows': s.rows},
      reportId: _docId,
      skipSubscriptionCheck: widget.skipSubscriptionCheck,
    );

    _docId = id;
    _lastSavedAt = DateTime.now();
    await _loadMediaCounts();

    widget.onSaved?.call(id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved @ ${_lastSavedAt!.toLocal()}')),
      );
      setState(() {});
    }
  }

  Future<void> _handleExportPdf() async {
    final m = snapshotWithLabels();
    m['excel'] = _excelConfig();
    final branding = await _loadBranding();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await exports.ExportService.exportPdfSimple(
      context: context,
      title: widget.reportTypeLabel,
      reports: [m],
      branding: branding,
    );
  }

  Future<void> _handleExportExcel() async {
    final m = snapshotWithLabels();
    m['excel'] = _excelConfig();
    final branding = await _loadBranding();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await exports.ExportService.exportExcelSimpleExcelPkg(
      context: context,
      title: widget.reportTypeLabel,
      reports: [m],
      branding: branding,
    );
  }

  void _handleStandardChanged(String? v) {
    _selectedStandard = v;
    setState(() {
      _rebuildEffectiveSchema();
      for (final d in _effectiveDetails) {
        final dk = (d['key'] ?? '').toString().trim();
        if (dk.isNotEmpty && !_detailCtrls.containsKey(dk)) {
          _detailCtrls[dk] = TextEditingController();
        }
      }
    });
    _notifyDetails();
  }

  void _showPhotoManager() {
    if (_docId == null) {
      _snack('Please save the report first');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => PhotoManagerModal(
        reportId: _docId!,
        userId: widget.userId,
        schemaId: widget.reportType,
      ),
    ).then((_) => _loadMediaCounts());
  }

  void _showSignatureManager() {
    if (_docId == null) {
      _snack('Please save the report first');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SignatureManagerModal(
        reportId: _docId!,
        userId: widget.userId,
        schemaId: widget.reportType,
      ),
    ).then((_) => _loadMediaCounts());
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _insertIntoActiveField(String text, {bool append = false}) {
    final controller = _lastFocusedController;

    if (controller == null) {
      _snack('Please tap a field first');
      return;
    }

    if (append) {
      controller.text = controller.text + text;
    } else {
      controller.text = text;
    }

    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    _checkAndRecomputeIfNeeded(controller);

    setState(() {});
    _notifyDetails();
  }

  void _checkAndRecomputeIfNeeded(TextEditingController ctrl) {
    for (final entry in _detailCtrls.entries) {
      if (entry.value == ctrl) {
        _calculateFormulas();
        return;
      }
    }

    for (int r = 0; r < _rowCtrls.length; r++) {
      for (final entry in _rowCtrls[r].entries) {
        if (entry.value == ctrl) {
          _calculateRowFormulas(r);
          return;
        }
      }
    }
  }

  Future<void> _handleScanPicker() async {
    final svc = widget.scanService;
    if (svc == null) return _snack('Scan not available');

    if (_lastFocusedController == null) {
      _snack('Please tap a field first');
      return;
    }

    final text = await svc.scanPicker(context, title: 'Scan');
    if (text == null || text.isEmpty) return;

    _insertIntoActiveField(text);
    _snack('Scanned: $text');
  }

  Future<void> _handleScanOcr() async {
    final svc = widget.scanService;
    if (svc == null) return _snack('OCR not available');

    if (_lastFocusedController == null) {
      _snack('Please tap a field first');
      return;
    }

    final text = await svc.scanText(context, title: 'OCR');
    if (text == null || text.isEmpty) return;

    _insertIntoActiveField(text, append: true);
    _snack('OCR text added');
  }

  void _notifyDetails() {
    final cb = widget.onDetailsChanged;
    if (cb == null) return;
    final map = <String, String>{};
    _detailCtrls.forEach((k, v) => map[k] = v.text);
    cb(map);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportActionBar(
              docId: _docId,
              lastSavedAt: _lastSavedAt,
              photoCount: _photoCount,
              hasSignatures: _hasSignatures,
              onSave: () => unawaited(_handleSave()),
              onExportPdf: () => unawaited(_handleExportPdf()),
              onExportExcel: () => unawaited(_handleExportExcel()),
              onScanPicker: () => unawaited(_handleScanPicker()),
              onScanOcr: () => unawaited(_handleScanOcr()),
              onPhotos: _showPhotoManager,
              onSignatures: _showSignatureManager,
            ),
            ReportDetailsGrid(
              effectiveDetails: _effectiveDetails,
              detailCtrls: _detailCtrls,
              selectedStandard: _selectedStandard,
              onStandardChanged: _handleStandardChanged,
              onDetailsChanged: _notifyDetails,
              onFocus: (ctrl) => _lastFocusedController = ctrl,
              onRecalculate: _calculateFormulas,
            ),
            const SizedBox(height: 16),
            ReportEntryTable(
              effectiveColumns: _effectiveColumns,
              rowCtrls: _rowCtrls,
              onFocus: (ctrl) => _lastFocusedController = ctrl,
              onAddRow: () => setState(() => _rowCtrls.add({})),
              onDeleteRow: (r) => setState(() {
                final removed = _rowCtrls.removeAt(r);
                for (final ctrl in removed.values) {
                  ctrl.dispose();
                }
              }),
              onRowRecalculate: _calculateRowFormulas,
              onNewReport: widget.onNewReport,
            ),
          ],
        ),
      ),
    );
  }
}
