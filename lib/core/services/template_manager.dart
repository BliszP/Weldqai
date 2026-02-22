// lib/core/services/template_manager.dart
// Manages custom template mappings - save, load, search

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/template_mapping.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class TemplateManager {
  static const String _storageKey = 'custom_templates';
  final _uuid = const Uuid();
  
  // Cache
  List<TemplateMapping>? _cachedTemplates;
  
  /// Save a new custom template
  Future<TemplateMapping> saveTemplate(TemplateMapping template) async {
    final templates = await getCustomTemplates();
    
    // Check if updating existing
    final existingIndex = templates.indexWhere((t) => t.id == template.id);
    if (existingIndex >= 0) {
      templates[existingIndex] = template.copyWith(
        lastModified: DateTime.now(),
      );
    } else {
      templates.add(template);
    }
    
    await _saveToStorage(templates);
    _cachedTemplates = templates;
    
    return template;
  }
  
  /// Get all custom templates
  Future<List<TemplateMapping>> getCustomTemplates() async {
    if (_cachedTemplates != null) {
      return _cachedTemplates!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);
    
    if (json == null || json.isEmpty) {
      _cachedTemplates = [];
      return [];
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(json);
      _cachedTemplates = decoded
          .map((t) => TemplateMapping.fromJson(t))
          .toList();
      return _cachedTemplates!;
    } catch (e) {
      AppLogger.error('Error loading templates: $e');
      _cachedTemplates = [];
      return [];
    }
  }
  
  /// Get all templates (built-in + custom)
  Future<List<TemplateMapping>> getAllTemplates() async {
    final custom = await getCustomTemplates();
    final builtIn = _getBuiltInTemplates();
    return [...builtIn, ...custom];
  }
  
  /// Get template by ID
  Future<TemplateMapping?> getTemplateById(String id) async {
    final templates = await getAllTemplates();
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }
  
  /// Delete template
  Future<bool> deleteTemplate(String id) async {
    final templates = await getCustomTemplates();
    final initialLength = templates.length;
    templates.removeWhere((t) => t.id == id);
    
    if (templates.length < initialLength) {
      await _saveToStorage(templates);
      _cachedTemplates = templates;
      return true;
    }
    
    return false;
  }
  
  /// Increment usage count
  Future<void> incrementUsageCount(String templateId) async {
    final templates = await getCustomTemplates();
    final index = templates.indexWhere((t) => t.id == templateId);
    
    if (index >= 0) {
      templates[index] = templates[index].copyWith(
        usageCount: templates[index].usageCount + 1,
        lastModified: DateTime.now(),
      );
      await _saveToStorage(templates);
      _cachedTemplates = templates;
    }
  }
  
  /// Search templates
  Future<List<TemplateMapping>> searchTemplates(String query) async {
    final templates = await getAllTemplates();
    if (query.trim().isEmpty) return templates;
    
    final lowerQuery = query.toLowerCase();
    return templates.where((t) {
      return t.name.toLowerCase().contains(lowerQuery) ||
             (t.description?.toLowerCase().contains(lowerQuery) ?? false) ||
             (t.originalFileName?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }
  
  /// Find template by fingerprint (to recognize uploaded templates)
  Future<TemplateMapping?> findByFingerprint(String fingerprint) async {
    final templates = await getAllTemplates();
    try {
      return templates.firstWhere((t) => t.fingerprint == fingerprint);
    } catch (e) {
      return null;
    }
  }
  
  /// Create new template from auto-detected schema
  TemplateMapping createFromSchema(
    Map<String, dynamic> schema, {
    String? fileName,
    TemplateMappingType type = TemplateMappingType.excel,
  }) {
    final id = _uuid.v4();
    
    // Convert schema to field mappings
    final detailFields = <FieldMapping>[];
    if (schema['details'] != null) {
      int order = 0;
      for (final detail in schema['details']) {
        detailFields.add(FieldMapping(
          key: detail['key'],
          label: detail['label'],
          type: _stringToFieldType(detail['type']),
          order: order++,
          required: false,
        ));
      }
    }
    
    // Convert tables
    final tables = <TableMapping>[];
    if (schema['tables'] != null) {
      for (final table in schema['tables']) {
        final columns = <ColumnMapping>[];
        int order = 0;
        
        for (final col in table['columns']) {
          columns.add(ColumnMapping(
            key: col['key'],
            label: col['label'],
            type: _stringToFieldType(col['type']),
            width: (col['width'] ?? 140.0).toDouble(),
            order: order++,
          ));
        }
        
        tables.add(TableMapping(
          key: table['key'],
          label: table['label'],
          columns: columns,
          minRows: table['minRows'] ?? 5,
        ));
      }
    }
    
    return TemplateMapping(
      id: id,
      name: schema['title'] ?? fileName ?? 'Custom Template',
      type: type,
      originalFileName: fileName,
      detailFields: detailFields,
      tables: tables,
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
    );
  }
  
  /// Get most used templates
  Future<List<TemplateMapping>> getMostUsed({int limit = 5}) async {
    final templates = await getAllTemplates();
    templates.sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return templates.take(limit).toList();
  }
  
  /// Get recently used templates
  Future<List<TemplateMapping>> getRecentlyUsed({int limit = 5}) async {
    final templates = await getAllTemplates();
    templates.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return templates.take(limit).toList();
  }
  
  // ==================== PRIVATE HELPERS ====================
  
  Future<void> _saveToStorage(List<TemplateMapping> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(templates.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }
  
  FieldType _stringToFieldType(String? type) {
    switch (type?.toLowerCase()) {
      case 'number':
        return FieldType.number;
      case 'date':
        return FieldType.date;
      case 'dropdown':
        return FieldType.dropdown;
      case 'calculated':
        return FieldType.calculated;
      case 'textarea':
        return FieldType.textarea;
      default:
        return FieldType.text;
    }
  }
  
  /// Built-in templates (pre-configured for common standards)
  List<TemplateMapping> _getBuiltInTemplates() {
    return [
      // AWS D1.1 Visual Inspection
      TemplateMapping(
        id: 'built_in_aws_d1_1_visual',
        name: 'AWS D1.1 Visual Inspection',
        description: 'Standard visual weld inspection form',
        type: TemplateMappingType.excel,
        detailFields: [
          FieldMapping(
            key: 'project_name',
            label: 'Project Name',
            type: FieldType.text,
            required: true,
            order: 0,
          ),
          FieldMapping(
            key: 'weld_id',
            label: 'Weld ID',
            type: FieldType.text,
            required: true,
            order: 1,
          ),
          FieldMapping(
            key: 'inspector',
            label: 'Inspector',
            type: FieldType.text,
            required: true,
            order: 2,
          ),
          FieldMapping(
            key: 'date',
            label: 'Date',
            type: FieldType.date,
            required: true,
            order: 3,
          ),
          FieldMapping(
            key: 'weld_type',
            label: 'Weld Type',
            type: FieldType.dropdown,
            options: ['Butt Weld', 'Fillet Weld', 'Corner Weld', 'T-Joint'],
            required: true,
            order: 4,
          ),
        ],
        tables: [
          TableMapping(
            key: 'entries',
            label: 'Visual Inspection Results',
            columns: [
              ColumnMapping(
                key: 'location',
                label: 'Location',
                type: FieldType.text,
                width: 150,
                order: 0,
              ),
              ColumnMapping(
                key: 'appearance',
                label: 'Appearance',
                type: FieldType.dropdown,
                options: ['Acceptable', 'Unacceptable'],
                width: 120,
                order: 1,
              ),
              ColumnMapping(
                key: 'undercut',
                label: 'Undercut (mm)',
                type: FieldType.number,
                width: 120,
                order: 2,
                decimals: 2,
              ),
              ColumnMapping(
                key: 'result',
                label: 'Result',
                type: FieldType.dropdown,
                options: ['Pass', 'Fail', 'Review'],
                width: 100,
                order: 3,
              ),
              ColumnMapping(
                key: 'remarks',
                label: 'Remarks',
                type: FieldType.text,
                width: 200,
                order: 4,
              ),
            ],
            minRows: 5,
          ),
        ],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      ),
      
      // ASME IX Welding Parameters
      TemplateMapping(
        id: 'built_in_asme_ix_params',
        name: 'ASME IX Welding Parameters',
        description: 'Welding procedure qualification record',
        type: TemplateMappingType.excel,
        detailFields: [
          FieldMapping(
            key: 'procedure_number',
            label: 'Procedure Number',
            type: FieldType.text,
            required: true,
            order: 0,
          ),
          FieldMapping(
            key: 'welder',
            label: 'Welder',
            type: FieldType.text,
            required: true,
            order: 1,
          ),
          FieldMapping(
            key: 'date',
            label: 'Date',
            type: FieldType.date,
            required: true,
            order: 2,
          ),
        ],
        tables: [
          TableMapping(
            key: 'welding_passes',
            label: 'Welding Passes',
            columns: [
              ColumnMapping(
                key: 'pass_no',
                label: 'Pass No.',
                type: FieldType.number,
                width: 80,
                order: 0,
              ),
              ColumnMapping(
                key: 'voltage',
                label: 'Voltage (V)',
                type: FieldType.number,
                width: 100,
                order: 1,
                decimals: 1,
              ),
              ColumnMapping(
                key: 'current',
                label: 'Current (A)',
                type: FieldType.number,
                width: 100,
                order: 2,
                decimals: 0,
              ),
              ColumnMapping(
                key: 'speed',
                label: 'Travel Speed (mm/s)',
                type: FieldType.number,
                width: 150,
                order: 3,
                decimals: 1,
              ),
              ColumnMapping(
                key: 'heat_input',
                label: 'Heat Input (kJ/mm)',
                type: FieldType.calculated,
                formula: '(voltage * current) / (speed * 1000)',
                dependencies: ['voltage', 'current', 'speed'],
                width: 140,
                order: 4,
                decimals: 2,
                unit: 'kJ/mm',
              ),
              ColumnMapping(
                key: 'interpass_temp',
                label: 'Interpass Temp (°C)',
                type: FieldType.number,
                width: 140,
                order: 5,
                decimals: 0,
              ),
            ],
            minRows: 10,
          ),
        ],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      ),
    ];
  }
}