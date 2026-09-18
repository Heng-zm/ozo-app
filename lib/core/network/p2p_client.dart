import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../crypto/crypto_service.dart';
import '../database/models.dart';

/// Manages outgoing P2P WebSocket connections to other peers and supports full-duplex socket reuse
class P2pClient {
  final String deviceId;
  final String deviceName;
  final CryptoService cryptoService;
  final WebSocket? Function(String peerId)? serverSocketProvider;

  // Active client sockets: peerId -> WebSocket
  final Map<String, WebSocket> _sockets = {};
  // Pending connection futures to avoid race conditions
  final Map<String, Future<WebSocket?>> _connectingFutures = {};

  // Callbacks for duplex reception on client socket
  void Function(ChatMessage message)? onMessageReceived;
  void Function(FileMetadata file, Peer sender)? onFileOffered;
  void Function(String messageId, MessageStatus status)? onDeliveryReceipt;
  void Function(String peerId, bool isTyping)? onTyping;
  void Function(GroupChat group)? onGroupInvite;
  void Function(ChatMessage message, String groupId)? onGroupMessage;
  void Function(String groupId, String newHostId, String newHostName, String? newBackupHostId, String? newBackupHostName)? onGroupMigrated;
  void Function(String messageId, String emoji, String senderId)? onReactionReceived;
  void Function(String messageId, [String? senderId])? onMessageDeleted;
  void Function(CallSignaling signaling)? onCallSignaling;
  void Function(LinkedDevice device, String token)? onDevicePairRequest;
  void Function(Map<String, dynamic> backupData)? onBackupReceived;
  void Function(String chatId, String messageId)? onMessagePinned;
  void Function(String chatId)? onMessageUnpinned;

  P2pClient({
    required this.deviceId,
    required this.deviceName,
    required this.cryptoService,
    this.serverSocketProvider,
  });

  /// Connects to a peer or returns existing open socket (client-initiated or server-accepted)
  Future<WebSocket?> getOrConnect(Peer peer) async {
    final existing = _sockets[peer.id];
    if (existing != null && existing.readyState == WebSocket.open) {
      return existing;
    } else if (existing != null) {
      _sockets.remove(peer.id);
    }

    // Bidirectional NAT bypass: check if peer has an open incoming server socket
    final serverSocket = serverSocketProvider?.call(peer.id);
    if (serverSocket != null && serverSocket.readyState == WebSocket.open) {
      return serverSocket;
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

  List<Uri> _buildCandidateUris(Peer peer) {
    final uris = <Uri>[];

    // Candidate 1: Remote tunnel if configured
    if (peer.remoteTunnelUrl != null && peer.remoteTunnelUrl!.isNotEmpty) {
      try {
        final parsed = Uri.parse(peer.remoteTunnelUrl!);
        final scheme = (parsed.scheme == 'https' || parsed.port == 443) ? 'wss' : 'ws';
        final host = parsed.host.isNotEmpty ? parsed.host : peer.ip;
        final port = parsed.port > 0 ? parsed.port : (scheme == 'wss' ? 443 : peer.port);
        uris.add(Uri(scheme: scheme, host: host, port: port, path: '/ws'));
      } catch (_) {}
    }

    // Candidate 2: Direct IP and port
    if (peer.ip.isNotEmpty && peer.port > 0) {
      if (peer.port == 443 || peer.ip.contains('trycloudflare.com')) {
        final host = peer.ip.replaceAll('https://', '').replaceAll('http://', '').split('/').first;
        uris.add(Uri(scheme: 'wss', host: host, port: 443, path: '/ws'));
      } else {
        uris.add(Uri(scheme: 'ws', host: peer.ip, port: peer.port, path: '/ws'));
      }
    }

    // Candidate 3: Loopback fallback if testing on same machine
    if (peer.ip == '127.0.0.1' || peer.ip == 'localhost') {
      uris.add(Uri(scheme: 'ws', host: '127.0.0.1', port: peer.port, path: '/ws'));
    }

    // Deduplicate URIs preserving insertion order
    final seen = <String>{};
    return uris.where((u) => seen.add(u.toString())).toList();
  }

  Future<WebSocket?> _connect(Peer peer) async {
    final candidates = _buildCandidateUris(peer);
    if (candidates.isEmpty) return null;

    const connectTimeout = Duration(milliseconds: 3500);

    for (final uri in candidates) {
      try {
        final socket = await WebSocket.connect(
          uri.toString(),
        ).timeout(connectTimeout);

        socket.pingInterval = const Duration(seconds: 15);
        _sockets[peer.id] = socket;

        // Send instant handshake frame to establish reverse routing immediately
        try {
          socket.add(jsonEncode({
            'type': 'HANDSHAKE',
            'senderId': deviceId,
            'senderName': deviceName,
            'senderPubKey': cryptoService.publicKeyBase64,
            'ts': DateTime.now().millisecondsSinceEpoch,
          }));
        } catch (_) {}

        _listenToSocket(socket, peer.id);
        return socket;
      } catch (e) {
        if (kDebugMode) {
          print('Candidate connect failed for ${peer.name} ($uri): $e');
        }
      }
    }

    return null;
  }

  void _listenToSocket(WebSocket socket, String fallbackPeerId) {
    String peerId = fallbackPeerId;

    socket.listen(
      (data) async {
        try {
          final text = data is String ? data : utf8.decode(data as List<int>);
          final msg = jsonDecode(text) as Map<String, dynamic>;
          final type = msg['type'] as String?;
          final senderId = msg['senderId'] as String?;
          if (senderId != null) {
            peerId = senderId;
            _sockets[senderId] = socket;
          }

          switch (type) {
            case 'HANDSHAKE':
              if (socket.readyState == WebSocket.open) {
                socket.add(jsonEncode({
                  'type': 'HANDSHAKE_ACK',
                  'senderId': deviceId,
                  'senderName': deviceName,
                  'senderPubKey': cryptoService.publicKeyBase64,
                  'ts': DateTime.now().millisecondsSinceEpoch,
                }));
              }
              break;
            case 'HANDSHAKE_ACK':
              break;
            case 'MSG':
              await _handleIncomingChatMessage(msg, socket);
              break;
            case 'FILE_OFFER':
              _handleIncomingFileOffer(msg);
              break;
            case 'ACK':
              final messageId = msg['messageId'] as String;
              final status = msg['status'] == 'read'
                  ? MessageStatus.read
                  : MessageStatus.delivered;
              onDeliveryReceipt?.call(messageId, status);
              break;
            case 'TYPING':
              final isTyping = msg['isTyping'] as bool? ?? false;
              if (senderId != null) {
                onTyping?.call(senderId, isTyping);
              }
              break;
            case 'GROUP_INVITE':
              _handleIncomingGroupInvite(msg);
              break;
            case 'GROUP_MSG':
            case 'GROUP_RELAY':
              _handleIncomingGroupMessage(msg);
              break;
            case 'REACTION':
              final messageId = msg['messageId'] as String;
              final emoji = msg['emoji'] as String;
              final rSenderId = senderId ?? peerId;
              onReactionReceived?.call(messageId, emoji, rSenderId);
              break;
            case 'DELETE_MSG':
              final messageId = msg['messageId'] as String;
              final reqSenderId = senderId ?? peerId;
              onMessageDeleted?.call(messageId, reqSenderId);
              break;
            case 'CALL_OFFER':
            case 'CALL_ANSWER':
            case 'CALL_REJECT':
            case 'CALL_END':
              final signaling = CallSignaling.fromJson(msg);
              onCallSignaling?.call(signaling);
              break;
            case 'GROUP_MIGRATED':
              final groupId = msg['groupId'] as String;
              final newHostId = msg['newHostId'] as String;
              final newHostName = msg['newHostName'] as String? ?? 'New Host';
              final newBackupHostId = msg['newBackupHostId'] as String?;
              final newBackupHostName = msg['newBackupHostName'] as String?;
              onGroupMigrated?.call(groupId, newHostId, newHostName, newBackupHostId, newBackupHostName);
              break;
            case 'DEVICE_PAIR':
              final dev = LinkedDevice(
                id: msg['id'] as String,
                name: msg['name'] as String,
                platform: msg['platform'] as String? ?? 'unknown',
                publicKey: msg['pubKey'] as String? ?? '',
                linkedAt: DateTime.now(),
              );
              final token = msg['token'] as String? ?? '';
              onDevicePairRequest?.call(dev, token);
              break;
            case 'BACKUP_TRANSFER':
              final backup = msg['backup'] as Map<String, dynamic>;
              onBackupReceived?.call(backup);
              break;
            case 'MESSAGE_PIN':
              final chatId = msg['chatId'] as String;
              final messageId = msg['messageId'] as String;
              onMessagePinned?.call(chatId, messageId);
              break;
            case 'MESSAGE_UNPIN':
              final chatId = msg['chatId'] as String;
              onMessageUnpinned?.call(chatId);
              break;
          }
        } catch (_) {}
      },
      onDone: () {
        _sockets.remove(peerId);
      },
      onError: (err) {
        _sockets.remove(peerId);
      },
    );
  }

  Future<void> _handleIncomingChatMessage(Map<String, dynamic> msg, WebSocket socket) async {
    final senderId = msg['senderId'] as String;
    final senderName = msg['senderName'] as String? ?? 'Peer';
    final senderPubKey = msg['senderPubKey'] as String;
    final encryptedData = msg['payload'] as Map<String, dynamic>;
    final messageId = msg['id'] as String;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['ts'] as int);

    String plaintext = '';
    try {
      plaintext = await cryptoService.decryptMessage(
        encryptedData: encryptedData,
        senderPublicKeyBase64: senderPubKey,
      );
    } catch (e) {
      if (kDebugMode) print('E2EE Decryption failed on client socket: $e');
      return;
    }

    final msgTypeStr = msg['msgType'] as String?;
    final msgType = MessageType.values.firstWhere(
      (e) => e.name == msgTypeStr,
      orElse: () => MessageType.text,
    );
    final voiceDuration = (msg['voiceDuration'] as num?)?.toDouble();
    final amplitudes = (msg['amplitudes'] as List<dynamic>?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    final fileMeta = msg['fileMetadata'] != null
        ? FileMetadata.fromJson(msg['fileMetadata'] as Map<String, dynamic>)
        : null;

    final replyToId = msg['replyToId'] as String?;
    final replyToText = msg['replyToText'] as String?;
    final replyToSenderName = msg['replyToSenderName'] as String?;
    final ephemeralSec = msg['ephemeralSeconds'] as int?;
    final expAt = ephemeralSec != null ? DateTime.now().add(Duration(seconds: ephemeralSec)) : null;

    final chatMsg = ChatMessage(
      id: messageId,
      chatId: senderId,
      senderId: senderId,
      senderName: senderName,
      recipientId: deviceId,
      content: plaintext,
      type: msgType,
      timestamp: timestamp,
      status: MessageStatus.delivered,
      voiceDurationSeconds: voiceDuration,
      waveformAmplitudes: amplitudes,
      fileMetadata: fileMeta,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
      ephemeralDurationSeconds: ephemeralSec,
      expiresAt: expAt,
    );

    if (socket.readyState == WebSocket.open) {
      try {
        socket.add(jsonEncode({
          'type': 'ACK',
          'messageId': messageId,
          'status': 'delivered',
          'senderId': deviceId,
        }));
      } catch (_) {}
    }

    onMessageReceived?.call(chatMsg);
  }

  void _handleIncomingFileOffer(Map<String, dynamic> msg) {
    final senderId = msg['senderId'] as String;
    final senderName = msg['senderName'] as String? ?? 'Peer';
    final senderPort = msg['senderPort'] as int? ?? AppConstants.defaultP2pPort;
    final senderPubKey = msg['senderPubKey'] as String? ?? '';

    final fileMeta = FileMetadata(
      transferId: msg['transferId'] as String,
      fileName: msg['fileName'] as String,
      fileSize: msg['fileSize'] as int,
      sha256: msg['sha256'] as String? ?? '',
    );

    final sender = Peer(
      id: senderId,
      name: senderName,
      ip: '127.0.0.1',
      port: senderPort,
      publicKey: senderPubKey,
      platform: msg['platform'] as String? ?? 'unknown',
      lastSeen: DateTime.now(),
    );

    onFileOffered?.call(fileMeta, sender);
  }

  void _handleIncomingGroupInvite(Map<String, dynamic> msg) {
    try {
      final groupJson = msg['group'] as Map<String, dynamic>;
      final group = GroupChat.fromJson(groupJson);
      onGroupInvite?.call(group);
    } catch (_) {}
  }

  void _handleIncomingGroupMessage(Map<String, dynamic> msg) {
    try {
      final groupId = msg['groupId'] as String;
      final id = msg['id'] as String;
      final senderId = msg['senderId'] as String;
      final senderName = msg['senderName'] as String? ?? 'Group Member';
      final content = msg['content'] as String;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['ts'] as int);
      final ephemeralSec = msg['ephemeralSeconds'] as int?;
      final expAt = ephemeralSec != null ? DateTime.now().add(Duration(seconds: ephemeralSec)) : null;

      final chatMsg = ChatMessage(
        id: id,
        chatId: groupId,
        senderId: senderId,
        senderName: senderName,
        recipientId: groupId,
        content: content,
        type: MessageType.text,
        timestamp: timestamp,
        status: MessageStatus.delivered,
        isGroup: true,
        groupId: groupId,
        ephemeralDurationSeconds: ephemeralSec,
        expiresAt: expAt,
      );

      onGroupMessage?.call(chatMsg, groupId);
    } catch (_) {}
  }

  /// Sends an encrypted chat message to a peer
  Future<bool> sendMessage({
    required Peer peer,
    required ChatMessage message,
  }) async {
    var socket = await getOrConnect(peer);
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
      'ephemeralSeconds': message.ephemeralDurationSeconds,
    });

    try {
      socket.add(payload);
      return true;
    } catch (e) {
      _sockets.remove(peer.id);
      // Fast retry on fresh connection in case of silent socket drop
      try {
        final freshSocket = await _connect(peer);
        if (freshSocket != null && freshSocket.readyState == WebSocket.open) {
          freshSocket.add(payload);
          return true;
        }
      } catch (_) {}
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
      'ephemeralSeconds': message.ephemeralDurationSeconds,
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
      'ephemeralSeconds': message.ephemeralDurationSeconds,
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
