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
import '../../core/utils/map_launcher.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOutgoing;
  final ValueChanged<String>? onQuotedMessageTap;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    this.onQuotedMessageTap,
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

    return _SwipeToReply(
      isOutgoing: isOutgoing,
      onReply: () => chatProvider?.setReplyingTo(message),
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _showMessageOptions(context, chatProvider);
            },
            onSecondaryTap: () => _showMessageOptions(context, chatProvider),
            onDoubleTap: () {
              HapticFeedback.lightImpact();
              chatProvider?.setReplyingTo(message);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: message.isSticker ? Colors.transparent : bubbleBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isOutgoing ? const Radius.circular(18) : const Radius.circular(4),
                  bottomRight: isOutgoing ? const Radius.circular(4) : const Radius.circular(18),
                ),
                border: message.isSticker
                    ? null
                    : Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.5,
                      ),
                boxShadow: message.isSticker
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
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
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (message.replyToId != null && onQuotedMessageTap != null) {
                        onQuotedMessageTap!(message.replyToId!);
                      }
                    },
                    child: Container(
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
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
                          if (message.replyToId != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 14,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ],
                        ],
                      ),
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
                else if (message.isLocation)
                  _buildLocationCard(context, isDark, isOutgoing)
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
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Quick Reaction Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['❤️', '👍', '👎', '😂', '🔥', '🎉', '👏', '⚡'].map((emoji) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          provider.toggleReaction(message.id, emoji);
                          Navigator.of(ctx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                          child: Text(emoji, style: const TextStyle(fontSize: 24)),
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
                        : (isPaused
                            ? Icons.play_circle_fill
                            : (activeTransfer?.status == TransferStatus.failed
                                ? Icons.refresh_rounded
                                : Icons.download_rounded)),
                    color: activeTransfer?.status == TransferStatus.failed
                        ? Colors.redAccent
                        : TelegramTheme.primaryBlue,
                    size: 28,
                  ),
                  onPressed: () {
                    if (isDownloading) {
                      chatProvider.transferManager.pauseTransfer(meta.transferId);
                    } else if (isPaused) {
                      chatProvider.transferManager.resumeTransfer(meta.transferId);
                    } else if (activeTransfer?.status == TransferStatus.failed) {
                      chatProvider.transferManager.retryTransfer(meta.transferId);
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
                  activeTransfer.formattedEta.isNotEmpty
                      ? '${activeTransfer.formattedSpeed} • ${activeTransfer.formattedEta}'
                      : activeTransfer.formattedSpeed,
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

    final hasLocalFile = meta.localPath != null && isCompleted;

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

  Widget _buildLocationCard(BuildContext context, bool isDark, bool isOutgoing) {
    final loc = LocationData.tryParse(message.content);
    final lat = loc?.latitude ?? 0.0;
    final lng = loc?.longitude ?? 0.0;
    final name = loc?.name ?? 'Shared Location';
    final address = loc?.address;

    return Container(
      width: 260,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2533) : const Color(0xFFEBF1FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map preview styling simulation with grid & pin
          Container(
            height: 110,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF202B3C), const Color(0xFF161E2E)]
                    : [const Color(0xFFD6E4F8), const Color(0xFFC4D9F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Stylized map roads/grid
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MapGridPainter(isDark: isDark),
                  ),
                ),
                // Center Map Pin
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                // Coordinates tag top right
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info Section
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Copy Coordinates',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: '$lat, $lng'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Coordinates copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                // Action Button: Open Default Device Map
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TelegramTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () => MapLauncher.openCoordinates(
                      latitude: lat,
                      longitude: lng,
                      name: name,
                    ),
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text(
                      'Open in Device Maps',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

/// Interactive horizontal drag wrapper that reveals a reply icon and triggers reply on swipe
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool isOutgoing;

  const _SwipeToReply({
    required this.child,
    required this.onReply,
    required this.isOutgoing,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  bool _hasTriggeredHaptic = false;

  static const double _replyThreshold = 48.0;
  static const double _maxDrag = 76.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragOffset = _animation.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    // Dragging to the left (negative offset) reveals reply icon on the right
    setState(() {
      _dragOffset = (_dragOffset + delta * 0.55).clamp(-_maxDrag, 0.0);
      if (_dragOffset.abs() >= _replyThreshold && !_hasTriggeredHaptic) {
        _hasTriggeredHaptic = true;
        HapticFeedback.lightImpact();
      } else if (_dragOffset.abs() < _replyThreshold) {
        _hasTriggeredHaptic = false;
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() >= _replyThreshold) {
      widget.onReply();
    }
    _hasTriggeredHaptic = false;
    _animation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset.abs() / _replyThreshold).clamp(0.0, 1.0);
    final scale = 0.5 + 0.5 * progress;
    final opacity = progress;

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          if (_dragOffset < 0)
            Positioned(
              right: 14 + (1.0 - progress) * 10,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: TelegramTheme.primaryBlue.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TelegramTheme.primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Custom painter to draw subtle simulated map roads/grid in location card
class _MapGridPainter extends CustomPainter {
  final bool isDark;
  const _MapGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1.5;

    // Grid / Diagonal roads
    canvas.drawLine(Offset(0, size.height * 0.25), Offset(size.width, size.height * 0.75), paint);
    canvas.drawLine(Offset(0, size.height * 0.7), Offset(size.width, size.height * 0.2), paint);
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.65, size.height), paint);

    // Accent line (highway)
    final hwyPaint = Paint()
      ..color = (isDark ? Colors.amberAccent : Colors.orangeAccent).withValues(alpha: 0.25)
      ..strokeWidth = 3.0;
    canvas.drawLine(Offset(0, size.height * 0.45), Offset(size.width, size.height * 0.55), hwyPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
