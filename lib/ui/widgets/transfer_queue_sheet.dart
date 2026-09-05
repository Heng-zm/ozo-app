import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';

/// Bottom sheet / drawer showing the active P2P transfer queue and download manager
class TransferQueueSheet extends StatelessWidget {
  const TransferQueueSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TransferQueueSheet(),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    return '${_formatBytes(bytesPerSec.toInt())}/s';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final transfers = provider.transferManager.activeTransfers;
    final theme = Theme.of(context);

    final activeCount = transfers
        .where((t) => t.status == TransferStatus.transferring)
        .length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.swap_vert_circle_rounded,
                    color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transfer Manager',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        activeCount > 0
                            ? '$activeCount active transfers in progress'
                            : 'All transfers finished or idle',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // List of transfers
          if (transfers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48.0),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_done_rounded,
                    size: 56,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No active or recent transfers',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                itemCount: transfers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = transfers[index];
                  final isUpload = item.direction == TransferDirection.upload;
                  final progress = item.progress;
                  final speedStr = _formatSpeed(item.speedBytesPerSec);

                  Color statusColor;
                  String statusLabel;

                  switch (item.status) {
                    case TransferStatus.transferring:
                      statusColor = theme.colorScheme.primary;
                      statusLabel = isUpload ? 'Uploading...' : 'Downloading...';
                      break;
                    case TransferStatus.completed:
                      statusColor = Colors.green;
                      statusLabel = 'Completed';
                      break;
                    case TransferStatus.paused:
                      statusColor = Colors.orange;
                      statusLabel = 'Paused';
                      break;
                    case TransferStatus.failed:
                      statusColor = Colors.redAccent;
                      statusLabel = 'Failed';
                      break;
                    case TransferStatus.offered:
                      statusColor = Colors.blueGrey;
                      statusLabel = 'Waiting...';
                      break;
                  }

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isUpload ? Colors.blue : Colors.teal)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isUpload
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                color: isUpload ? Colors.blue : Colors.teal,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.fileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${_formatBytes(item.bytesTransferred)} of ${_formatBytes(item.fileSize)} • $statusLabel ${speedStr.isNotEmpty ? '• $speedStr' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: statusColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.status == TransferStatus.completed
                                ? 1.0
                                : progress,
                            backgroundColor:
                                theme.colorScheme.onSurface.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                            minHeight: 6,
                          ),
                        ),
                        if (item.status == TransferStatus.completed &&
                            item.localPath.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final file = File(item.localPath);
                                if (await file.exists()) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('File saved to: ${item.localPath}'),
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.folder_open_rounded, size: 16),
                              label: const Text('Show in Folder', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
