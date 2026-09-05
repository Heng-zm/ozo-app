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

  // Callbacks for duplex reception on client socket
  void Function(String messageId, MessageStatus status)? onDeliveryReceipt;
  void Function(String peerId, bool isTyping)? onTyping;

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

      // Handle events on this client socket (duplex)
      socket.listen(
        (data) {
          try {
            final text = data is String ? data : utf8.decode(data as List<int>);
            final msg = jsonDecode(text) as Map<String, dynamic>;
            final type = msg['type'] as String?;
            if (type == 'ACK') {
              final messageId = msg['messageId'] as String;
              final status = msg['status'] == 'read'
                  ? MessageStatus.read
                  : MessageStatus.delivered;
              onDeliveryReceipt?.call(messageId, status);
            } else if (type == 'TYPING') {
              final senderId = msg['senderId'] as String?;
              final isTyping = msg['isTyping'] as bool? ?? false;
              if (senderId != null) {
                onTyping?.call(senderId, isTyping);
              }
            }
          } catch (_) {}
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
      'msgType': message.type.name,
      'fileMetadata': message.fileMetadata?.toJson(),
      'voiceDuration': message.voiceDurationSeconds,
      'amplitudes': message.waveformAmplitudes,
    });

    try {
      socket.add(payload);
      return true;
    } catch (e) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Sends a read receipt to a peer for a message
  Future<void> sendReadReceipt(Peer peer, String messageId) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return;
    try {
      socket.add(jsonEncode({
        'type': 'ACK',
        'messageId': messageId,
        'status': 'read',
        'senderId': deviceId,
      }));
    } catch (_) {}
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

  /// Sends a group invitation to a peer
  Future<bool> sendGroupInvite({
    required Peer peer,
    required GroupChat group,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;

    final payload = jsonEncode({
      'type': 'GROUP_INVITE',
      'senderId': deviceId,
      'group': group.toJson(),
    });

    try {
      socket.add(payload);
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Member sends message to group Host
  Future<bool> sendGroupMessage({
    required Peer hostPeer,
    required GroupChat group,
    required ChatMessage message,
  }) async {
    final socket = await getOrConnect(hostPeer);
    if (socket == null) return false;

    final payload = jsonEncode({
      'type': 'GROUP_MSG',
      'groupId': group.id,
      'id': message.id,
      'senderId': deviceId,
      'senderName': deviceName,
      'content': message.content,
      'ts': message.timestamp.millisecondsSinceEpoch,
    });

    try {
      socket.add(payload);
      return true;
    } catch (_) {
      _sockets.remove(hostPeer.id);
      return false;
    }
  }

  /// Host relays message to a group member
  Future<bool> relayGroupMessage({
    required Peer memberPeer,
    required GroupChat group,
    required ChatMessage message,
  }) async {
    final socket = await getOrConnect(memberPeer);
    if (socket == null) return false;

    final payload = jsonEncode({
      'type': 'GROUP_RELAY',
      'groupId': group.id,
      'id': message.id,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'content': message.content,
      'ts': message.timestamp.millisecondsSinceEpoch,
    });

    try {
      socket.add(payload);
      return true;
    } catch (_) {
      _sockets.remove(memberPeer.id);
      return false;
    }
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
