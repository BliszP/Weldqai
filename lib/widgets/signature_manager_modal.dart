// lib/widgets/signature_manager_modal.dart
// Signature capture for contractor and client

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class SignatureData {
  final String? name;
  final String? date;
  final String? imageUrl;
  
  SignatureData({this.name, this.date, this.imageUrl});
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'date': date,
    'imageUrl': imageUrl,
  };
  
  factory SignatureData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return SignatureData();
    return SignatureData(
      name: json['name'],
      date: json['date'],
      imageUrl: json['imageUrl'],
    );
  }
}

class SignatureManagerModal extends StatefulWidget {
  const SignatureManagerModal({
    super.key,
    required this.reportId,
    required this.userId,
    required this.schemaId,
  });
  
  final String reportId;
  final String userId;
  final String schemaId;
  
  @override
  State<SignatureManagerModal> createState() => _SignatureManagerModalState();
}

class _SignatureManagerModalState extends State<SignatureManagerModal> {
  late TextEditingController _contractorNameCtrl;
  late TextEditingController _contractorDateCtrl;
  late TextEditingController _clientNameCtrl;
  late TextEditingController _clientDateCtrl;
  
  String? _contractorSigUrl;
  String? _clientSigUrl;
  
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();
    _contractorNameCtrl = TextEditingController();
    _contractorDateCtrl = TextEditingController(text: _todayDate());
    _clientNameCtrl = TextEditingController();
    _clientDateCtrl = TextEditingController(text: _todayDate());
    _loadSignatures();
  }
  
  @override
  void dispose() {
    _contractorNameCtrl.dispose();
    _contractorDateCtrl.dispose();
    _clientNameCtrl.dispose();
    _clientDateCtrl.dispose();
    super.dispose();
  }
  
  String _todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  
  Future<void> _loadSignatures() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('reports')
          .doc(widget.schemaId)
          .collection('items')
          .doc(widget.reportId)
          .get();
      
      if (doc.exists) {
        final data = doc.data() ?? {};
        final signatures = data['signatures'] as Map<String, dynamic>?;
        
        if (signatures != null) {
          final contractor = SignatureData.fromJson(signatures['contractor']);
          final client = SignatureData.fromJson(signatures['client']);
          
          _contractorNameCtrl.text = contractor.name ?? '';
          _contractorDateCtrl.text = contractor.date ?? _todayDate();
          _contractorSigUrl = contractor.imageUrl;
          
          _clientNameCtrl.text = client.name ?? '';
          _clientDateCtrl.text = client.date ?? _todayDate();
          _clientSigUrl = client.imageUrl;
        }
      }
      
      setState(() => _loading = false);
    } catch (e) {
      AppLogger.error('Error loading signatures: $e');
      setState(() => _loading = false);
    }
  }
  
  Future<void> _signContractor() async {
    final signature = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => const _SignaturePad(title: 'Contractor Signature'),
      ),
    );
    
    if (signature == null) return;
    
    try {
      _showLoading();
      
      final path = 'reports/${widget.userId}/${widget.schemaId}/${widget.reportId}/contractor_sig.png';
      final ref = FirebaseStorage.instance.ref(path);
      
      await ref.putData(signature, SettableMetadata(contentType: 'image/png'));
      final url = await ref.getDownloadURL();
      
      setState(() => _contractorSigUrl = url);
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contractor signature saved')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Failed to save signature: $e');
    }
  }
  
  Future<void> _signClient() async {
    final signature = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => const _SignaturePad(title: 'Client Signature'),
      ),
    );
    
    if (signature == null) return;
    
    try {
      _showLoading();
      
      final path = 'reports/${widget.userId}/${widget.schemaId}/${widget.reportId}/client_sig.png';
      final ref = FirebaseStorage.instance.ref(path);
      
      await ref.putData(signature, SettableMetadata(contentType: 'image/png'));
      final url = await ref.getDownloadURL();
      
      setState(() => _clientSigUrl = url);
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Client signature saved')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Failed to save signature: $e');
    }
  }
  
  Future<void> _save() async {
    try {
      _showLoading();
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('reports')
          .doc(widget.schemaId)
          .collection('items')
          .doc(widget.reportId)
          .set({
        'signatures': {
          'contractor': {
            'name': _contractorNameCtrl.text.trim(),
            'date': _contractorDateCtrl.text.trim(),
            'imageUrl': _contractorSigUrl,
          },
          'client': {
            'name': _clientNameCtrl.text.trim(),
            'date': _clientDateCtrl.text.trim(),
            'imageUrl': _clientSigUrl,
          },
        },
      }, SetOptions(merge: true));
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pop(context); // Close modal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signatures saved')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Save failed: $e');
    }
  }
  
  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
  
  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    
    if (picked != null) {
      controller.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.draw),
                const SizedBox(width: 8),
                Text('Signatures', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // CONTRACTOR
            Row(
              children: [
                const Icon(Icons.engineering, size: 20),
                const SizedBox(width: 8),
                Text('CONTRACTOR', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _contractorNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            
            TextField(
              controller: _contractorDateCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () => _pickDate(_contractorDateCtrl),
            ),
            const SizedBox(height: 12),
            
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _contractorSigUrl != null
                  ? Image.network(_contractorSigUrl!, fit: BoxFit.contain)
                  : const Center(child: Text('No signature')),
            ),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _signContractor,
                    icon: const Icon(Icons.edit),
                    label: Text(_contractorSigUrl == null ? 'Sign' : 'Re-sign'),
                  ),
                ),
                if (_contractorSigUrl != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => _contractorSigUrl = null),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 32),
            
            // CLIENT
            Row(
              children: [
                const Icon(Icons.business, size: 20),
                const SizedBox(width: 8),
                Text('CLIENT', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _clientNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            
            TextField(
              controller: _clientDateCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () => _pickDate(_clientDateCtrl),
            ),
            const SizedBox(height: 12),
            
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _clientSigUrl != null
                  ? Image.network(_clientSigUrl!, fit: BoxFit.contain)
                  : const Center(child: Text('No signature')),
            ),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _signClient,
                    icon: const Icon(Icons.edit),
                    label: Text(_clientSigUrl == null ? 'Sign' : 'Re-sign'),
                  ),
                ),
                if (_clientSigUrl != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => _clientSigUrl = null),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save Signatures'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({required this.title});
  
  final String title;
  
  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<Offset?> _points = [];
  
  void _clear() {
    setState(() => _points.clear());
  }
  
  Future<void> _done() async {
  if (_points.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please draw your signature first')),
    );
    return;
  }
  
  try {
    // ✅ FIXED: Get actual canvas size
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? const Size(400, 200);
    
    // ✅ FIXED: Calculate bounds of the actual signature
    double minX = double.infinity;
    double maxX = 0;
    double minY = double.infinity;
    double maxY = 0;
    
    for (final point in _points) {
      if (point != null) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }
    }
    
    // ✅ Add padding around signature
    const padding = 20.0;
    minX = (minX - padding).clamp(0, canvasSize.width);
    maxX = (maxX + padding).clamp(0, canvasSize.width);
    minY = (minY - padding).clamp(0, canvasSize.height);
    maxY = (maxY + padding).clamp(0, canvasSize.height);
    
    final sigWidth = maxX - minX;
    final sigHeight = maxY - minY;
    
    // ✅ FIXED: Create image with signature bounds, not full screen
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, sigWidth, sigHeight),
      Paint()..color = Colors.white,
    );
    
    // ✅ FIXED: Thicker stroke and translate to crop bounds
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0; // ✅ Thicker stroke
    
    // Draw signature (translated to start at 0,0)
    for (int i = 0; i < _points.length - 1; i++) {
      if (_points[i] != null && _points[i + 1] != null) {
        final p1 = Offset(_points[i]!.dx - minX, _points[i]!.dy - minY);
        final p2 = Offset(_points[i + 1]!.dx - minX, _points[i + 1]!.dy - minY);
        canvas.drawLine(p1, p2, paint);
      }
    }
    
    final picture = recorder.endRecording();
    
    // ✅ FIXED: Export at 2x resolution for better quality
    final image = await picture.toImage(
      (sigWidth * 2).toInt(), 
      (sigHeight * 2).toInt(),
    );
    
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    
    AppLogger.info('✅ Signature image created: ${bytes.length} bytes (${sigWidth.toInt()}x${sigHeight.toInt()} @ 2x)');
      
      if (mounted) {
        Navigator.pop(context, bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save signature: $e')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clear,
            tooltip: 'Clear',
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _done,
            tooltip: 'Done',
          ),
        ],
      ),
      body: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _points.add(details.localPosition);
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _points.add(details.localPosition);
          });
        },
        onPanEnd: (details) {
          setState(() {
            _points.add(null);
          });
        },
        child: CustomPaint(
          painter: _SignaturePainter(_points),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  
  _SignaturePainter(this.points);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;
    
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }
  
  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}