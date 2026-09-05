import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cryptography service providing E2EE:
/// - X25519 key exchange
/// - ChaCha20-Poly1305 AEAD symmetric encryption
/// - Shared secret caching per peer
class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _x25519 = X25519();
  final _aead = Chacha20.poly1305Aead();

  SimpleKeyPair? _keyPair;
  SimplePublicKey? _publicKey;
  String? _publicKeyBase64;

  // Cache of derived shared secret keys by peer public key Base64 string
  final Map<String, SecretKey> _sharedSecretCache = {};

  String? get publicKeyBase64 => _publicKeyBase64;
  SimplePublicKey? get publicKey => _publicKey;

  /// Initializes or restores the local device X25519 keypair
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPrivateKeyBase64 = prefs.getString('lan_tg_private_key');

    if (savedPrivateKeyBase64 != null) {
      final privateKeyBytes = base64Decode(savedPrivateKeyBase64);
      _keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
    } else {
      _keyPair = await _x25519.newKeyPair();
      final privateKey = await _keyPair!.extractPrivateKeyBytes();
      await prefs.setString('lan_tg_private_key', base64Encode(privateKey));
    }

    _publicKey = await _keyPair!.extractPublicKey();
    _publicKeyBase64 = base64Encode(_publicKey!.bytes);
  }

  /// Derives or retrieves cached shared secret key for a peer's public key
  Future<SecretKey> _getOrCreateSharedKey(String peerPublicKeyBase64) async {
    if (_sharedSecretCache.containsKey(peerPublicKeyBase64)) {
      return _sharedSecretCache[peerPublicKeyBase64]!;
    }

    final peerPublicKeyBytes = base64Decode(peerPublicKeyBase64);
    final remotePublicKey = SimplePublicKey(
      peerPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: remotePublicKey,
    );

    _sharedSecretCache[peerPublicKeyBase64] = sharedSecret;
    return sharedSecret;
  }

  /// Encrypts plaintext string using ChaCha20-Poly1305
  /// Returns a Map with {ct, nonce, mac} in Base64
  Future<Map<String, String>> encryptMessage({
    required String plaintext,
    required String peerPublicKeyBase64,
  }) async {
    if (_keyPair == null) await initialize();

    final secretKey = await _getOrCreateSharedKey(peerPublicKeyBase64);
    final plaintextBytes = utf8.encode(plaintext);

    final secretBox = await _aead.encrypt(
      plaintextBytes,
      secretKey: secretKey,
    );

    return {
      'ct': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypts payload {ct, nonce, mac} using ChaCha20-Poly1305
  Future<String> decryptMessage({
    required Map<String, dynamic> encryptedData,
    required String senderPublicKeyBase64,
  }) async {
    if (_keyPair == null) await initialize();

    final secretKey = await _getOrCreateSharedKey(senderPublicKeyBase64);

    final cipherText = base64Decode(encryptedData['ct'] as String);
    final nonce = base64Decode(encryptedData['nonce'] as String);
    final macBytes = base64Decode(encryptedData['mac'] as String);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _aead.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decryptedBytes);
  }

  /// Encrypts a binary chunk for file transfer
  Future<Uint8List> encryptChunk({
    required Uint8List chunk,
    required String peerPublicKeyBase64,
  }) async {
    if (_keyPair == null) await initialize();

    final secretKey = await _getOrCreateSharedKey(peerPublicKeyBase64);
    final secretBox = await _aead.encrypt(chunk, secretKey: secretKey);

    // Format: 12 bytes nonce + 16 bytes mac + ciphertext
    final bb = BytesBuilder(copy: false);
    bb.add(secretBox.nonce);
    bb.add(secretBox.mac.bytes);
    bb.add(secretBox.cipherText);
    return bb.toBytes();
  }

  /// Decrypts a binary chunk for file transfer
  Future<Uint8List> decryptChunk({
    required Uint8List encryptedData,
    required String senderPublicKeyBase64,
  }) async {
    if (_keyPair == null) await initialize();

    final secretKey = await _getOrCreateSharedKey(senderPublicKeyBase64);

    // Parse: 12 bytes nonce, 16 bytes mac, rest ciphertext
    final nonce = encryptedData.sublist(0, 12);
    final mac = Mac(encryptedData.sublist(12, 28));
    final cipherText = encryptedData.sublist(28);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final clearBytes = await _aead.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(clearBytes);
  }
}
