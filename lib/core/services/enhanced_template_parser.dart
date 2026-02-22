// lib/core/services/enhanced_universal_parser.dart
// Enhanced parser that extracts ALL fields with cell locations and current values

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:weldqai_app/core/services/logger_service.dart';

class EnhancedUniversalParser {
  
  /// Parse with FULL field information including cell locations and values
  Future<Map<String, dynamic>> parseWithFullDetails(
    Uint8List bytes, 
    {String? fileName}
  ) async {
    final isPDF = fileName?.toLowerCase().endsWith('.pdf') ?? false;
    
    if (isPDF) {
      return await _parsePDFWithDetails(bytes, fileName);
    } else {
      return await _parseExcelWithDetails(bytes);
    }
  }
  
  // ==================== ENHANCED EXCEL PARSER ====================
  
  Future<Map<String, dynamic>> _parseExcelWithDetails(Uint8List bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      
      if (excel.tables.isEmpty) {
        throw Exception('Empty Excel file - no sheets found');
      }
      
      final sheet = excel.tables.values.first;
      
      AppLogger.debug('=== EXCEL PARSING (ENHANCED) ===');
      AppLogger.debug('Total rows: ${sheet.maxRows}, Total columns: ${sheet.maxCols}');
      
      // Extract title
      final title = _findTitle(sheet);
      
      // Find where the table starts
      var tableStartRow = -1;
      for (int row = 0; row < math.min(30, sheet.maxRows); row++) {
        final rowData = _getRowData(sheet, row);
        if (_looksLikeTableHeader(rowData)) {
          tableStartRow = row;
          AppLogger.debug('Table header found at row $row');
          break;
        }
      }
      
      // Extract ALL details
      final details = <Map<String, dynamic>>[];
      final detailEndRow = tableStartRow > 0 ? tableStartRow : sheet.maxRows;
      
      for (int row = 0; row < detailEndRow; row++) {
        final rowData = _getRowData(sheet, row);
        
        for (int col = 0; col < math.min(10, rowData.length); col++) {
          final cellValue = rowData[col];
          
          if (cellValue.isEmpty || cellValue.length > 100) continue;
          
          // Find value in next columns
          String? valueCellAddress;
          dynamic currentValue;
          
          for (int valueCol = col + 1; valueCol < math.min(col + 4, rowData.length); valueCol++) {
            if (rowData[valueCol].isNotEmpty) {
              valueCellAddress = _getCellAddress(valueCol, row);
              currentValue = rowData[valueCol];
              break;
            }
          }
          
          if (valueCellAddress == null && !_isLikelyTableHeader(cellValue)) {
            valueCellAddress = _getCellAddress(col, row);
            currentValue = cellValue;
          }
          
          if (_isLikelyTableHeader(cellValue)) continue;
          
          details.add({
            'key': _makeKey(cellValue),
            'label': _cleanLabel(cellValue),
            'type': _guessType(currentValue),
            'cellAddress': valueCellAddress ?? _getCellAddress(col + 1, row),
            'currentValue': currentValue,
            'rowIndex': row,
            'colIndex': col,
          });
        }
      }
      
      AppLogger.debug('Total details extracted: ${details.length}');
      
      // Extract table columns
      final columns = <Map<String, dynamic>>[];
      if (tableStartRow >= 0 && tableStartRow < sheet.maxRows) {
        final headerRow = _getRowData(sheet, tableStartRow);
        
        for (int col = 0; col < headerRow.length; col++) {
          final header = headerRow[col].trim();
          if (header.isEmpty) continue;
          
          dynamic sampleValue;
          for (int sampleRow = tableStartRow + 1; 
               sampleRow < math.min(tableStartRow + 5, sheet.maxRows); 
               sampleRow++) {
            final dataRow = _getRowData(sheet, sampleRow);
            if (col < dataRow.length && dataRow[col].isNotEmpty) {
              sampleValue = dataRow[col];
              break;
            }
          }
          
          columns.add({
            'key': _makeKey(header),
            'label': _cleanLabel(header),
            'type': _guessType(sampleValue),
            'width': 140.0,
            'columnLetter': _getColumnLetter(col),
            'columnIndex': col,
            'sampleValue': sampleValue,
          });
        }
      }
      
      AppLogger.debug('Total columns extracted: ${columns.length}');
      
      return {
        'title': title,
        'allFields': [
          ...details.map((d) => {...d, 'suggestedSection': 'details'}),
          ...columns.map((c) => {...c, 'suggestedSection': 'entries'}),
        ],
        'details': details,
        'tables': [{
          'key': 'entries',
          'label': 'Entries',
          'columns': columns,
          'minRows': 5,
          'startRow': tableStartRow >= 0 ? tableStartRow + 1 : null,
        }],
        'metadata': {
          'totalRows': sheet.maxRows,
          'totalColumns': sheet.maxCols,
          'detailRowsCount': detailEndRow,
          'tableStartRow': tableStartRow,
        },
      };
      
    } catch (e, stackTrace) {
      AppLogger.debug('Excel parse error: $e');
      AppLogger.debug('Stack trace: $stackTrace');
      return _getDefaultSchema();
    }
  }
  
  // ==================== ENHANCED PDF PARSER ====================
  
  Future<Map<String, dynamic>> _parsePDFWithDetails(
    Uint8List bytes, 
    String? fileName
  ) async {
    try {
      final document = sf.PdfDocument(inputBytes: bytes);
      final textExtractor = sf.PdfTextExtractor(document);
      final fullText = textExtractor.extractText();
      
      AppLogger.debug('=== PDF PARSING (ENHANCED) ===');
      
      var title = 'Template';
      if (fileName != null) {
        title = fileName
            .replaceAll(RegExp(r'\.(pdf|PDF)$'), '')
            .replaceAll(RegExp(r'[_-]'), ' ')
            .trim();
      }
      
      final allLines = fullText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      
      AppLogger.debug('Total lines: ${allLines.length}');
      
      // Find table start
      var tableStart = -1;
      String? tableHeaderLine;
      
      for (var i = 0; i < allLines.length; i++) {
        final line = allLines[i];
        if (_looksLikeTableHeaderPDF(line)) {
          tableStart = i;
          tableHeaderLine = line;
          AppLogger.debug('Table header at line $i: $line');
          break;
        }
      }
      
      // Extract details
      final details = <Map<String, dynamic>>[];
      final detailLines = tableStart > 0 ? allLines.sublist(0, tableStart) : allLines;
      
      for (var i = 0; i < detailLines.length; i++) {
        final line = detailLines[i];
        
        if (line.contains(':')) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();
            
            if (key.isNotEmpty && key.length < 100 && !RegExp(r'^\d+$').hasMatch(key)) {
              details.add({
                'key': _makeKey(key),
                'label': key,
                'type': _guessType(value),
                'currentValue': value.isNotEmpty ? value : null,
                'lineIndex': i,
              });
            }
          }
        } else {
          final parts = line.split(RegExp(r'\s{2,}'));
          if (parts.length >= 2) {
            for (var j = 0; j < parts.length - 1; j += 2) {
              final key = parts[j].trim();
              final value = j + 1 < parts.length ? parts[j + 1].trim() : '';
              
              if (key.isNotEmpty && key.length < 80) {
                details.add({
                  'key': _makeKey(key),
                  'label': key,
                  'type': _guessType(value),
                  'currentValue': value.isNotEmpty ? value : null,
                  'lineIndex': i,
                });
              }
            }
          }
        }
      }
      
      AppLogger.debug('Found ${details.length} detail fields');
      
      // Extract columns
      final columns = <Map<String, dynamic>>[];
      
      if (tableStart >= 0 && tableHeaderLine != null) {
        final headerParts = _smartSplitPDFHeader(tableHeaderLine);
        
        AppLogger.debug('Split header into ${headerParts.length} parts');
        
        for (var i = 0; i < headerParts.length; i++) {
          final header = headerParts[i].trim();
          if (header.isEmpty) continue;
          
          dynamic sampleValue;
          for (var sampleRow = tableStart + 1; 
               sampleRow < math.min(tableStart + 10, allLines.length); 
               sampleRow++) {
            final dataLine = allLines[sampleRow];
            final dataParts = dataLine.split(RegExp(r'\s{2,}'));
            
            if (i < dataParts.length && dataParts[i].trim().isNotEmpty) {
              sampleValue = dataParts[i].trim();
              break;
            }
          }
          
          columns.add({
            'key': _makeKey(header),
            'label': header,
            'type': _guessType(sampleValue),
            'width': 140.0,
            'columnIndex': i,
            'sampleValue': sampleValue,
          });
        }
      }
      
      AppLogger.debug('Total columns extracted: ${columns.length}');
      
      document.dispose();
      
      return {
        'title': title,
        'allFields': [
          ...details.map((d) => {...d, 'suggestedSection': 'details'}),
          ...columns.map((c) => {...c, 'suggestedSection': 'entries'}),
        ],
        'details': details,
        'tables': [{
          'key': 'entries',
          'label': 'Entries',
          'columns': columns,
          'minRows': 5,
        }],
        'metadata': {
          'totalLines': allLines.length,
          'detailLinesCount': tableStart,
        },
      };
      
    } catch (e, stackTrace) {
      AppLogger.debug('PDF parse error: $e');
      AppLogger.debug('Stack trace: $stackTrace');
      return _getDefaultSchema();
    }
  }
  
  // ==================== HELPERS ====================
  
  String _findTitle(Sheet sheet) {
    for (int row = 0; row < math.min(10, sheet.maxRows); row++) {
      final rowData = _getRowData(sheet, row);
      for (final cell in rowData) {
        if (cell.length > 10 && cell.length < 100) {
          final lower = cell.toLowerCase();
          if (lower.contains('report') || lower.contains('inspection') ||
              lower.contains('form') || lower.contains('certificate')) {
            return cell;
          }
        }
      }
    }
    return 'Template';
  }
  
  bool _looksLikeTableHeader(List<String> row) {
    final nonEmpty = row.where((c) => c.isNotEmpty).length;
    if (nonEmpty < 3) return false;
    
    final text = row.join(' ').toLowerCase();
    return text.contains('s/no') || text.contains('description') ||
           text.contains('result') || text.contains('remarks');
  }
  
  bool _looksLikeTableHeaderPDF(String line) {
    final lower = line.toLowerCase();
    return lower.contains('s/no') || 
           (lower.contains('pipe') && lower.contains('nos')) ||
           lower.contains('remarks') ||
           line.split(RegExp(r'\s{2,}')).length >= 4;
  }
  
  bool _isLikelyTableHeader(String text) {
    final lower = text.toLowerCase();
    return lower.contains('s/no') || 
           lower.contains('s/n') ||
           lower.contains('description') ||
           lower.contains('result') ||
           lower.contains('remarks');
  }
  
  List<String> _smartSplitPDFHeader(String text) {
    // Known headers from common templates
    final knownHeaders = [
      'S/No', 'Line Pipe Nos', 'Heat No', 'Relative Humidity', 'Surface Prep',
      'Field Joint No', 'Preheat temp', 'Before Epoxy Primer', 'After Epoxy Primer',
      'PE Coating Repair', 'Visual Inspection', 'Holiday Test', 'Acc/Rej', 'Remarks',
    ];
    
    final found = <String>[];
    var remaining = text;
    
    for (final header in knownHeaders) {
      final pattern = RegExp(header, caseSensitive: false);
      if (pattern.hasMatch(remaining)) {
        found.add(header);
      }
    }
    
    if (found.isNotEmpty) return found;
    
    // Fallback: split by multiple spaces
    final parts = text.split(RegExp(r'\s{2,}'));
    return parts.where((s) => s.trim().isNotEmpty).toList();
  }
  
  List<String> _getRowData(Sheet sheet, int rowIndex) {
    final data = <String>[];
    for (int col = 0; col < sheet.maxCols; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: rowIndex,
      ));
      data.add(cell.value?.toString().trim() ?? '');
    }
    return data;
  }
  
  String _getCellAddress(int col, int row) {
    return '${_getColumnLetter(col)}${row + 1}';
  }
  
  String _getColumnLetter(int col) {
    var letter = '';
    var temp = col;
    while (temp >= 0) {
      letter = String.fromCharCode(65 + (temp % 26)) + letter;
      temp = (temp ~/ 26) - 1;
    }
    return letter;
  }
  
  String _guessType(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'text';
    
    final str = value.toString().toLowerCase();
    
    if (RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}').hasMatch(str)) {
      return 'date';
    }
    
    if (double.tryParse(str) != null) {
      return 'number';
    }
    
    if (['pass', 'fail', 'n/a', 'yes', 'no', 'ok'].contains(str)) {
      return 'dropdown';
    }
    
    return 'text';
  }
  
  String _makeKey(String label) {
    return label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
  
  String _cleanLabel(String label) {
    return label
        .replaceAll(RegExp(r'[:*]+$'), '')
        .trim();
  }
  
  List<Map<String, dynamic>> _getDefaultDetails() {
    return [
      {'key': 'project', 'label': 'Project', 'type': 'text'},
      {'key': 'date', 'label': 'Date', 'type': 'date'},
      {'key': 'inspector', 'label': 'Inspector', 'type': 'text'},
    ];
  }
  
  List<Map<String, dynamic>> _getDefaultColumns() {
    return [
      {'key': 'sno', 'label': 'S/No', 'type': 'number', 'width': 80.0},
      {'key': 'description', 'label': 'Description', 'type': 'text', 'width': 200.0},
      {'key': 'result', 'label': 'Result', 'type': 'text', 'width': 120.0},
    ];
  }
  
  Map<String, dynamic> _getDefaultSchema() {
    return {
      'title': 'Template',
      'details': _getDefaultDetails(),
      'tables': [{
        'key': 'entries',
        'label': 'Entries',
        'columns': _getDefaultColumns(),
        'minRows': 5,
      }],
    };
  }
}