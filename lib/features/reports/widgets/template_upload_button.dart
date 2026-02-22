// lib/features/reports/widgets/template_upload_button.dart
// ✅ UPDATED: Added Firebase Performance Monitoring & Analytics
// ignore_for_file: unused_local_variable

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_performance/firebase_performance.dart'; // ✅ NEW
import 'package:firebase_analytics/firebase_analytics.dart'; // ✅ NEW
import 'package:weldqai_app/core/services/enhanced_template_parser.dart';
import 'package:weldqai_app/screens/field_mapping_screen.dart';
import 'package:weldqai_app/core/models/template_mapping.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// Conflict handling
enum _ConflictAction { replace, keepBoth, cancel }

class TemplateUploadButton extends StatefulWidget {
  const TemplateUploadButton({
    super.key,
    this.onSchemaGenerated,
    this.heroTag,
    this.debug = false,
  });

  final VoidCallback? onSchemaGenerated;
  final Object? heroTag;
  final bool debug;

  @override
  State<TemplateUploadButton> createState() => _TemplateUploadButtonState();
}

class _TemplateUploadButtonState extends State<TemplateUploadButton> {
  bool _uploading = false;

  void _log(String msg) {
    // ignore: avoid_print
    AppLogger.debug('[UPLOAD DEBUG] $msg');
    if (widget.debug && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[UPLOAD] $msg'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      _log('User cancelled file picker');
      return;
    }

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      _log('Picked file has no bytes');
      return;
    }

    // ✅ STEP 1: Create Performance Trace for Parsing
    final parseTrace = FirebasePerformance.instance.newTrace('template_parsing');
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    bool parseTraceStopped = false;

    setState(() => _uploading = true);
    
    try {
      // ✅ START PARSING TRACE
      await parseTrace.start();
      final parseStartTime = DateTime.now();
      
      final fileExtension = (file.name).toLowerCase().split('.').last;
      _log('Parsing ${fileExtension.toUpperCase()} file with enhanced parser…');
      
      // ✅ Track file metrics
      try {
        parseTrace.setMetric('file_size_bytes', bytes.length);
        parseTrace.putAttribute('file_extension', fileExtension);
        parseTrace.putAttribute('user_id', uid);
      } catch (e) {
        _log('Parse trace metric error (ignored): $e');
      }
      
      // ✅ Use enhanced parser that extracts ALL fields with locations
      final parser = EnhancedUniversalParser();
      final schema = await parser.parseWithFullDetails(bytes, fileName: file.name);
      
      final detailFieldCount = (schema['details'] as List).length;
      final tableColumnCount = ((schema['tables'] as List).first['columns'] as List).length;
      
      _log('Detected $detailFieldCount detail fields');
      _log('Detected $tableColumnCount table columns');
      
      // ✅ Track parsing completion
      final parseEndTime = DateTime.now();
      final parseDuration = parseEndTime.difference(parseStartTime);
      
      try {
        parseTrace.setMetric('parse_duration_ms', parseDuration.inMilliseconds);
        parseTrace.putAttribute('detail_fields', '$detailFieldCount');
        parseTrace.putAttribute('table_columns', '$tableColumnCount');
        parseTrace.setMetric('success', 1);
      } catch (e) {
        _log('Parse trace metric error (ignored): $e');
      }
      
      // ✅ STOP PARSING TRACE (before user interaction)
      try {
        if (!parseTraceStopped) {
          await parseTrace.stop();
          parseTraceStopped = true;
          _log('✅ Parsing trace stopped successfully');
        }
      } catch (traceError) {
        _log('Parse trace stop error (ignored): $traceError');
      }
      
      // ✅ Navigate to field mapping screen (USER INTERACTION - NOT TRACED)
      if (!mounted) return;
      
      final mappedTemplate = await Navigator.push<TemplateMapping>(
        context,
        MaterialPageRoute(
          builder: (context) => FieldMappingScreen(
            detectedSchema: schema,
            fileName: file.name,
            templateType: fileExtension == 'pdf' 
                ? TemplateMappingType.pdf 
                : TemplateMappingType.excel,
            isEditMode: false,
          ),
        ),
      );
      
      if (mappedTemplate == null) {
        _log('User cancelled field mapping');
        return;
      }
      
      _log('User completed mapping: ${mappedTemplate.name}');
      
      // ✅ STEP 2: Create Performance Trace for Saving
      final saveTrace = FirebasePerformance.instance.newTrace('template_save');
      bool saveTraceStopped = false;
      
      // ✅ Convert mapped template back to schema format for Firestore
      final finalSchema = _convertTemplateToSchema(mappedTemplate);
      
      try {
        // ✅ START TRACE NOW (after user mapping is complete)
        await saveTrace.start();
        final saveStartTime = DateTime.now();
        
        if (uid == 'unknown') {
          throw StateError('User not authenticated');
        }

        _log('Saving to Firestore (custom_schemas)…');
        final savedId = await _saveCustomSchema(finalSchema, file.name);
        _log('Saved schemaId: $savedId');

        // ✅ Verify save
        final exists = await _verifySaved(uid, savedId);
        _log('Verify saved doc: ${exists ? "FOUND" : "MISSING"}');

        if (!exists) {
          throw StateError('Schema save verification failed');
        }

       // ✅ No draft creation needed - user will create report when they save
       _log('Template schema saved: $savedId');
        
        // ✅ Track save completion
        final saveEndTime = DateTime.now();
        final saveDuration = saveEndTime.difference(saveStartTime);
        
        try {
          saveTrace.setMetric('save_duration_ms', saveDuration.inMilliseconds);
          saveTrace.setMetric('field_count', detailFieldCount + tableColumnCount);
          saveTrace.putAttribute('template_name', mappedTemplate.name);
          saveTrace.setMetric('success', 1);
        } catch (e) {
          _log('Save trace metric error (ignored): $e');
        }
        
        // ✅ STOP SAVE TRACE
        try {
          if (!saveTraceStopped) {
            await saveTrace.stop();
            saveTraceStopped = true;
            _log('✅ Save trace stopped successfully');
          }
        } catch (traceError) {
          _log('Save trace stop error (ignored): $traceError');
        }
        
        // ✅ Log Analytics Event
        try {
          await FirebaseAnalytics.instance.logEvent(
            name: 'template_uploaded',
            parameters: {
              'user_id': uid,
              'template_name': mappedTemplate.name,
              'file_type': fileExtension,
              'field_count': detailFieldCount + tableColumnCount,
              'detail_fields': detailFieldCount,
              'table_columns': tableColumnCount,
            },
          );
        } catch (analyticsError) {
          _log('Analytics error (ignored): $analyticsError');
        }

        if (!mounted) return;

        // ✅ NAVIGATE TO THE REPORT
        _log('Navigating to report screen with schemaId: $savedId');
        
        final navigationResult = await Navigator.pushNamed(
          context,
          '/qc_report',
          arguments: {
            'schemaId': savedId,
            'schemaTitle': mappedTemplate.name,
            'userId': uid,
            'reportId': null,  // ✅ CHANGED: null = new report, user fills it themselves
          },
        );

        // ✅ After returning from report, trigger catalog refresh
        widget.onSchemaGenerated?.call();
        
      } catch (saveError) {
        // ✅ Track save failure
        try {
          saveTrace.setMetric('success', 0);
          if (!saveTraceStopped) {
            await saveTrace.stop();
            saveTraceStopped = true;
          }
        } catch (traceError) {
          _log('Save trace stop error on failure (ignored): $traceError');
        }
        rethrow;
      }
      
    } catch (e) {
      _log('ERROR: $e');
      
      // ✅ Track parsing failure
      try {
        parseTrace.setMetric('success', 0);
        parseTrace.putAttribute('error', e.toString());
        if (!parseTraceStopped) {
          await parseTrace.stop();
          parseTraceStopped = true;
        }
      } catch (traceError) {
        _log('Parse trace stop error on failure (ignored): $traceError');
      }
      
      // ✅ Log failure to Analytics
      try {
        await FirebaseAnalytics.instance.logEvent(
          name: 'template_upload_failed',
          parameters: {
            'user_id': uid,
            'error': e.toString(),
            'error_type': e.runtimeType.toString(),
          },
        );
      } catch (analyticsError) {
        _log('Analytics error (ignored): $analyticsError');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ✅ Convert TemplateMapping to schema format for Firestore
  Map<String, dynamic> _convertTemplateToSchema(TemplateMapping template) {
    return {
      'title': template.name,
      'details': template.detailFields.map((f) => {
        'key': f.key,
        'label': f.label,
        'type': _fieldTypeToString(f.type),
        'required': f.required,
        'formula': f.formula,
        'dependencies': f.dependencies,
        'options': f.options,
        'decimals': f.decimals,
        'unit': f.unit,
      }).toList(),
      'tables': template.tables.map((t) => {
        'key': t.key,
        'label': t.label,
        'columns': t.columns.map((c) => {
          'key': c.key,
          'label': c.label,
          'type': _fieldTypeToString(c.type),
          'width': c.width,
          'formula': c.formula,
          'dependencies': c.dependencies,
          'options': c.options,
          'decimals': c.decimals,
          'unit': c.unit,
        }).toList(),
        'minRows': t.minRows,
      }).toList(),
    };
  }

  // ✅ Helper to convert FieldType enum to string
  String _fieldTypeToString(FieldType type) {
    switch (type) {
      case FieldType.text:
        return 'text';
      case FieldType.number:
        return 'number';
      case FieldType.date:
        return 'date';
      case FieldType.dropdown:
        return 'dropdown';
      case FieldType.calculated:
        return 'calculated';
      case FieldType.textarea:
        return 'textarea';
    }
  }

  /// Returns schemaId actually used (handles duplicates).
  Future<String> _saveCustomSchema(Map<String, dynamic> schema, String fileName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('User not authenticated');

    final db = FirebaseFirestore.instance;
    final col = db.collection('users').doc(uid).collection('custom_schemas');

    final String title = (schema['title'] as String?)?.trim().isNotEmpty == true
        ? (schema['title'] as String).trim()
        : 'Untitled Template';

    final baseId = _titleToSchemaId(title);
    final baseRef = await col.doc(baseId).get();

    String schemaIdToUse = baseId;
    if (baseRef.exists) {
      _log('Conflict: "$title" exists as $baseId');
      final action = await _confirmConflictAction(title);
      if (action == _ConflictAction.cancel) {
        throw StateError('Upload cancelled by user');
      } else if (action == _ConflictAction.keepBoth) {
        schemaIdToUse = await _getUniqueSchemaId(col, baseId);
        _log('Keeping both → new id: $schemaIdToUse');
      } else {
        _log('Replacing existing schema at $baseId');
      }
    }

    final now = FieldValue.serverTimestamp();
    final toSave = {
      'schemaId': schemaIdToUse,
      'title': title,
      'schema': schema,
      'fileName': fileName,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': uid,
    };

    await col.doc(schemaIdToUse).set(toSave);
    return schemaIdToUse;
  }

  Future<bool> _verifySaved(String uid, String schemaId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_schemas')
          .doc(schemaId)
          .get();
      final ok = snap.exists && snap.data()?['schema'] != null;
      if (!ok) {
        _log('Doc present? ${snap.exists}, schema key present? ${snap.data()?['schema'] != null}');
      }
      return ok;
    } catch (e) {
      _log('Verify error: $e');
      return false;
    }
  }


  Future<_ConflictAction> _confirmConflictAction(String title) async {
    return await showDialog<_ConflictAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Template exists'),
            content: Text('A custom template named "$title" already exists.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, _ConflictAction.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _ConflictAction.keepBoth),
                child: const Text('Keep both'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, _ConflictAction.replace),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        _ConflictAction.cancel;
  }

  Future<String> _getUniqueSchemaId(
    CollectionReference<Map<String, dynamic>> col,
    String baseId,
  ) async {
    var i = 2;
    var candidate = '${baseId}_$i';
    while ((await col.doc(candidate).get()).exists) {
      i++;
      candidate = '${baseId}_$i';
    }
    return candidate;
  }

  String _titleToSchemaId(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: widget.heroTag ?? 'template_upload_fab',
      onPressed: _uploading ? null : _handleUpload,
      icon: _uploading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.upload_file),
      label: Text(_uploading ? 'Processing...' : 'Upload Template'),
    );
  }
}