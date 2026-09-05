import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../constants.dart';

enum MessageType { text, file, image, voice }
enum MessageStatus { pending, sent, delivered, read, failed }
enum TransferDirection { upload, download }
enum TransferStatus { offered, transferring, paused, completed, failed }

/// Represents a peer discovered on the local network
class Peer {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String publicKey;
  final String platform;
  DateTime lastSeen;
  bool hasIdentityConflict;
  bool isRemote;
  String? remoteTunnelUrl;

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.publicKey,
    required this.platform,
    required this.lastSeen,
    this.hasIdentityConflict = false,
    this.isRemote = false,
    this.remoteTunnelUrl,
  });

  bool get isOnline =>
      isRemote || DateTime.now().difference(lastSeen) < AppConstants.peerOfflineThreshold;

  /// Short 8-character cryptographic safety fingerprint (e.g. A1B2-C3D4)
  String get safetyFingerprint {
    if (publicKey.isEmpty) return '0000-0000';
    final digest = sha256.convert(utf8.encode(publicKey)).toString().toUpperCase();
    return '${digest.substring(0, 4)}-${digest.substring(4, 8)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'publicKey': publicKey,
        'platform': platform,
        'lastSeen': lastSeen.toIso8601String(),
        'hasIdentityConflict': hasIdentityConflict,
        'isRemote': isRemote,
        'remoteTunnelUrl': remoteTunnelUrl,
      };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unknown Device',
        ip: json['ip'] as String,
        port: json['port'] as int? ?? AppConstants.defaultP2pPort,
        publicKey: json['publicKey'] as String? ?? '',
        platform: json['platform'] as String? ?? 'unknown',
        lastSeen: json['lastSeen'] != null
            ? DateTime.parse(json['lastSeen'] as String)
            : DateTime.now(),
        hasIdentityConflict: json['hasIdentityConflict'] as bool? ?? false,
        isRemote: json['isRemote'] as bool? ?? false,
        remoteTunnelUrl: json['remoteTunnelUrl'] as String?,
      );

  Peer copyWith({
    String? name,
    String? ip,
    int? port,
    String? publicKey,
    String? platform,
    DateTime? lastSeen,
    bool? hasIdentityConflict,
    bool? isRemote,
    String? remoteTunnelUrl,
  }) {
    return Peer(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      publicKey: publicKey ?? this.publicKey,
      platform: platform ?? this.platform,
      lastSeen: lastSeen ?? this.lastSeen,
      hasIdentityConflict: hasIdentityConflict ?? this.hasIdentityConflict,
      isRemote: isRemote ?? this.isRemote,
      remoteTunnelUrl: remoteTunnelUrl ?? this.remoteTunnelUrl,
    );
  }
}

/// Helper to serialize and parse remote connection links & QR codes
class PeerConnectionLink {
  final String id;
  final String name;
  final String host;
  final int port;
  final String publicKey;
  final String platform;
  final bool isSecure;

  PeerConnectionLink({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.publicKey,
    this.platform = 'unknown',
    this.isSecure = false,
  });

  String toUriString() {
    final uri = Uri(
      scheme: 'ozo',
      host: 'connect',
      queryParameters: {
        'id': id,
        'name': name,
        'host': host,
        'port': port.toString(),
        'key': publicKey,
        'platform': platform,
        'ssl': isSecure ? '1' : '0',
      },
    );
    return uri.toString();
  }

  static PeerConnectionLink? parse(String input) {
    try {
      final trimmed = input.trim();
      if (trimmed.startsWith('ozo://') || trimmed.contains('connect?')) {
        final uri = Uri.parse(trimmed);
        final q = uri.queryParameters;
        return PeerConnectionLink(
          id: q['id'] ?? '',
          name: q['name'] ?? 'Remote Peer',
          host: q['host'] ?? '',
          port: int.tryParse(q['port'] ?? '') ?? 45455,
          publicKey: q['key'] ?? '',
          platform: q['platform'] ?? 'unknown',
          isSecure: q['ssl'] == '1',
        );
      } else if (trimmed.contains('trycloudflare.com') ||
          trimmed.startsWith('http://') ||
          trimmed.startsWith('https://')) {
        final uri = Uri.parse(
            trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
        return PeerConnectionLink(
          id: 'cf-${uri.host}',
          name: uri.host.split('.').first,
          host: uri.host,
          port: uri.port > 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80),
          publicKey: '',
          platform: 'remote',
          isSecure: uri.scheme == 'https',
        );
      } else if (trimmed.contains(':')) {
        final parts = trimmed.split(':');
        return PeerConnectionLink(
          id: 'manual-${parts[0]}',
          name: parts[0],
          host: parts[0],
          port: int.tryParse(parts[1]) ?? 45455,
          publicKey: '',
          platform: 'remote',
        );
      }
    } catch (_) {}
    return null;
  }
}

/// Represents a local group chat coordinated via Host-Relay
class GroupChat {
  final String id;
  final String name;
  final String hostId;
  final String hostName;
  final List<String> memberIds;
  final DateTime createdAt;

  GroupChat({
    required this.id,
    required this.name,
    required this.hostId,
    required this.hostName,
    required this.memberIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostId': hostId,
        'hostName': hostName,
        'memberIds': memberIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GroupChat.fromJson(Map<String, dynamic> json) => GroupChat(
        id: json['id'] as String,
        name: json['name'] as String,
        hostId: json['hostId'] as String,
        hostName: json['hostName'] as String? ?? 'Host',
        memberIds: (json['memberIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
      );
}

/// Metadata for file attachment in chat
class FileMetadata {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String sha256;
  String? localPath;
  bool isCompleted;

  FileMetadata({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    this.localPath,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': sha256,
        'localPath': localPath,
        'isCompleted': isCompleted,
      };

  factory FileMetadata.fromJson(Map<String, dynamic> json) => FileMetadata(
        transferId: json['transferId'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int,
        sha256: json['sha256'] as String? ?? '',
        localPath: json['localPath'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
      );
}

/// Represents a chat message (1-on-1 or Host-Relayed Group)
class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  MessageStatus status;
  final FileMetadata? fileMetadata;
  final bool isGroup;
  final String? groupId;
  final double? voiceDurationSeconds;
  final List<double>? waveformAmplitudes;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderName;
  final Map<String, List<String>> reactions;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.content,
    this.type = MessageType.text,
    required this.timestamp,
    this.status = MessageStatus.pending,
    this.fileMetadata,
    this.isGroup = false,
    this.groupId,
    this.voiceDurationSeconds,
    this.waveformAmplitudes,
    this.replyToId,
    this.replyToText,
    this.replyToSenderName,
    Map<String, List<String>>? reactions,
  }) : reactions = reactions ?? {};

  bool get isImage {
    if (type == MessageType.image) return true;
    if (type == MessageType.file && fileMetadata != null) {
      final ext = fileMetadata!.fileName.toLowerCase();
      return ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.png') ||
          ext.endsWith('.gif') ||
          ext.endsWith('.webp') ||
          ext.endsWith('.bmp');
    }
    return false;
  }

  bool get isVoice => type == MessageType.voice;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'recipientId': recipientId,
        'content': content,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
        'fileMetadata': fileMetadata?.toJson(),
        'isGroup': isGroup,
        'groupId': groupId,
        'voiceDurationSeconds': voiceDurationSeconds,
        'waveformAmplitudes': waveformAmplitudes,
        'replyToId': replyToId,
        'replyToText': replyToText,
        'replyToSenderName': replyToSenderName,
        'reactions': reactions,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'] as Map<String, dynamic>?;
    final parsedReactions = <String, List<String>>{};
    if (rawReactions != null) {
      rawReactions.forEach((key, val) {
        if (val is List) {
          parsedReactions[key] = val.map((e) => e.toString()).toList();
        }
      });
    }

    return ChatMessage(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String? ?? 'Unknown',
      recipientId: json['recipientId'] as String,
      content: json['content'] as String? ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.delivered,
      ),
      fileMetadata: json['fileMetadata'] != null
          ? FileMetadata.fromJson(
              json['fileMetadata'] as Map<String, dynamic>)
          : null,
      isGroup: json['isGroup'] as bool? ?? false,
      groupId: json['groupId'] as String?,
      voiceDurationSeconds: (json['voiceDurationSeconds'] as num?)?.toDouble(),
      waveformAmplitudes: (json['waveformAmplitudes'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      replyToId: json['replyToId'] as String?,
      replyToText: json['replyToText'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      reactions: parsedReactions,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? recipientId,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    MessageStatus? status,
    FileMetadata? fileMetadata,
    bool? isGroup,
    String? groupId,
    double? voiceDurationSeconds,
    List<double>? waveformAmplitudes,
    String? replyToId,
    String? replyToText,
    String? replyToSenderName,
    Map<String, List<String>>? reactions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      recipientId: recipientId ?? this.recipientId,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      fileMetadata: fileMetadata ?? this.fileMetadata,
      isGroup: isGroup ?? this.isGroup,
      groupId: groupId ?? this.groupId,
      voiceDurationSeconds: voiceDurationSeconds ?? this.voiceDurationSeconds,
      waveformAmplitudes: waveformAmplitudes ?? this.waveformAmplitudes,
      replyToId: replyToId ?? this.replyToId,
      replyToText: replyToText ?? this.replyToText,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      reactions: reactions ?? Map<String, List<String>>.from(this.reactions),
    );
  }
}

/// Call status lifecycle for 1-on-1 audio calls
enum CallStatus {
  idle,
  outgoingCalling,
  incomingRinging,
  connected,
  ended,
}

/// P2P Call Signaling payload
class CallSignaling {
  final String callId;
  final String callerId;
  final String callerName;
  final String type; // 'offer', 'answer', 'reject', 'end'
  final bool? accepted;
  final DateTime timestamp;

  CallSignaling({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.type,
    this.accepted,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'type': type,
        'accepted': accepted,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CallSignaling.fromJson(Map<String, dynamic> json) => CallSignaling(
        callId: json['callId'] as String,
        callerId: json['callerId'] as String,
        callerName: json['callerName'] as String? ?? 'Peer',
        type: json['type'] as String,
        accepted: json['accepted'] as bool?,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
      );
}

/// Represents an active or completed file transfer
class FileTransferInfo {
  final String transferId;
  final String messageId;
  final String fileName;
  final int fileSize;
  int bytesTransferred;
  String localPath;
  final String remoteIp;
  final int remotePort;
  final String remotePublicKey;
  final TransferDirection direction;
  TransferStatus status;
  double speedBytesPerSec;
  final String sha256;

  FileTransferInfo({
    required this.transferId,
    required this.messageId,
    required this.fileName,
    required this.fileSize,
    this.bytesTransferred = 0,
    required this.localPath,
    required this.remoteIp,
    required this.remotePort,
    required this.remotePublicKey,
    required this.direction,
    this.status = TransferStatus.offered,
    this.speedBytesPerSec = 0.0,
    required this.sha256,
  });

  double get progress =>
      fileSize > 0 ? (bytesTransferred / fileSize).clamp(0.0, 1.0) : 0.0;
}
