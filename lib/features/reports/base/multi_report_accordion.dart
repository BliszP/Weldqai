// lib/features/reports/base/multi_report_accordion.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:weldqai_app/core/repositories/report_repository.dart';
import 'package:weldqai_app/core/services/export_service.dart' as exports;
import 'package:weldqai_app/core/services/scan_service.dart';
import 'package:weldqai_app/features/reports/base/dynamic_report_form.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class MultiReportAccordion extends StatefulWidget {
  const MultiReportAccordion({
    super.key,
    required this.userId, // CHANGED: from projectId to userId
    required this.reportType,
    required this.reportTypeLabel,
    required this.schema,
    this.defaultMinRowsOverride,
    this.scanService,
    this.repo,
    this.reportId,
  });

  final String userId; // CHANGED
  final String reportType;
  final String reportTypeLabel;
  final Map<String, dynamic> schema;
  final int? defaultMinRowsOverride;
  final ScanService? scanService;
  final ReportRepository? repo;
  final String? reportId; // ✅ FIX: This was "get reportId => null;" - now it's a proper field

  @override
  State<MultiReportAccordion> createState() => _MultiReportAccordionState();
}

class _ReportMeta {
  _ReportMeta({
    required this.key,
    required this.isExpanded,
    this.itemId,
    Map<String, String>? summary,
    this.initialPayload,
    this.skipSubscriptionCheck = false,  // ✅ NEW
  }) : summary = summary ?? <String, String>{};

  final GlobalKey<DynamicReportFormState> key;
  bool isExpanded;
  String? itemId;
  Map<String, String> summary;
  Map<String, dynamic>? initialPayload;
  bool skipSubscriptionCheck;  // ✅ NEW: If true, bypass subscription checks
}

class _MultiReportAccordionState extends State<MultiReportAccordion> {
  final List<_ReportMeta> _panes = <_ReportMeta>[];

  int get _defaultMinRows {
    if (widget.defaultMinRowsOverride != null) return widget.defaultMinRowsOverride!;
    final slug = widget.reportType.toLowerCase();
    return (slug.contains('welding') && slug.contains('param')) ? 4 : 5;
  }

  @override
  void initState() {
    super.initState();
    _loadExistingPanels();
  }

  Future<void> _loadExistingPanels() async {
    final repo = widget.repo;
    if (repo == null) {
      _panes.add(_ReportMeta(key: GlobalKey<DynamicReportFormState>(), isExpanded: true));
      if (mounted) setState(() {});
      return;
    }

    try {
      // CHANGED: Load from user's reports
      final items = await repo.listItems(
        userId: widget.userId, // CHANGED
        schemaId: widget.reportType,
        limit: 50,
      );

      if (!mounted) return;

      if (items.isEmpty) {
        _panes.add(_ReportMeta(key: GlobalKey<DynamicReportFormState>(), isExpanded: true));
      } else {
        for (final d in items) {
          final id = (d['id'] ?? '').toString();
          final payload = (d['payload'] is Map)
              ? Map<String, dynamic>.from(d['payload'])
              : <String, dynamic>{};
          _panes.add(
            _ReportMeta(
              key: GlobalKey<DynamicReportFormState>(),
              isExpanded: false,
              itemId: id,
              initialPayload: payload,
            ),
          );
        }
        if (_panes.isNotEmpty) _panes.first.isExpanded = true;
      }
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _panes.add(_ReportMeta(key: GlobalKey<DynamicReportFormState>(), isExpanded: true));
      setState(() {});
    }
  }

 void _addReport() {
  setState(() {
    for (final p in _panes) {
      p.isExpanded = false;
    }
    _panes.insert(
      0,
      _ReportMeta(
        key: GlobalKey<DynamicReportFormState>(), 
        isExpanded: true,
        skipSubscriptionCheck: true,  // ✅ NEW: Mark as "Add Report" sheet
      ),
    );
  });
}

 // Replace the _deleteReport method in multi_report_accordion.dart with this enhanced version
Future<void> _deleteReport(int i) async {
  // Get photo and signature counts for confirmation message
  int photoCount = 0;
  bool hasSignatures = false;
  
  final repo = widget.repo;
  final itemId = _panes[i].itemId;
  
  if (repo != null && itemId != null && itemId.isNotEmpty) {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('reports')
          .doc(widget.reportType)
          .collection('items')
          .doc(itemId)
          .get();
      
      if (doc.exists) {
        final data = doc.data() ?? {};
        
        // Count photos
        final photos = (data['photos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        photoCount = photos.length;
        
        // Check for signatures
        final signatures = data['signatures'] as Map<String, dynamic>?;
        hasSignatures = signatures != null && 
            (signatures['contractor']?['imageUrl'] != null || 
             signatures['client']?['imageUrl'] != null);
      }
    } catch (e) {
      AppLogger.error('Error checking report content: $e');
    }
  }
  
  // Show enhanced confirmation dialog
  if (!mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Are you sure you want to delete Report ${i + 1}?'),
          const SizedBox(height: 16),
          const Text('This will permanently delete:', 
            style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('• All report data'),
          if (photoCount > 0)
            Text('• $photoCount photo${photoCount == 1 ? '' : 's'}'),
          if (hasSignatures)
            Text('• Digital signatures'),
          const SizedBox(height: 16),
          const Text(
            'This action cannot be undone.',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return; // User cancelled

  // Show loading indicator
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  try {
    // Delete using repository (which now handles photos and signatures)
    if (repo != null && itemId != null && itemId.isNotEmpty) {
      await repo.deleteItem(
        userId: widget.userId,
        schemaId: widget.reportType,
        itemId: itemId,
      );
    }
    
    if (!mounted) return;
    
    // Close loading dialog
    Navigator.pop(context);
    
    // Remove from UI
    setState(() {
      _panes.removeAt(i);
      if (_panes.isEmpty) {
        _panes.add(_ReportMeta(key: GlobalKey<DynamicReportFormState>(), isExpanded: true));
      }
    });
    
    _toast('Report ${i + 1} deleted successfully');
  } catch (e) {
    if (!mounted) return;
    
    // Close loading dialog
    Navigator.pop(context);
    
    // Show error
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to delete report: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<void> _saveAll() async {
  final repo = widget.repo;
  if (repo == null) {
    _toast('No repository configured.');
    return;
  }
  int saved = 0;
  final now = DateTime.now();
  
  for (final p in _panes) {
    final s = p.key.currentState?.snapshot();
    if (s == null) continue;
    
    final id = await repo.saveReport(
      userId: widget.userId,
      schemaId: widget.reportType,
      payload: {'details': s.details, 'rows': s.rows},
      reportId: p.itemId,
      skipSubscriptionCheck: p.skipSubscriptionCheck,  // ✅ NEW: Pass the flag
    );
    
    p.itemId = id;
    p.skipSubscriptionCheck = false;  // ✅ NEW: Reset after first save
    saved++;
  }
  
  if (!mounted) return;
  _toast(saved == 0 ? 'Nothing to save.' : 'Saved $saved report${saved == 1 ? '' : 's'} @ ${now.toLocal()}');
  setState(() {});
}

  Future<DocumentSnapshot<Map<String, dynamic>>> _getDocSafe(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return await ref.get(const GetOptions(source: Source.serverAndCache));
    } on FirebaseException catch (_) {
      return await ref.get(const GetOptions(source: Source.server));
    }
  }

/// Loads branding for export from user profile
Future<exports.ExportServiceBrandingConfig> _loadBranding() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseFirestore.instance;

    String? companyName;
    String? companyLogoUrl;
    String? clientName;
    String? clientLogoUrl;

    if (uid != null) {
      // Read /users/{uid}/profile/info (same doc used in Account Settings)
      final u = await _getDocSafe(
        db.collection('users').doc(uid).collection('profile').doc('info'),
      );
      final d = u.data() ?? <String, dynamic>{};

      companyName    = (d['company'] ?? '').toString();
      companyLogoUrl = (d['companyLogoUrl'] ?? '').toString();

      // ⬇️ NEW: client fields stored alongside company fields
      clientName     = (d['clientName'] ?? '').toString();
      clientLogoUrl  = (d['clientLogoUrl'] ?? '').toString();
    }

    Future<Uint8List?> fetchBytes(String? urlOrPath) async {
      if (urlOrPath == null || urlOrPath.isEmpty) return null;

      try {
        final ref = FirebaseStorage.instance.refFromURL(urlOrPath);
        return await ref.getData(5 * 1024 * 1024);
      } catch (_) {}

      try {
        final ref = FirebaseStorage.instance.ref(urlOrPath);
        return await ref.getData(5 * 1024 * 1024);
      } catch (_) {}

      return null;
    }

    Future<String?> resolveHttpsUrl(String? urlOrPath) async {
      if (urlOrPath == null || urlOrPath.isEmpty) return null;

      if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
        return urlOrPath;
      }

      try {
        final ref = FirebaseStorage.instance.refFromURL(urlOrPath);
        return await ref.getDownloadURL();
      } catch (_) {}

      try {
        final ref = FirebaseStorage.instance.ref(urlOrPath);
        return await ref.getDownloadURL();
      } catch (_) {}

      return null;
    }

    // Left = company; Right = client
    final leftBytes  = await fetchBytes(companyLogoUrl);
    final rightBytes = await fetchBytes(clientLogoUrl);
    final leftHttps  = await resolveHttpsUrl(companyLogoUrl);
    final rightHttps = await resolveHttpsUrl(clientLogoUrl);

    // Build a small meta grid from the first panel’s summary (optional)
    final metaRows = <List<String>>[];
    final summary = _panes.isNotEmpty ? _panes.first.summary : <String, String>{};
    void addKV(String k, String? v) {
      final val = (v ?? '').trim();
      if (val.isNotEmpty) metaRows.add([k, val]);
    }
    addKV('Date', summary['date']);
    addKV('Shift', summary['shift']);
    if ((clientName ?? '').isNotEmpty) addKV('Client', clientName);

    return exports.ExportServiceBrandingConfig(
      leftLogoBytes: leftBytes,
      rightLogoBytes: rightBytes,     // ⬅️ now included
      leftLogoUrl: leftHttps,
      rightLogoUrl: rightHttps,       // ⬅️ now included
      headerTitle: widget.reportTypeLabel,
      headerSubtitle: companyName ?? '',
      footerLeft: (companyName?.isNotEmpty == true) ? companyName : 'Generated by WeldQAi',
      footerRight: 'Page',
      metaRows: metaRows,
    );
  } catch (_) {
    return const exports.ExportServiceBrandingConfig(metaRows: <List<String>>[]);
  }
}


  Future<void> _exportAllExcel(BuildContext context) async {
    final payloads = _collectExports();
    if (payloads.isEmpty) return;
    final branding = await _loadBranding();
    if (!context.mounted) return;
    await exports.ExportService.exportExcelSimpleExcelPkg(
      context: context,
      title: widget.reportTypeLabel,
      reports: payloads,
      branding: branding,
    );
  }

  Future<void> _exportAllPdf(BuildContext context) async {
    final payloads = _collectExports();
    if (payloads.isEmpty) return;
    final branding = await _loadBranding();
    if (!context.mounted) return;
    await exports.ExportService.exportPdfSimple(
      context: context,
      title: widget.reportTypeLabel,
      reports: payloads,
      branding: branding,
    );
  }

  List<Map<String, dynamic>> _collectExports() {
    final detailsList = (widget.schema['details'] as List?) ?? const [];
    final detailsOrder = <String>[
      for (final f in detailsList)
        if (f is Map && ((f['key'] ?? '').toString().trim().isNotEmpty))
          (f['key'] as Object).toString().trim(),
    ];
    final firstTable = ((widget.schema['tables'] as List?)?.first as Map?) ?? const {};
    final schemaCols = (firstTable['columns'] as List?) ?? const [];
    final cols = [
      for (final c in schemaCols.whereType<Map>())
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

    final out = <Map<String, dynamic>>[];
    for (int i = 0; i < _panes.length; i++) {
      final s = _panes[i].key.currentState?.snapshot();
      if (s == null) continue;

      final title = _summaryText(_panes[i].summary).isEmpty
          ? 'Report ${i + 1}'
          : 'Report ${i + 1} — ${_summaryText(_panes[i].summary)}';

      final m = s.toJson();
      m['sheetName'] = title;
      m['reportTypeLabel'] = widget.reportTypeLabel;
      m['excel'] = {
        'detailsOrder': detailsOrder,
        'detailsPairsPerRow': widget.reportType.toLowerCase().contains('welding') ? 3 : 2,
        'detailsPairWidths': [14, 18, 14, 18, 14, 18],
        'table': {'columns': cols},
        'standardKeys': standardKeys,
      };
      out.add(m);
    }
    return out;
  }

  String _summaryText(Map<String, String> d) {
    final date = (d['date'] ?? '').trim();
    final doc = (d['document_no'] ?? d['documentNo'] ?? '').trim();
    final parts = <String>[];
    if (date.isNotEmpty) parts.add('Date: $date');
    if (doc.isNotEmpty) parts.add('Doc: $doc');
    if (parts.isEmpty) {
      int seen = 0;
      for (final v in d.values) {
        final s = v.trim();
        if (s.isNotEmpty) {
          parts.add(s);
          if (++seen >= 2) break;
        }
      }
    }
    return parts.join('  •  ');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _saveAll,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save All'),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: 'Export all',
                onSelected: (v) async {
                  if (v == 'xlsx') {
                    await _exportAllExcel(context);
                  } else if (v == 'pdf') {
                    await _exportAllPdf(context);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'xlsx', child: Text('Export ALL → Excel')),
                  PopupMenuItem(value: 'pdf', child: Text('Export ALL → PDF')),
                ],
                child: const Icon(Icons.ios_share),
              ),
              const Spacer(),
              Text('All: ${_panes.length} ${_panes.length == 1 ? "report" : "reports"}'),
            ],
          ),
        ),

        ExpansionPanelList(
          expansionCallback: (i, isExpanded) =>
              setState(() => _panes[i].isExpanded = !isExpanded),
          children: [
            for (int i = 0; i < _panes.length; i++)
              ExpansionPanel(
                canTapOnHeader: true,
                isExpanded: _panes[i].isExpanded,
                headerBuilder: (ctx, expanded) {
                  final title = 'Report ${i + 1}';
                  final summary = _summaryText(_panes[i].summary);
                  return ListTile(
                    dense: true,
                    title: Text(
                      summary.isEmpty ? title : '$title  —  $summary',
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: expanded ? 'Collapse' : 'Expand',
                          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                          onPressed: () =>
                              setState(() => _panes[i].isExpanded = !expanded),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteReport(i),
                        ),
                      ],
                    ),
                  );
                },
              body: Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  child: Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: DynamicReportForm(
        key: _panes[i].key,
        userId: widget.userId,
        reportType: widget.reportType,
        reportTypeLabel: widget.reportTypeLabel,
        schema: widget.schema,
        defaultMinRows: _defaultMinRows,
        scanService: widget.scanService,
        repo: widget.repo,
        reportId: widget.reportId, // <-- pass through so the accordion/editor loads/saves the draft
        onNewReport: _addReport,
        onDetailsChanged: (d) => setState(() => _panes[i].summary = d),
        existingDocId: _panes[i].itemId,
        initialPayload: _panes[i].initialPayload,
        skipSubscriptionCheck: _panes[i].skipSubscriptionCheck,  // ✅ NEW
        onSaved: (String savedId) {  // ✅ NEW: Callback after individual save
          setState(() {
            _panes[i].itemId = savedId;
            _panes[i].skipSubscriptionCheck = false;  // Reset flag
          });
        },
      ),
    ),
  ),
),
              ),
          ],
        ),
      ],
    );
  }
}