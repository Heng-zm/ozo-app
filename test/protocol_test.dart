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

  test('ChatMessage with Voice Note serialization and properties', () {
    final voiceMsg = ChatMessage(
      id: 'voice-001',
      chatId: 'peer-uuid-1234',
      senderId: 'my-device-id',
      senderName: 'My Phone',
      recipientId: 'peer-uuid-1234',
      content: 'Voice message (4.2s)',
      type: MessageType.voice,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      voiceDurationSeconds: 4.2,
      waveformAmplitudes: [0.1, 0.4, 0.8, 0.9, 0.5, 0.2],
    );

    expect(voiceMsg.isVoice, isTrue);
    expect(voiceMsg.isImage, isFalse);

    final json = voiceMsg.toJson();
    expect(json['type'], equals('voice'));
    expect(json['voiceDurationSeconds'], equals(4.2));
    expect(json['waveformAmplitudes'], equals([0.1, 0.4, 0.8, 0.9, 0.5, 0.2]));

    final restored = ChatMessage.fromJson(json);
    expect(restored.isVoice, isTrue);
    expect(restored.voiceDurationSeconds, equals(4.2));
    expect(restored.waveformAmplitudes?.length, equals(6));
  });

  test('ChatMessage with Inline Image detection', () {
    final imageMsg = ChatMessage(
      id: 'img-001',
      chatId: 'peer-uuid-1234',
      senderId: 'my-device-id',
      senderName: 'My PC',
      recipientId: 'peer-uuid-1234',
      content: 'Sent photo.png',
      type: MessageType.image,
      timestamp: DateTime.now(),
      status: MessageStatus.read,
      fileMetadata: FileMetadata(
        transferId: 'tx-img-1',
        fileName: 'vacation_photo.PNG',
        fileSize: 204800,
        sha256: 'mock-sha',
        localPath: '/downloads/vacation_photo.PNG',
        isCompleted: true,
      ),
    );

    expect(imageMsg.isImage, isTrue);
    expect(imageMsg.isVoice, isFalse);
    expect(imageMsg.status, equals(MessageStatus.read));

    final json = imageMsg.toJson();
    expect(json['type'], equals('image'));
    expect(json['status'], equals('read'));

    final restored = ChatMessage.fromJson(json);
    expect(restored.isImage, isTrue);
    expect(restored.status, equals(MessageStatus.read));
  });

  test('PeerConnectionLink generates and parses ozo:// and Cloudflare links', () {
    final link = PeerConnectionLink(
      id: 'peer-cf-1',
      name: 'Alice Remote',
      host: 'peaceful-tiger.trycloudflare.com',
      port: 443,
      publicKey: 'mock-pub-key',
      platform: 'linux',
      isSecure: true,
    );

    final uriStr = link.toUriString();
    expect(uriStr, startsWith('ozo://connect?'));

    final parsed = PeerConnectionLink.parse(uriStr);
    expect(parsed, isNotNull);
    expect(parsed!.id, equals('peer-cf-1'));
    expect(parsed.name, equals('Alice Remote'));
    expect(parsed.host, equals('peaceful-tiger.trycloudflare.com'));
    expect(parsed.port, equals(443));
    expect(parsed.publicKey, equals('mock-pub-key'));
    expect(parsed.isSecure, isTrue);

    // Parsing direct Cloudflare URL
    final cfParsed = PeerConnectionLink.parse('https://mystic-orca.trycloudflare.com');
    expect(cfParsed, isNotNull);
    expect(cfParsed!.host, equals('mystic-orca.trycloudflare.com'));
    expect(cfParsed.port, equals(443));
    expect(cfParsed.isSecure, isTrue);
  });

  test('ChatMessage with quoted reply and emoji reactions', () {
    final msg = ChatMessage(
      id: 'reply-msg-1',
      chatId: 'peer-1',
      senderId: 'alice',
      senderName: 'Alice',
      recipientId: 'bob',
      content: 'I agree completely!',
      type: MessageType.text,
      timestamp: DateTime.now(),
      replyToId: 'original-msg-0',
      replyToText: 'Should we release today?',
      replyToSenderName: 'Bob',
      reactions: {
        '❤️': ['bob'],
        '👍': ['alice', 'charlie'],
      },
    );

    final json = msg.toJson();
    expect(json['replyToId'], equals('original-msg-0'));
    expect(json['replyToText'], equals('Should we release today?'));
    expect(json['replyToSenderName'], equals('Bob'));
    expect(json['reactions']['❤️'], equals(['bob']));
    expect(json['reactions']['👍'], equals(['alice', 'charlie']));

    final restored = ChatMessage.fromJson(json);
    expect(restored.replyToId, equals('original-msg-0'));
    expect(restored.replyToText, equals('Should we release today?'));
    expect(restored.reactions['❤️'], equals(['bob']));
    expect(restored.reactions['👍']?.length, equals(2));
  });

  test('CallSignaling model serialization and parsing', () {
    final signaling = CallSignaling(
      callId: 'call-12345',
      callerId: 'alice',
      callerName: 'Alice',
      type: 'CALL_OFFER',
    );

    final json = signaling.toJson();
    expect(json['callId'], equals('call-12345'));
    expect(json['type'], equals('CALL_OFFER'));

    final restored = CallSignaling.fromJson(json);
    expect(restored.callId, equals('call-12345'));
    expect(restored.callerName, equals('Alice'));
  });
}
