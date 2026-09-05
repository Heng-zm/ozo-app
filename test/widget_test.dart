import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/ui/theme/app_theme.dart';
import 'package:lan_telegram/ui/widgets/chat_bubble.dart';
import 'package:lan_telegram/ui/widgets/peer_list_tile.dart';

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
      MaterialApp(
        theme: TelegramTheme.lightTheme,
        home: Scaffold(
          body: ChatBubble(
            message: message,
            isOutgoing: true,
          ),
        ),
      ),
    );

    expect(find.text('Hello over LAN P2P!'), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
  });
}
