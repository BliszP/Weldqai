// lib/features/reports/base/dynamic_report_form.dart
// FIXED: Properly handles custom fields and labels for export
// ADDED: Photo and Signature management


import 'dart:math' as math;
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
    this.skipSubscriptionCheck = false,  // ✅ NEW
    this.onSaved,  // ✅ NEW
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
  final bool skipSubscriptionCheck;  // ✅ NEW: Bypass subscription if true
  final void Function(String)? onSaved;  // ✅ NEW: Called after save with document ID

  @override
  State<DynamicReportForm> createState() => DynamicReportFormState();
}

class DynamicReportFormState extends State<DynamicReportForm> {
  final Map<String, TextEditingController> _detailCtrls = {};
  final List<Map<String, TextEditingController>> _rowCtrls = [];
  final ScrollController _hCtrl = ScrollController();
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
    _hCtrl.dispose();
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
      'userId': widget.userId, // ✅ ADD THIS LINE
      'details': det,
      'detailLabels': detailLabels,
      'rows': rows,
      'columnLabels': columnLabels,
      'docId': _docId,
      'savedAt': _lastSavedAt?.toIso8601String(),
    };
  }

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
    skipSubscriptionCheck: widget.skipSubscriptionCheck,  // ✅ NEW: Pass flag from parent
  );

  _docId = id;
  _lastSavedAt = DateTime.now();
  await _loadMediaCounts();
  
  // ✅ NEW: Notify parent after save
  widget.onSaved?.call(id);
  
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved @ ${_lastSavedAt!.toLocal()}')),
    );
    setState(() {});
  }
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

  Widget _detailsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final avail = constraints.maxWidth;
        
        final minField = avail < 600 ? 120.0 : 150.0;
        
        final cols = math.max(1, ((avail + gap) / (minField + gap)).floor());
        final cellW = (avail - (cols - 1) * gap) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final f in _effectiveDetails)
              if ((f['key'] ?? '').toString().trim().isNotEmpty)
                SizedBox(width: cellW, child: _detailField(f)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = _effectiveColumns;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Scan',
            icon: const Icon(Icons.document_scanner),
            onSelected: (v) async {
              if (v == 'picker') await _handleScanPicker();
              if (v == 'ocr') await _handleScanOcr();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'picker',
                child: Row(children: [
                  Icon(Icons.center_focus_strong, size: 18),
                  SizedBox(width: 8),
                  Text('Scan')
                ]),
              ),
              PopupMenuItem(
                value: 'ocr',
                child: Row(children: [
                  Icon(Icons.text_fields, size: 18),
                  SizedBox(width: 8),
                  Text('OCR')
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _handleSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Export',
            onSelected: (v) async {
              final m = snapshotWithLabels();
              m['excel'] = _excelConfig();
              final branding = await _loadBranding();
              if (!context.mounted) return;

              if (v == 'pdf') {
                // ignore: use_build_context_synchronously
                await exports.ExportService.exportPdfSimple(
                  context: context,
                  title: widget.reportTypeLabel,
                  reports: [m],
                  branding: branding,
                );
              } else if (v == 'xlsx') {
                // ignore: use_build_context_synchronously
                await exports.ExportService.exportExcelSimpleExcelPkg(
                  context: context,
                  title: widget.reportTypeLabel,
                  reports: [m],
                  branding: branding,
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
            ],
            child: const Icon(Icons.ios_share),
          ),
          const SizedBox(width: 8),
          
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.camera_alt),
                if (_photoCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Colors.blue,
                      child: Text(
                        '$_photoCount',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Photos',
            onPressed: _showPhotoManager,
          ),
          
          IconButton(
            icon: Icon(
              Icons.draw,
              color: _hasSignatures ? Colors.blue : null,
            ),
            tooltip: 'Signatures',
            onPressed: _showSignatureManager,
          ),
          
          const Spacer(),
          if (_lastSavedAt != null)
            Text(
              'Saved: ${_lastSavedAt!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );

    final detailsWrap = _detailsGrid();

    final entries = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entries', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Scrollbar(
          controller: _hCtrl,
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _hCtrl,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(
                  700,
                  columns.fold<double>(0.0, (w, c) {
                    final cw = (c['width'] is num) ? (c['width'] as num).toDouble() : 140.0;
                    return w + cw + 12.0;
                  }),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final c in columns)
                        SizedBox(
                          width: (c['width'] is num) ? (c['width'] as num).toDouble() : 140.0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Text(
                              (c['label'] ?? c['key'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const Divider(height: 1),

                  for (int r = 0; r < _rowCtrls.length; r++)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in columns)
                          SizedBox(
                            width: (c['width'] is num) ? (c['width'] as num).toDouble() : 140.0,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: _cellEditor(r, c),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove row',
                          onPressed: () {
                            setState(() {
                              final removed = _rowCtrls.removeAt(r);
                              for (final ctrl in removed.values) {
                                ctrl.dispose();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _rowCtrls.add({})),
              icon: const Icon(Icons.add),
              label: const Text('Add Row'),
            ),
            if (widget.onNewReport != null)
              TextButton.icon(
                onPressed: widget.onNewReport,
                icon: const Icon(Icons.add_to_photos_outlined),
                label: const Text('Add Report'),
              ),
          ],
        ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          detailsWrap,
          const SizedBox(height: 16),
          entries,
        ],
      ),
    );

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus
        },
      ),
      child: content,
    );
  }

  InputDecoration _detailDecoration(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelText: label,
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2D31) : Colors.white,
      labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : null),
    );
  }

  InputDecoration _cellDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2D31) : Colors.white,
    );
  }

  Widget _detailField(Map f) {
    final key = ((f['key'] ?? '') as Object).toString().trim();
    if (key.isEmpty) return const SizedBox.shrink();

    final label = (f['label'] ?? key).toString();
    final type = (f['type'] ?? 'text').toString().toLowerCase();
    final isRequired = f['required'] == true;

    final ctrl = _detailCtrls.putIfAbsent(key, () => TextEditingController());
    
    final displayLabel = isRequired ? '$label *' : label;

    if (key == kStdKey) {
      final itemsRaw = (f['choices'] ?? f['options'] ?? const []) as List;
      final items = _uniqueChoices(itemsRaw.map((e) => e.toString()).toList());

      final want = ctrl.text.isEmpty ? _selectedStandard : ctrl.text;
      final safeValue = _coerceDropdownValue(want, items);
      if (safeValue != (_selectedStandard ?? '')) _selectedStandard = safeValue;
      if (safeValue != ctrl.text) ctrl.text = safeValue ?? '';

      return DropdownButtonFormField<String>(
        isExpanded: true,
        value: safeValue,
        items: [
          for (final v in items)
            DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          _selectedStandard = v;
          ctrl.text = v ?? '';
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
        },
        decoration: _detailDecoration(displayLabel),
      );
    }

    if (type == 'calculated') {
      final formula = f['formula']?.toString();
      final unit = f['unit']?.toString();
      
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _detailDecoration(displayLabel).copyWith(
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unit != null && unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(unit, style: const TextStyle(fontSize: 12)),
                ),
              const Icon(Icons.calculate, size: 20),
            ],
          ),
          helperText: formula != null ? 'Formula: $formula' : null,
          helperMaxLines: 2,
        ),
        style: TextStyle(
          color: Colors.blue[700],
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (type == 'dropdown' || type == 'choice') {
      final raw = (f['options'] ?? f['choices'] ?? const []) as List;
      final items = _uniqueChoices(raw.map((e) => e.toString()).toList());

      if (items.isEmpty) {
        return TextFormField(
          controller: ctrl,
          onTap: () => _lastFocusedController = ctrl,
          decoration: _detailDecoration(displayLabel),
          onChanged: (_) => _notifyDetails(),
        );
      }

      final safeValue = _coerceDropdownValue(ctrl.text, items);
      if (safeValue != ctrl.text) ctrl.text = safeValue ?? '';

      return DropdownButtonFormField<String>(
        isExpanded: true,
        value: safeValue,
        items: [
          for (final v in items)
            DropdownMenuItem(
              value: v,
              child: Text(v, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          ctrl.text = v ?? '';
          setState(() {});
          _notifyDetails();
        },
        decoration: _detailDecoration(displayLabel),
      );
    }

    if (type == 'date') {
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _detailDecoration(displayLabel).copyWith(
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(now.year - 10),
            lastDate: DateTime(now.year + 10),
          );
          if (picked != null) {
            final s = '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}';
            setState(() => ctrl.text = s);
            _notifyDetails();
          }
        },
      );
    }

    if (type == 'number') {
      final unit = f['unit']?.toString();
      final decimals = f['decimals'] as int?;
      
      return TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        onTap: () => _lastFocusedController = ctrl,
        decoration: _detailDecoration(displayLabel).copyWith(
          suffixText: unit,
          helperText: decimals != null ? 'Decimals: $decimals' : null,
        ),
        onChanged: (_) {
          _calculateFormulas();
          _notifyDetails();
        },
      );
    }

    if (type == 'textarea') {
      return TextFormField(
        controller: ctrl,
        maxLines: 3,
        onTap: () => _lastFocusedController = ctrl,
        decoration: _detailDecoration(displayLabel),
        onChanged: (_) => _notifyDetails(),
      );
    }

    return TextFormField(
      controller: ctrl,
      onTap: () => _lastFocusedController = ctrl,
      decoration: _detailDecoration(displayLabel),
      onChanged: (_) {
        _calculateFormulas();
        _notifyDetails();
      },
    );
  }

  Widget _cellEditor(int rowIndex, Map<String, dynamic> col) {
    final key = (col['key'] ?? '').toString();
    if (key.isEmpty) return const SizedBox.shrink();

    final type = (col['type'] ?? 'text').toString().toLowerCase();
    final ctrl = _rowCtrls[rowIndex].putIfAbsent(key, () => TextEditingController());

    if (type == 'calculated') {
      final unit = col['unit']?.toString();
      
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _cellDecoration(context).copyWith(
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unit != null && unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(unit, style: const TextStyle(fontSize: 10)),
                ),
              const Icon(Icons.calculate, size: 16),
            ],
          ),
        ),
        style: TextStyle(
          color: Colors.blue[700],
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      );
    }

    if (type == 'dropdown' || type == 'choice') {
      final raw = (col['options'] ?? col['choices'] ?? const []) as List;
      final items = _uniqueChoices(raw.map((e) => e.toString()).toList());

      if (items.isEmpty) {
        return TextFormField(
          controller: ctrl,
          onTap: () => _lastFocusedController = ctrl,
          onChanged: (_) {
            _calculateRowFormulas(rowIndex);
            setState(() {});
          },
          decoration: _cellDecoration(context),
        );
      }

      final safeValue = _coerceDropdownValue(ctrl.text, items);
      if (safeValue != ctrl.text) ctrl.text = safeValue ?? '';

      return DropdownButtonFormField<String>(
        isExpanded: true,
        value: safeValue,
        items: [
          for (final v in items)
            DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          ctrl.text = v ?? '';
          _calculateRowFormulas(rowIndex);
          setState(() {});
        },
        decoration: _cellDecoration(context),
      );
    }

    if (type == 'date') {
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _cellDecoration(context).copyWith(
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(now.year - 10),
            lastDate: DateTime(now.year + 10),
          );
          if (picked != null) {
            final s = '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}';
            setState(() => ctrl.text = s);
          }
        },
      );
    }

    final keyboard = (type == 'number') ? TextInputType.number : TextInputType.text;
    
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      readOnly: type == 'calculated',
      onTap: () => _lastFocusedController = ctrl,
      onChanged: (_) {
        _calculateRowFormulas(rowIndex);
        setState(() {});
      },
      decoration: _cellDecoration(context),
    );
  }

String _fmt(num v) {
    final s = v.toStringAsFixed(3);
    // remove trailing zeros and optionally the decimal point if no fractional part remains
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
  void _notifyDetails() {
    final cb = widget.onDetailsChanged;
    if (cb == null) return;
    final map = <String, String>{};
    _detailCtrls.forEach((k, v) => map[k] = v.text);
    cb(map);
  }
}