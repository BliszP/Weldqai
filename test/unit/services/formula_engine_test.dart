// test/unit/services/formula_engine_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:weldqai_app/core/services/formula_engine.dart';

void main() {
  late FormulaEngine engine;

  setUp(() {
    engine = FormulaEngine();
  });

  group('FormulaEngine.evaluate — arithmetic', () {
    test('addition', () {
      final result = engine.evaluate('a + b', {'a': 3, 'b': 7});
      expect(result, 10.0);
    });

    test('subtraction', () {
      final result = engine.evaluate('a - b', {'a': 10, 'b': 4});
      expect(result, 6.0);
    });

    test('multiplication', () {
      final result = engine.evaluate('a * b', {'a': 3, 'b': 4});
      expect(result, 12.0);
    });

    test('division', () {
      final result = engine.evaluate('a / b', {'a': 10, 'b': 2});
      expect(result, 5.0);
    });

    test('division by zero returns null', () {
      final result = engine.evaluate('a / b', {'a': 10, 'b': 0});
      expect(result, isNull);
    });

    test('missing field returns null', () {
      final result = engine.evaluate('a + b', {'a': 5});
      expect(result, isNull);
    });

    test('empty formula returns null', () {
      final result = engine.evaluate('', {});
      expect(result, isNull);
    });

    test('string number values are coerced', () {
      final result = engine.evaluate('a + b', {'a': '3', 'b': '7'});
      expect(result, 10.0);
    });
  });

  group('FormulaEngine.evaluate — advanced functions', () {
    test('sqrt', () {
      final result = engine.evaluate('sqrt(a)', {'a': 9});
      expect(result, closeTo(3.0, 0.0001));
    });

    test('abs of negative', () {
      final result = engine.evaluate('abs(a)', {'a': -5});
      expect(result, 5.0);
    });

    test('min of two values', () {
      final result = engine.evaluate('min(a,b)', {'a': 3, 'b': 7});
      expect(result, 3.0);
    });

    test('max of two values', () {
      final result = engine.evaluate('max(a,b)', {'a': 3, 'b': 7});
      expect(result, 7.0);
    });
  });

  group('FormulaEngine.evaluate — field references', () {
    test('field names are case-insensitive', () {
      final result = engine.evaluate('Voltage + Current', {'voltage': 10, 'current': 5});
      expect(result, 15.0);
    });

    test('weld heat input formula', () {
      // Heat Input = (voltage * current) / (speed * 1000)
      final data = {'voltage': 25.0, 'current': 180.0, 'speed': 3.0};
      final result = engine.evaluate('voltage * current / speed * 1000', data);
      expect(result, isNotNull);
    });
  });

  group('FormulaEngine.evaluateConditional', () {
    test('true branch returns correct string', () {
      final result = engine.evaluateConditional(
        "heatinput > 1.5 ? 'Review' : 'Pass'",
        {'heatinput': 2.0},
      );
      expect(result, 'Review');
    });

    test('false branch returns correct string', () {
      final result = engine.evaluateConditional(
        "heatinput > 1.5 ? 'Review' : 'Pass'",
        {'heatinput': 1.0},
      );
      expect(result, 'Pass');
    });
  });

  group('FormulaEngine.extractDependencies', () {
    test('extracts field names from formula', () {
      final deps = engine.extractDependencies('voltage * current / speed');
      expect(deps, containsAll(['voltage', 'current', 'speed']));
    });

    test('ignores operators and numbers', () {
      final deps = engine.extractDependencies('a + 100');
      expect(deps, contains('a'));
      expect(deps, isNot(contains('100')));
    });
  });

  group('FormulaEngine.isValidFormula', () {
    test('valid simple formula', () {
      expect(engine.isValidFormula('a + b'), isTrue);
    });

    test('empty string is invalid', () {
      expect(engine.isValidFormula(''), isFalse);
    });

    test('unbalanced parenthesis is invalid', () {
      expect(engine.isValidFormula('a + (b'), isFalse);
    });

    test('valid formula with parens', () {
      expect(engine.isValidFormula('(a + b) * c'), isTrue);
    });
  });

  group('FormulaEngine.hasCircularDependency', () {
    test('detects self-reference', () {
      expect(engine.hasCircularDependency('a', ['a'], {}), isTrue);
    });

    test('detects indirect cycle', () {
      // a depends on b; b depends on a — full graph must include both entries
      final deps = {'a': ['b'], 'b': ['a']};
      expect(engine.hasCircularDependency('a', ['b'], deps), isTrue);
    });

    test('no cycle passes', () {
      final deps = {'b': ['c']};
      expect(engine.hasCircularDependency('a', ['b'], deps), isFalse);
    });
  });
}
