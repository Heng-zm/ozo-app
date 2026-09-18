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
            if (!_isLoading)
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
      body: Stack(
        children: [
          PdfViewer.file(
            widget.filePath,
            controller: _pdfController,
            params: PdfViewerParams(
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
