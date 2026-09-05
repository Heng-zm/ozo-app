import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'chat_bubble.dart';

class ActiveChatView extends StatefulWidget {
  final Peer peer;
  final VoidCallback? onBack;

  const ActiveChatView({
    super.key,
    required this.peer,
    this.onBack,
  });

  @override
  State<ActiveChatView> createState() => _ActiveChatViewState();
}

class _ActiveChatViewState extends State<ActiveChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;

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

    provider.sendTextMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final messages = provider.activeMessages;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = widget.peer.isOnline;
    final isTyping = provider.isPeerTyping(widget.peer.id);

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
              backgroundColor: TelegramTheme.primaryBlue,
              child: Text(
                widget.peer.name.isNotEmpty ? widget.peer.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isTyping
                        ? 'typing...'
                        : (isOnline ? 'online (${widget.peer.ip})' : 'offline'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isTyping
                          ? TelegramTheme.primaryBlue
                          : (isOnline ? TelegramTheme.onlineGreen : Colors.grey),
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'E2EE ChaCha20-Poly1305 Protected',
            icon: const Icon(Icons.lock_rounded, color: TelegramTheme.onlineGreen, size: 20),
            onPressed: () {
              _showSecurityDetails(context, widget.peer);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Security banner
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            color: Colors.black.withValues(alpha: 0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'End-to-End Encrypted via Direct LAN P2P',
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
                      child: const Text(
                        'No messages yet. Say hi over the local network!',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
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
          // Input bar
          _buildInputBar(context, provider, isDark),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, ChatProvider provider, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: isDark ? TelegramTheme.darkSidebar : Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_rounded),
              color: Colors.grey.shade600,
              tooltip: 'Send File / Media',
              onPressed: () => provider.pickAndSendFile(),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Write a message...',
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
                  provider.sendTypingIndicator(hasText);
                },
                onSubmitted: (_) => _handleSubmitted(provider),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: TelegramTheme.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _isComposing ? () => _handleSubmitted(provider) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSecurityDetails(BuildContext context, Peer peer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: TelegramTheme.onlineGreen),
            SizedBox(width: 8),
            Text('E2EE Security Info'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Messages & files between you and this peer are end-to-end encrypted using X25519 ECDH key exchange and ChaCha20-Poly1305 AEAD.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Peer Public Key Fingerprint:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(
              peer.publicKey.isNotEmpty ? peer.publicKey : 'Generating...',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text('IP Address: ${peer.ip}:${peer.port}', style: const TextStyle(fontSize: 12)),
            Text('Platform: ${peer.platform.toUpperCase()}', style: const TextStyle(fontSize: 12)),
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
