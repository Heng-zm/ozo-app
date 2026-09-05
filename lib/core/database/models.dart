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

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.publicKey,
    required this.platform,
    required this.lastSeen,
    this.hasIdentityConflict = false,
  });

  bool get isOnline =>
      DateTime.now().difference(lastSeen) < AppConstants.peerOfflineThreshold;

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
      );

  Peer copyWith({
    String? name,
    String? ip,
    int? port,
    String? publicKey,
    String? platform,
    DateTime? lastSeen,
    bool? hasIdentityConflict,
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
    );
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
  });

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
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
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
      );

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
    );
  }
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
