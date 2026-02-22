// lib/features/reports/widgets/scan_camera_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:weldqai_app/core/services/scan_service.dart';

/// Full-screen camera page for barcode/QR scanning.
/// Uses only supported parameters for mobile_scanner ^5.2.3.
class ScanCameraPage extends StatefulWidget {
  const ScanCameraPage({
    super.key,
    required this.mode,
    this.title = 'Scan',
  });

  final ScanMode mode; // reserved for future modes; currently barcode/QR
  final String title;

  @override
  State<ScanCameraPage> createState() => _ScanCameraPageState();
}

class _ScanCameraPageState extends State<ScanCameraPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    final codes = cap.barcodes;
    if (codes.isEmpty) return;

    final raw = codes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    _done = true; // debounce
    if (!mounted) return;
    Navigator.of(context).pop<String>(raw.trim());
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() {});
    } catch (_) {
      // ignore: device may not support torch
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
      if (mounted) setState(() {});
    } catch (_) {
      // ignore: single-camera device
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.flip_camera_android),
            onPressed: _switchCamera,
          ),
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flash_on),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Subtle overlay with a center guide
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.30),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
              ),
            ),
          ),

          // Bottom hint
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Point camera at QR/Barcode',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
