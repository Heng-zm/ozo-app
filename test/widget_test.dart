import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/providers/chat_provider.dart';
import 'package:lan_telegram/ui/theme/app_theme.dart';
import 'package:lan_telegram/ui/widgets/chat_bubble.dart';
import 'package:lan_telegram/ui/widgets/peer_list_tile.dart';
import 'package:lan_telegram/ui/widgets/voice_note_player.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('PeerListTile renders peer info and online indicator', (WidgetTester tester) async {
    final peer = Peer(
      id: 'peer-1',
      name: 'MacBook Pro',
      ip: '192.168.1.50',
      port: 45455,
      publicKey: 'pub-key-123',
      platform: 'macos',
      lastSeen: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TelegramTheme.lightTheme,
        home: Scaffold(
          body: PeerListTile(
            peer: peer,
            isSelected: false,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('MacBook Pro'), findsOneWidget);
    expect(find.text('192.168.1.50:45455'), findsOneWidget);
  });

  testWidgets('ChatBubble renders text message with timestamp', (WidgetTester tester) async {
    final message = ChatMessage(
      id: 'msg-1',
      chatId: 'chat-1',
      senderId: 'alice',
      senderName: 'Alice',
      recipientId: 'bob',
      content: 'Hello over LAN P2P!',
      type: MessageType.text,
      timestamp: DateTime(2026, 9, 5, 14, 30),
      status: MessageStatus.delivered,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => ChatProvider(),
        child: MaterialApp(
          theme: TelegramTheme.lightTheme,
          home: Scaffold(
            body: ChatBubble(
              message: message,
              isOutgoing: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Hello over LAN P2P!'), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
  });

  testWidgets('VoiceNotePlayer renders play/download button and duration', (WidgetTester tester) async {
    final voiceMsg = ChatMessage(
      id: 'voice-1',
      chatId: 'chat-1',
      senderId: 'alice',
      senderName: 'Alice',
      recipientId: 'bob',
      content: 'Voice note',
      type: MessageType.voice,
      timestamp: DateTime(2026, 9, 5, 14, 35),
      voiceDurationSeconds: 12.5,
      waveformAmplitudes: [0.2, 0.5, 0.9, 0.4],
      status: MessageStatus.delivered,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => ChatProvider(),
        child: MaterialApp(
          theme: TelegramTheme.lightTheme,
          home: Scaffold(
            body: VoiceNotePlayer(
              message: voiceMsg,
              isMe: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
  });

  testWidgets('ChatBubble renders quoted reply and reaction chips', (WidgetTester tester) async {
    final msg = ChatMessage(
      id: 'reply-1',
      chatId: 'chat-1',
      senderId: 'alice',
      senderName: 'Alice',
      recipientId: 'bob',
      content: 'This sounds great!',
      type: MessageType.text,
      timestamp: DateTime(2026, 9, 5, 15, 0),
      status: MessageStatus.read,
      replyToId: 'orig-1',
      replyToText: 'Can you review the PR?',
      replyToSenderName: 'Bob',
      reactions: {
        '❤️': ['bob'],
        '👍': ['alice', 'charlie'],
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => ChatProvider(),
        child: MaterialApp(
          theme: TelegramTheme.lightTheme,
          home: Scaffold(
            body: ChatBubble(
              message: msg,
              isOutgoing: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('This sounds great!'), findsOneWidget);
    expect(find.text('Can you review the PR?'), findsOneWidget);
    expect(find.text('Bob'), findsWidgets);
    expect(find.text('❤️ 1'), findsOneWidget);
    expect(find.text('👍 2'), findsOneWidget);
  });

  testWidgets('PeerListTile renders Remote badge for Cloudflare tunnel peers', (WidgetTester tester) async {
    final remotePeer = Peer(
      id: 'remote-1',
      name: 'Cloud Node',
      ip: 'peaceful-tiger.trycloudflare.com',
      port: 443,
      publicKey: 'pub-key-remote',
      platform: 'linux',
      lastSeen: DateTime.now(),
      isRemote: true,
      remoteTunnelUrl: 'https://peaceful-tiger.trycloudflare.com',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TelegramTheme.lightTheme,
        home: Scaffold(
          body: PeerListTile(
            peer: remotePeer,
            isSelected: false,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Cloud Node'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Remote Cloudflare Tunnel'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_rounded), findsOneWidget);
  });
}
