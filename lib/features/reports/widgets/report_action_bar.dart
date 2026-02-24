// lib/features/reports/widgets/report_action_bar.dart
//
// Toolbar row for DynamicReportForm: Scan, Save, Export, Photos, Signatures.
// Purely presentational — all logic is handled via callbacks.

import 'package:flutter/material.dart';

class ReportActionBar extends StatelessWidget {
  const ReportActionBar({
    super.key,
    required this.docId,
    required this.lastSavedAt,
    required this.photoCount,
    required this.hasSignatures,
    required this.onSave,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.onScanPicker,
    required this.onScanOcr,
    required this.onPhotos,
    required this.onSignatures,
  });

  final String? docId;
  final DateTime? lastSavedAt;
  final int photoCount;
  final bool hasSignatures;
  final VoidCallback onSave;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;
  final VoidCallback onScanPicker;
  final VoidCallback onScanOcr;
  final VoidCallback onPhotos;
  final VoidCallback onSignatures;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Scan',
            icon: const Icon(Icons.document_scanner),
            onSelected: (v) {
              if (v == 'picker') onScanPicker();
              if (v == 'ocr') onScanOcr();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'picker',
                child: Row(children: [
                  Icon(Icons.center_focus_strong, size: 18),
                  SizedBox(width: 8),
                  Text('Scan'),
                ]),
              ),
              PopupMenuItem(
                value: 'ocr',
                child: Row(children: [
                  Icon(Icons.text_fields, size: 18),
                  SizedBox(width: 8),
                  Text('OCR'),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Export',
            onSelected: (v) {
              if (v == 'pdf') onExportPdf();
              if (v == 'xlsx') onExportExcel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
            ],
            child: const Icon(Icons.ios_share),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.camera_alt),
                if (photoCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Colors.blue,
                      child: Text(
                        '$photoCount',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Photos',
            onPressed: onPhotos,
          ),
          IconButton(
            icon: Icon(
              Icons.draw,
              color: hasSignatures ? Colors.blue : null,
            ),
            tooltip: 'Signatures',
            onPressed: onSignatures,
          ),
          const Spacer(),
          if (lastSavedAt != null)
            Text(
              'Saved: ${lastSavedAt!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
