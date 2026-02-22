import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:weldqai_app/features/reports/widgets/scan_camera_page.dart';

/// Supported scanning modes for the camera page.
enum ScanMode { barcode, text }

/// Unified scan helper used by forms and accordions.
class ScanService {
  /// Back-compat entry point used by older widgets:
  /// - If [mode] == ScanMode.barcode → opens camera for QR/Barcode and returns a String.
  /// - If [mode] == ScanMode.text    → captures image and runs OCR and returns a String.
  ///
  /// Optionally, provide [parse] to convert a scanned String into a Map you can merge.
  /// If [parse] returns null (or throws), the raw String is returned.
  Future<Object?> startScan(
    BuildContext context, {
    ScanMode mode = ScanMode.barcode,
    String? title,
    Map<String, dynamic>? Function(String raw)? parse,
  }) {
    if (!context.mounted) return Future.value(null);
    // Context is captured synchronously before any suspension point.
    final Future<String?> scan = (mode == ScanMode.barcode)
        ? scanBarcode(context, title: title ?? 'Scan Code')
        : scanText(context, title: title ?? 'OCR Text');
    return scan.then((raw) {
      if (raw == null || raw.isEmpty) return null;
      if (parse != null) {
        try {
          final m = parse(raw);
          if (m != null) return m; // allow accordion to merge it
        } catch (_) {
          // fall through to return the raw string
        }
      }
      return raw; // default: return the string
    });
  }

  /// Shows a choice: try barcode first, then OCR (or vice-versa).
  Future<String?> scanPicker(BuildContext context, {String? title}) {
    // Context is captured synchronously; chaining avoids async gap warnings.
    return scanBarcode(context, title: title ?? 'Scan Code').then((code) {
      if (code != null && code.isNotEmpty) return Future<String?>.value(code);
      if (!context.mounted) return Future<String?>.value(null);
      return scanText(context, title: 'OCR Text');
    });
  }

  /// Full-screen barcode/QR scanning (opens camera).
  Future<String?> scanBarcode(BuildContext context, {String? title}) async {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScanCameraPage(
          mode: ScanMode.barcode,
          title: title ?? 'Scan',
        ),
      ),
    );
  }

  /// OCR text from camera (mobile) or file picker (web/desktop).
  Future<String?> scanText(BuildContext context, {String? title}) async {
    final ImagePicker picker = ImagePicker();
    XFile? file;

    try {
      file = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (_) {
      // ignore and fallback
    }

    file ??= await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;

    if (kIsWeb) {
      return 'OCR not supported on web. Picked: ${file.name}';
    }

    try {
      final input = InputImage.fromFilePath(file.path);
      final recognizer = TextRecognizer();
      final result = await recognizer.processImage(input);
      await recognizer.close();

      final buffer = StringBuffer();
      for (final block in result.blocks) {
        for (final line in block.lines) {
          buffer.writeln(line.text);
        }
      }
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }
}
