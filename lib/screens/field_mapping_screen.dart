// lib/screens/field_mapping_screen.dart
// Interactive screen for mapping template fields - WITH TABBED CONFIGURE VIEW

// ignore_for_file: prefer_final_fields

import 'package:flutter/material.dart';
import '../core/models/template_mapping.dart';
import '../core/services/template_manager.dart';
import '../core/services/formula_engine.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class FieldMappingScreen extends StatefulWidget {
  final Map<String, dynamic> detectedSchema;
  final String? fileName;
  final TemplateMappingType templateType;
  final bool isEditMode; // ✅ NEW: Flag to detect if editing existing template

  const FieldMappingScreen({
    super.key,
    required this.detectedSchema,
    this.fileName,
    this.templateType = TemplateMappingType.excel,
    this.isEditMode = false, // ✅ NEW: Default to false (new upload)
  });

  @override
  State<FieldMappingScreen> createState() => _FieldMappingScreenState();
}

class _FieldMappingScreenState extends State<FieldMappingScreen> with SingleTickerProviderStateMixin {
  final _templateManager = TemplateManager();
  final _formulaEngine = FormulaEngine();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  late TemplateMapping _workingTemplate;
  int _currentStep = 0;
  
  List<String> _selectedDetailKeys = [];
  List<String> _selectedEntryKeys = [];
  Set<String> _excludedKeys = {};
  
  // ✅ NEW: Tab controller for Configure step
  late TabController _configureTabController;
  int _currentConfigureTab = 0;

  @override
  void initState() {
    super.initState();
    _workingTemplate = _templateManager.createFromSchema(
      widget.detectedSchema,
      fileName: widget.fileName,
      type: widget.templateType,
    );
    _nameController.text = _workingTemplate.name;
    
    // ✅ SMART DETECTION: Restore organization only in EDIT mode
    if (widget.isEditMode) {
      // EDIT MODE: Restore previous field organization
      _selectedDetailKeys = _workingTemplate.detailFields.map((f) => f.key).toList();
      _selectedEntryKeys = _workingTemplate.tables.isNotEmpty
          ? _workingTemplate.tables.first.columns.map((c) => c.key).toList()
          : [];
      
      AppLogger.debug('🔄 EDIT MODE: Restored Details: ${_selectedDetailKeys.length} fields');
      AppLogger.debug('🔄 EDIT MODE: Restored Entries: ${_selectedEntryKeys.length} fields');
    } else {
      // NEW UPLOAD: Start with empty lists - all fields in "All Fields" pool
      _selectedDetailKeys = [];
      _selectedEntryKeys = [];
      
      AppLogger.debug('✨ NEW UPLOAD: All ${_workingTemplate.detailFields.length} fields in "All Fields" pool');
      AppLogger.debug('📋 Details: 0 fields (organize manually)');
      AppLogger.debug('📊 Entries: 0 fields (organize manually)');
    }
    
    // Initialize tab controller
    _configureTabController = TabController(length: 2, vsync: this);
    _configureTabController.addListener(() {
      setState(() {
        _currentConfigureTab = _configureTabController.index;
      });
    });
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _configureTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Template Fields'),
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(child: _buildCurrentStep()),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStepIndicator(0, 'Review', _currentStep >= 0),
          Expanded(child: _buildStepLine(_currentStep >= 1)),
          _buildStepIndicator(1, 'Configure', _currentStep >= 1),
          Expanded(child: _buildStepLine(_currentStep >= 2)),
          _buildStepIndicator(2, 'Save', _currentStep >= 2),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive 
                ? Theme.of(context).primaryColor 
                : (isDark ? Colors.grey[700] : Colors.grey[300]),
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive 
                    ? Colors.white 
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label, 
          style: TextStyle(
            fontSize: 12, 
            color: isActive 
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? Colors.grey[500] : Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: 2,
      color: isActive 
          ? Theme.of(context).primaryColor 
          : (isDark ? Colors.grey[700] : Colors.grey[300]),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildReviewFieldsStep();
      case 1:
        return _buildConfigureFieldsStep();
      case 2:
        return _buildSaveTemplateStep();
      default:
        return const SizedBox();
    }
  }

  // ==================== STEP 1: REVIEW FIELDS (unchanged) ====================

  Widget _buildReviewFieldsStep() {
    final allFields = <Map<String, dynamic>>[];
    
    for (final field in _workingTemplate.detailFields) {
      allFields.add({
        'key': field.key,
        'label': field.label,
        'type': field.type,
        'order': field.order,
        'isColumn': false,
      });
    }
    
    if (_workingTemplate.tables.isNotEmpty) {
      for (final column in _workingTemplate.tables.first.columns) {
        allFields.add({
          'key': column.key,
          'label': column.label,
          'type': column.type,
          'order': column.order,
          'isColumn': true,
        });
      }
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Organize Fields', style: Theme.of(context).textTheme.headlineSmall),
              ),
              IconButton.filled(
                icon: const Icon(Icons.add),
                tooltip: 'Add Custom Field',
                onPressed: _showAddCustomFieldDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Drag fields between sections. Long-press to exclude. Double-tap to edit.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          
          Card(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[850] 
                : Colors.grey[100],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'All Fields (${allFields.where((f) => !_excludedKeys.contains(f['key'])).length})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allFields
                        .where((f) => !_excludedKeys.contains(f['key']) && 
                                     !_selectedDetailKeys.contains(f['key']) && 
                                     !_selectedEntryKeys.contains(f['key']))
                        .map((field) => _buildDraggableFieldChip(field))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          _buildReorderableSection(
            title: '📋 Details Section',
            subtitle: 'Single-value fields',
            selectedKeys: _selectedDetailKeys,
            color: Colors.blue,
            sectionType: 'details',
            onAddField: () => _showAddCustomFieldDialog(sectionType: 'details'),
          ),
          
          const SizedBox(height: 16),
          
          _buildReorderableSection(
            title: '📊 Entries Section',
            subtitle: 'Table columns',
            selectedKeys: _selectedEntryKeys,
            color: Colors.green,
            sectionType: 'entries',
            onAddField: () => _showAddCustomFieldDialog(sectionType: 'entries'),
          ),
          
          const SizedBox(height: 16),
          
          if (_excludedKeys.isNotEmpty) _buildExcludedSection(),
        ],
      ),
    );
  }

  // ==================== STEP 2: CONFIGURE (NEW TABBED VIEW) ====================

  Widget _buildConfigureFieldsStep() {
    AppLogger.debug('🔍 CONFIGURE: Details=$_selectedDetailKeys, Entries=$_selectedEntryKeys');
    
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text('Configure Fields', style: Theme.of(context).textTheme.headlineSmall),
              ),
              Text(
                '${_selectedDetailKeys.length + _selectedEntryKeys.length} fields',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
        
        // ✅ NEW: Tab Bar (MAXIMUM CONTRAST - FINAL FIX)
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[850] 
                : Colors.grey[100],
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[700]! 
                    : Colors.grey[300]!,
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _configureTabController,
            labelColor: Theme.of(context).primaryColor,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            // ✅ CRITICAL: Make inactive tabs MUCH more visible
            unselectedLabelColor: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[100]  // ✅ Almost white for dark mode!
                : Colors.grey[800],  // ✅ Almost black for light mode!
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            indicatorColor: Theme.of(context).primaryColor,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.description, size: 20),
                    const SizedBox(width: 8),
                    Text('Details (${_selectedDetailKeys.length})'),
                  ],
                ),
              ),
              Tab(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.table_chart, size: 20),
                    const SizedBox(width: 8),
                    Text('Entries (${_selectedEntryKeys.length})'),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // ✅ NEW: Tab View Content
        Expanded(
          child: TabBarView(
            controller: _configureTabController,
            children: [
              _buildDetailFieldsGrid(),
              _buildEntryFieldsGrid(),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ NEW: Details fields in grid layout (OPTIMIZED)
  Widget _buildDetailFieldsGrid() {
    if (_selectedDetailKeys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No detail fields selected',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Go back to Review step to add fields',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, // ✅ Max width per card
        childAspectRatio: 2.0, // ✅ More compact (width:height = 2:1)
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _selectedDetailKeys.length,
      itemBuilder: (context, index) {
        final key = _selectedDetailKeys[index];
        final field = _findFieldByKey(key);
        if (field == null) return const SizedBox.shrink();
        
        return _buildFieldCard(field, isColumn: false);
      },
    );
  }

  // ✅ NEW: Entry fields in grid layout (OPTIMIZED)
  Widget _buildEntryFieldsGrid() {
    if (_selectedEntryKeys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No entry columns selected',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Go back to Review step to add columns',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, // ✅ Max width per card
        childAspectRatio: 2.0, // ✅ More compact (width:height = 2:1)
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _selectedEntryKeys.length,
      itemBuilder: (context, index) {
        final key = _selectedEntryKeys[index];
        final field = _findFieldByKey(key);
        if (field == null) return const SizedBox.shrink();
        
        return _buildFieldCard(field, isColumn: true);
      },
    );
  }

  // ✅ NEW: Compact field configuration card (OPTIMIZED)
  Widget _buildFieldCard(FieldMapping field, {required bool isColumn}) {
    final typeColor = _getTypeColor(field.type);
    
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showFieldConfigDialog(field, isColumn: isColumn),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header - Field name + edit icon
              Row(
                children: [
                  Expanded(
                    child: Text(
                      field.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 14, color: Colors.grey[500]),
                ],
              ),
              const SizedBox(height: 6),
              
              // Type badge + additional info in one row
              Row(
                children: [
                  // Type badge
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: typeColor.withValues(alpha: 0.25), width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getTypeIcon(field.type), size: 11, color: typeColor),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _getFieldTypeLabel(field.type),
                              style: TextStyle(
                                fontSize: 10,
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Additional indicators
                  if (field.required && !isColumn)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.star, size: 11, color: Colors.orange[700]),
                    ),
                  
                  if (field.type == FieldType.dropdown && field.options != null && field.options!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '(${field.options!.length})',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  
                  if (field.type == FieldType.calculated && field.formula != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.functions, size: 11, color: Colors.purple[700]),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NEW: Full field configuration dialog
  Future<void> _showFieldConfigDialog(FieldMapping field, {required bool isColumn}) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(field.label),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Field Type
              DropdownButtonFormField<FieldType>(
                value: field.type,
                decoration: const InputDecoration(
                  labelText: 'Field Type',
                  border: OutlineInputBorder(),
                ),
                items: FieldType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_getTypeIcon(type), size: 18, color: _getTypeColor(type)),
                        const SizedBox(width: 8),
                        Text(_getFieldTypeLabel(type)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (newType) {
                  if (newType != null) {
                    _updateFieldType(field.key, newType, isColumn: isColumn);
                    Navigator.pop(context);
                    _showFieldConfigDialog(
                      _findFieldByKey(field.key)!,
                      isColumn: isColumn,
                    );
                  }
                },
              ),
              
              const SizedBox(height: 16),
              
              // Required checkbox (details only)
              if (!isColumn)
                CheckboxListTile(
                  title: const Text('Required Field'),
                  value: field.required,
                  onChanged: (value) {
                    _updateFieldRequired(field.key, value ?? false);
                    Navigator.pop(context);
                    _showFieldConfigDialog(
                      _findFieldByKey(field.key)!,
                      isColumn: isColumn,
                    );
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              
              // Formula configuration
              if (field.type == FieldType.calculated) ...[
                const SizedBox(height: 16),
                _buildFormulaConfig(field, isColumn: isColumn),
              ],
              
              // Dropdown options
              if (field.type == FieldType.dropdown) ...[
                const SizedBox(height: 16),
                _buildDropdownConfig(field, isColumn: isColumn),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper to get icon for field type
  IconData _getTypeIcon(FieldType type) {
    switch (type) {
      case FieldType.text:
        return Icons.text_fields;
      case FieldType.number:
        return Icons.numbers;
      case FieldType.date:
        return Icons.calendar_today;
      case FieldType.dropdown:
        return Icons.arrow_drop_down_circle;
      case FieldType.calculated:
        return Icons.functions;
      case FieldType.textarea:
        return Icons.notes;
    }
  }

  // Helper to get color for field type
  Color _getTypeColor(FieldType type) {
    switch (type) {
      case FieldType.text:
        return Colors.blue;
      case FieldType.number:
        return Colors.green;
      case FieldType.date:
        return Colors.orange;
      case FieldType.dropdown:
        return Colors.purple;
      case FieldType.calculated:
        return Colors.red;
      case FieldType.textarea:
        return Colors.teal;
    }
  }

  // ==================== STEP 3: SAVE (unchanged) ====================

  Widget _buildSaveTemplateStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Save Template', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Template Name *',
              border: OutlineInputBorder(),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Card(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.blue[900]?.withValues(alpha: 0.3) 
                : Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📊 Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('Details: ${_selectedDetailKeys.length}'),
                  Text('Entries: ${_selectedEntryKeys.length}'),
                  Text('Excluded: ${_excludedKeys.length}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ACTIONS ====================

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  if (mounted) setState(() => _currentStep--);
                },
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _currentStep < 2
                  ? () {
                      if (mounted) setState(() => _currentStep++);
                    }
                  : _saveTemplate,
              child: Text(_currentStep < 2 ? 'Continue' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ALL OTHER METHODS (unchanged from your code) ====================
  // I'll include the rest of your existing methods here...

  Future<void> _showAddCustomFieldDialog({String? sectionType}) async {
    final labelController = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          sectionType == 'details' 
              ? 'Add Detail Field' 
              : sectionType == 'entries'
                  ? 'Add Entry Column'
                  : 'Add Custom Field'
        ),
        content: TextField(
          controller: labelController,
          decoration: InputDecoration(
            labelText: 'Field Name',
            hintText: sectionType == 'details' 
                ? 'e.g., Inspector Signature'
                : sectionType == 'entries'
                    ? 'e.g., Serial Number'
                    : 'e.g., Custom Field',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (labelController.text.trim().isNotEmpty) {
                Navigator.pop(context, labelController.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty && mounted) {
      _addCustomField(result, sectionType: sectionType);
    }
  }

  void _addCustomField(String label, {String? sectionType}) {
    if (!mounted) return;
    
    setState(() {
      final baseKey = label
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final uniqueKey = '${baseKey}_${DateTime.now().millisecondsSinceEpoch}';
      
      if (sectionType == 'details') {
        final newField = FieldMapping(
          key: uniqueKey,
          label: label,
          type: FieldType.text,
          order: _workingTemplate.detailFields.length,
        );
        
        _workingTemplate = _workingTemplate.copyWith(
          detailFields: [..._workingTemplate.detailFields, newField],
        );
        
        _selectedDetailKeys.add(uniqueKey);
        AppLogger.info('✅ Added detail field: $uniqueKey = $label');
        
      } else if (sectionType == 'entries') {
        if (_workingTemplate.tables.isEmpty) {
          final defaultTable = TableMapping(
            key: 'entries',
            label: 'Entries',
            columns: [],
            minRows: 5,
          );
          _workingTemplate = _workingTemplate.copyWith(
            tables: [defaultTable],
          );
        }
        
        final newColumn = ColumnMapping(
          key: uniqueKey,
          label: label,
          type: FieldType.text,
          order: _workingTemplate.tables.first.columns.length,
        );
        
        final updatedTable = _workingTemplate.tables.first.copyWith(
          columns: [..._workingTemplate.tables.first.columns, newColumn],
        );
        
        _workingTemplate = _workingTemplate.copyWith(
          tables: [updatedTable, ..._workingTemplate.tables.skip(1)],
        );
        
        _selectedEntryKeys.add(uniqueKey);
        AppLogger.info('✅ Added entry column: $uniqueKey = $label');
        
      } else {
        final newField = FieldMapping(
          key: uniqueKey,
          label: label,
          type: FieldType.text,
          order: _workingTemplate.detailFields.length,
        );
        
        _workingTemplate = _workingTemplate.copyWith(
          detailFields: [..._workingTemplate.detailFields, newField],
        );
        
        AppLogger.info('✅ Added custom field to pool: $uniqueKey = $label');
      }
    });
    
    if (mounted) {
      final sectionName = sectionType == 'details' 
          ? 'Details section' 
          : sectionType == 'entries' 
              ? 'Entries section' 
              : 'All fields';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ "$label" added to $sectionName'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildDraggableFieldChip(Map<String, dynamic> field) {
    final key = field['key'] as String;
    final label = field['label'] as String;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Draggable<String>(
      data: key,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.blue[700] : Colors.blue.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildFieldChipContent(label),
      ),
      child: GestureDetector(
        onLongPress: () {
          if (!mounted) return;
          setState(() {
            _excludedKeys.add(key);
            _selectedDetailKeys.remove(key);
            _selectedEntryKeys.remove(key);
          });
        },
        onDoubleTap: () => _editFieldName(key, label),
        child: _buildFieldChipContent(label),
      ),
    );
  }

  Widget _buildFieldChipContent(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        border: Border.all(color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 4),
          Icon(Icons.edit, size: 12, color: Colors.grey[600]),
        ],
      ),
    );
  }

  Future<void> _editFieldName(String key, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Field Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Field Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (newName != null && newName.isNotEmpty && newName != currentLabel && mounted) {
      _updateFieldLabel(key, newName);
    }
  }

  void _updateFieldLabel(String key, String newLabel) {
    if (!mounted) return;
    
    setState(() {
      final detailIndex = _workingTemplate.detailFields.indexWhere((f) => f.key == key);
      if (detailIndex >= 0) {
        final field = _workingTemplate.detailFields[detailIndex];
        _workingTemplate = _workingTemplate.copyWith(
          detailFields: List.from(_workingTemplate.detailFields)
            ..[detailIndex] = field.copyWith(label: newLabel),
        );
        AppLogger.info('✅ Updated detail label: $key = $newLabel');
        return;
      }
      
      for (int i = 0; i < _workingTemplate.tables.length; i++) {
        final table = _workingTemplate.tables[i];
        final columnIndex = table.columns.indexWhere((c) => c.key == key);
        if (columnIndex >= 0) {
          final column = table.columns[columnIndex];
          final updatedColumns = List<ColumnMapping>.from(table.columns)
            ..[columnIndex] = column.copyWith(label: newLabel);
          
          final updatedTables = List<TableMapping>.from(_workingTemplate.tables)
            ..[i] = table.copyWith(columns: updatedColumns);
          
          _workingTemplate = _workingTemplate.copyWith(tables: updatedTables);
          AppLogger.info('✅ Updated column label: $key = $newLabel');
          return;
        }
      }
    });
  }

  Widget _buildReorderableSection({
    required String title,
    required String subtitle,
    required List<String> selectedKeys,
    required Color color,
    required String sectionType,
    VoidCallback? onAddField,
  }) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final fieldKey = details.data;
        if (!mounted) return;
        setState(() {
          _moveFieldToSection(fieldKey, sectionType);
          
          _selectedDetailKeys.remove(fieldKey);
          _selectedEntryKeys.remove(fieldKey);
          _excludedKeys.remove(fieldKey);
          
          if (sectionType == 'details') {
            _selectedDetailKeys.add(fieldKey);
            AppLogger.debug('📋 Added to Details: $fieldKey');
          } else {
            _selectedEntryKeys.add(fieldKey);
            AppLogger.debug('📊 Added to Entries: $fieldKey');
          }
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        
        return Card(
          elevation: isHovering ? 8 : 2,
          color: isHovering ? color.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(isHovering ? Icons.add_circle : Icons.category, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    Text('${selectedKeys.length} fields', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                    if (onAddField != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.add_circle_outline, color: color),
                        tooltip: 'Add field to ${title.toLowerCase()}',
                        onPressed: onAddField,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                if (selectedKeys.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedKeys.asMap().entries.map((entry) {
                      final index = entry.key;
                      final key = entry.value;
                      final field = _findFieldByKey(key);
                      if (field == null) return const SizedBox.shrink();

                      return _buildReorderableChip(
                        key: key,
                        label: field.label,
                        color: color,
                        index: index,
                        selectedKeys: selectedKeys,
                        onDelete: () {
                          if (!mounted) return;
                          setState(() => selectedKeys.removeAt(index));
                        },
                      );
                    }).toList(),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      isHovering ? 'Drop here' : 'Drag fields here',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReorderableChip({
    required String key,
    required String label,
    required Color color,
    required int index,
    required List<String> selectedKeys,
    required VoidCallback onDelete,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return LongPressDraggable<Map<String, dynamic>>(
      data: {
        'key': key,
        'sourceList': selectedKeys,
        'sourceIndex': index,
      },
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? color.withValues(alpha: 0.7) : color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drag_indicator, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildChipContent(label, color, showDragHandle: true),
      ),
      child: DragTarget<Map<String, dynamic>>(
        onWillAcceptWithDetails: (details) {
          final sourceList = details.data['sourceList'] as List<String>?;
          return sourceList == selectedKeys;
        },
        onAcceptWithDetails: (details) {
          final data = details.data;
          final draggedKey = data['key'] as String;
          final sourceList = data['sourceList'] as List<String>;
          final sourceIndex = data['sourceIndex'] as int;
          
          if (sourceList == selectedKeys && mounted) {
            setState(() {
              final item = selectedKeys.removeAt(sourceIndex);
              final targetIndex = selectedKeys.indexOf(key);
              if (targetIndex >= 0) {
                selectedKeys.insert(targetIndex, item);
              } else {
                selectedKeys.insert(sourceIndex, item);
              }
              AppLogger.debug('🔄 Reordered: moved $draggedKey from $sourceIndex to $targetIndex');
            });
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: isHovering ? Border.all(color: color, width: 2) : null,
            ),
            child: _buildChipContent(label, color, showDragHandle: true, onDelete: onDelete),
          );
        },
      ),
    );
  }

  Widget _buildChipContent(String label, Color color, {bool showDragHandle = false, VoidCallback? onDelete}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark 
            ? color.withValues(alpha: 0.25)  // Darker background in dark mode
            : color.withValues(alpha: 0.2),   // Light background in light mode
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.5) : color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            Icon(Icons.drag_indicator, size: 16, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label, 
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onDelete,
              child: Icon(
                Icons.close, 
                size: 18, 
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _moveFieldToSection(String key, String targetSection) {
    FieldMapping? field = _findFieldByKey(key);
    if (field == null) {
      AppLogger.warning('⚠️ Cannot move field $key - not found');
      return;
    }

    final currentlyInDetails = _workingTemplate.detailFields.any((f) => f.key == key);
    final currentlyInColumns = _workingTemplate.tables.isNotEmpty && 
                                _workingTemplate.tables.first.columns.any((c) => c.key == key);

    if (targetSection == 'details') {
      if (currentlyInDetails) {
        AppLogger.debug('✓ Field $key already in details');
        return;
      }
      
      if (currentlyInColumns) {
        AppLogger.debug('🔄 Moving $key from columns to details');
        
        final updatedTables = _workingTemplate.tables.map((table) {
          final filteredColumns = table.columns.where((c) => c.key != key).toList();
          return table.copyWith(columns: filteredColumns);
        }).toList();
        
        final newDetailField = FieldMapping(
          key: field.key,
          label: field.label,
          type: field.type,
          order: _workingTemplate.detailFields.length,
          formula: field.formula,
          dependencies: field.dependencies,
          options: field.options,
          required: false,
        );
        
        _workingTemplate = _workingTemplate.copyWith(
          detailFields: [..._workingTemplate.detailFields, newDetailField],
          tables: updatedTables,
        );
      }
    } else {
      if (currentlyInColumns) {
        AppLogger.debug('✓ Field $key already in columns');
        return;
      }
      
      if (currentlyInDetails) {
        AppLogger.debug('🔄 Moving $key from details to columns');
        
        final filteredDetails = _workingTemplate.detailFields.where((f) => f.key != key).toList();
        
        if (_workingTemplate.tables.isEmpty) {
          AppLogger.warning('⚠️ No tables exist, cannot move to entries');
          return;
        }
        
        final newColumn = ColumnMapping(
          key: field.key,
          label: field.label,
          type: field.type,
          order: _workingTemplate.tables.first.columns.length,
          formula: field.formula,
          dependencies: field.dependencies,
          options: field.options,
        );
        
        final updatedTable = _workingTemplate.tables.first.copyWith(
          columns: [..._workingTemplate.tables.first.columns, newColumn],
        );
        
        _workingTemplate = _workingTemplate.copyWith(
          detailFields: filteredDetails,
          tables: [updatedTable, ..._workingTemplate.tables.skip(1)],
        );
      }
    }
  }

  Widget _buildExcludedSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Card(
      color: isDark ? Colors.red[900]?.withValues(alpha: 0.3) : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🗑️ Excluded Fields', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _excludedKeys.map((key) {
                final field = _findFieldByKey(key);
                if (field == null) return const SizedBox.shrink();
                
                return Chip(
                  label: Text(field.label),
                  deleteIcon: const Icon(Icons.restore, size: 18),
                  onDeleted: () {
                    if (!mounted) return;
                    setState(() => _excludedKeys.remove(key));
                  },
                  backgroundColor: isDark ? Colors.red[800] : Colors.red[100],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaConfig(FieldMapping field, {required bool isColumn}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🔧 Formula', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: field.formula ?? '',
          decoration: const InputDecoration(
            labelText: 'Formula',
            hintText: '(voltage * current) / speed',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _updateFieldFormula(field.key, value, isColumn: isColumn),
        ),
      ],
    );
  }

  Widget _buildDropdownConfig(FieldMapping field, {required bool isColumn}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📝 Options', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...?field.options?.asMap().entries.map((entry) {
          return ListTile(
            leading: const Icon(Icons.circle, size: 8),
            title: Text(entry.value),
            trailing: IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _removeDropdownOption(field.key, entry.key, isColumn: isColumn),
            ),
          );
        }),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Option'),
          onPressed: () => _showAddOptionDialog(field.key, isColumn: isColumn),
        ),
      ],
    );
  }

  FieldMapping? _findFieldByKey(String key) {
    try {
      return _workingTemplate.detailFields.firstWhere((f) => f.key == key);
    } catch (e) {
      for (final table in _workingTemplate.tables) {
        try {
          final column = table.columns.firstWhere((c) => c.key == key);
          return FieldMapping(
            key: column.key,
            label: column.label,
            type: column.type,
            order: column.order,
            formula: column.formula,
            dependencies: column.dependencies,
            options: column.options,
          );
        } catch (e) {
          continue;
        }
      }
    }
    return null;
  }

  String _getFieldTypeLabel(FieldType type) {
    switch (type) {
      case FieldType.text: return 'Text';
      case FieldType.number: return 'Number';
      case FieldType.date: return 'Date';
      case FieldType.dropdown: return 'Dropdown';
      case FieldType.calculated: return 'Calculated';
      case FieldType.textarea: return 'Text Area';
    }
  }

  void _updateFieldType(String key, FieldType newType, {required bool isColumn}) {
    if (!mounted) return;
    
    setState(() {
      if (isColumn) {
        for (int i = 0; i < _workingTemplate.tables.length; i++) {
          final table = _workingTemplate.tables[i];
          final columnIndex = table.columns.indexWhere((c) => c.key == key);
          if (columnIndex >= 0) {
            final column = table.columns[columnIndex];
            final updatedColumns = List<ColumnMapping>.from(table.columns)
              ..[columnIndex] = column.copyWith(type: newType);
            
            final updatedTables = List<TableMapping>.from(_workingTemplate.tables)
              ..[i] = table.copyWith(columns: updatedColumns);
            
            _workingTemplate = _workingTemplate.copyWith(tables: updatedTables);
            return;
          }
        }
      } else {
        final detailIndex = _workingTemplate.detailFields.indexWhere((f) => f.key == key);
        if (detailIndex >= 0) {
          final field = _workingTemplate.detailFields[detailIndex];
          _workingTemplate = _workingTemplate.copyWith(
            detailFields: List.from(_workingTemplate.detailFields)
              ..[detailIndex] = field.copyWith(type: newType),
          );
        }
      }
    });
  }

  void _updateFieldRequired(String key, bool required) {
    if (!mounted) return;
    
    final detailIndex = _workingTemplate.detailFields.indexWhere((f) => f.key == key);
    if (detailIndex >= 0) {
      final field = _workingTemplate.detailFields[detailIndex];
      setState(() {
        _workingTemplate = _workingTemplate.copyWith(
          detailFields: List.from(_workingTemplate.detailFields)
            ..[detailIndex] = field.copyWith(required: required),
        );
      });
    }
  }

  void _updateFieldFormula(String key, String formula, {required bool isColumn}) {
    if (!mounted) return;
    
    final dependencies = _formulaEngine.extractDependencies(formula);
    
    setState(() {
      if (isColumn) {
        for (int i = 0; i < _workingTemplate.tables.length; i++) {
          final table = _workingTemplate.tables[i];
          final columnIndex = table.columns.indexWhere((c) => c.key == key);
          if (columnIndex >= 0) {
            final column = table.columns[columnIndex];
            final updatedColumns = List<ColumnMapping>.from(table.columns)
              ..[columnIndex] = column.copyWith(
                formula: formula,
                dependencies: dependencies,
              );
            
            final updatedTables = List<TableMapping>.from(_workingTemplate.tables)
              ..[i] = table.copyWith(columns: updatedColumns);
            
            _workingTemplate = _workingTemplate.copyWith(tables: updatedTables);
            return;
          }
        }
      } else {
        final detailIndex = _workingTemplate.detailFields.indexWhere((f) => f.key == key);
        if (detailIndex >= 0) {
          final field = _workingTemplate.detailFields[detailIndex];
          _workingTemplate = _workingTemplate.copyWith(
            detailFields: List.from(_workingTemplate.detailFields)
              ..[detailIndex] = field.copyWith(
                formula: formula,
                dependencies: dependencies,
              ),
          );
        }
      }
    });
  }

  void _removeDropdownOption(String key, int index, {required bool isColumn}) {
    if (!mounted) return;
    
    setState(() {
      if (isColumn) {
        for (int i = 0; i < _workingTemplate.tables.length; i++) {
          final table = _workingTemplate.tables[i];
          final columnIndex = table.columns.indexWhere((c) => c.key == key);
          if (columnIndex >= 0) {
            final column = table.columns[columnIndex];
            if (column.options != null) {
              final newOptions = List<String>.from(column.options!)..removeAt(index);
              final updatedColumns = List<ColumnMapping>.from(table.columns)
                ..[columnIndex] = column.copyWith(options: newOptions);
              
              final updatedTables = List<TableMapping>.from(_workingTemplate.tables)
                ..[i] = table.copyWith(columns: updatedColumns);
              
              _workingTemplate = _workingTemplate.copyWith(tables: updatedTables);
            }
            return;
          }
        }
      } else {
        final field = _findFieldByKey(key);
        if (field?.options != null) {
          final newOptions = List<String>.from(field!.options!)..removeAt(index);
          
          final detailIndex = _workingTemplate.detailFields.indexWhere((f) => f.key == key);
          if (detailIndex >= 0) {
            final updatedField = _workingTemplate.detailFields[detailIndex].copyWith(
              options: newOptions,
            );
            _workingTemplate = _workingTemplate.copyWith(
              detailFields: List.from(_workingTemplate.detailFields)
                ..[detailIndex] = updatedField,
            );
          }
        }
      }
    });
  }

  void _showAddOptionDialog(String key, {required bool isColumn}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Option'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Option Value',
            hintText: 'e.g., Pass, Fail',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _addDropdownOption(key, controller.text.trim(), isColumn: isColumn);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addDropdownOption(String key, String option, {required bool isColumn}) {
    if (!mounted) return;
    
    setState(() {
      if (isColumn) {
        for (int i = 0; i < _workingTemplate.tables.length; i++) {
          final table = _workingTemplate.tables[i];
          final columnIndex = table.columns.indexWhere((c) => c.key == key);
          if (columnIndex >= 0) {
            final column = table.columns[columnIndex];
            final currentOptions = column.options ?? [];
            final newOptions = [...currentOptions, option];
            
            final updatedColumns = List<ColumnMapping>.from(table.columns)
              ..[columnIndex] = column.copyWith(options: newOptions);
            
            final updatedTables = List<TableMapping>.from(_workingTemplate.tables)
              ..[i] = table.copyWith(columns: updatedColumns);
            
            _workingTemplate = _workingTemplate.copyWith(tables: updatedTables);
            return;
          }
        }
      } else {
        final detailIndex = _workingTemplate.detailFields.indexWhere((f) => f.key == key);
        if (detailIndex >= 0) {
          final field = _workingTemplate.detailFields[detailIndex];
          final currentOptions = field.options ?? [];
          final newOptions = [...currentOptions, option];
          
          final updatedField = field.copyWith(options: newOptions);
          _workingTemplate = _workingTemplate.copyWith(
            detailFields: List.from(_workingTemplate.detailFields)
              ..[detailIndex] = updatedField,
          );
        }
      }
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Added "$option"'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveTemplate() async {
    if (_nameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a template name')),
        );
      }
      return;
    }

    final finalDetailFields = <FieldMapping>[];
    for (final key in _selectedDetailKeys) {
      try {
        final field = _workingTemplate.detailFields.firstWhere((f) => f.key == key);
        finalDetailFields.add(field);
        AppLogger.info('✅ Saving detail: ${field.key} = ${field.label} (type: ${field.type}, options: ${field.options})');
      } catch (e) {
        AppLogger.warning('⚠️ Detail field $key not found');
      }
    }
    
    final finalTables = <TableMapping>[];
    if (_workingTemplate.tables.isNotEmpty) {
      for (final table in _workingTemplate.tables) {
        final finalColumns = <ColumnMapping>[];
        for (final key in _selectedEntryKeys) {
          try {
            final column = table.columns.firstWhere((c) => c.key == key);
            finalColumns.add(column);
            AppLogger.info('✅ Saving column: ${column.key} = ${column.label} (type: ${column.type}, options: ${column.options})');
          } catch (e) {
            AppLogger.warning('⚠️ Column $key not found');
          }
        }
        finalTables.add(table.copyWith(columns: finalColumns));
      }
    }

    final finalTemplate = _workingTemplate.copyWith(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      detailFields: finalDetailFields,
      tables: finalTables,
      lastModified: DateTime.now(),
    );

    try {
      await _templateManager.saveTemplate(finalTemplate);
      
      AppLogger.debug('📊 SAVED TEMPLATE:');
      AppLogger.debug('  Name: ${finalTemplate.name}');
      AppLogger.debug('  Details: ${finalTemplate.detailFields.length}');
      AppLogger.debug('  Columns: ${finalTables.isNotEmpty ? finalTables.first.columns.length : 0}');
      
      if (mounted) {
        final columnsCount = finalTables.isNotEmpty ? finalTables.first.columns.length : 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Saved: ${finalDetailFields.length} details, $columnsCount columns'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
        Navigator.pop(context, finalTemplate);
      }
    } catch (e) {
      AppLogger.error('❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}