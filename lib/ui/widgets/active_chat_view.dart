import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'call_screen.dart';
import 'chat_bubble.dart';
import 'safety_number_dialog.dart';

class ActiveChatView extends StatefulWidget {
  final Peer? peer;
  final GroupChat? group;
  final VoidCallback? onBack;

  const ActiveChatView({
    super.key,
    this.peer,
    this.group,
    this.onBack,
  }) : assert(peer != null || group != null);

  @override
  State<ActiveChatView> createState() => _ActiveChatViewState();
}

class _ActiveChatViewState extends State<ActiveChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;
  bool _isDragging = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSubmitted(ChatProvider provider) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() {
      _isComposing = false;
    });

    provider.sendTypingIndicator(false);
    provider.sendTextMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final messages = provider.activeMessages;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isGroup = widget.group != null;
    final group = widget.group;
    final peer = widget.peer;

    final isOnline = isGroup ? provider.isGroupHostOnline : peer!.isOnline;
    final isTyping = !isGroup && provider.isPeerTyping(peer!.id);

    _scrollToBottom();

    return Scaffold(
      backgroundColor: isDark ? TelegramTheme.darkChatBg : TelegramTheme.lightChatBg,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        titleSpacing: widget.onBack != null ? 0 : 16,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isGroup ? Colors.indigo.shade600 : TelegramTheme.primaryBlue,
              child: Icon(
                isGroup ? Icons.group_rounded : Icons.person,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isGroup ? group!.name : peer!.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isGroup
                        ? '${group!.memberIds.length} members • Host: ${group.hostName}'
                        : (isTyping
                            ? 'typing...'
                            : (isOnline ? 'online (${peer!.ip})' : 'offline')),
                    style: TextStyle(
                      fontSize: 12,
                      color: isGroup
                          ? (isOnline ? TelegramTheme.onlineGreen : Colors.orange)
                          : (isTyping
                              ? TelegramTheme.primaryBlue
                              : (isOnline ? TelegramTheme.onlineGreen : Colors.grey)),
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!isGroup) ...[
            IconButton(
              tooltip: 'Voice Call',
              icon: const Icon(Icons.phone_rounded, size: 22),
              onPressed: () => provider.startCall(peer!),
            ),
            IconButton(
              tooltip: 'Safety Number / E2EE',
              icon: Icon(
                peer!.hasIdentityConflict
                    ? Icons.warning_amber_rounded
                    : Icons.verified_user_outlined,
                color: peer.hasIdentityConflict ? Colors.orange : TelegramTheme.onlineGreen,
                size: 22,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => SafetyNumberDialog(peer: peer),
                );
              },
            ),
          ] else ...[
            IconButton(
              tooltip: 'Group Information',
              icon: const Icon(Icons.info_outline_rounded, size: 22),
              onPressed: () => _showGroupInfo(context, group!),
            ),
          ],
        ],
      ),
      body: DropTarget(
        onDragDone: (detail) {
          for (final f in detail.files) {
            provider.sendFile(File(f.path));
          }
        },
        onDragEntered: (detail) => setState(() => _isDragging = true),
        onDragExited: (detail) => setState(() => _isDragging = false),
        child: Stack(
          children: [
            Column(
              children: [
                // Banner
                if (isGroup && !isOnline)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                    color: Colors.orange.withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Group creator (${group!.hostName}) is offline. This group is read-only until the host reconnects.',
                            style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!isGroup && peer!.hasIdentityConflict)
                  InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => SafetyNumberDialog(peer: peer),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                      color: Colors.red.withValues(alpha: 0.12),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Identity Warning: Device key changed! Tap to verify safety number.',
                              style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                    color: Colors.black.withValues(alpha: 0.05),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isGroup ? Icons.hub_outlined : Icons.shield_outlined,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isGroup
                              ? 'Host-Relay Group via ${group!.hostName}'
                              : (peer!.isRemote
                                  ? 'End-to-End Encrypted via Remote Cloudflare Tunnel'
                                  : 'End-to-End Encrypted via Direct LAN P2P'),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                // Messages list
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              isGroup
                                  ? 'No messages in this group yet.'
                                  : 'No messages yet. Say hi over the network!',
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isOutgoing = msg.senderId == provider.deviceId;
                            return ChatBubble(
                              message: msg,
                              isOutgoing: isOutgoing,
                            );
                          },
                        ),
                ),
                // Reply preview banner
                if (provider.replyingToMessage != null)
                  _buildReplyBanner(context, provider, isDark),
                // Input bar
                _buildInputBar(context, provider, isDark, isGroup, isOnline),
              ],
            ),
            // Drag-and-drop Overlay
            if (_isDragging)
              Positioned.fill(
                child: Container(
                  color: TelegramTheme.primaryBlue.withValues(alpha: 0.85),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.file_upload_rounded, color: Colors.white, size: 60),
                        const SizedBox(height: 16),
                        const Text(
                          'Drop files here to send securely via P2P',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Call Screen Overlay
            if (provider.callStatus != CallStatus.idle)
              const Positioned.fill(
                child: CallScreen(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBanner(BuildContext context, ChatProvider provider, bool isDark) {
    final msg = provider.replyingToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? TelegramTheme.darkSidebar : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(color: TelegramTheme.primaryBlue, width: 3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.reply_rounded, color: TelegramTheme.primaryBlue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.senderName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: TelegramTheme.primaryBlue,
                    ),
                  ),
                  Text(
                    msg.content.isNotEmpty ? msg.content : (msg.isImage ? 'Photo' : 'Voice/File'),
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
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => provider.cancelReplying(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(
    BuildContext context,
    ChatProvider provider,
    bool isDark,
    bool isGroup,
    bool isOnline,
  ) {
    final isReadOnly = isGroup && !isOnline;

    if (provider.isRecordingVoice) {
      final minutes = provider.recordedDuration.inMinutes;
      final seconds = provider.recordedDuration.inSeconds % 60;
      final timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isDark ? TelegramTheme.darkSidebar : Colors.white,
        child: SafeArea(
          child: Row(
            children: [
              // Red recording pulse
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                timeStr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              // Live amplitude visualization dots
              Expanded(
                child: SizedBox(
                  height: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: provider.liveAmplitudes.take(18).map((amp) {
                      return Container(
                        width: 3,
                        height: (amp * 20).clamp(4.0, 20.0),
                        decoration: BoxDecoration(
                          color: TelegramTheme.primaryBlue.withAlpha(180),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Cancel button
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                tooltip: 'Cancel recording',
                onPressed: () => provider.cancelVoiceRecording(),
              ),
              const SizedBox(width: 4),
              // Stop & Send button
              Container(
                decoration: const BoxDecoration(
                  color: TelegramTheme.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  tooltip: 'Send Voice Note',
                  onPressed: () => provider.stopAndSendVoiceRecording(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: isDark ? TelegramTheme.darkSidebar : Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            if (!isGroup)
              IconButton(
                icon: const Icon(Icons.attach_file_rounded),
                color: Colors.grey.shade600,
                tooltip: 'Send File / Media',
                onPressed: () => provider.pickAndSendFile(),
              ),
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !isReadOnly,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: isReadOnly
                      ? 'Group is read-only (host offline)...'
                      : 'Write a message...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? TelegramTheme.darkBackground
                      : Colors.grey.shade100,
                ),
                onChanged: (text) {
                  final hasText = text.trim().isNotEmpty;
                  if (hasText != _isComposing) {
                    setState(() {
                      _isComposing = hasText;
                    });
                  }
                  if (!isGroup) {
                    provider.sendTypingIndicator(hasText);
                  }
                },
                onSubmitted: isReadOnly ? null : (_) => _handleSubmitted(provider),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: isReadOnly ? Colors.grey : TelegramTheme.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: _isComposing || isGroup
                  ? IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _isComposing && !isReadOnly
                          ? () => _handleSubmitted(provider)
                          : null,
                    )
                  : IconButton(
                      icon: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                      tooltip: 'Record Voice Note',
                      onPressed: !isReadOnly
                          ? () => provider.startVoiceRecording()
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupInfo(BuildContext context, GroupChat group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.group_rounded, color: TelegramTheme.primaryBlue),
            const SizedBox(width: 8),
            Text(group.name),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group ID: ${group.id}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            Text('Host / Creator: ${group.hostName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Architecture: Host-Relay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Text(
              'All messages in this group are relayed through the creator node to ensure low connection overhead and reliable ordering on LAN.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Text('Members (${group.memberIds.length}):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            ...group.memberIds.map((m) => Text('• $m', style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
