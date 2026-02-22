// lib/models/template_mapping.dart
// Data models for custom template mapping


/// Represents a saved custom template configuration
class TemplateMapping {
  final String id;
  final String name;
  final String? description;
  final TemplateMappingType type; // excel or pdf
  final String? originalFileName;
  
  // Template structure
  final List<FieldMapping> detailFields;
  final List<TableMapping> tables;
  
  // Metadata
  final DateTime createdAt;
  final DateTime lastModified;
  final int usageCount;
  
  // Template fingerprint (to recognize same template later)
  final String? fingerprint;

  TemplateMapping({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.originalFileName,
    required this.detailFields,
    required this.tables,
    required this.createdAt,
    required this.lastModified,
    this.usageCount = 0,
    this.fingerprint,
  });

  TemplateMapping copyWith({
    String? name,
    String? description,
    List<FieldMapping>? detailFields,
    List<TableMapping>? tables,
    DateTime? lastModified,
    int? usageCount,
  }) {
    return TemplateMapping(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type,
      originalFileName: originalFileName,
      detailFields: detailFields ?? this.detailFields,
      tables: tables ?? this.tables,
      createdAt: createdAt,
      lastModified: lastModified ?? this.lastModified,
      usageCount: usageCount ?? this.usageCount,
      fingerprint: fingerprint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.toString(),
      'originalFileName': originalFileName,
      'detailFields': detailFields.map((f) => f.toJson()).toList(),
      'tables': tables.map((t) => t.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'usageCount': usageCount,
      'fingerprint': fingerprint,
    };
  }

  factory TemplateMapping.fromJson(Map<String, dynamic> json) {
    return TemplateMapping(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: TemplateMappingType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => TemplateMappingType.excel,
      ),
      originalFileName: json['originalFileName'],
      detailFields: (json['detailFields'] as List)
          .map((f) => FieldMapping.fromJson(f))
          .toList(),
      tables: (json['tables'] as List)
          .map((t) => TableMapping.fromJson(t))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      lastModified: DateTime.parse(json['lastModified']),
      usageCount: json['usageCount'] ?? 0,
      fingerprint: json['fingerprint'],
    );
  }
}

enum TemplateMappingType { excel, pdf }

/// Represents a single field in the Details section
class FieldMapping {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final int order;
  
  // For calculated fields
  final String? formula;
  final List<String>? dependencies;
  
  // For dropdowns
  final List<String>? options;
  
  // For validation
  final double? minValue;
  final double? maxValue;
  
  // Cell location (for Excel)
  final String? cellAddress;
  
  // Display settings
  final int? decimals;
  final String? unit;

  FieldMapping({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    required this.order,
    this.formula,
    this.dependencies,
    this.options,
    this.minValue,
    this.maxValue,
    this.cellAddress,
    this.decimals,
    this.unit,
  });

  FieldMapping copyWith({
    String? label,
    FieldType? type,
    bool? required,
    int? order,
    String? formula,
    List<String>? dependencies,
    List<String>? options,
    double? minValue,
    double? maxValue,
    String? cellAddress,
    int? decimals,
    String? unit,
  }) {
    return FieldMapping(
      key: key,
      label: label ?? this.label,
      type: type ?? this.type,
      required: required ?? this.required,
      order: order ?? this.order,
      formula: formula ?? this.formula,
      dependencies: dependencies ?? this.dependencies,
      options: options ?? this.options,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      cellAddress: cellAddress ?? this.cellAddress,
      decimals: decimals ?? this.decimals,
      unit: unit ?? this.unit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'type': type.toString(),
      'required': required,
      'order': order,
      'formula': formula,
      'dependencies': dependencies,
      'options': options,
      'minValue': minValue,
      'maxValue': maxValue,
      'cellAddress': cellAddress,
      'decimals': decimals,
      'unit': unit,
    };
  }

  factory FieldMapping.fromJson(Map<String, dynamic> json) {
    return FieldMapping(
      key: json['key'],
      label: json['label'],
      type: FieldType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => FieldType.text,
      ),
      required: json['required'] ?? false,
      order: json['order'],
      formula: json['formula'],
      dependencies: json['dependencies'] != null
          ? List<String>.from(json['dependencies'])
          : null,
      options: json['options'] != null
          ? List<String>.from(json['options'])
          : null,
      minValue: json['minValue']?.toDouble(),
      maxValue: json['maxValue']?.toDouble(),
      cellAddress: json['cellAddress'],
      decimals: json['decimals'],
      unit: json['unit'],
    );
  }
}

enum FieldType {
  text,
  number,
  date,
  dropdown,
  calculated,
  textarea,
}

/// Represents a table section (like Entries)
class TableMapping {
  final String key;
  final String label;
  final List<ColumnMapping> columns;
  final int minRows;
  final int? startRow; // For Excel

  TableMapping({
    required this.key,
    required this.label,
    required this.columns,
    this.minRows = 5,
    this.startRow,
  });

  TableMapping copyWith({
    String? label,
    List<ColumnMapping>? columns,
    int? minRows,
    int? startRow,
  }) {
    return TableMapping(
      key: key,
      label: label ?? this.label,
      columns: columns ?? this.columns,
      minRows: minRows ?? this.minRows,
      startRow: startRow ?? this.startRow,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'columns': columns.map((c) => c.toJson()).toList(),
      'minRows': minRows,
      'startRow': startRow,
    };
  }

  factory TableMapping.fromJson(Map<String, dynamic> json) {
    return TableMapping(
      key: json['key'],
      label: json['label'],
      columns: (json['columns'] as List)
          .map((c) => ColumnMapping.fromJson(c))
          .toList(),
      minRows: json['minRows'] ?? 5,
      startRow: json['startRow'],
    );
  }
}

/// Represents a column in a table
class ColumnMapping {
  final String key;
  final String label;
  final FieldType type;
  final double width;
  final int order;
  
  // For calculated columns
  final String? formula;
  final List<String>? dependencies;
  
  // For dropdowns
  final List<String>? options;
  
  // For Excel
  final String? columnLetter;
  
  // Display
  final int? decimals;
  final String? unit;

  ColumnMapping({
    required this.key,
    required this.label,
    required this.type,
    this.width = 140.0,
    required this.order,
    this.formula,
    this.dependencies,
    this.options,
    this.columnLetter,
    this.decimals,
    this.unit,
  });

  ColumnMapping copyWith({
    String? label,
    FieldType? type,
    double? width,
    int? order,
    String? formula,
    List<String>? dependencies,
    List<String>? options,
    String? columnLetter,
    int? decimals,
    String? unit,
  }) {
    return ColumnMapping(
      key: key,
      label: label ?? this.label,
      type: type ?? this.type,
      width: width ?? this.width,
      order: order ?? this.order,
      formula: formula ?? this.formula,
      dependencies: dependencies ?? this.dependencies,
      options: options ?? this.options,
      columnLetter: columnLetter ?? this.columnLetter,
      decimals: decimals ?? this.decimals,
      unit: unit ?? this.unit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'type': type.toString(),
      'width': width,
      'order': order,
      'formula': formula,
      'dependencies': dependencies,
      'options': options,
      'columnLetter': columnLetter,
      'decimals': decimals,
      'unit': unit,
    };
  }

  factory ColumnMapping.fromJson(Map<String, dynamic> json) {
    return ColumnMapping(
      key: json['key'],
      label: json['label'],
      type: FieldType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => FieldType.text,
      ),
      width: json['width']?.toDouble() ?? 140.0,
      order: json['order'],
      formula: json['formula'],
      dependencies: json['dependencies'] != null
          ? List<String>.from(json['dependencies'])
          : null,
      options: json['options'] != null
          ? List<String>.from(json['options'])
          : null,
      columnLetter: json['columnLetter'],
      decimals: json['decimals'],
      unit: json['unit'],
    );
  }
}