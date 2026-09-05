import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../crypto/crypto_service.dart';
import '../database/models.dart';

/// Manages outgoing P2P WebSocket connections to other peers
class P2pClient {
  final String deviceId;
  final String deviceName;
  final CryptoService cryptoService;

  // Active client sockets: peerId -> WebSocket
  final Map<String, WebSocket> _sockets = {};
  // Pending connection futures to avoid race conditions
  final Map<String, Future<WebSocket?>> _connectingFutures = {};

  P2pClient({
    required this.deviceId,
    required this.deviceName,
    required this.cryptoService,
  });

  /// Connects to a peer or returns existing open socket
  Future<WebSocket?> getOrConnect(Peer peer) async {
    final existing = _sockets[peer.id];
    if (existing != null && existing.readyState == WebSocket.open) {
      return existing;
    }

    if (_connectingFutures.containsKey(peer.id)) {
      return await _connectingFutures[peer.id];
    }

    final future = _connect(peer);
    _connectingFutures[peer.id] = future;

    try {
      final ws = await future;
      return ws;
    } finally {
      _connectingFutures.remove(peer.id);
    }
  }

  Future<WebSocket?> _connect(Peer peer) async {
    try {
      final uri = Uri.parse('ws://${peer.ip}:${peer.port}/ws');
      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 5));

      _sockets[peer.id] = socket;

      // Handle events on this client socket
      socket.listen(
        (data) {
          // Can handle incoming ACKs or data on this socket if peer uses it duplex
        },
        onDone: () {
          _sockets.remove(peer.id);
        },
        onError: (err) {
          _sockets.remove(peer.id);
        },
      );

      return socket;
    } catch (e) {
      if (kDebugMode) print('Failed to connect to peer ${peer.name} (${peer.ip}:${peer.port}): $e');
      return null;
    }
  }

  /// Sends an encrypted chat message to a peer
  Future<bool> sendMessage({
    required Peer peer,
    required ChatMessage message,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;

    // Encrypt content with recipient's public key using ChaCha20-Poly1305
    final encrypted = await cryptoService.encryptMessage(
      plaintext: message.content,
      peerPublicKeyBase64: peer.publicKey,
    );

    final payload = jsonEncode({
      'type': 'MSG',
      'id': message.id,
      'senderId': deviceId,
      'senderName': deviceName,
      'senderPubKey': cryptoService.publicKeyBase64,
      'ts': message.timestamp.millisecondsSinceEpoch,
      'payload': encrypted,
    });

    try {
      socket.add(payload);
      return true;
    } catch (e) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Sends a file transfer offer to a peer
  Future<bool> sendFileOffer({
    required Peer peer,
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sha256,
    required int myPort,
    required String myPlatform,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;

    final payload = jsonEncode({
      'type': 'FILE_OFFER',
      'transferId': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
      'sha256': sha256,
      'senderId': deviceId,
      'senderName': deviceName,
      'senderPort': myPort,
      'senderPubKey': cryptoService.publicKeyBase64,
      'platform': myPlatform,
    });

    try {
      socket.add(payload);
      return true;
    } catch (e) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Sends typing indicator to peer
  Future<void> sendTyping(Peer peer, bool isTyping) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return;

    try {
      socket.add(jsonEncode({
        'type': 'TYPING',
        'senderId': deviceId,
        'isTyping': isTyping,
      }));
    } catch (_) {}
  }

  void close() {
    for (final s in _sockets.values) {
      try {
        s.close();
      } catch (_) {}
    }
    _sockets.clear();
  }
}
