import 'dart:io';
import 'dart:ui';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'attachment_action_sheet.dart';
import 'call_screen.dart';
import 'chat_bubble.dart';
import 'chat_details_sheet.dart';
import 'safety_number_dialog.dart';
import 'sticker_picker_sheet.dart';
import 'bluetooth_discovery_sheet.dart';
import 'ios_pressable.dart';

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
  final TextEditingController _inChatSearchController = TextEditingController();
  bool _isComposing = false;
  bool _isDragging = false;
  bool _isSearchingInChat = false;
  int _searchMatchIndex = 0;
  List<int> _matchedIndices = [];
  int _pinnedMessageIndex = 0;
  int _previousMessageCount = 0;
  String? _previousChatId;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final isFar = (_scrollController.position.maxScrollExtent - _scrollController.offset) > 220;
      if (isFar != _showScrollToBottom) {
        setState(() {
          _showScrollToBottom = isFar;
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _inChatSearchController.dispose();
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

    HapticFeedback.lightImpact();
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
    final chatId = isGroup ? group!.id : peer!.id;
    final pinnedMsgs = provider.getPinnedMessages(chatId);

    if (_previousChatId != chatId) {
      _previousChatId = chatId;
      _previousMessageCount = messages.length;
      _scrollToBottom();
    } else if (messages.length > _previousMessageCount) {
      final wasNearBottom = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent - _scrollController.offset) < 150;
      _previousMessageCount = messages.length;
      if (wasNearBottom) {
        _scrollToBottom();
      }
    } else {
      _previousMessageCount = messages.length;
    }

    return Scaffold(
      backgroundColor: isDark ? TelegramTheme.darkChatBg : TelegramTheme.lightChatBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark
            ? const Color(0xCC17212B)
            : const Color(0xCCE6EEF5),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: widget.onBack != null
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Center(
                  child: IosIconButton(
                    size: 34,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
                    iconColor: TelegramTheme.primaryBlue,
                    onPressed: widget.onBack,
                  ),
                ),
              )
            : null,
        titleSpacing: widget.onBack != null ? 0 : 16,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            ChatDetailsSheet.show(
              context,
              peer: peer,
              group: group,
              onSearchTap: () => setState(() => _isSearchingInChat = true),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: isGroup ? Colors.indigo.shade600 : TelegramTheme.primaryBlue,
                  child: Icon(
                    isGroup ? Icons.group_rounded : Icons.person,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isGroup ? group!.name : peer!.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        isGroup
                            ? '${group!.memberIds.length} members • ${isOnline ? "online" : "offline"}'
                            : (isTyping
                                ? 'typing...'
                                : (isOnline ? 'online' : 'offline')),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isGroup
                              ? (isOnline ? TelegramTheme.onlineGreen : Colors.orange)
                              : (isTyping
                                  ? TelegramTheme.primaryBlue
                                  : (isOnline ? TelegramTheme.onlineGreen : Colors.grey)),
                          fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isGroup)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IosIconButton(
                size: 34,
                tooltip: 'Voice Call',
                icon: const Icon(CupertinoIcons.phone_fill, size: 17),
                iconColor: TelegramTheme.primaryBlue,
                onPressed: () => provider.startCall(peer!),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IosIconButton(
              size: 34,
              tooltip: 'Search in Chat',
              icon: Icon(
                _isSearchingInChat
                    ? Icons.search_off_rounded
                    : Icons.search_rounded,
                size: 18,
              ),
              iconColor: _isSearchingInChat ? Colors.orange : TelegramTheme.primaryBlue,
              onPressed: () {
                setState(() {
                  _isSearchingInChat = !_isSearchingInChat;
                  if (!_isSearchingInChat) {
                    _inChatSearchController.clear();
                    _matchedIndices = [];
                    _searchMatchIndex = 0;
                  }
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              icon: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x33FFFFFF) : const Color(0x14000000),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.65),
                    width: 0.75,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.more_vert_rounded, size: 18),
                ),
              ),
              tooltip: 'Chat Options',
            onSelected: (val) {
              switch (val) {
                case 'details':
                  ChatDetailsSheet.show(
                    context,
                    peer: peer,
                    group: group,
                    onSearchTap: () => setState(() => _isSearchingInChat = true),
                  );
                  break;
                case 'calendar':
                  _jumpToDate(context, messages);
                  break;
                case 'timer':
                  _showTimerMenu(context, provider);
                  break;
                case 'walkie':
                  BluetoothDiscoverySheet.show(context);
                  break;
                case 'safety':
                  if (peer != null) {
                    showDialog(
                      context: context,
                      builder: (_) => SafetyNumberDialog(peer: peer),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'details',
                child: Row(
                  children: [
                    Icon(isGroup ? CupertinoIcons.group_solid : CupertinoIcons.person_solid, size: 18),
                    const SizedBox(width: 10),
                    Text(isGroup ? 'Group Info' : 'Contact Info'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'calendar',
                child: Row(
                  children: const [
                    Icon(CupertinoIcons.calendar, size: 18),
                    SizedBox(width: 10),
                    Text('Jump to Date'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'timer',
                child: Row(
                  children: const [
                    Icon(CupertinoIcons.timer, size: 18),
                    SizedBox(width: 10),
                    Text('Disappearing Messages'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'walkie',
                child: Row(
                  children: const [
                    Icon(CupertinoIcons.waveform_circle, size: 18),
                    SizedBox(width: 10),
                    Text('Walkie-Talkie'),
                  ],
                ),
              ),
              if (!isGroup)
                PopupMenuItem(
                  value: 'safety',
                  child: Row(
                    children: const [
                      Icon(CupertinoIcons.shield_lefthalf_fill, size: 18),
                      SizedBox(width: 10),
                      Text('Encryption & TOFU'),
                    ],
                  ),
                ),
            ],
          ),
        ),
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
                if (_isSearchingInChat)
                  _buildInChatSearchBar(context, messages),
                if (pinnedMsgs.isNotEmpty)
                  _buildPinnedBanner(context, provider, pinnedMsgs, messages),
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
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: TelegramTheme.primaryBlue.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.chat_bubble_2_fill,
                                    size: 32,
                                    color: TelegramTheme.primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  isGroup ? 'Welcome to ${group!.name}' : 'Chat with ${peer!.name}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isGroup
                                      ? 'Start the conversation with your group members.'
                                      : 'Direct end-to-end encrypted connection.',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: TelegramTheme.primaryBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 0,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    provider.sendTextMessage('Hello! 👋');
                                  },
                                  icon: const Text('👋', style: TextStyle(fontSize: 16)),
                                  label: const Text('Say Hello!'),
                                ),
                              ],
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
                            final showDateBadge = index == 0 ||
                                !_isSameDay(msg.timestamp, messages[index - 1].timestamp);

                            return RepaintBoundary(
                              key: ValueKey('bubble_${msg.id}'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showDateBadge)
                                    _buildDateBadge(msg.timestamp, isDark),
                                  ChatBubble(
                                    key: ValueKey(msg.id),
                                    message: msg,
                                    isOutgoing: isOutgoing,
                                    onQuotedMessageTap: (quotedId) =>
                                        _jumpToMessage(quotedId, messages),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                // Typing indicator
                if (isTyping)
                  _buildTypingIndicator(context, isDark),
                // Reply preview
                if (provider.replyingToMessage != null)
                  _buildReplyBanner(context, provider, isDark, messages),
                // Input Bar
                _buildInputBar(context, provider, isDark, isGroup, isOnline),
              ],
            ),
            // Floating Scroll-To-Bottom Button
            if (_showScrollToBottom)
              Positioned(
                bottom: 84,
                right: 16,
                child: IosIconButton(
                  size: 38,
                  icon: const Icon(CupertinoIcons.chevron_down, size: 19),
                  iconColor: TelegramTheme.primaryBlue,
                  backgroundColor: isDark ? const Color(0xE61E293B) : Colors.white.withValues(alpha: 0.9),
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  onPressed: _scrollToBottom,
                ),
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

  Widget _buildTypingIndicator(BuildContext context, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(TelegramTheme.primaryBlue),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'typing...',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBanner(
      BuildContext context, ChatProvider provider, bool isDark, List<ChatMessage> messages) {
    final msg = provider.replyingToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: isDark ? TelegramTheme.darkSidebar : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _jumpToMessage(msg.id, messages),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: const Border(
              left: BorderSide(color: TelegramTheme.primaryBlue, width: 3.5),
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
                      msg.content.isNotEmpty
                          ? msg.content
                          : (msg.isImage ? '📷 Photo' : (msg.isVoice ? '🎤 Voice Note' : '📁 File')),
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

      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xCC17212B)
                  : Colors.white.withValues(alpha: 0.88),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: Row(
                children: [
                  // Red recording indicator with pulsing effect
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.redAccent,
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
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      provider.cancelVoiceRecording();
                    },
                  ),
                  const SizedBox(width: 4),
                  // Stop & Send button
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: TelegramTheme.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      tooltip: 'Send Voice Note',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        provider.stopAndSendVoiceRecording();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xD0121212)
                : Colors.white.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: isDark ? IosTheme.hairlineDark : IosTheme.hairlineLight,
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Single Cupertino '+' Attachment Button
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, right: 6),
                  child: IosIconButton(
                    size: 36,
                    icon: const Icon(CupertinoIcons.add, size: 21),
                    iconColor: isReadOnly ? IosTheme.systemGray : TelegramTheme.primaryBlue,
                    tooltip: 'Attachments & Tools',
                    onPressed: isReadOnly
                        ? null
                        : () async {
                            final action = await AttachmentActionSheet.show(
                              context,
                              isGroup: isGroup,
                              currentEphemeralSeconds: provider.activeChatEphemeralSeconds,
                            );
                            if (action == null || !context.mounted) return;
                            switch (action) {
                              case AttachmentAction.photo:
                                provider.takeAndSendPhoto();
                                break;
                              case AttachmentAction.file:
                                provider.pickAndSendFile();
                                break;
                              case AttachmentAction.location:
                                _openLocationDialog(context, provider);
                                break;
                              case AttachmentAction.stickers:
                                _openStickerPicker(context, provider);
                                break;
                              case AttachmentAction.timer:
                                _openTimerPicker(context, provider);
                                break;
                              case AttachmentAction.walkieTalkie:
                                BluetoothDiscoverySheet.show(context);
                                break;
                            }
                          },
                  ),
                ),
                // Wide Text Input Field
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !isReadOnly,
                    minLines: 1,
                    maxLines: 5,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: isReadOnly
                          ? 'Group is read-only (host offline)...'
                          : 'Message',
                      hintStyle: const TextStyle(
                        color: IosTheme.systemGray,
                        fontSize: 15,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: TelegramTheme.primaryBlue,
                          width: 1.0,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? IosTheme.searchFieldDark
                          : IosTheme.searchFieldLight,
                      suffixIcon: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          CupertinoIcons.smiley,
                          color: IosTheme.systemGray,
                          size: 21,
                        ),
                        tooltip: 'Stickers & Memoji',
                        onPressed: isReadOnly ? null : () => _openStickerPicker(context, provider),
                      ),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IosPressable(
                    onPressed: isReadOnly
                        ? null
                        : (_isComposing || isGroup
                            ? () => _handleSubmitted(provider)
                            : () {
                                HapticFeedback.mediumImpact();
                                provider.startVoiceRecording();
                              }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: (_isComposing || isGroup) && !isReadOnly
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                              )
                            : null,
                        color: isReadOnly
                            ? IosTheme.systemGray3
                            : (!(_isComposing || isGroup)
                                ? (isDark ? IosTheme.systemGray5Dark : IosTheme.systemGray5Light)
                                : null),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.65),
                          width: 0.75,
                        ),
                        boxShadow: [
                          if ((_isComposing || isGroup) && !isReadOnly)
                            BoxShadow(
                              color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          else
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                        child: _isComposing || isGroup
                            ? const Icon(
                                Icons.arrow_upward_rounded,
                                key: ValueKey('send_btn'),
                                color: Colors.white,
                                size: 20,
                              )
                            : Icon(
                                Icons.mic_rounded,
                                key: const ValueKey('mic_btn'),
                                color: isDark ? Colors.white70 : Colors.black54,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  void _openStickerPicker(BuildContext context, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StickerPickerSheet(
        onStickerSelected: (sticker) {
          final chatId = widget.group?.id ?? widget.peer?.id;
          if (chatId != null) {
            provider.sendStickerMessage(chatId, sticker);
          }
        },
      ),
    );
  }

  void _openLocationDialog(BuildContext context, ChatProvider provider) {
    LocationShareDialog.show(
      context,
      onShare: (lat, lng, name, address) {
        provider.sendLocation(
          latitude: lat,
          longitude: lng,
          name: name,
          address: address,
        );
      },
    );
  }

  void _openTimerPicker(BuildContext context, ChatProvider provider) {
    _showTimerMenu(context, provider);
  }

  void _showTimerMenu(BuildContext context, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Disappearing Messages',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ...[
                    (null, 'Off', Icons.timer_off_rounded),
                    (10, '10 Seconds (Test)', Icons.local_fire_department_rounded),
                    (60, '1 Minute', Icons.timer_rounded),
                    (3600, '1 Hour', Icons.timer_rounded),
                    (86400, '24 Hours', Icons.timer_rounded),
                  ].map((item) {
                    final isSelected = provider.activeChatEphemeralSeconds == item.$1;
                    return ListTile(
                      leading: Icon(item.$3, color: isSelected ? TelegramTheme.primaryBlue : null),
                      title: Text(item.$2),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: TelegramTheme.primaryBlue)
                          : null,
                      onTap: () {
                        provider.setChatEphemeralSeconds(item.$1);
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              item.$1 == null
                                  ? 'Disappearing messages turned off'
                                  : 'Disappearing messages set to ${_formatDuration(item.$1!)}',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinnedBanner(
    BuildContext context,
    ChatProvider provider,
    List<ChatMessage> pinnedMsgs,
    List<ChatMessage> messages,
  ) {
    if (pinnedMsgs.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatId = widget.group?.id ?? widget.peer?.id ?? '';
    final safeIndex = _pinnedMessageIndex.clamp(0, pinnedMsgs.length - 1);
    final pinnedMsg = pinnedMsgs[safeIndex];

    void scrollToPinned(String msgId) {
      final index = messages.indexWhere((m) => m.id == msgId);
      if (index != -1 && _scrollController.hasClients) {
        final target = index * 80.0;
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
          ),
          left: const BorderSide(
            color: TelegramTheme.primaryBlue,
            width: 3.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.push_pin_rounded,
              color: TelegramTheme.primaryBlue,
              size: 18,
            ),
            onPressed: () => scrollToPinned(pinnedMsg.id),
            tooltip: 'Jump to message',
          ),
          Expanded(
            child: InkWell(
              onTap: () => scrollToPinned(pinnedMsg.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pinned Message • ${pinnedMsg.senderName}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: TelegramTheme.primaryBlue,
                        ),
                      ),
                      if (pinnedMsgs.length > 1) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: TelegramTheme.primaryBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${safeIndex + 1} of ${pinnedMsgs.length}',
                            style: const TextStyle(fontSize: 10, color: TelegramTheme.primaryBlue, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    pinnedMsg.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (pinnedMsgs.length > 1) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              tooltip: 'Previous Pin',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() {
                  _pinnedMessageIndex = (_pinnedMessageIndex - 1 + pinnedMsgs.length) % pinnedMsgs.length;
                });
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              tooltip: 'Next Pin',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() {
                  _pinnedMessageIndex = (_pinnedMessageIndex + 1) % pinnedMsgs.length;
                });
              },
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => provider.unpinMessage(chatId, pinnedMsg.id),
            tooltip: 'Unpin Message',
          ),
        ],
      ),
    );
  }

  Widget _buildInChatSearchBar(
      BuildContext context, List<ChatMessage> messages) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inChatSearchController,
              decoration: const InputDecoration(
                hintText: 'Search in this chat...',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  if (val.trim().isEmpty) {
                    _matchedIndices = [];
                    _searchMatchIndex = 0;
                  } else {
                    final q = val.toLowerCase();
                    _matchedIndices = [];
                    for (var i = 0; i < messages.length; i++) {
                      if (messages[i].content.toLowerCase().contains(q)) {
                        _matchedIndices.add(i);
                      }
                    }
                    _searchMatchIndex = 0;
                    if (_matchedIndices.isNotEmpty) {
                      _jumpToMatch(messages);
                    }
                  }
                });
              },
            ),
          ),
          if (_matchedIndices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${_searchMatchIndex + 1} of ${_matchedIndices.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
            onPressed: _matchedIndices.isNotEmpty
                ? () {
                    setState(() {
                      if (_searchMatchIndex > 0) {
                        _searchMatchIndex--;
                      } else {
                        _searchMatchIndex = _matchedIndices.length - 1;
                      }
                    });
                    _jumpToMatch(messages);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            onPressed: _matchedIndices.isNotEmpty
                ? () {
                    setState(() {
                      if (_searchMatchIndex < _matchedIndices.length - 1) {
                        _searchMatchIndex++;
                      } else {
                        _searchMatchIndex = 0;
                      }
                    });
                    _jumpToMatch(messages);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () {
              setState(() {
                _isSearchingInChat = false;
                _inChatSearchController.clear();
                _matchedIndices = [];
                _searchMatchIndex = 0;
              });
            },
          ),
        ],
      ),
    );
  }

  void _jumpToMatch(List<ChatMessage> messages) {
    if (_matchedIndices.isEmpty) return;
    final matchIdx = _matchedIndices[_searchMatchIndex];
    if (_scrollController.hasClients) {
      final target = matchIdx * 80.0;
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _jumpToDate(
      BuildContext context, List<ChatMessage> messages) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      final index = messages.indexWhere((m) {
        return m.timestamp.year == picked.year &&
            m.timestamp.month == picked.month &&
            m.timestamp.day == picked.day;
      });
      if (index != -1 && _scrollController.hasClients) {
        final target = index * 80.0;
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No messages found on this date.')),
          );
        }
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateBadge(DateTime date, bool isDark) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else if (date.year == now.year) {
      label = DateFormat('MMMM d').format(date);
    } else {
      label = DateFormat('MMMM d, yyyy').format(date);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _jumpToMessage(String messageId, List<ChatMessage> messages) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1 && _scrollController.hasClients) {
      final target = index * 75.0;
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    if (seconds < 3600) return '${seconds ~/ 60} minutes';
    if (seconds < 86400) return '${seconds ~/ 3600} hours';
    return '${seconds ~/ 86400} days';
  }
}

/// Modal dialog allowing the user to select and share a geographic location
class LocationShareDialog extends StatefulWidget {
  final void Function(double latitude, double longitude, String name, String? address) onShare;

  const LocationShareDialog({
    super.key,
    required this.onShare,
  });

  static Future<void> show(
    BuildContext context, {
    required void Function(double latitude, double longitude, String name, String? address) onShare,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => LocationShareDialog(onShare: onShare),
    );
  }

  @override
  State<LocationShareDialog> createState() => _LocationShareDialogState();
}

class _PresetLocation {
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
  final IconData icon;

  const _PresetLocation({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    required this.icon,
  });
}

class _LocationShareDialogState extends State<LocationShareDialog> {
  final _nameController = TextEditingController(text: 'Current Location');
  final _latController = TextEditingController(text: '37.7749');
  final _lngController = TextEditingController(text: '-122.4194');
  final _addressController = TextEditingController();

  final List<_PresetLocation> _presets = const [
    _PresetLocation(
      title: 'Current Location',
      subtitle: 'Accurate to device sensors',
      latitude: 37.7749,
      longitude: -122.4194,
      icon: Icons.my_location_rounded,
    ),
    _PresetLocation(
      title: 'Coffee & Coworking',
      subtitle: 'Downtown Workspace',
      latitude: 37.7891,
      longitude: -122.4014,
      icon: Icons.local_cafe_rounded,
    ),
    _PresetLocation(
      title: 'Tech Campus / Lab',
      subtitle: 'Hardware & Mesh Node Lab',
      latitude: 37.4220,
      longitude: -122.0841,
      icon: Icons.computer_rounded,
    ),
    _PresetLocation(
      title: 'Central Station',
      subtitle: 'Public Transit Terminal',
      latitude: 37.7766,
      longitude: -122.3942,
      icon: Icons.train_rounded,
    ),
  ];

  void _applyPreset(_PresetLocation preset) {
    setState(() {
      _nameController.text = preset.title;
      _latController.text = preset.latitude.toString();
      _lngController.text = preset.longitude.toString();
      _addressController.text = preset.subtitle;
    });
  }

  void _submit() {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    final name = _nameController.text.trim().isEmpty ? 'Shared Location' : _nameController.text.trim();
    final address = _addressController.text.trim().isEmpty ? null : _addressController.text.trim();

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid numeric latitude & longitude'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coordinates out of range (-90..90, -180..180)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    widget.onShare(lat, lng, name, address);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.redAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Send coordinates to open directly in device maps',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Presets row
              Text(
                'QUICK PRESETS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _presets.map((preset) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InkWell(
                        onTap: () => _applyPreset(preset),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF282E3A) : const Color(0xFFF0F3F8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(preset.icon, size: 16, color: primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                preset.title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // Location Name
              TextField(
                controller: _nameController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Place Name / Label',
                  prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Lat & Long Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Latitude',
                        prefixIcon: const Icon(Icons.explore_outlined, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Longitude',
                        prefixIcon: const Icon(Icons.explore_outlined, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Address / Notes
              TextField(
                controller: _addressController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Address or Notes (Optional)',
                  prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text(
                        'Send Location',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
