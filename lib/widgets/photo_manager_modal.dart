// lib/widgets/photo_manager_modal.dart
// Complete photo management for reports

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weldqai_app/core/services/analytics_service.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class PhotoData {
  final String url;
  final DateTime timestamp;
  final int size;
  
  PhotoData({
    required this.url,
    required this.timestamp,
    required this.size,
  });
  
  Map<String, dynamic> toJson() => {
    'url': url,
    'timestamp': timestamp.toIso8601String(),
    'size': size,
  };
  
  factory PhotoData.fromJson(Map<String, dynamic> json) => PhotoData(
    url: json['url'] ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    size: json['size'] ?? 0,
  );
}

class PhotoManagerModal extends StatefulWidget {
  const PhotoManagerModal({
    super.key,
    required this.reportId,
    required this.userId,
    required this.schemaId,
  });
  
  final String reportId;
  final String userId;
  final String schemaId;
  
  @override
  State<PhotoManagerModal> createState() => _PhotoManagerModalState();
}

class _PhotoManagerModalState extends State<PhotoManagerModal> {
  List<PhotoData> _photos = [];
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }
  
  Future<void> _loadPhotos() async {
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
        final photosList = (data['photos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _photos = photosList.map((p) => PhotoData.fromJson(p)).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      AppLogger.error('Error loading photos: $e');
      setState(() => _loading = false);
    }
  }
  
  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image == null) return;
      
      await _uploadPhoto(await image.readAsBytes(), image.name);
    } catch (e) {
      _showError('Failed to take photo: $e');
    }
  }
  
  Future<void> _uploadFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image == null) return;
      
      await _uploadPhoto(await image.readAsBytes(), image.name);
    } catch (e) {
      _showError('Failed to upload photo: $e');
    }
  }
  
  Future<void> _uploadPhoto(Uint8List bytes, String filename) async {
  // ✅ CREATE PERFORMANCE TRACE
  final trace = FirebasePerformance.instance.newTrace('photo_upload');
  
  try {
    _showLoading();
    
    // ✅ START TRACE
    await trace.start();
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'reports/${widget.userId}/${widget.schemaId}/${widget.reportId}/photo_$timestamp.jpg';
    
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      
      final url = await ref.getDownloadURL();
      
      final photoData = PhotoData(
        url: url,
        timestamp: DateTime.now(),
        size: bytes.length,
      );
      
      _photos.add(photoData);
      
      await _savePhotosToFirestore();

      // ✅ STOP TRACE & ADD METRICS
    trace.setMetric('file_size_bytes', bytes.length);
    trace.setMetric('success', 1);
    await trace.stop();

      // ✅ Track photo upload
    await AnalyticsService.logPhotoUploaded(
      userId: widget.userId,
      reportId: widget.reportId,
      photoCount: 1,
      fileSizeMB: bytes.length / (1024 * 1024),
    );
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo uploaded')),
        );
      }
   } catch (e) {
    // ✅ STOP TRACE ON ERROR
    trace.setMetric('success', 0);
    await trace.stop();
    
    if (mounted) Navigator.pop(context);
    _showError('Upload failed: $e');
  }
}
  Future<void> _deletePhoto(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      _showLoading();
      
      final photo = _photos[index];
      
      // Delete from Storage
      try {
        final ref = FirebaseStorage.instance.refFromURL(photo.url);
        await ref.delete();
      } catch (e) {
        AppLogger.debug('Failed to delete from storage: $e');
      }
      
      // Remove from list
      _photos.removeAt(index);
      
      // Update Firestore
      await _savePhotosToFirestore();

      // ✅ Track photo deletion
    await AnalyticsService.logPhotoDeleted(
      userId: widget.userId,
      reportId: widget.reportId,
    );
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo deleted')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Delete failed: $e');
    }
  }
  
  Future<void> _savePhotosToFirestore() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('reports')
        .doc(widget.schemaId)
        .collection('items')
        .doc(widget.reportId)
        .set({
      'photos': _photos.map((p) => p.toJson()).toList(),
    }, SetOptions(merge: true));
  }
  
  void _viewPhoto(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _PhotoViewer(
          photos: _photos,
          initialIndex: index,
          onDelete: () async {
            Navigator.pop(context);
            await _deletePhoto(index);
          },
        ),
      ),
    );
  }
  
  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      height: screenHeight * 0.85,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library),
              const SizedBox(width: 8),
              Text(
                'Report Photos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Upload'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_photos.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text('No photos yet', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Take a photo or upload from gallery', 
                      style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  return GestureDetector(
                    onTap: () => _viewPhoto(index),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            photo.url,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return const Center(
                                child: Icon(Icons.broken_image),
                              );
                            },
                          ),
                        ),
                        // Delete button overlay
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _deletePhoto(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        // Time stamp
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black87, Colors.transparent],
                              ),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                            child: Text(
                              '${photo.timestamp.hour}:${photo.timestamp.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          
          const Divider(height: 20),
          
          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: ${_photos.length} photo${_photos.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Storage: ${_formatSize(_photos.fold<int>(0, (acc, p) => acc + p.size))}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });
  
  final List<PhotoData> photos;
  final int initialIndex;
  final VoidCallback onDelete;
  
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late PageController _controller;
  late int _currentIndex;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Photo ${_currentIndex + 1} of ${widget.photos.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.onDelete,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                widget.photos[index].url,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}