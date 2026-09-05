import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/stickers/sticker_packs.dart';

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

  test('UserAccount serialization, deserialization, and copyWith', () {
    final now = DateTime.now();
    final account = UserAccount(
      id: 'acc-uuid-1',
      username: 'johndoe',
      displayName: 'John Doe',
      bio: 'P2P enthusiast & developer',
      avatarColorIndex: 2,
      avatarEmoji: '🚀',
      createdAt: now,
      isCurrent: true,
    );

    final json = account.toJson();
    expect(json['id'], equals('acc-uuid-1'));
    expect(json['username'], equals('johndoe'));
    expect(json['displayName'], equals('John Doe'));
    expect(json['bio'], equals('P2P enthusiast & developer'));
    expect(json['avatarColorIndex'], equals(2));
    expect(json['avatarEmoji'], equals('🚀'));
    expect(json['isCurrent'], isTrue);

    final restored = UserAccount.fromJson(json);
    expect(restored.id, equals(account.id));
    expect(restored.username, equals('johndoe'));
    expect(restored.displayName, equals('John Doe'));
    expect(restored.bio, equals('P2P enthusiast & developer'));
    expect(restored.avatarEmoji, equals('🚀'));
    expect(restored.isCurrent, isTrue);

    final updated = restored.copyWith(displayName: 'Johnny', bio: 'Updated bio');
    expect(updated.displayName, equals('Johnny'));
    expect(updated.bio, equals('Updated bio'));
    expect(updated.username, equals('johndoe'));
    expect(updated.id, equals('acc-uuid-1'));
  });

  test('GroupChat with backup host failover serialization', () {
    final now = DateTime.now();
    final group = GroupChat(
      id: 'grp-failover-123',
      name: 'Engineering Hub',
      hostId: 'host-alice',
      hostName: 'Alice',
      memberIds: ['host-alice', 'backup-bob', 'charlie'],
      createdAt: now,
      backupHostId: 'backup-bob',
      backupHostName: 'Bob',
      isPinned: true,
    );

    final json = group.toJson();
    expect(json['backupHostId'], equals('backup-bob'));
    expect(json['backupHostName'], equals('Bob'));
    expect(json['isPinned'], isTrue);

    final restored = GroupChat.fromJson(json);
    expect(restored.backupHostId, equals('backup-bob'));
    expect(restored.backupHostName, equals('Bob'));
    expect(restored.isPinned, isTrue);

    // Test promotion of backup host to primary host
    final promoted = restored.copyWith(
      hostId: restored.backupHostId!,
      hostName: restored.backupHostName ?? 'Bob',
      backupHostId: 'charlie',
      backupHostName: 'Charlie',
    );
    expect(promoted.hostId, equals('backup-bob'));
    expect(promoted.hostName, equals('Bob'));
    expect(promoted.backupHostId, equals('charlie'));
    expect(promoted.backupHostName, equals('Charlie'));
  });

  test('ChatFolder enum values and Peer isPinned attribute', () {
    expect(ChatFolder.values.length, equals(4));
    expect(ChatFolder.values, contains(ChatFolder.all));
    expect(ChatFolder.values, contains(ChatFolder.personal));
    expect(ChatFolder.values, contains(ChatFolder.groups));
    expect(ChatFolder.values, contains(ChatFolder.unread));

    final peer = Peer(
      id: 'peer-pin-1',
      name: 'Pinned Peer',
      ip: '192.168.1.10',
      port: 45455,
      publicKey: 'key',
      platform: 'android',
      lastSeen: DateTime.now(),
      isPinned: true,
      username: 'pinned_user',
    );

    expect(peer.isPinned, isTrue);
    expect(peer.username, equals('pinned_user'));

    final json = peer.toJson();
    expect(json['isPinned'], isTrue);
    expect(json['username'], equals('pinned_user'));

    final restored = Peer.fromJson(json);
    expect(restored.isPinned, isTrue);
    expect(restored.username, equals('pinned_user'));
  });

  test('StickerData and StickerPack serialization and ChatMessage isSticker', () {
    const sticker = StickerData(
      id: 'cat_love',
      packId: 'cyber_cats',
      name: 'Heart Eyes Cat',
      emoji: '😻',
    );
    final stickerJson = sticker.toJson();
    expect(stickerJson['id'], equals('cat_love'));
    expect(stickerJson['packId'], equals('cyber_cats'));
    expect(stickerJson['name'], equals('Heart Eyes Cat'));
    expect(stickerJson['emoji'], equals('😻'));

    final restoredSticker = StickerData.fromJson(stickerJson);
    expect(restoredSticker.id, equals(sticker.id));
    expect(restoredSticker.name, equals('Heart Eyes Cat'));
    expect(restoredSticker.emoji, equals('😻'));

    const pack = StickerPack(
      id: 'cyber_cats',
      name: 'Cyber Cats',
      icon: '🐱',
      stickers: [sticker],
    );
    final packJson = pack.toJson();
    expect(packJson['id'], equals('cyber_cats'));
    expect(packJson['name'], equals('Cyber Cats'));
    expect(packJson['icon'], equals('🐱'));
    expect(packJson['stickers'].length, equals(1));

    final restoredPack = StickerPack.fromJson(packJson);
    expect(restoredPack.id, equals(pack.id));
    expect(restoredPack.name, equals('Cyber Cats'));
    expect(restoredPack.stickers.first.emoji, equals('😻'));

    final stickerMsg = ChatMessage(
      id: 'msg-stk-1',
      chatId: 'peer-1',
      senderId: 'me',
      senderName: 'Me',
      recipientId: 'peer-1',
      content: '😻',
      type: MessageType.sticker,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
    );
    expect(stickerMsg.isSticker, isTrue);
    expect(stickerMsg.isVoice, isFalse);
    expect(stickerMsg.isImage, isFalse);

    final msgJson = stickerMsg.toJson();
    expect(msgJson['type'], equals('sticker'));
    final restoredMsg = ChatMessage.fromJson(msgJson);
    expect(restoredMsg.isSticker, isTrue);
    expect(restoredMsg.content, equals('😻'));
  });

  test('SecuritySettings serialization and default values', () {
    final defaultSettings = SecuritySettings();
    expect(defaultSettings.isPinEnabled, isFalse);
    expect(defaultSettings.autoLockMinutes, equals(5));
    expect(defaultSettings.isBiometricEnabled, isFalse);

    final customSettings = SecuritySettings(
      isPinEnabled: true,
      pinSalt: 'random_salt_123',
      pinHash: 'hashed_pin_value',
      autoLockMinutes: 1,
      isBiometricEnabled: true,
    );
    final json = customSettings.toJson();
    expect(json['isPinEnabled'], isTrue);
    expect(json['pinSalt'], equals('random_salt_123'));
    expect(json['pinHash'], equals('hashed_pin_value'));
    expect(json['autoLockMinutes'], equals(1));
    expect(json['isBiometricEnabled'], isTrue);

    final restored = SecuritySettings.fromJson(json);
    expect(restored.isPinEnabled, isTrue);
    expect(restored.pinSalt, equals('random_salt_123'));
    expect(restored.pinHash, equals('hashed_pin_value'));
    expect(restored.autoLockMinutes, equals(1));
    expect(restored.isBiometricEnabled, isTrue);
  });

  test('LinkedDevice serialization and deserialization', () {
    final now = DateTime.now();
    final device = LinkedDevice(
      id: 'linked-laptop-01',
      name: 'Alice ThinkPad',
      platform: 'linux',
      publicKey: 'laptop-public-key',
      linkedAt: now,
      lastSeen: now,
    );

    final json = device.toJson();
    expect(json['id'], equals('linked-laptop-01'));
    expect(json['name'], equals('Alice ThinkPad'));
    expect(json['platform'], equals('linux'));
    expect(json['publicKey'], equals('laptop-public-key'));

    final restored = LinkedDevice.fromJson(json);
    expect(restored.id, equals(device.id));
    expect(restored.name, equals('Alice ThinkPad'));
    expect(restored.platform, equals('linux'));
    expect(restored.publicKey, equals('laptop-public-key'));
  });

  test('DirectHotspotInfo serialization and URI parsing', () {
    const hotspot = DirectHotspotInfo(
      ssid: 'DIRECT-OZO-NODE',
      ip: '192.168.49.1',
      port: 45455,
      deviceId: 'device-node-1',
      deviceName: 'Hotspot Phone',
    );

    final uriStr = hotspot.toUriString();
    expect(uriStr, startsWith('ozo://hotspot?'));

    final parsed = DirectHotspotInfo.parse(uriStr);
    expect(parsed, isNotNull);
    expect(parsed!.ssid, equals('DIRECT-OZO-NODE'));
    expect(parsed.ip, equals('192.168.49.1'));
    expect(parsed.port, equals(45455));
    expect(parsed.deviceId, equals('device-node-1'));
    expect(parsed.deviceName, equals('Hotspot Phone'));
  });

  test('PairingToken serialization, expiration, and replay protection', () {
    final now = DateTime.now();
    final validToken = PairingToken(
      nonce: 'secure-single-use-token-123',
      deviceId: 'primary-phone',
      deviceName: 'Alice iPhone',
      publicKey: 'mock-primary-pk',
      timestamp: now.millisecondsSinceEpoch,
      expiresAt: now.add(const Duration(seconds: 90)).millisecondsSinceEpoch,
      isConsumed: false,
    );

    expect(validToken.isValid, isTrue);

    // Serialization to URI and parsing
    final uri = validToken.toUriString();
    expect(uri, startsWith('ozo://pair?'));
    expect(uri, contains('token=secure-single-use-token-123'));
    expect(uri, contains('id=primary-phone'));

    final parsed = PairingToken.parse(uri);
    expect(parsed, isNotNull);
    expect(parsed!.nonce, equals('secure-single-use-token-123'));
    expect(parsed.deviceId, equals('primary-phone'));
    expect(parsed.deviceName, equals('Alice iPhone'));
    expect(parsed.publicKey, equals('mock-primary-pk'));
    expect(parsed.isValid, isTrue);

    // Expired token is invalid
    final expiredToken = PairingToken(
      nonce: 'expired-token',
      deviceId: 'primary-phone',
      deviceName: 'Alice iPhone',
      publicKey: 'mock-primary-pk',
      timestamp: now.subtract(const Duration(seconds: 100)).millisecondsSinceEpoch,
      expiresAt: now.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch,
      isConsumed: false,
    );
    expect(expiredToken.isValid, isFalse);

    // Consumed token (replay protection) is invalid even before expiry
    final consumedToken = validToken.copyWith(isConsumed: true);
    expect(consumedToken.isValid, isFalse);

    // PairingConfirmationRequest model
    final confirmReq = PairingConfirmationRequest(
      device: LinkedDevice(
        id: 'laptop-node',
        name: 'Bob MacBook',
        platform: 'macos',
        publicKey: 'mock-pk',
        linkedAt: now,
        lastSeen: now,
      ),
      tokenNonce: 'req-token-999',
      onConfirm: () {},
      onReject: () {},
    );
    expect(confirmReq.tokenNonce, equals('req-token-999'));
    expect(confirmReq.device.name, equals('Bob MacBook'));
  });

  test('StickerCatalog uses expressive_reactions and standard Unicode', () {
    final reactionPack = StickerCatalog.packs.firstWhere(
      (p) => p.id == 'expressive_reactions',
    );
    expect(reactionPack.name, equals('Reactions'));
    expect(reactionPack.stickers.length, greaterThan(0));

    final sticker = StickerCatalog.findSticker('react_party');
    expect(sticker, isNotNull);
    expect(sticker!.emoji, equals('🥳'));
  });
}


