import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/models.dart';

void main() {
  test('Peer serialization and deserialization', () {
    final now = DateTime.now();
    final peer = Peer(
      id: 'peer-uuid-1234',
      name: 'Alice MacBook',
      ip: '192.168.1.100',
      port: 45455,
      publicKey: 'mock-public-key-base64',
      platform: 'macos',
      lastSeen: now,
    );

    final json = peer.toJson();
    expect(json['id'], equals('peer-uuid-1234'));
    expect(json['name'], equals('Alice MacBook'));
    expect(json['port'], equals(45455));

    final parsed = Peer.fromJson(json);
    expect(parsed.id, equals(peer.id));
    expect(parsed.name, equals(peer.name));
    expect(parsed.isOnline, isTrue);
  });

  test('ChatMessage with FileMetadata serialization', () {
    final fileMeta = FileMetadata(
      transferId: 'tx-999',
      fileName: 'dataset.zip',
      fileSize: 10485760, // 10 MB
      sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      localPath: '/downloads/dataset.zip',
      isCompleted: true,
    );

    final msg = ChatMessage(
      id: 'msg-001',
      chatId: 'peer-uuid-1234',
      senderId: 'my-device-id',
      senderName: 'My PC',
      recipientId: 'peer-uuid-1234',
      content: 'Sent dataset.zip',
      type: MessageType.file,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      fileMetadata: fileMeta,
    );

    final json = msg.toJson();
    expect(json['type'], equals('file'));
    expect(json['fileMetadata']['fileName'], equals('dataset.zip'));
    expect(json['fileMetadata']['fileSize'], equals(10485760));

    final restored = ChatMessage.fromJson(json);
    expect(restored.type, equals(MessageType.file));
    expect(restored.fileMetadata?.fileName, equals('dataset.zip'));
    expect(restored.fileMetadata?.isCompleted, isTrue);
  });
}
