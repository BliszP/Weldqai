// test/widget/report_widgets_test.dart
//
// Widget tests for ReportDetailsGrid and ReportEntryTable.
// These widgets have no Firebase dependency — they are pure Flutter UI.
// All callbacks are verified through captured invocations rather than
// Firebase or Provider interactions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weldqai_app/features/reports/widgets/report_details_grid.dart';
import 'package:weldqai_app/features/reports/widgets/report_entry_table.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A text-field schema entry.
Map<String, dynamic> _textField(String key, String label,
    {bool required = false}) =>
    {'key': key, 'label': label, 'type': 'text', 'required': required};

/// A dropdown schema entry.
Map<String, dynamic> _dropdownField(
    String key, String label, List<String> choices) =>
    {'key': key, 'label': label, 'type': 'dropdown', 'choices': choices};

/// A numeric schema entry.
Map<String, dynamic> _numberField(String key, String label) =>
    {'key': key, 'label': label, 'type': 'number'};

/// A table column (text by default).
Map<String, dynamic> _col(String key, String label,
    {String type = 'text'}) =>
    {'key': key, 'label': label, 'type': type};

// ── ReportDetailsGrid ─────────────────────────────────────────────────────────

void main() {
  group('ReportDetailsGrid', () {
    late Map<String, TextEditingController> ctrls;

    setUp(() => ctrls = {});
    tearDown(() {
      for (final c in ctrls.values) {
        c.dispose();
      }
    });

    testWidgets('renders label for each text field', (tester) async {
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: [
            _textField('job_no', 'Job No'),
            _textField('weld_no', 'Weld No'),
          ],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () {},
          onFocus: (_) {},
          onRecalculate: () {},
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Job No'), findsOneWidget);
      expect(find.textContaining('Weld No'), findsOneWidget);
    });

    testWidgets('required field label contains asterisk', (tester) async {
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: [_textField('ref', 'Ref No', required: true)],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () {},
          onFocus: (_) {},
          onRecalculate: () {},
        ),
      ));
      await tester.pump();

      // Required fields display "Label *"
      expect(find.textContaining('Ref No *'), findsOneWidget);
    });

    testWidgets('typing in a text field invokes onDetailsChanged', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: [_textField('job_no', 'Job No')],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () => callCount++,
          onFocus: (_) {},
          onRecalculate: () {},
        ),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).first, 'JOB-001');
      await tester.pump();

      expect(callCount, greaterThan(0));
    });

    testWidgets('onFocus is called when a text field is tapped', (tester) async {
      TextEditingController? focused;
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: [_textField('location', 'Location')],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () {},
          onFocus: (c) => focused = c,
          onRecalculate: () {},
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();

      expect(focused, isNotNull);
    });

    testWidgets('renders dropdown for dropdown-type field', (tester) async {
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: [
            _dropdownField('process', 'Process', ['SMAW', 'GMAW', 'GTAW']),
          ],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () {},
          onFocus: (_) {},
          onRecalculate: () {},
        ),
      ));
      await tester.pump();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('empty effectiveDetails renders without error', (tester) async {
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: const [],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () {},
          onFocus: (_) {},
          onRecalculate: () {},
        ),
      ));
      await tester.pump();
      // No crash — widget renders (empty grid).
      expect(find.byType(ReportDetailsGrid), findsOneWidget);
    });

    testWidgets('onRecalculate is invoked when a number field changes',
        (tester) async {
      int recalcCount = 0;
      await tester.pumpWidget(_wrap(
        ReportDetailsGrid(
          effectiveDetails: [_numberField('thickness', 'Thickness')],
          detailCtrls: ctrls,
          selectedStandard: null,
          onStandardChanged: (_) {},
          onDetailsChanged: () {},
          onFocus: (_) {},
          onRecalculate: () => recalcCount++,
        ),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).first, '12.5');
      await tester.pump();

      expect(recalcCount, greaterThan(0));
    });
  });

  // ── ReportEntryTable ────────────────────────────────────────────────────────

  group('ReportEntryTable', () {
    List<Map<String, TextEditingController>> makeRows(int count) => [
          for (int i = 0; i < count; i++) <String, TextEditingController>{},
        ];

    void disposeRows(List<Map<String, TextEditingController>> rows) {
      for (final row in rows) {
        for (final c in row.values) {
          c.dispose();
        }
      }
    }

    testWidgets('shows column headers from effectiveColumns', (tester) async {
      final rows = makeRows(1);
      await tester.pumpWidget(_wrap(
        ReportEntryTable(
          effectiveColumns: [
            _col('weld_id', 'Weld ID'),
            _col('diameter', 'Diameter'),
          ],
          rowCtrls: rows,
          onFocus: (_) {},
          onAddRow: () {},
          onDeleteRow: (_) {},
          onRowRecalculate: (_) {},
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Weld ID'), findsOneWidget);
      expect(find.textContaining('Diameter'), findsOneWidget);
      disposeRows(rows);
    });

    testWidgets('renders Add Row button', (tester) async {
      final rows = makeRows(0);
      await tester.pumpWidget(_wrap(
        ReportEntryTable(
          effectiveColumns: [_col('weld_id', 'Weld ID')],
          rowCtrls: rows,
          onFocus: (_) {},
          onAddRow: () {},
          onDeleteRow: (_) {},
          onRowRecalculate: (_) {},
        ),
      ));
      await tester.pump();

      // There should be a button to add a row.
      expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
      disposeRows(rows);
    });

    testWidgets('tapping Add Row button calls onAddRow', (tester) async {
      int added = 0;
      final rows = makeRows(0);
      await tester.pumpWidget(_wrap(
        ReportEntryTable(
          effectiveColumns: [_col('weld_id', 'Weld ID')],
          rowCtrls: rows,
          onFocus: (_) {},
          onAddRow: () => added++,
          onDeleteRow: (_) {},
          onRowRecalculate: (_) {},
        ),
      ));
      await tester.pump();

      final addButton = find.byIcon(Icons.add);
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton.first);
        await tester.pump();
        expect(added, 1);
      }
      disposeRows(rows);
    });

    testWidgets('shows one data row per entry in rowCtrls', (tester) async {
      final rows = makeRows(3);
      await tester.pumpWidget(_wrap(
        ReportEntryTable(
          effectiveColumns: [_col('weld_id', 'Weld ID')],
          rowCtrls: rows,
          onFocus: (_) {},
          onAddRow: () {},
          onDeleteRow: (_) {},
          onRowRecalculate: (_) {},
        ),
      ));
      await tester.pump();

      // Each row has a text field for its cell; 3 rows × 1 column = 3 fields.
      expect(find.byType(TextField), findsAtLeastNWidgets(3));
      disposeRows(rows);
    });

    testWidgets('empty columns list renders without crash', (tester) async {
      final rows = makeRows(0);
      await tester.pumpWidget(_wrap(
        ReportEntryTable(
          effectiveColumns: const [],
          rowCtrls: rows,
          onFocus: (_) {},
          onAddRow: () {},
          onDeleteRow: (_) {},
          onRowRecalculate: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.byType(ReportEntryTable), findsOneWidget);
      disposeRows(rows);
    });
  });
}
