import '../constants.dart';

enum MessageType { text, file }
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

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.publicKey,
    required this.platform,
    required this.lastSeen,
  });

  bool get isOnline =>
      DateTime.now().difference(lastSeen) < AppConstants.peerOfflineThreshold;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'publicKey': publicKey,
        'platform': platform,
        'lastSeen': lastSeen.toIso8601String(),
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
      );

  Peer copyWith({
    String? name,
    String? ip,
    int? port,
    String? publicKey,
    String? platform,
    DateTime? lastSeen,
  }) {
    return Peer(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      publicKey: publicKey ?? this.publicKey,
      platform: platform ?? this.platform,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
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

/// Represents a chat message (text or file offer)
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
  });

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
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        chatId: json['chatId'] as String,
        senderId: json['senderId'] as String,
        senderName: json['senderName'] as String? ?? 'Unknown',
        recipientId: json['recipientId'] as String,
        content: json['content'] as String? ?? '',
        type: json['type'] == 'file' ? MessageType.file : MessageType.text,
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
