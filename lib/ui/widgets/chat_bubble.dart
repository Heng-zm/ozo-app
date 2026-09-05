import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOutgoing;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    final bubbleBg = isOutgoing
        ? (isDark ? TelegramTheme.darkOutgoingBubble : TelegramTheme.lightOutgoingBubble)
        : (isDark ? TelegramTheme.darkIncomingBubble : TelegramTheme.lightIncomingBubble);

    final textColor = isDark
        ? TelegramTheme.darkTextPrimary
        : TelegramTheme.lightTextPrimary;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleBg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isOutgoing ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: isOutgoing ? const Radius.circular(4) : const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isOutgoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.senderName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: TelegramTheme.primaryBlue,
                    ),
                  ),
                ),
              if (message.type == MessageType.file && message.fileMetadata != null)
                _buildFileAttachmentCard(context, message.fileMetadata!)
              else
                Text(
                  message.content,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? TelegramTheme.darkTextSecondary
                          : TelegramTheme.lightTextSecondary,
                    ),
                  ),
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileAttachmentCard(BuildContext context, FileMetadata meta) {
    final chatProvider = context.watch<ChatProvider>();
    final activeTransfer = chatProvider.transferManager.getTransfer(meta.transferId);

    final isDownloading = activeTransfer != null &&
        activeTransfer.status == TransferStatus.transferring;
    final isPaused = activeTransfer != null &&
        activeTransfer.status == TransferStatus.paused;
    final isCompleted = meta.isCompleted ||
        (activeTransfer != null && activeTransfer.status == TransferStatus.completed);

    final sizeStr = _formatBytes(meta.fileSize);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: TelegramTheme.primaryBlue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getFileIcon(meta.fileName),
                  color: TelegramTheme.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOutgoing && !isCompleted)
                IconButton(
                  icon: Icon(
                    isDownloading
                        ? Icons.pause_circle_filled
                        : (isPaused ? Icons.play_circle_fill : Icons.download_rounded),
                    color: TelegramTheme.primaryBlue,
                    size: 28,
                  ),
                  onPressed: () {
                    if (isDownloading) {
                      chatProvider.transferManager.pauseTransfer(meta.transferId);
                    } else if (isPaused) {
                      chatProvider.transferManager.resumeTransfer(meta.transferId);
                    } else {
                      chatProvider.acceptIncomingFile(message);
                    }
                  },
                ),
              if (isCompleted)
                const Icon(
                  Icons.check_circle_rounded,
                  color: TelegramTheme.onlineGreen,
                  size: 24,
                ),
            ],
          ),
          if (activeTransfer != null && isDownloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: activeTransfer.progress,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(TelegramTheme.primaryBlue),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(activeTransfer.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  '${_formatBytes(activeTransfer.speedBytesPerSec.toInt())}/s',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 13, color: Colors.grey);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.grey);
      case MessageStatus.delivered:
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: TelegramTheme.checkmarkBlue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 13, color: Colors.red);
    }
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'mp4':
      case 'mkv':
      case 'mov':
        return Icons.video_file_rounded;
      case 'mp3':
      case 'wav':
      case 'ogg':
        return Icons.audio_file_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
