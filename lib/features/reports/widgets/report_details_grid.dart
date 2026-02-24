// lib/features/reports/widgets/report_details_grid.dart
//
// Renders the header details section of a DynamicReportForm.
// Extracted from DynamicReportFormState._detailsGrid / _detailField.
// Manages its own local setState for dropdown/date display; notifies
// the parent via callbacks for anything that mutates shared state.

import 'dart:math' as math;
import 'package:flutter/material.dart';

// Private sentinel key for the standard-selector field.
const String _kStdKey = '__standard';

class ReportDetailsGrid extends StatefulWidget {
  const ReportDetailsGrid({
    super.key,
    required this.effectiveDetails,
    required this.detailCtrls,
    required this.selectedStandard,
    required this.onStandardChanged,
    required this.onDetailsChanged,
    required this.onFocus,
    required this.onRecalculate,
  });

  /// Schema fields to display.
  final List<Map<String, dynamic>> effectiveDetails;

  /// Shared controller map (passed by reference — parent owns disposal).
  final Map<String, TextEditingController> detailCtrls;

  /// Currently selected standard key, or null.
  final String? selectedStandard;

  /// Called when the user picks a different standard.
  /// Parent must update its schema and call setState.
  final void Function(String?) onStandardChanged;

  /// Called on any field value change so the parent can propagate to listeners.
  final void Function() onDetailsChanged;

  /// Called when a field receives focus so the parent can track the last
  /// focused controller (used by the OCR/Scan feature).
  final void Function(TextEditingController) onFocus;

  /// Called when a numeric field changes so the parent can re-run formulas.
  final void Function() onRecalculate;

  @override
  State<ReportDetailsGrid> createState() => _ReportDetailsGridState();
}

class _ReportDetailsGridState extends State<ReportDetailsGrid> {
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
    final i = items.indexWhere((e) => e.toLowerCase() == current.toLowerCase());
    return i >= 0 ? items[i] : null;
  }

  // --- decoration -----------------------------------------------------------

  InputDecoration _detailDecoration(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide:
            BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelText: label,
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2D31) : Colors.white,
      labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : null),
    );
  }

  // --- field builder --------------------------------------------------------

  Widget _detailField(Map<dynamic, dynamic> f) {
    final key = ((f['key'] ?? '') as Object).toString().trim();
    if (key.isEmpty) return const SizedBox.shrink();

    final label = (f['label'] ?? key).toString();
    final type = (f['type'] ?? 'text').toString().toLowerCase();
    final isRequired = f['required'] == true;

    final ctrl =
        widget.detailCtrls.putIfAbsent(key, () => TextEditingController());

    final displayLabel = isRequired ? '$label *' : label;

    // ---- Standard selector ------------------------------------------------
    if (key == _kStdKey) {
      final itemsRaw = (f['choices'] ?? f['options'] ?? const []) as List;
      final items =
          _uniqueChoices(itemsRaw.map((e) => e.toString()).toList());

      final want =
          ctrl.text.isEmpty ? widget.selectedStandard : ctrl.text;
      final safeValue = _coerceDropdownValue(want, items);
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
          widget.onStandardChanged(v);
          widget.onDetailsChanged();
        },
        decoration: _detailDecoration(displayLabel),
      );
    }

    // ---- Calculated (read-only) -------------------------------------------
    if (type == 'calculated') {
      final formula = f['formula']?.toString();
      final unit = f['unit']?.toString();

      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _detailDecoration(displayLabel).copyWith(
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unit != null && unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(unit, style: const TextStyle(fontSize: 12)),
                ),
              const Icon(Icons.calculate, size: 20),
            ],
          ),
          helperText: formula != null ? 'Formula: $formula' : null,
          helperMaxLines: 2,
        ),
        style:
            TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
      );
    }

    // ---- Dropdown / choice ------------------------------------------------
    if (type == 'dropdown' || type == 'choice') {
      final raw = (f['options'] ?? f['choices'] ?? const []) as List;
      final items = _uniqueChoices(raw.map((e) => e.toString()).toList());

      if (items.isEmpty) {
        return TextFormField(
          controller: ctrl,
          onTap: () => widget.onFocus(ctrl),
          decoration: _detailDecoration(displayLabel),
          onChanged: (_) => widget.onDetailsChanged(),
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
          setState(() {}); // local rebuild to reflect new dropdown value
          widget.onDetailsChanged();
        },
        decoration: _detailDecoration(displayLabel),
      );
    }

    // ---- Date ------------------------------------------------------------
    if (type == 'date') {
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: _detailDecoration(displayLabel).copyWith(
          suffixIcon: const Icon(Icons.calendar_today),
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
            widget.onDetailsChanged();
          }
        },
      );
    }

    // ---- Number ----------------------------------------------------------
    if (type == 'number') {
      final unit = f['unit']?.toString();
      final decimals = f['decimals'] as int?;

      return TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        onTap: () => widget.onFocus(ctrl),
        decoration: _detailDecoration(displayLabel).copyWith(
          suffixText: unit,
          helperText: decimals != null ? 'Decimals: $decimals' : null,
        ),
        onChanged: (_) {
          widget.onRecalculate();
          widget.onDetailsChanged();
        },
      );
    }

    // ---- Textarea --------------------------------------------------------
    if (type == 'textarea') {
      return TextFormField(
        controller: ctrl,
        maxLines: 3,
        onTap: () => widget.onFocus(ctrl),
        decoration: _detailDecoration(displayLabel),
        onChanged: (_) => widget.onDetailsChanged(),
      );
    }

    // ---- Default text ----------------------------------------------------
    return TextFormField(
      controller: ctrl,
      onTap: () => widget.onFocus(ctrl),
      decoration: _detailDecoration(displayLabel),
      onChanged: (_) {
        widget.onRecalculate();
        widget.onDetailsChanged();
      },
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final avail = constraints.maxWidth;
        final minField = avail < 600 ? 120.0 : 150.0;
        final cols =
            math.max(1, ((avail + gap) / (minField + gap)).floor());
        final cellW = (avail - (cols - 1) * gap) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final f in widget.effectiveDetails)
              if ((f['key'] ?? '').toString().trim().isNotEmpty)
                SizedBox(width: cellW, child: _detailField(f)),
          ],
        );
      },
    );
  }
}
