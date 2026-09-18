import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Instant In-App PDF & Document Viewer
class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String? title;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    this.title,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _pageCount = 1;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      _errorMessage = 'PDF file not found at: ${widget.filePath}';
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.title ?? p.basename(widget.filePath);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (!_isLoading && _errorMessage == null)
              Text(
                'Page $_currentPage of $_pageCount',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.zoom_in),
            tooltip: 'Zoom In',
            onPressed: () {
              _pdfController.zoomUp();
            },
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.zoom_out),
            tooltip: 'Zoom Out',
            onPressed: () {
              _pdfController.zoomDown();
            },
          ),
        ],
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                        color: Colors.amber, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(CupertinoIcons.arrow_left),
                      label: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                PdfViewer.file(
                  widget.filePath,
                  controller: _pdfController,
                  params: PdfViewerParams(
                    errorBannerBuilder: (context, error, stackTrace, documentRef) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                                  color: Colors.amber, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'Error loading document: $error',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    onViewerReady: (document, controller) {
                      setState(() {
                        _pageCount = document.pages.length;
                        _isLoading = false;
                      });
                    },
                    onPageChanged: (pageNumber) {
                      if (pageNumber != null) {
                        setState(() {
                          _currentPage = pageNumber;
                        });
                      }
                    },
                  ),
                ),
                if (_isLoading)
                  const Center(
                    child: CupertinoActivityIndicator(radius: 16),
                  ),
              ],
            ),
      bottomNavigationBar: !_isLoading && _pageCount > 1
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_left),
                    onPressed: _currentPage > 1
                        ? () => _pdfController.goToPage(pageNumber: _currentPage - 1)
                        : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: _currentPage.toDouble().clamp(1.0, _pageCount.toDouble()),
                      min: 1.0,
                      max: _pageCount.toDouble(),
                      divisions: _pageCount > 1 ? _pageCount - 1 : 1,
                      onChanged: (val) {
                        final target = val.round();
                        _pdfController.goToPage(pageNumber: target);
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_right),
                    onPressed: _currentPage < _pageCount
                        ? () => _pdfController.goToPage(pageNumber: _currentPage + 1)
                        : null,
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
