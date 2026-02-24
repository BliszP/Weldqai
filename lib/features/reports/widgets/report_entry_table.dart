// lib/features/reports/widgets/report_entry_table.dart
//
// Horizontally-scrollable data-entry table for DynamicReportForm.
// Extracted from DynamicReportFormState entries section / _cellEditor.
// Owns the horizontal ScrollController. Row adds/removes delegate to parent
// via callbacks so parent can dispose controllers and call setState.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class ReportEntryTable extends StatefulWidget {
  const ReportEntryTable({
    super.key,
    required this.effectiveColumns,
    required this.rowCtrls,
    required this.onFocus,
    required this.onAddRow,
    required this.onDeleteRow,
    required this.onRowRecalculate,
    this.onNewReport,
  });

  /// Schema columns to display.
  final List<Map<String, dynamic>> effectiveColumns;

  /// Shared row-controller list (passed by reference — parent owns disposal).
  final List<Map<String, TextEditingController>> rowCtrls;

  /// Called when a cell receives focus so the parent tracks the last controller.
  final void Function(TextEditingController) onFocus;

  /// Parent adds an empty row and calls its own setState.
  final VoidCallback onAddRow;

  /// Parent removes the row at [index], disposes its controllers, calls setState.
  final void Function(int index) onDeleteRow;

  /// Parent re-runs row formulas for [rowIndex] (modifies controller text).
  final void Function(int rowIndex) onRowRecalculate;

  /// Optional callback shown as "Add Report" button when non-null.
  final VoidCallback? onNewReport;

  @override
  State<ReportEntryTable> createState() => _ReportEntryTableState();
}

class _ReportEntryTableState extends State<ReportEntryTable> {
  final ScrollController _hCtrl = ScrollController();

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  // --- helpers (pure functions, duplicated from parent state) ---------------

  List<String> _uniqueChoices(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in raw.map((e) => e.toString())) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  String? _coerceDropdownValue(String? current, List<String> items) {
    if (current == null || current.isEmpty) return null;
    if (items.contains(current)) return current;
    final i =
        items.indexWhere((e) => e.toLowerCase() == current.toLowerCase());
    return i >= 0 ? items[i] : null;
  }

  // --- decoration -----------------------------------------------------------

  InputDecoration _cellDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide:
            BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2D31) : Colors.white,
    );
  }

  // --- cell builder ---------------------------------------------------------

  Widget _cellEditor(int rowIndex, Map<String, dynamic> col) {
    final key = (col['key'] ?? '').toString();
    if (key.isEmpty) return const SizedBox.shrink();

    final type = (col['type'] ?? 'text').toString().toLowerCase();
    final ctrl = widget.rowCtrls[rowIndex]
        .putIfAbsent(key, () => TextEditingController());

    // ---- Calculated (read-only) ------------------------------------------
    if (type == 'calculated') {
      final unit = col['unit']?.toString();

      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _cellDecoration(context).copyWith(
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unit != null && unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(unit, style: const TextStyle(fontSize: 10)),
                ),
              const Icon(Icons.calculate, size: 16),
            ],
          ),
        ),
        style: TextStyle(
          color: Colors.blue[700],
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      );
    }

    // ---- Dropdown / choice -----------------------------------------------
    if (type == 'dropdown' || type == 'choice') {
      final raw = (col['options'] ?? col['choices'] ?? const []) as List;
      final items = _uniqueChoices(raw.map((e) => e.toString()).toList());

      if (items.isEmpty) {
        return TextFormField(
          controller: ctrl,
          onTap: () => widget.onFocus(ctrl),
          onChanged: (_) {
            widget.onRowRecalculate(rowIndex);
            setState(() {}); // local rebuild to show updated values
          },
          decoration: _cellDecoration(context),
        );
      }

      final safeValue = _coerceDropdownValue(ctrl.text, items);
      if (safeValue != ctrl.text) ctrl.text = safeValue ?? '';

      return DropdownButtonFormField<String>(
        isExpanded: true,
        value: safeValue,
        items: [
          for (final v in items)
            DropdownMenuItem(
                value: v, child: Text(v, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          ctrl.text = v ?? '';
          widget.onRowRecalculate(rowIndex);
          setState(() {});
        },
        decoration: _cellDecoration(context),
      );
    }

    // ---- Date -----------------------------------------------------------
    if (type == 'date') {
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _cellDecoration(context).copyWith(
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(now.year - 10),
            lastDate: DateTime(now.year + 10),
          );
          if (picked != null) {
            final s = '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}';
            setState(() => ctrl.text = s);
          }
        },
      );
    }

    // ---- Default (text / number) -----------------------------------------
    final keyboard =
        (type == 'number') ? TextInputType.number : TextInputType.text;

    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      readOnly: type == 'calculated',
      onTap: () => widget.onFocus(ctrl),
      onChanged: (_) {
        widget.onRowRecalculate(rowIndex);
        setState(() {});
      },
      decoration: _cellDecoration(context),
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final columns = widget.effectiveColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entries', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Scrollbar(
          controller: _hCtrl,
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _hCtrl,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(
                  700,
                  columns.fold<double>(0.0, (w, c) {
                    final cw = (c['width'] is num)
                        ? (c['width'] as num).toDouble()
                        : 140.0;
                    return w + cw + 12.0;
                  }),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      for (final c in columns)
                        SizedBox(
                          width: (c['width'] is num)
                              ? (c['width'] as num).toDouble()
                              : 140.0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            child: Text(
                              (c['label'] ?? c['key'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const Divider(height: 1),
                  // Data rows
                  for (int r = 0; r < widget.rowCtrls.length; r++)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in columns)
                          SizedBox(
                            width: (c['width'] is num)
                                ? (c['width'] as num).toDouble()
                                : 140.0,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: _cellEditor(r, c),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove row',
                          onPressed: () => widget.onDeleteRow(r),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: widget.onAddRow,
              icon: const Icon(Icons.add),
              label: const Text('Add Row'),
            ),
            if (widget.onNewReport != null)
              TextButton.icon(
                onPressed: widget.onNewReport,
                icon: const Icon(Icons.add_to_photos_outlined),
                label: const Text('Add Report'),
              ),
          ],
        ),
      ],
    );
  }
}
