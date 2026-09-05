import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/app_database.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/security/security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityService PBKDF2 & Legacy Migration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('PBKDF2-HMAC-SHA256 (100k rounds) PIN setting and verification', () async {
      final security = SecurityService();
      await security.initialize();

      expect(security.isPinConfigured, isFalse);

      // Configure PIN
      await security.setPin('8492');
      expect(security.isPinConfigured, isTrue);

      // Verify that stored PIN hash is base64 encoded PBKDF2 (32 bytes = 44 base64 chars)
      expect(security.settings.pinHash.length, equals(44));
      expect(security.settings.pinSalt.length, equals(44)); // 32 bytes base64

      // Verification
      final correctUnlock = await security.unlock('8492');
      expect(correctUnlock, isTrue);
      expect(security.isLocked, isFalse);

      // Lock and test incorrect PIN
      security.lock();
      expect(security.isLocked, isTrue);

      final wrongUnlock = await security.unlock('0000');
      expect(wrongUnlock, isFalse);
      expect(security.isLocked, isTrue);
    });

    test('Legacy SHA-256 PIN hash auto-migrates to PBKDF2 upon successful unlock', () async {
      // Simulate existing legacy app installation with fast SHA-256 PIN
      const legacyPin = '1357';
      const legacySalt = 'mock_legacy_salt_value';
      final legacyHash = crypto.sha256
          .convert(utf8.encode('$legacyPin:$legacySalt:ozo_lock_salt'))
          .toString();

      // Legacy SHA-256 produces 64 hex characters
      expect(legacyHash.length, equals(64));

      SharedPreferences.setMockInitialValues({
        'security_pin_enabled': true,
        'security_pin_hash': legacyHash,
        'security_pin_salt': legacySalt,
      });

      final security = SecurityService();
      await security.initialize();

      expect(security.settings.pinHash.length, equals(64)); // Initially legacy

      // Unlock with correct legacy PIN triggers transparent upgrade
      final unlocked = await security.unlock(legacyPin);
      expect(unlocked, isTrue);

      // Upgraded to PBKDF2 (44 chars base64)
      expect(security.settings.pinHash.length, equals(44));
      expect(security.settings.pinHash, isNot(equals(legacyHash)));

      // Next unlock uses PBKDF2
      security.lock();
      final pbkdf2Unlock = await security.unlock(legacyPin);
      expect(pbkdf2Unlock, isTrue);
    });
  });

  group('AppDatabase Multi-Pin and Backup v2 with PBKDF2', () {
    late Directory tempDir;
    late AppDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_hardening_test');
      db = AppDatabase();
      await db.initialize(customDirectory: tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('Multi-pin chat messages: ordering, retrieval, and unpinning', () async {
      const chatId = 'peer-multi-pin-chat';

      // Initially no pinned messages
      expect(db.getPinnedMessages(chatId), isEmpty);
      expect(db.getPinnedMessageIds(chatId), isEmpty);
      expect(db.getPinnedMessage(chatId), isNull);

      // Create and save 3 messages
      final msgA = ChatMessage(
        id: 'msg-alpha',
        chatId: chatId,
        senderId: 'me',
        senderName: 'Me',
        recipientId: 'peer',
        content: 'Alpha pinned note',
        timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      );
      final msgB = ChatMessage(
        id: 'msg-beta',
        chatId: chatId,
        senderId: 'me',
        senderName: 'Me',
        recipientId: 'peer',
        content: 'Beta pinned note',
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final msgC = ChatMessage(
        id: 'msg-gamma',
        chatId: chatId,
        senderId: 'me',
        senderName: 'Me',
        recipientId: 'peer',
        content: 'Gamma pinned note',
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await db.saveMessage(msgA);
      await db.saveMessage(msgB);
      await db.saveMessage(msgC);

      // Pin 3 messages in sequence
      await db.pinChatMessage(chatId, 'msg-alpha');
      await db.pinChatMessage(chatId, 'msg-beta');
      await db.pinChatMessage(chatId, 'msg-gamma');

      // Pinned IDs: newest pinned first
      final pinnedIds = db.getPinnedMessageIds(chatId);
      expect(pinnedIds.length, equals(3));
      expect(pinnedIds, equals(['msg-gamma', 'msg-beta', 'msg-alpha']));

      // Pinned message models
      final pins = db.getPinnedMessages(chatId);
      expect(pins.length, equals(3));
      expect(pins.map((m) => m.id).toList(), equals(['msg-gamma', 'msg-beta', 'msg-alpha']));

      // Latest pin is msg-gamma
      expect(db.getPinnedMessage(chatId)?.id, equals('msg-gamma'));

      // Unpin middle message
      await db.unpinChatMessage(chatId, 'msg-beta');
      expect(db.getPinnedMessageIds(chatId), equals(['msg-gamma', 'msg-alpha']));
      expect(db.getPinnedMessages(chatId).map((m) => m.id).toList(), equals(['msg-gamma', 'msg-alpha']));

      // Unpin all
      await db.unpinAllChatMessages(chatId);
      expect(db.getPinnedMessages(chatId), isEmpty);
      expect(db.getPinnedMessageIds(chatId), isEmpty);
    });

    test('PBKDF2 Encrypted Backup v2 export and import verification', () async {
      // Seed database with account and messages
      final account = UserAccount(
        id: 'acc-test-1',
        username: 'alice_secure',
        displayName: 'Alice Security',
        createdAt: DateTime.now(),
        isCurrent: true,
      );
      await db.saveAccount(account);

      final msg = ChatMessage(
        id: 'msg-sec-1',
        chatId: 'chat-sec-1',
        senderId: 'acc-test-1',
        senderName: 'Alice',
        recipientId: 'bob-node',
        content: 'Confidential message',
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
      );
      await db.saveMessage(msg);

      const password = 'CorrectHorseBatteryStaple99!';

      // Export encrypted backup
      final backupEnvelope = await db.exportEncryptedBackup(password);

      // Check format versioning and PBKDF2 envelope metadata
      expect(backupEnvelope['format'], equals('ozobackup'));
      expect(backupEnvelope['version'], equals(2));
      expect(backupEnvelope['kdf'], equals('pbkdf2-hmac-sha256-100k'));
      expect(backupEnvelope['salt'], isNotEmpty);
      expect(backupEnvelope['checksum'], isNotEmpty);
      expect(backupEnvelope['payload'], isNotEmpty);

      // Test import with incorrect password returns false
      final wrongPasswordResult =
          await db.importEncryptedBackup(backupEnvelope, 'WrongPassword123');
      expect(wrongPasswordResult, isFalse);

      // Test import into a fresh database with correct password succeeds
      final tempDir2 = await Directory.systemTemp.createTemp('db_restore_test');
      final restoreDb = AppDatabase();
      await restoreDb.initialize(customDirectory: tempDir2);

      final successResult =
          await restoreDb.importEncryptedBackup(backupEnvelope, password);
      expect(successResult, isTrue);

      // Verify restored message
      final restoredMsgs = restoreDb.getMessagesForChat('chat-sec-1');
      expect(restoredMsgs.length, equals(1));
      expect(restoredMsgs.first.content, equals('Confidential message'));

      try {
        tempDir2.deleteSync(recursive: true);
      } catch (_) {}
    });
  });
}
