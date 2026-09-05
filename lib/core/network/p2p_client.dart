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
  void Function(String messageId, String emoji, String senderId)? onReactionReceived;
  void Function(String messageId)? onMessageDeleted;
  void Function(CallSignaling signaling)? onCallSignaling;

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
      Uri uri;
      if (peer.remoteTunnelUrl != null && peer.remoteTunnelUrl!.isNotEmpty) {
        final parsed = Uri.parse(peer.remoteTunnelUrl!);
        final scheme = (parsed.scheme == 'https' || parsed.port == 443) ? 'wss' : 'ws';
        final host = parsed.host.isNotEmpty ? parsed.host : peer.ip;
        final port = parsed.port > 0 ? parsed.port : (scheme == 'wss' ? 443 : peer.port);
        uri = Uri(scheme: scheme, host: host, port: port, path: '/ws');
      } else if (peer.port == 443 || peer.ip.contains('trycloudflare.com')) {
        final host = peer.ip.replaceAll('https://', '').replaceAll('http://', '').split('/').first;
        uri = Uri(scheme: 'wss', host: host, port: 443, path: '/ws');
      } else {
        uri = Uri.parse('ws://${peer.ip}:${peer.port}/ws');
      }

      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 8));

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
            } else if (type == 'REACTION') {
              final messageId = msg['messageId'] as String;
              final emoji = msg['emoji'] as String;
              final senderId = msg['senderId'] as String? ?? peer.id;
              onReactionReceived?.call(messageId, emoji, senderId);
            } else if (type == 'DELETE_MSG') {
              final messageId = msg['messageId'] as String;
              onMessageDeleted?.call(messageId);
            } else if (type == 'CALL_OFFER' ||
                type == 'CALL_ANSWER' ||
                type == 'CALL_REJECT' ||
                type == 'CALL_END') {
              final signaling = CallSignaling.fromJson(msg);
              onCallSignaling?.call(signaling);
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
      'replyToId': message.replyToId,
      'replyToText': message.replyToText,
      'replyToSenderName': message.replyToSenderName,
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

  /// Dispatches an emoji reaction for a message
  Future<bool> sendReaction({
    required Peer peer,
    required String messageId,
    required String emoji,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'REACTION',
        'messageId': messageId,
        'emoji': emoji,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Sends a delete-for-everyone request to a peer
  Future<bool> sendDeleteMessage({
    required Peer peer,
    required String messageId,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'DELETE_MSG',
        'messageId': messageId,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Dispatches a call signaling packet
  Future<bool> sendCallSignaling({
    required Peer peer,
    required CallSignaling signaling,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode(signaling.toJson()));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Broadcasts a group migration notification to a member
  Future<bool> sendGroupMigration({
    required Peer memberPeer,
    required GroupChat group,
  }) async {
    final socket = await getOrConnect(memberPeer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'GROUP_MIGRATED',
        'groupId': group.id,
        'newHostId': group.hostId,
        'newHostName': group.hostName,
        'newBackupHostId': group.backupHostId,
        'newBackupHostName': group.backupHostName,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(memberPeer.id);
      return false;
    }
  }

  /// Sends device pairing credentials with one-time pairing token
  Future<bool> sendDevicePairing(
    Peer peer, {
    required String id,
    required String name,
    required String platform,
    required String pubKey,
    String? token,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'DEVICE_PAIR',
        'id': id,
        'name': name,
        'platform': platform,
        'pubKey': pubKey,
        'token': token ?? '',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Transmits encrypted database backup for device-to-device migration
  Future<bool> sendBackupMigration(
    Peer peer,
    Map<String, dynamic> backup,
  ) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'BACKUP_TRANSFER',
        'backup': backup,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Broadcasts a pinned message event to chat recipient
  Future<bool> sendPinMessage(
    Peer peer, {
    required String chatId,
    required String messageId,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'MESSAGE_PIN',
        'chatId': chatId,
        'messageId': messageId,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  /// Broadcasts an unpinned message event to chat recipient
  Future<bool> sendUnpinMessage(
    Peer peer, {
    required String chatId,
  }) async {
    final socket = await getOrConnect(peer);
    if (socket == null) return false;
    try {
      socket.add(jsonEncode({
        'type': 'MESSAGE_UNPIN',
        'chatId': chatId,
        'senderId': deviceId,
      }));
      return true;
    } catch (_) {
      _sockets.remove(peer.id);
      return false;
    }
  }

  void close() {
    for (final s in _sockets.values.toList()) {
      try {
        s.close();
      } catch (_) {}
    }
    _sockets.clear();
  }
}
