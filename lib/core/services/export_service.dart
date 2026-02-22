// lib/core/services/export_service.dart
// ✅ FIXED: Properly uses detailLabels and columnLabels from snapshot
// ignore_for_file: unused_element, unused_local_variable
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:excel/excel.dart' as ex;
import 'package:weldqai_app/core/services/analytics_service.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// Branding config passed in by callers (MultiReportAccordion / DynamicReportForm).
class ExportServiceBrandingConfig {
  final Uint8List? leftLogoBytes;
  final Uint8List? rightLogoBytes;
  final String? leftLogoUrl;
  final String? rightLogoUrl;
  final String? headerTitle;
  final String? headerSubtitle;
  final String? footerLeft;
  final String? footerRight;
  final List<List<String>> metaRows;

  const ExportServiceBrandingConfig({
    this.leftLogoBytes,
    this.rightLogoBytes,
    this.leftLogoUrl,
    this.rightLogoUrl,
    this.headerTitle,
    this.headerSubtitle,
    this.footerLeft,
    this.footerRight,
    this.metaRows = const <List<String>>[],
  });
}

class ExportService {
  const ExportService._();

  // ---------- field aliases ----------
  static const Map<String, List<String>> _defaultAliasGroups = {
    'document_no': ['document_no', 'documentNo', 'doc_no', 'document number', 'document_spec', 'document/spec', 'documentSpec', 'document'],
    'job_no': ['job_no', 'jobNo'],
    'report_no': ['report_no', 'reportNo'],
    'date': ['date', 'date_range', 'dateRange'],
    'page': ['page'],
    'shift': ['shift'],
    'project': ['project', 'project_title', 'projectTitle', 'project_name', 'projectName'],
    'client': ['client', 'client_name', 'clientName'],
    'location': ['location', 'field_location', 'fieldLocation'],
    'worksite': ['worksite', 'work_site'],
    'weld_no': ['weld_no', 'weldNo'],
    'wps_no': ['wps_no', 'wpsNo'],
  };

  static Map<String, List<String>> _mergedAliasGroups(Map<String, dynamic> excelCfg) {
    final out = <String, List<String>>{}..addAll(_defaultAliasGroups);
    final cfgGroups = (excelCfg['aliasGroups'] is Map)
        ? Map<String, dynamic>.from(excelCfg['aliasGroups'] as Map)
        : const <String, dynamic>{};
    cfgGroups.forEach((canon, v) {
      final list = (v is List) ? v.map((e) => e.toString()).toList() : <String>[v.toString()];
      out[canon] = list;
    });
    return out;
  }

  static Set<String> _computeReservedDetailKeys(
    Map<String, String> details,
    Map<String, dynamic> excelCfg,
  ) {
    final reserved = <String>{};

    final explicit = (excelCfg['standardKeys'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    reserved.addAll(explicit);

    final groups = _mergedAliasGroups(excelCfg);
    for (final aliases in groups.values) {
      if (aliases.any(details.containsKey)) {
        reserved.addAll(aliases);
      }
    }
    return reserved;
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  // Nicely format a detail key for display (fallback only).
  static String _prettyKey(String key) {
    var k = key.trim();
    if (k.startsWith('__')) k = k.replaceFirst(RegExp(r'^__+'), '');
    k = k.replaceAll('_', ' ');
    if (k.isEmpty) return '';
    return k[0].toUpperCase() + k.substring(1);
  }

  static ({List<List<String>> rows, Map<String, String> remaining}) _extractMetaFromDetails(
    Map<String, String> details,
    Map<String, dynamic> excelCfg,
  ) {
    final groups = _mergedAliasGroups(excelCfg);

    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = details[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final rows = <List<String>>[];
    final remaining = Map<String, String>.from(details);

    void addRow(String label, List<String> candidates) {
      final v = pick(candidates);
      if (v != null && v.isNotEmpty) {
        rows.add([label, v]);
        for (final k in candidates) {
          remaining.remove(k);
        }
      }
    }

    addRow('Client', groups['client'] ?? const []);
    addRow('Document/Spec', groups['document_no'] ?? const []);
    addRow('Date', groups['date'] ?? const []);
    addRow('Shift', groups['shift'] ?? const []);
    addRow('Project', groups['project'] ?? const []);

    return (rows: rows, remaining: remaining);
  }

  // ------------------------------------------------------------------
  // EXCEL (excel package) — ✅ FIXED TO USE LABELS
  // ------------------------------------------------------------------
  static Future<void> exportExcelSimpleExcelPkg({
    required BuildContext context,
    required String title,
    required List<dynamic> reports,
    ExportServiceBrandingConfig? branding,
  }) async {
    try {
      final excel = ex.Excel.createExcel();
      final defaultSheetName = excel.getDefaultSheet();

      final titleStyle = ex.CellStyle(bold: true, fontSize: 14);
      final headerStyle = ex.CellStyle(bold: true);
      final sectionStyle = ex.CellStyle(bold: true);

      String safeSheetName(String? raw, int index, Set<String> used) {
        final base0 =
            (raw ?? 'Report ${index + 1}').replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
        final base = base0.isEmpty ? 'Report ${index + 1}' : base0;
        String name = base.length > 31 ? base.substring(0, 31) : base;
        if (!used.contains(name)) return name;
        int n = 2;
        while (true) {
          final suffix = ' ($n)';
          final maxLen = 31 - suffix.length;
          final head = name.length > maxLen ? name.substring(0, maxLen) : name;
          final candidate = '$head$suffix';
          if (!used.contains(candidate)) return candidate;
          n++;
        }
      }

      void writeCell(ex.Sheet sh, int c, int r, String v, [ex.CellStyle? st]) {
        final cell = sh.cell(ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        cell.value = v;
        if (st != null) cell.cellStyle = st;
      }

      void setColWidthSafe(ex.Sheet sh, int col, double w) {
        try { sh.setColWidth(col, w); } catch (_) {}
      }

      List<double> computeCompactWidths(
        List<String> keys, List<String> labels, List<double?> cfgWidths,
      ) {
        bool isNumericLike(String s) => RegExp(
          r'(amp|volt|current|speed|temp|len|dia|od\b|id\b|mm\b|in\b|qty|count|no\b|kJ|heat|time|min|max|avg|meter|m\b)',
          caseSensitive: false).hasMatch(s);
        bool isDateTime(String s) => RegExp(r'(date|time|shift)', caseSensitive: false).hasMatch(s);
        final widths = <double>[];
        for (int i = 0; i < labels.length; i++) {
          final key = keys[i]; final label = labels[i];
          double w;
          if (cfgWidths[i] != null) {
            w = cfgWidths[i]!.clamp(7.0, 22.0);
          } else if (isNumericLike(key) || isNumericLike(label)) {
            w = 9.0;
          } else if (isDateTime(key) || isDateTime(label)) {
            w = 12.0;
          } else if (label.length >= 18) {
            w = 14.0;
          } else if (label.length >= 12) {
            w = 12.0;
          } else {
            w = 11.0;
          }
          widths.add(w.clamp(8.0, 16.0));
        }
        final sum = widths.fold<double>(0, (a, b) => a + b);
        final target = (labels.length <= 12) ? 120.0 : 140.0;
        if (sum > target) {
          final k = target / sum;
          for (int i = 0; i < widths.length; i++) {
            widths[i] = (widths[i] * k).clamp(7.0, 14.5);
          }
        }
        return widths;
      }

      final usedNames = <String>{};

      for (var i = 0; i < reports.length; i++) {
        final raw = Map<String, dynamic>.from(reports[i] as Map);

        final requestedName = (raw['sheetName'] as String?)?.trim();
        final baseForName = (requestedName != null && requestedName.isNotEmpty)
            ? requestedName
            : raw['reportTypeLabel']?.toString();

        final sheetName = (i == 0 && defaultSheetName != null)
            ? defaultSheetName
            : safeSheetName(baseForName, i, usedNames);
        usedNames.add(sheetName);
        final sheet = excel[sheetName];

        final excelCfg = (raw['excel'] is Map)
            ? Map<String, dynamic>.from(raw['excel'] as Map)
            : const <String, dynamic>{};

        final tableCols = <Map<String, dynamic>>[
          for (final c in ((excelCfg['table'] as Map?)?['columns'] as List? ?? const []).whereType<Map>())
            {
              'key': (c['key'] ?? '').toString(),
              'label': (c['label'] ?? c['key'] ?? '').toString(),
              if (c['width'] is num) 'width': (c['width'] as num).toDouble(),
            }
        ];

        final details = <String, String>{};
        if (raw['details'] is Map) {
          final tmp = Map<String, dynamic>.from(raw['details'] as Map);
          for (final e in tmp.entries) {
            details[e.key.toString()] = (e.value ?? '').toString();
          }
        }

        // ✅ CRITICAL FIX: Extract detailLabels from snapshot
        final detailLabels = <String, String>{};
        if (raw['detailLabels'] is Map) {
          final tmp = Map<String, dynamic>.from(raw['detailLabels'] as Map);
          for (final e in tmp.entries) {
            detailLabels[e.key.toString()] = (e.value ?? '').toString();
          }
        }

        // ✅ CRITICAL FIX: Extract columnLabels from snapshot
        final columnLabels = <String, String>{};
        if (raw['columnLabels'] is Map) {
          final tmp = Map<String, dynamic>.from(raw['columnLabels'] as Map);
          for (final e in tmp.entries) {
            columnLabels[e.key.toString()] = (e.value ?? '').toString();
          }
        }

        final rows = <Map<String, String>>[];
        if (raw['rows'] is List) {
          for (final item in (raw['rows'] as List)) {
            if (item is Map) {
              final mm = Map<String, dynamic>.from(item);
              final out = <String, String>{};
              for (final e in mm.entries) {
                out[e.key.toString()] = (e.value ?? '').toString();
              }
              rows.add(out);
            }
          }
        }

        int r = 0;

        final titleText = (raw['reportTypeLabel']?.toString() ?? 'Report').trim();
        writeCell(sheet, 0, r, titleText.isEmpty ? 'Report' : titleText, titleStyle);
        r += 2;

        if (details.isNotEmpty) {
          final reserved = _computeReservedDetailKeys(details, excelCfg);
          final cfgOrder = <String>[
            ...((excelCfg['detailsOrder'] as List?)?.map((e) => e.toString()) ?? const []),
          ];
          final pairsPerRow = (excelCfg['detailsPairsPerRow'] as int?)?.clamp(1, 4) ?? 2;
          var pairWidths = <double>[
            ...((excelCfg['detailsPairWidths'] as List?)?.whereType<num>().map((n) => n.toDouble()) ?? const []),
          ];
          if (pairWidths.isEmpty) {
            pairWidths = [ for (int p = 0; p < pairsPerRow; p++) ...[14.0, 18.0] ];
          }

          final remaining = details.keys.where((k) => !reserved.contains(k)).toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final orderedKeys = <String>[
            ...cfgOrder.where((k) => remaining.contains(k)),
            ...remaining.where((k) => !cfgOrder.contains(k)),
          ];

          writeCell(sheet, 0, r, 'Details', sectionStyle);
          r++;

          int idx = 0;
          while (idx < orderedKeys.length) {
            for (int p = 0; p < pairsPerRow && idx < orderedKeys.length; p++) {
              final key = orderedKeys[idx++];
              final value = details[key] ?? '';
              final labelCol = p * 3;
              final valueCol = labelCol + 1;
              
              // ✅ FIXED: Use detailLabels instead of _prettyKey
              final displayLabel = detailLabels[key] ?? _prettyKey(key);
              writeCell(sheet, labelCol, r, displayLabel);
              writeCell(sheet, valueCol, r, value);
              
              final wLabel = (p * 2 < pairWidths.length) ? pairWidths[p * 2] : 14.0;
              final wValue = (p * 2 + 1 < pairWidths.length) ? pairWidths[p * 2 + 1] : 18.0;
              setColWidthSafe(sheet, labelCol, wLabel);
              setColWidthSafe(sheet, valueCol, wValue);
            }
            r++;
          }
          r++;
        }

        if (rows.isNotEmpty) {
          late final List<String> keys;
          late final List<String> labels;
          late final List<double?> widths;
          if (tableCols.isNotEmpty) {
            keys = [for (final c in tableCols) c['key'] as String];
            
            // ✅ FIXED: Use columnLabels from snapshot
            labels = [
              for (final c in tableCols) 
                columnLabels[c['key'] as String] ?? (c['label'] as String?) ?? (c['key'] as String)
            ];
            
            widths = [for (final c in tableCols) (c['width'] as double?)];
          } else {
            keys = rows.first.keys.toList();
            
            // ✅ FIXED: Use columnLabels for auto-detected columns
            labels = [for (final k in keys) columnLabels[k] ?? k];
            
            widths = List<double?>.filled(keys.length, null);
          }

          final compact = computeCompactWidths(keys, labels, widths);
          for (int c = 0; c < keys.length; c++) {
            writeCell(sheet, c, r, labels[c], headerStyle);
            setColWidthSafe(sheet, c, compact[c]);
          }
          r++;

          for (final m in rows) {
            for (int c = 0; c < keys.length; c++) {
              writeCell(sheet, c, r, m[keys[c]] ?? '');
            }
            r++;
          }
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Excel encoding returned null bytes.');

      final fname = _safe('$title.xlsx');
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fname, bytes: Uint8List.fromList(bytes), mimeType: MimeType.other, fileExtension: 'xlsx',
        );
      } else {
        final path = await FileSaver.instance.saveFile(
          name: fname, bytes: Uint8List.fromList(bytes), mimeType: MimeType.other, fileExtension: 'xlsx',
        );
        await OpenFilex.open(path);
      }
    } catch (e, st) {
      AppLogger.debug('Excel export error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
      }
    }
  }

  // ---------- helpers for PDF ----------
  static Future<pw.ImageProvider?> _logoProvider({
    Uint8List? bytes,
    String? url,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return pw.MemoryImage(bytes);
    }
    if (url == null || url.isEmpty) return null;

    try {
      final prov = await networkImage(url);
      return prov;
    } catch (e) {
      AppLogger.debug('printing.networkImage failed for $url: $e');
    }

    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return pw.MemoryImage(resp.bodyBytes);
      }
    } catch (e) {
      AppLogger.debug('HTTP logo download failed for $url: $e');
    }
    return null;
  }

// Read signatures from Firestore
static Future<Map<String, dynamic>?> _loadSignatures({
  required String userId,
  required String schemaId,
  required String reportId,
}) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('reports')
        .doc(schemaId)
        .collection('items')
        .doc(reportId)
        .get();
    
    if (!doc.exists) return null;
    
    final data = doc.data();
    if (data == null) return null;
    
    return data['signatures'] as Map<String, dynamic>?;
  } catch (e) {
    AppLogger.error('Error loading signatures: $e');
    return null;
  }
}

// Download signature image from Firebase Storage
static Future<Uint8List?> _downloadSignatureImage(String url) async {
  if (url.isEmpty) return null;
  
  try {
    // Try as Storage reference first
    final ref = FirebaseStorage.instance.refFromURL(url);
    return await ref.getData();
  } catch (_) {
    try {
      // Try as path
      final ref = FirebaseStorage.instance.ref(url);
      return await ref.getData();
    } catch (e) {
      AppLogger.debug('Failed to download signature: $e');
      return null;
    }
  }
}

  static pw.Widget _brandingHeader(
    ExportServiceBrandingConfig branding,
    String reportTitle, {
    pw.ImageProvider? leftProvider,
    pw.ImageProvider? rightProvider,
  }) {
    pw.Widget logo(pw.ImageProvider? provider) {
      if (provider == null) return pw.SizedBox(width: 60, height: 60);
      return pw.SizedBox(width: 60, height: 60, child: pw.Image(provider, fit: pw.BoxFit.contain));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.8, color: pdf.PdfColors.grey600),
      columnWidths: const {
        0: pw.FixedColumnWidth(110),
        1: pw.FlexColumnWidth(1),
        2: pw.FixedColumnWidth(110),
      },
      children: [
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Center(child: logo(leftProvider)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 10),
              child: pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      (branding.headerTitle ?? reportTitle),
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    if ((branding.headerSubtitle ?? '').trim().isNotEmpty)
                      pw.SizedBox(height: 2),
                    if ((branding.headerSubtitle ?? '').trim().isNotEmpty)
                      pw.Text(
                        branding.headerSubtitle!,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Center(child: logo(rightProvider)),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _metaGrid(List<List<String>> rows) {
    if (rows.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Table(
        border: pw.TableBorder.all(width: 0.3),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {0: pw.FlexColumnWidth(12), 1: pw.FlexColumnWidth(20)},
        children: [
          for (final r in rows)
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  (r.isNotEmpty ? r[0] : ''),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text((r.length > 1 ? r[1] : ''), style: const pw.TextStyle(fontSize: 9)),
              ),
            ]),
        ],
      ),
    );
  }

  static pw.Widget _hLine() => pw.Container(
        height: 0.9,
        margin: const pw.EdgeInsets.only(top: 6),
        color: pdf.PdfColors.grey600,
      );

 static pw.Widget _signatureBlock({
  Map<String, dynamic>? signatures,
  pw.ImageProvider? contractorImage, // ✅ NEW: Direct image parameters
  pw.ImageProvider? clientImage,     // ✅ NEW: Direct image parameters
}) {
  final contractorData = signatures?['contractor'] as Map<String, dynamic>?;
  final clientData = signatures?['client'] as Map<String, dynamic>?;
  
  final contractorName = contractorData?['name']?.toString() ?? '';
  final contractorDate = contractorData?['date']?.toString() ?? '';
  final clientName = clientData?['name']?.toString() ?? '';
  final clientDate = clientData?['date']?.toString() ?? '';
  
  pw.Widget col(String title, String? name, String? date, pw.ImageProvider? sigImage) {
    pw.Widget nameRow() {
      if (name != null && name.isNotEmpty) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 70,
                child: pw.Text('Print Name:', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(width: 8),
              pw.Text(name, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
      }
      // Blank line
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 70,
              child: pw.Text('Print Name:', style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(child: _hLine()),
          ],
        ),
      );
    }
    
  pw.Widget sigRow() {
  if (sigImage != null) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 70,
            child: pw.Text('Signature:', style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.SizedBox(width: 8),
          // ✅ Just the signature image - no box, no line, no container
          pw.Expanded(
            child: pw.Image(
              sigImage,
              fit: pw.BoxFit.contain,
              alignment: pw.Alignment.centerLeft,
              height: 40,
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ When no signature, also no line - just blank
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 70,
          child: pw.Text('Signature:', style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(child: pw.SizedBox()), // ✅ Just empty space, no line
      ],
    ),
  );
}
    
    pw.Widget dateRow() {
      if (date != null && date.isNotEmpty) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 70,
                child: pw.Text('Date:', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(width: 8),
              pw.Text(date, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
      }
      // Blank line
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 70,
              child: pw.Text('Date:', style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(child: _hLine()),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        nameRow(),
        sigRow(),
        dateRow(),
      ],
    );
  }
 return pw.Padding(
  padding: const pw.EdgeInsets.only(top: 14),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: col('CONTRACTOR:', contractorName, contractorDate, contractorImage)),
      pw.SizedBox(width: 24),
      pw.Expanded(child: col('CLIENT:', clientName, clientDate, clientImage)),
    ],
  ),
);
}
  // ------------------------------------------------------------------
  // PDF — ✅ FIXED TO USE LABELS
  // ------------------------------------------------------------------
  static Future<void> exportPdfSimple({
    required BuildContext context,
    required String title,
    required List<dynamic> reports,
    ExportServiceBrandingConfig? branding,
  }) async {
  // ✅ Extract user info for analytics
  final userId = reports.isNotEmpty 
      ? reports.first['userId']?.toString() 
      : null;
  final reportId = reports.isNotEmpty 
      ? reports.first['docId']?.toString() 
      : null;
  final inspectionType = reports.isNotEmpty
      ? reports.first['reportType']?.toString() ?? 'unknown'
      : 'unknown';
  
  // ✅ CREATE PERFORMANCE TRACE
  final trace = FirebasePerformance.instance.newTrace('pdf_generation');
  
  try {
    // ✅ START PERFORMANCE TRACE
    await trace.start();
    final startTime = DateTime.now();

      final fontRegular = await PdfGoogleFonts.notoSansRegular();
      final fontBold    = await PdfGoogleFonts.notoSansBold();

      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      );

      final titleStyle   = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
      final sectionStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
      final headerStyle  = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
      final smallStyle   = const pw.TextStyle(fontSize: 9);

      List<double> computePdfFlex(
        List<String> keys, List<String> labels, List<double?> cfgWidths,
      ) {
        bool isNumericLike(String s) => RegExp(
          r'(amp|volt|current|speed|temp|len|dia|od\b|id\b|mm\b|in\b|qty|count|no\b|kJ|heat|time|min|max|avg|meter|m\b)',
          caseSensitive: false).hasMatch(s);
        bool isDateTime(String s) => RegExp(r'(date|time|shift)', caseSensitive: false).hasMatch(s);

        final flex = <double>[];
        for (int i = 0; i < labels.length; i++) {
          final key = keys[i]; final label = labels[i];
          double w;
          if (cfgWidths[i] != null) {
            w = cfgWidths[i]!.clamp(30.0, 90.0);
          } else if (isNumericLike(key) || isNumericLike(label)) {
            w = 40.0;
          } else if (isDateTime(key) || isDateTime(label)) {
            w = 55.0;
          } else if (label.length >= 18) {
            w = 70.0;
          } else if (label.length >= 12) {
            w = 60.0;
          } else {
            w = 50.0;
          }
          flex.add(w);
        }
        final sum = flex.fold<double>(0, (a, b) => a + b);
        final target = 700.0;
        if (sum > target) {
          final k = target / sum;
          for (int i = 0; i < flex.length; i++) {
            flex[i] = (flex[i] * k).clamp(30.0, 80.0);
          }
        }
        return flex;
      }

      pw.Widget buildDetailsTable({
        required Map<String, String> details,
        required Map<String, String> detailLabels, // ✅ ADD PARAMETER
        required Map<String, dynamic> cfg,
      }) {
        if (details.isEmpty) return pw.SizedBox.shrink();

        final reserved = _computeReservedDetailKeys(details, cfg);

        final cfgOrder = <String>[
          ...((cfg['detailsOrder'] as List?)?.map((e) => e.toString()) ?? const []),
        ];
        final pairsPerRow = (cfg['detailsPairsPerRow'] as int?)?.clamp(1, 4) ?? 2;
        var pairWidths = <double>[
          ...((cfg['detailsPairWidths'] as List?)?.whereType<num>().map((n) => n.toDouble()) ?? const []),
        ];
        if (pairWidths.isEmpty) {
          pairWidths = [ for (int p = 0; p < pairsPerRow; p++) ...[14.0, 18.0] ];
        }

        final remaining = details.keys.where((k) => !reserved.contains(k)).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final orderedKeys = <String>[
          ...cfgOrder.where((k) => remaining.contains(k)),
          ...remaining.where((k) => !cfgOrder.contains(k)),
        ];

        final rows = <pw.TableRow>[];
        for (int i = 0; i < orderedKeys.length; i += pairsPerRow) {
          final cells = <pw.Widget>[];
          for (int p = 0; p < pairsPerRow; p++) {
            final idx = i + p;
            if (idx < orderedKeys.length) {
              final k = orderedKeys[idx];
              final v = details[k] ?? '';
              
              // ✅ FIXED: Use detailLabels instead of _prettyKey
              final displayLabel = detailLabels[k] ?? _prettyKey(k);
              
              cells.add(pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(displayLabel, style: sectionStyle),
              ));
              cells.add(pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(v),
              ));
            } else {
              cells.add(pw.SizedBox());
              cells.add(pw.SizedBox());
            }
          }
          rows.add(pw.TableRow(children: cells));
        }

        final colWidths = <int, pw.TableColumnWidth>{};
        for (int p = 0; p < pairsPerRow; p++) {
          final labelW = (p * 2 < pairWidths.length) ? pairWidths[p * 2] : 14.0;
          final valueW = (p * 2 + 1 < pairWidths.length) ? pairWidths[p * 2 + 1] : 18.0;
          colWidths[p * 2] = pw.FlexColumnWidth(labelW);
          colWidths[p * 2 + 1] = pw.FlexColumnWidth(valueW);
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(width: 0.3),
              columnWidths: colWidths,
              children: rows,
            ),
            pw.SizedBox(height: 12),
          ],
        );
      }

      pw.Widget buildEntriesTable({
        required List<Map<String, String>> rows,
        required Map<String, String> columnLabels, // ✅ ADD PARAMETER
        required Map<String, dynamic> cfg,
      }) {
        if (rows.isEmpty) return pw.SizedBox.shrink();

        final tableCols = <Map<String, dynamic>>[
          for (final c in ((cfg['table'] as Map?)?['columns'] as List? ?? const []).whereType<Map>())
            {
              'key': (c['key'] ?? '').toString(),
              'label': (c['label'] ?? c['key'] ?? '').toString(),
              if (c['width'] is num) 'width': (c['width'] as num).toDouble(),
            }
        ];

        late final List<String> keys;
        late final List<String> labels;
        late final List<double?> widths;
        if (tableCols.isNotEmpty) {
          keys = [for (final c in tableCols) c['key'] as String];
          
          // ✅ FIXED: Use columnLabels from snapshot
          labels = [
            for (final c in tableCols) 
              columnLabels[c['key'] as String] ?? (c['label'] as String?) ?? (c['key'] as String)
          ];
          
          widths = [for (final c in tableCols) (c['width'] as double?)];
        } else {
          keys = rows.first.keys.toList();
          
          // ✅ FIXED: Use columnLabels for auto columns
          labels = [for (final k in keys) columnLabels[k] ?? k];
          
          widths = List<double?>.filled(keys.length, null);
        }

        final flexes = computePdfFlex(keys, labels, widths);
        final colWidths = <int, pw.TableColumnWidth>{
          for (int c = 0; c < labels.length; c++) c: pw.FlexColumnWidth(flexes[c]),
        };

        final header = pw.TableRow(
          decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
          children: [
            for (final h in labels)
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(h, style: headerStyle),
              ),
          ],
        );

        final dataRows = rows.map<pw.TableRow>((m) {
          return pw.TableRow(
            children: [
              for (final k in keys)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(m[k] ?? ''),
                ),
            ],
          );
        }).toList();

        return pw.Table(
          border: pw.TableBorder.all(width: 0.3),
          columnWidths: colWidths,
          children: [header, ...dataRows],
        );
      }

      for (final r in reports) {
        final map = Map<String, dynamic>.from(r as Map);

 // ✅ NEW: Extract userId, schemaId, reportId for signature loading
final userId = map['userId']?.toString();
final schemaId = map['reportType']?.toString();
final reportId = map['docId']?.toString();

// ✅ NEW: Load signatures from Firestore
Map<String, dynamic>? signatures;
pw.ImageProvider? contractorSigImage;
pw.ImageProvider? clientSigImage;

if (userId != null && schemaId != null && reportId != null) {
  AppLogger.debug('🔍 Loading signatures for report: $reportId'); // Debug
  
  signatures = await _loadSignatures(
    userId: userId,
    schemaId: schemaId,
    reportId: reportId,
  );
  
  AppLogger.debug('🔍 Signatures loaded: $signatures'); // Debug
  
  // Download signature images if they exist
  if (signatures != null) {
    final contractorData = signatures['contractor'] as Map<String, dynamic>?;
    final contractorUrl = contractorData?['imageUrl']?.toString();
    
    AppLogger.debug('🔍 Contractor signature URL: $contractorUrl'); // Debug
    
    if (contractorUrl != null && contractorUrl.isNotEmpty) {
      final bytes = await _downloadSignatureImage(contractorUrl);
      if (bytes != null && bytes.isNotEmpty) {
        AppLogger.info('✅ Contractor signature downloaded: ${bytes.length} bytes'); // Debug
        contractorSigImage = pw.MemoryImage(bytes);
      } else {
        AppLogger.error('❌ Failed to download contractor signature'); // Debug
      }
    }
    
    final clientData = signatures['client'] as Map<String, dynamic>?;
    final clientUrl = clientData?['imageUrl']?.toString();
    
    AppLogger.debug('🔍 Client signature URL: $clientUrl'); // Debug
    
    if (clientUrl != null && clientUrl.isNotEmpty) {
      final bytes = await _downloadSignatureImage(clientUrl);
      if (bytes != null && bytes.isNotEmpty) {
        AppLogger.info('✅ Client signature downloaded: ${bytes.length} bytes'); // Debug
        clientSigImage = pw.MemoryImage(bytes);
      } else {
        AppLogger.error('❌ Failed to download client signature'); // Debug
      }
    }
  }
}

        final cfg = (map['excel'] is Map)
            ? Map<String, dynamic>.from(map['excel'] as Map)
            : const <String, dynamic>{};

        final rawDetails = (map['details'] is Map)
            ? Map<String, String>.from(map['details'] as Map)
            : <String, String>{};

        // ✅ CRITICAL FIX: Extract detailLabels from snapshot
        final detailLabels = <String, String>{};
        if (map['detailLabels'] is Map) {
          final tmp = Map<String, dynamic>.from(map['detailLabels'] as Map);
          for (final e in tmp.entries) {
            detailLabels[e.key.toString()] = (e.value ?? '').toString();
          }
        }

        // ✅ CRITICAL FIX: Extract columnLabels from snapshot
        final columnLabels = <String, String>{};
        if (map['columnLabels'] is Map) {
          final tmp = Map<String, dynamic>.from(map['columnLabels'] as Map);
          for (final e in tmp.entries) {
            columnLabels[e.key.toString()] = (e.value ?? '').toString();
          }
        }

        final rows = (map['rows'] is List)
            ? List<Map<String, String>>.from(
                (map['rows'] as List).map((e) => Map<String, String>.from(e as Map)),
              )
            : <Map<String, String>>[];

        final colCountForPortrait = 8;
        final forcePortrait =
            ((cfg['pdf'] as Map?)?['orientation'] as String?)?.toLowerCase() == 'portrait';
        final autoPortrait = rows.isNotEmpty && rows.first.length <= colCountForPortrait;
        final pageFmt = (forcePortrait || autoPortrait)
            ? pdf.PdfPageFormat.a4
            : pdf.PdfPageFormat.a4.landscape;

        final reportTitle = map['reportTypeLabel']?.toString() ?? 'Report';

        final leftProv  = await _logoProvider(bytes: branding?.leftLogoBytes,  url: branding?.leftLogoUrl);
        final rightProv = await _logoProvider(bytes: branding?.rightLogoBytes, url: branding?.rightLogoUrl);

        final metaAndRemain = _extractMetaFromDetails(rawDetails, cfg);
        final metaRows = metaAndRemain.rows;
        final displayDetails = Map<String, String>.from(metaAndRemain.remaining);

        pdfDoc.addPage(
          pw.MultiPage(
            pageFormat: pageFmt,
            margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            header: (ctx) => _brandingHeader(
              branding ?? const ExportServiceBrandingConfig(),
              reportTitle,
              leftProvider: leftProv,
              rightProvider: rightProv,
            ),
            footer: (ctx) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(branding?.footerLeft ?? title, style: smallStyle),
                pw.Text(
                  '${branding?.footerRight ?? 'Page'} ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: smallStyle,
                ),
              ],
            ),
            build: (ctx) => [
              _metaGrid(metaRows),
              if (displayDetails.isNotEmpty)
                buildDetailsTable(
                  details: displayDetails,
                  detailLabels: detailLabels, // ✅ PASS LABELS
                  cfg: cfg,
                ),
              if (rows.isNotEmpty)
                buildEntriesTable(
                  rows: rows,
                  columnLabels: columnLabels, // ✅ PASS LABELS
                  cfg: cfg,
                ),
              _signatureBlock( 
                 signatures: signatures,
                 contractorImage: contractorSigImage, // ✅ FIXED: Pass images directly
                 clientImage: clientSigImage, 
              ),
            ],
          ),
        );
      }

      final bytes = await pdfDoc.save();
      await Printing.layoutPdf(
        onLayout: (pdf.PdfPageFormat format) async => bytes,
        name: _safe('$title.pdf'),
      );
     // ✅ STOP PERFORMANCE TRACE & ADD METRICS
    final duration = DateTime.now().difference(startTime);
    trace.setMetric('duration_ms', duration.inMilliseconds);
    trace.setMetric('page_count', reports.length);
    trace.setMetric('success', 1);
    await trace.stop();

       // ✅ Track successful PDF generation
    if (userId != null && reportId != null) {
      await AnalyticsService.logEvent(
        name: 'pdf_generated',
        parameters: {
          'user_id': userId,
          'report_id': reportId,
          'inspection_type': inspectionType,
          'duration_ms': duration.inMilliseconds,
          'success': 1,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    }
    
     } catch (e, st) {
    // ✅ STOP TRACE ON ERROR
    trace.setMetric('success', 0);
    await trace.stop();
    // ✅ Track PDF generation failure
    if (userId != null && reportId != null) {
      await AnalyticsService.logEvent(
        name: 'pdf_generation_failed',
        parameters: {
          'user_id': userId,
          'report_id': reportId,
          'inspection_type': inspectionType,
          'error': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    }
    
    if (kDebugMode) {
      AppLogger.debug('PDF export failed: $e\n$st');
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    }
  }
}
}