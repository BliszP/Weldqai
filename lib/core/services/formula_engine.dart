// lib/core/services/formula_engine.dart
// Evaluates formulas for calculated fields

import 'dart:math' as math;
import 'package:weldqai_app/core/services/logger_service.dart';

class FormulaEngine {
  /// Evaluate a formula with given data
  /// formula: "(voltage * current) / (speed * 1000)"
  /// data: {"voltage": 25, "current": 180, "speed": 3}
  /// returns: 1.5
  double? evaluate(String formula, Map<String, dynamic> data) {
    try {
      // Replace field names with values
      var expression = formula.toLowerCase().trim();
      
      // Handle advanced math functions FIRST before replacing field names
      expression = _processAdvancedFunctions(expression, data);
      
      // Remove parentheses for processing
      expression = expression.replaceAll('(', '').replaceAll(')', '');
      
      // Replace field names with values
      for (var entry in data.entries) {
        final key = entry.key.toLowerCase();
        final value = entry.value;
        
        if (value != null) {
          final numValue = _toNumber(value);
          if (numValue != null) {
            expression = expression.replaceAll(key, numValue.toString());
          }
        }
      }
      
      // Evaluate the expression
      return _evaluateExpression(expression);
    } catch (e) {
      AppLogger.debug('Formula evaluation error: $e');
      return null;
    }
  }
  
  /// Process advanced math functions
  String _processAdvancedFunctions(String expression, Map<String, dynamic> data) {
    var result = expression;
    
    // Handle SQRT
    result = _processFunctionCall(result, 'sqrt', (value) => math.sqrt(value), data);
    
    // Handle POW
    result = _processPowerFunction(result, data);
    
    // Handle ABS (absolute value)
    result = _processFunctionCall(result, 'abs', (value) => value.abs(), data);
    
    // Handle ROUND
    result = _processFunctionCall(result, 'round', (value) => value.roundToDouble(), data);
    
    // Handle CEIL
    result = _processFunctionCall(result, 'ceil', (value) => value.ceilToDouble(), data);
    
    // Handle FLOOR
    result = _processFunctionCall(result, 'floor', (value) => value.floorToDouble(), data);
    
    // Handle MIN
    result = _processMinMaxFunction(result, 'min', data);
    
    // Handle MAX
    result = _processMinMaxFunction(result, 'max', data);
    
    // Handle SIN, COS, TAN (for engineering calculations)
    result = _processFunctionCall(result, 'sin', (value) => math.sin(value), data);
    result = _processFunctionCall(result, 'cos', (value) => math.cos(value), data);
    result = _processFunctionCall(result, 'tan', (value) => math.tan(value), data);
    
    return result;
  }
  
  /// Process single-argument function calls like sqrt(x), abs(x), etc.
  String _processFunctionCall(
    String expression,
    String functionName,
    double Function(double) operation,
    Map<String, dynamic> data,
  ) {
    final pattern = RegExp('$functionName\\(([^)]+)\\)', caseSensitive: false);
    
    while (expression.contains(pattern)) {
      final match = pattern.firstMatch(expression);
      if (match == null) break;
      
      final argument = match.group(1)!.trim();
      final value = _evaluateArgument(argument, data);
      
      if (value != null) {
        final result = operation(value);
        expression = expression.replaceFirst(pattern, result.toString());
      } else {
        break; // Can't evaluate, stop
      }
    }
    
    return expression;
  }
  
  /// Process POW(base, exponent)
  String _processPowerFunction(String expression, Map<String, dynamic> data) {
    final pattern = RegExp(r'pow\(([^,]+),([^)]+)\)', caseSensitive: false);
    
    while (expression.contains(pattern)) {
      final match = pattern.firstMatch(expression);
      if (match == null) break;
      
      final base = _evaluateArgument(match.group(1)!.trim(), data);
      final exponent = _evaluateArgument(match.group(2)!.trim(), data);
      
      if (base != null && exponent != null) {
        final result = math.pow(base, exponent);
        expression = expression.replaceFirst(pattern, result.toString());
      } else {
        break;
      }
    }
    
    return expression;
  }
  
  /// Process MIN(...) and MAX(...)
  String _processMinMaxFunction(
    String expression,
    String functionName,
    Map<String, dynamic> data,
  ) {
    final pattern = RegExp('$functionName\\(([^)]+)\\)', caseSensitive: false);
    
    while (expression.contains(pattern)) {
      final match = pattern.firstMatch(expression);
      if (match == null) break;
      
      final arguments = match.group(1)!.split(',');
      final values = <double>[];
      
      for (final arg in arguments) {
        final value = _evaluateArgument(arg.trim(), data);
        if (value != null) {
          values.add(value);
        }
      }
      
      if (values.isNotEmpty) {
        final result = functionName == 'min'
            ? values.reduce(math.min)
            : values.reduce(math.max);
        expression = expression.replaceFirst(pattern, result.toString());
      } else {
        break;
      }
    }
    
    return expression;
  }
  
  /// Evaluate a single argument (could be a number or field name)
  double? _evaluateArgument(String argument, Map<String, dynamic> data) {
    // Try as direct number first
    final numValue = double.tryParse(argument);
    if (numValue != null) return numValue;
    
    // Try as field name
    final fieldValue = data[argument.toLowerCase()];
    return _toNumber(fieldValue);
  }
  
  /// Evaluate a conditional formula (IF statements)
  /// formula: "heatInput > 1.5 ? 'Review' : 'Pass'"
  dynamic evaluateConditional(String formula, Map<String, dynamic> data) {
    try {
      var expression = formula.trim();
      
      // Check if it's a ternary operator
      if (expression.contains('?') && expression.contains(':')) {
        final parts = expression.split('?');
        if (parts.length != 2) return null;
        
        final condition = parts[0].trim();
        final outcomes = parts[1].split(':');
        if (outcomes.length != 2) return null;
        
        final trueValue = outcomes[0].trim().replaceAll("'", '').replaceAll('"', '');
        final falseValue = outcomes[1].trim().replaceAll("'", '').replaceAll('"', '');
        
        // Evaluate condition
        final conditionResult = _evaluateCondition(condition, data);
        return conditionResult ? trueValue : falseValue;
      }
      
      return null;
    } catch (e) {
      AppLogger.debug('Conditional evaluation error: $e');
      return null;
    }
  }
  
  /// Check if formula has circular dependencies
  bool hasCircularDependency(
    String fieldKey,
    List<String> dependencies,
    Map<String, List<String>> allDependencies,
  ) {
    final visited = <String>{};
    return _checkCircular(fieldKey, dependencies, allDependencies, visited);
  }
  
  bool _checkCircular(
    String current,
    List<String> deps,
    Map<String, List<String>> allDeps,
    Set<String> visited,
  ) {
    if (visited.contains(current)) return true;
    visited.add(current);
    
    for (final dep in deps) {
      if (dep == current) return true;
      final nextDeps = allDeps[dep];
      if (nextDeps != null) {
        if (_checkCircular(dep, nextDeps, allDeps, visited)) {
          return true;
        }
      }
    }
    
    visited.remove(current);
    return false;
  }
  
  /// Extract field dependencies from formula
  List<String> extractDependencies(String formula) {
    final dependencies = <String>[];
    
    // Remove operators and numbers
    var cleaned = formula
        .replaceAll(RegExp(r'[+\-*/().,\d\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Split and filter
    final parts = cleaned.split(' ');
    for (final part in parts) {
      if (part.isNotEmpty && !_isOperator(part) && !_isNumber(part)) {
        dependencies.add(part.toLowerCase());
      }
    }
    
    return dependencies.toSet().toList();
  }
  
  // ==================== PRIVATE HELPERS ====================
  
  double? _toNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
  
  double? _evaluateExpression(String expression) {
    try {
      // Very simple expression evaluator
      // Handles: +, -, *, /
      
      expression = expression.trim();
      
      // Handle division first
      if (expression.contains('/')) {
        final parts = expression.split('/');
        if (parts.length == 2) {
          final left = _evaluateExpression(parts[0].trim());
          final right = _evaluateExpression(parts[1].trim());
          if (left != null && right != null && right != 0) {
            return left / right;
          }
        }
      }
      
      // Handle multiplication
      if (expression.contains('*')) {
        final parts = expression.split('*');
        if (parts.length == 2) {
          final left = _evaluateExpression(parts[0].trim());
          final right = _evaluateExpression(parts[1].trim());
          if (left != null && right != null) {
            return left * right;
          }
        }
      }
      
      // Handle addition
      if (expression.contains('+')) {
        final parts = expression.split('+');
        if (parts.length == 2) {
          final left = _evaluateExpression(parts[0].trim());
          final right = _evaluateExpression(parts[1].trim());
          if (left != null && right != null) {
            return left + right;
          }
        }
      }
      
      // Handle subtraction
      if (expression.contains('-')) {
        final parts = expression.split('-');
        if (parts.length == 2) {
          final left = _evaluateExpression(parts[0].trim());
          final right = _evaluateExpression(parts[1].trim());
          if (left != null && right != null) {
            return left - right;
          }
        }
      }
      
      // Just a number
      return double.tryParse(expression);
    } catch (e) {
      return null;
    }
  }
  
  bool _evaluateCondition(String condition, Map<String, dynamic> data) {
    // Simple condition evaluator: "fieldName > value"
    condition = condition.trim();
    
    // Handle OR conditions
    if (condition.contains('||')) {
      final parts = condition.split('||');
      for (final part in parts) {
        if (_evaluateCondition(part.trim(), data)) {
          return true;
        }
      }
      return false;
    }
    
    // Handle AND conditions
    if (condition.contains('&&')) {
      final parts = condition.split('&&');
      for (final part in parts) {
        if (!_evaluateCondition(part.trim(), data)) {
          return false;
        }
      }
      return true;
    }
    
    // Single condition
    if (condition.contains('>')) {
      final parts = condition.split('>');
      if (parts.length == 2) {
        final left = _getFieldValue(parts[0].trim(), data);
        final right = double.tryParse(parts[1].trim());
        if (left != null && right != null) {
          return left > right;
        }
      }
    }
    
    if (condition.contains('<')) {
      final parts = condition.split('<');
      if (parts.length == 2) {
        final left = _getFieldValue(parts[0].trim(), data);
        final right = double.tryParse(parts[1].trim());
        if (left != null && right != null) {
          return left < right;
        }
      }
    }
    
    if (condition.contains('==')) {
      final parts = condition.split('==');
      if (parts.length == 2) {
        final left = _getFieldValue(parts[0].trim(), data);
        final right = double.tryParse(parts[1].trim());
        if (left != null && right != null) {
          return left == right;
        }
      }
    }
    
    return false;
  }
  
  double? _getFieldValue(String fieldName, Map<String, dynamic> data) {
    final value = data[fieldName.toLowerCase()];
    return _toNumber(value);
  }
  
  bool _isOperator(String s) {
    return ['+', '-', '*', '/', '>', '<', '==', '&&', '||'].contains(s);
  }
  
  bool _isNumber(String s) {
    return double.tryParse(s) != null;
  }
  
  /// Validate formula syntax
  bool isValidFormula(String formula) {
    try {
      // Basic validation
      if (formula.trim().isEmpty) return false;
      
      // Check balanced parentheses
      int openCount = 0;
      for (var char in formula.split('')) {
        if (char == '(') openCount++;
        if (char == ')') openCount--;
        if (openCount < 0) return false;
      }
      if (openCount != 0) return false;
      
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Helper extensions
extension FormulaHelpers on String {
  String toFormulaKey() {
    return toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}