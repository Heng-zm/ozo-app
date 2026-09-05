import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/app_database.dart';
import 'package:lan_telegram/core/database/models.dart';

void main() {
  test('Trust-On-First-Use (TOFU) pins keys and detects identity changes', () async {
    final tempDir = await Directory.systemTemp.createTemp('tofu_test');
    final db = AppDatabase();
    await db.initialize(customDirectory: tempDir);

    try {
      // 1. First contact with Alice's device
      final aliceV1 = Peer(
        id: 'alice-device-uuid',
        name: "Alice's MacBook",
        ip: '192.168.1.10',
        port: 45455,
        publicKey: 'ORIGINAL_GENUINE_PUBLIC_KEY_BASE64',
        platform: 'macos',
        lastSeen: DateTime.now(),
      );

      await db.savePeer(aliceV1);

      // Key should be pinned permanently
      expect(db.pinnedKeys['alice-device-uuid'], equals('ORIGINAL_GENUINE_PUBLIC_KEY_BASE64'));
      expect(aliceV1.hasIdentityConflict, isFalse);
      expect(aliceV1.safetyFingerprint, isNotEmpty);
      expect(aliceV1.safetyFingerprint.contains('-'), isTrue);
      expect(aliceV1.safetyFingerprint.length, equals(9)); // XXXX-XXXX format

      // 2. An attacker or changed device reappears with the same deviceId but DIFFERENT public key
      final aliceSpoofed = Peer(
        id: 'alice-device-uuid',
        name: "Alice's MacBook (Impersonator)",
        ip: '192.168.1.99',
        port: 45455,
        publicKey: 'ATTACKER_SPOOFED_PUBLIC_KEY_BASE64',
        platform: 'linux',
        lastSeen: DateTime.now(),
      );

      await db.savePeer(aliceSpoofed);

      // Identity conflict MUST be flagged
      expect(aliceSpoofed.hasIdentityConflict, isTrue);
      expect(db.pinnedKeys['alice-device-uuid'], equals('ORIGINAL_GENUINE_PUBLIC_KEY_BASE64'));
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });
}
