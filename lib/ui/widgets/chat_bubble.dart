import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'media_gallery_viewer.dart';
import 'voice_note_player.dart';

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
    ChatProvider? chatProvider;
    try {
      chatProvider = context.watch<ChatProvider>();
    } catch (_) {
      chatProvider = null;
    }

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
        child: GestureDetector(
          onLongPress: () => _showMessageOptions(context, chatProvider),
          onSecondaryTap: () => _showMessageOptions(context, chatProvider),
          onDoubleTap: () => chatProvider?.setReplyingTo(message),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: message.isSticker ? Colors.transparent : bubbleBg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isOutgoing ? const Radius.circular(16) : const Radius.circular(4),
                bottomRight: isOutgoing ? const Radius.circular(4) : const Radius.circular(16),
              ),
              boxShadow: message.isSticker
                  ? null
                  : [
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

                // Quoted Reply preview if this is a reply to another message
                if (message.replyToText != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(
                          color: TelegramTheme.primaryBlue,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.replyToSenderName ?? 'Reply',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: TelegramTheme.primaryBlue,
                          ),
                        ),
                        Text(
                          message.replyToText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (message.isSticker)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      message.content,
                      style: const TextStyle(fontSize: 80),
                    ),
                  )
                else if (message.isVoice)
                  VoiceNotePlayer(message: message, isMe: isOutgoing)
                else if (message.isImage && message.fileMetadata != null)
                  _buildImageAttachmentCard(context, message.fileMetadata!)
                else if (message.type == MessageType.file && message.fileMetadata != null)
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

                // Emoji Reaction Chips
                if (message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: message.reactions.entries.map((entry) {
                      final emoji = entry.key;
                      final userIds = entry.value;
                      final count = userIds.length;
                      final hasReacted = chatProvider != null && userIds.contains(chatProvider.deviceId);
                      return GestureDetector(
                        onTap: () => chatProvider?.toggleReaction(message.id, emoji),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hasReacted
                                ? TelegramTheme.primaryBlue.withValues(alpha: 0.2)
                                : (isDark ? Colors.white12 : Colors.black12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: hasReacted ? TelegramTheme.primaryBlue : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            '$emoji $count',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: hasReacted ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context, ChatProvider? provider) {
    if (provider == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick Reaction Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['❤️', '👍', '👎', '😂', '🔥', '🎉'].map((emoji) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          provider.toggleReaction(message.id, emoji);
                          Navigator.of(ctx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: TelegramTheme.primaryBlue),
                  title: const Text('Reply'),
                  onTap: () {
                    provider.setReplyingTo(message);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.push_pin_rounded, color: TelegramTheme.primaryBlue),
                  title: const Text('Pin Message'),
                  onTap: () {
                    provider.pinMessage(message.chatId, message.id);
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message pinned!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                if (message.content.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copy Text'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message copied to clipboard'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  title: const Text('Delete for Everyone', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    provider.deleteMessageForEveryone(message.id);
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _buildImageAttachmentCard(BuildContext context, FileMetadata meta) {
    final chatProvider = context.watch<ChatProvider>();
    final activeTransfer = chatProvider.transferManager.getTransfer(meta.transferId);

    final isDownloading = activeTransfer != null &&
        activeTransfer.status == TransferStatus.transferring;
    final isCompleted = meta.isCompleted ||
        (activeTransfer != null && activeTransfer.status == TransferStatus.completed);

    final hasLocalFile = meta.localPath != null && File(meta.localPath!).existsSync();

    if (hasLocalFile && isCompleted) {
      final file = File(meta.localPath!);
      return GestureDetector(
        onTap: () => MediaGalleryViewer.show(
          context,
          imageFile: file,
          fileName: meta.fileName,
          subtitle: _formatBytes(meta.fileSize),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 260,
              minWidth: 160,
            ),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildFileAttachmentCard(context, meta),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_rounded, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _formatBytes(meta.fileSize),
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If not yet downloaded, show thumbnail placeholder with download button
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: TelegramTheme.primaryBlue.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.image_rounded,
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
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatBytes(meta.fileSize),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (!isOutgoing)
                IconButton(
                  icon: Icon(
                    isDownloading ? Icons.hourglass_top_rounded : Icons.download_rounded,
                    color: TelegramTheme.primaryBlue,
                    size: 26,
                  ),
                  onPressed: () => chatProvider.acceptIncomingFile(message),
                ),
            ],
          ),
          if (activeTransfer != null && isDownloading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: activeTransfer.progress,
              backgroundColor: Colors.grey.withAlpha(50),
              valueColor: const AlwaysStoppedAnimation(TelegramTheme.primaryBlue),
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
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
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
