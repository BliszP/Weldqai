// lib/features/reports/screens/report_catalog_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/features/reports/widgets/template_upload_button.dart';
import 'package:weldqai_app/screens/field_mapping_screen.dart';
import 'package:weldqai_app/core/models/template_mapping.dart';
class ReportCatalogScreen extends StatefulWidget {
  const ReportCatalogScreen({
    super.key,
    required this.userId,
    this.projectId,
  });

  final String userId;
  final String? projectId;

  @override
  State<ReportCatalogScreen> createState() => _ReportCatalogScreenState();
}

class _ReportCatalogScreenState extends State<ReportCatalogScreen> {
  late Future<List<_SchemaEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadSchemas();
  }

  Future<List<_SchemaEntry>> _loadSchemas() async {
    const files = <String>[
      'assets/schemas/welding_operation.json',
      'assets/schemas/structural_fillet.json',
      'assets/schemas/visual_inspection.json',
      'assets/schemas/ndt_rt.json',
      'assets/schemas/ndt_ut.json',
      'assets/schemas/ndt_mpi.json',
      'assets/schemas/hydrotest.json',
      'assets/schemas/coating_painting.json',
      'assets/schemas/anode_installation.json',
      'assets/schemas/pipe_tally_log.json',
      'assets/schemas/wps_pqr_register.json',
      'assets/schemas/welder_qualification_record.json',
      'assets/schemas/pwht_record.json',
      'assets/schemas/fit_up_inspection_report.json',
      'assets/schemas/custom_template_example.json',
    ];

    final out = <_SchemaEntry>[];

    for (final path in files) {
      try {
        final raw = await rootBundle.loadString(path);
        final json = jsonDecode(raw);
        String? title;
        if (json is Map && json['title'] is String) title = json['title'] as String;
        title ??= _prettyName(path.split('/').last.replaceAll('.json', ''));
        final id = path.split('/').last.replaceAll('.json', '');
        out.add(_SchemaEntry(id: id, title: title, isCustom: false));
      } catch (_) {}
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('custom_schemas')
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          out.add(_SchemaEntry(
            id: doc.id,
            title: (data['title'] as String?) ?? 'Untitled Template',
            isCustom: true,
          ));
        }
      } catch (_) {}
    }

    out.sort((a, b) {
      if (a.isCustom != b.isCustom) return a.isCustom ? 1 : -1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return out;
  }

  String _prettyName(String slug) {
    return slug
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSchemas();
    });
    await _future;
  }

  Future<void> _openSchema(_SchemaEntry e) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to view reports')),
        );
      }
      return;
    }

    final result = await Navigator.pushNamed(
      context,
      Paths.dynamicReport,
      arguments: {
        'schemaId': e.id,
        'schemaTitle': e.title,
        'userId': widget.userId,
        if (widget.projectId != null) 'projectId': widget.projectId!,
      },
    );
    
    if (!mounted) return;
    if (result == true) {
      setState(() {
        _future = _loadSchemas();
      });
    }
  }

  // ✅ NEW: Duplicate template
  Future<void> _duplicateCustomSchema(String schemaId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Please sign in')),
        );
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_schemas')
          .doc(schemaId)
          .get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Template not found')),
          );
        }
        return;
      }

      final data = doc.data()!;
      final originalTitle = data['title'] as String? ?? 'Untitled Template';
      
      if (!mounted) return;
      final newName = await _showDuplicateDialog(originalTitle);
      
      if (newName == null || newName.trim().isEmpty) {
        return;
      }

      final baseId = _titleToSchemaId(newName);
      final newSchemaId = await _getUniqueSchemaId(uid, baseId);
      
      final now = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_schemas')
          .doc(newSchemaId)
          .set({
        'schemaId': newSchemaId,
        'title': newName,
        'schema': data['schema'],
        'fileName': data['fileName'],
        'createdAt': now,
        'updatedAt': now,
        'createdBy': uid,
        'duplicatedFrom': schemaId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Template duplicated as "$newName"'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Edit',
              textColor: Colors.white,
              onPressed: () => _editCustomSchema(newSchemaId),
            ),
          ),
        );
        
        setState(() {
          _future = _loadSchemas();
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error duplicating template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _showDuplicateDialog(String originalTitle) async {
    final controller = TextEditingController(text: '$originalTitle (Copy)');
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a copy of "$originalTitle"',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'New Template Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
  }

  String _titleToSchemaId(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<String> _getUniqueSchemaId(String uid, String baseId) async {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('custom_schemas');
    
    final baseDoc = await col.doc(baseId).get();
    if (!baseDoc.exists) return baseId;
    
    var i = 2;
    var candidate = '${baseId}_$i';
    while ((await col.doc(candidate).get()).exists) {
      i++;
      candidate = '${baseId}_$i';
    }
    return candidate;
  }

  Future<void> _editCustomSchema(String schemaId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Please sign in')),
        );
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_schemas')
          .doc(schemaId)
          .get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Template not found')),
          );
        }
        return;
      }

      final data = doc.data()!;
      final schema = data['schema'] as Map<String, dynamic>;
      
      if (!mounted) return;

      final updatedTemplate = await Navigator.push<TemplateMapping>(
        context,
        MaterialPageRoute(
          builder: (context) => FieldMappingScreen(
            detectedSchema: schema,
            fileName: data['fileName'] as String? ?? 'template.xlsx',
            templateType: TemplateMappingType.excel,
            isEditMode: true, // ✅ NEW: This is editing an existing template
          ),
        ),
      );

      if (updatedTemplate == null) {
        return;
      }

      final updatedSchema = _convertTemplateToSchema(updatedTemplate);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_schemas')
          .doc(schemaId)
          .update({
        'schema': updatedSchema,
        'title': updatedTemplate.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ "${updatedTemplate.name}" updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        
        setState(() {
          _future = _loadSchemas();
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error editing template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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

  Future<void> _deleteCustomSchema(String schemaId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error: User not authenticated'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    int reportCount = 0;
    try {
      final reportsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reports')
          .doc(schemaId)
          .collection('items')
          .get();
      reportCount = reportsSnapshot.docs.length;
    } catch (_) {}

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Text('Delete Everything?'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'THIS WILL PERMANENTLY DELETE:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              const Text('- Template structure'),
              const Text('- ALL filled reports using this template'),
              if (reportCount > 0)
                Text('- Your $reportCount saved report${reportCount == 1 ? '' : 's'}'),
              const Text('- All activity entries'),
              const Text('- All queue entries'),
              const Text('- All alerts'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'CANNOT BE UNDONE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All data will be permanently lost.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Template: "$schemaId"',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
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
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Text(reportCount > 0 
                  ? 'Deleting template and $reportCount report${reportCount == 1 ? '' : 's'}...'
                  : 'Deleting template...'),
            ],
          ),
          duration: const Duration(seconds: 60),
        ),
      );
    }

    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);

      final schemaRef = userRef.collection('custom_schemas').doc(schemaId);
      final schemaSnapshot = await schemaRef.get();
      
      if (!schemaSnapshot.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Template "$schemaId" not found'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _future = _loadSchemas();
          });
        }
        return;
      }

      final schemaData = schemaSnapshot.data();
      final templateTitle = schemaData?['title'] as String? ?? schemaId;

      final reportsRef = userRef.collection('reports').doc(schemaId).collection('items');
      final reportDocs = await reportsRef.get();
      final batch1 = db.batch();
      int deleteCount = 0;
      
      for (final doc in reportDocs.docs) {
        batch1.delete(doc.reference);
        deleteCount++;
        
        if (deleteCount % 500 == 0) {
          await batch1.commit();
        }
      }
      if (deleteCount % 500 != 0) {
        await batch1.commit();
      }

      await userRef.collection('reports').doc(schemaId).delete();

      final activityDocs = await userRef
          .collection('activity')
          .where('schema', isEqualTo: schemaId)
          .get();
      
      final batch2 = db.batch();
      for (final doc in activityDocs.docs) {
        batch2.delete(doc.reference);
      }
      await batch2.commit();

      final queueDocs = await userRef
          .collection('queue')
          .where('schema', isEqualTo: schemaId)
          .get();
      
      final batch3 = db.batch();
      for (final doc in queueDocs.docs) {
        batch3.delete(doc.reference);
      }
      await batch3.commit();

      final alertDocs = await userRef
          .collection('alerts')
          .where('schema', isEqualTo: schemaId)
          .get();
      
      final batch4 = db.batch();
      for (final doc in alertDocs.docs) {
        batch4.delete(doc.reference);
      }
      await batch4.commit();

      await schemaRef.delete();

      final verifySnapshot = await schemaRef.get();
      if (verifySnapshot.exists) {
        throw Exception('Failed to delete template - document still exists');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('✓ "$templateTitle" deleted'),
                    ),
                  ],
                ),
                if (deleteCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 28),
                    child: Text(
                      'Removed $deleteCount report${deleteCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        
        setState(() {
          _future = _loadSchemas();
        });
      }

    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❌ Firebase Error',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Code: ${e.code}'),
                Text('Message: ${e.message ?? "Unknown error"}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _deleteCustomSchema(schemaId),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❌ Delete Failed',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Error: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _deleteCustomSchema(schemaId),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QC Report Catalog')),
      body: FutureBuilder<List<_SchemaEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <_SchemaEntry>[];
          if (items.isEmpty) {
            return const Center(child: Text('No schemas found.'));
          }

          final builtIn = items.where((e) => !e.isCustom).toList();
          final custom = items.where((e) => e.isCustom).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                if (builtIn.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Built-in Reports',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${builtIn.length} templates — tap to expand'),
                      initiallyExpanded: false,
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: builtIn.map((e) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(e.title),
                              subtitle: Text(e.id),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openSchema(e),
                            ),
                          )).toList(),
                    ),
                  ),
                if (custom.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Custom Templates',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ...custom.map((e) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.upload_file),
                          title: Text(e.title),
                          subtitle: Text(e.id),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ✅ NEW: Duplicate Icon
                              IconButton(
                                icon: const Icon(Icons.content_copy, color: Colors.green),
                                tooltip: 'Duplicate template',
                                onPressed: () => _duplicateCustomSchema(e.id),
                              ),
                              // Edit Icon
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                tooltip: 'Edit template',
                                onPressed: () => _editCustomSchema(e.id),
                              ),
                              // Delete Icon
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Delete template',
                                onPressed: () => _deleteCustomSchema(e.id),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _openSchema(e),
                        ),
                      )),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: TemplateUploadButton(
        heroTag: 'catalog_upload_fab',
        onSchemaGenerated: () {
          if (mounted) {
            setState(() {
              _future = _loadSchemas();
            });
          }
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _SchemaEntry {
  final String id;
  final String title;
  final bool isCustom;

  const _SchemaEntry({
    required this.id,
    required this.title,
    required this.isCustom,
  });
}