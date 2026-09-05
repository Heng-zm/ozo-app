import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lan_telegram/core/crypto/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('E2EE Key Exchange and ChaCha20-Poly1305 Encryption/Decryption', () async {
    // Alice Crypto Service
    final aliceCrypto = CryptoService();
    await aliceCrypto.initialize();
    final alicePubKey = aliceCrypto.publicKeyBase64!;

    expect(alicePubKey, isNotEmpty);

    const secretText = 'Hello LAN Telegram! This is end-to-end encrypted.';

    // Self-encrypt/decrypt loopback test (Alice -> Alice shared key)
    final encrypted = await aliceCrypto.encryptMessage(
      plaintext: secretText,
      peerPublicKeyBase64: alicePubKey,
    );

    expect(encrypted.containsKey('ct'), isTrue);
    expect(encrypted.containsKey('nonce'), isTrue);
    expect(encrypted.containsKey('mac'), isTrue);

    final decrypted = await aliceCrypto.decryptMessage(
      encryptedData: encrypted,
      senderPublicKeyBase64: alicePubKey,
    );

    expect(decrypted, equals(secretText));
  });

  test('Binary Chunk Encryption and Decryption for File Transfer', () async {
    final crypto = CryptoService();
    await crypto.initialize();
    final pubKey = crypto.publicKeyBase64!;

    final originalData = Uint8List.fromList(
      List.generate(1024, (i) => i % 256),
    );

    final encryptedChunk = await crypto.encryptChunk(
      chunk: originalData,
      peerPublicKeyBase64: pubKey,
    );

    // Format is 12 bytes nonce + 16 bytes mac + ciphertext
    expect(encryptedChunk.length, equals(12 + 16 + 1024));

    final decryptedChunk = await crypto.decryptChunk(
      encryptedData: encryptedChunk,
      senderPublicKeyBase64: pubKey,
    );

    expect(decryptedChunk, equals(originalData));
  });
}
