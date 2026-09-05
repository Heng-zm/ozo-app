import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../constants.dart';

enum MessageType { text, file, image, voice, sticker }
enum MessageStatus { pending, sent, delivered, read, failed }
enum TransferDirection { upload, download }
enum TransferStatus { offered, transferring, paused, completed, failed }

/// Telegram-style chat folders
enum ChatFolder {
  all,
  personal,
  groups,
  unread,
}

/// User account profile for multi-account login & profile customization
class UserAccount {
  final String id;
  final String username;
  final String displayName;
  final String bio;
  final int avatarColorIndex;
  final String avatarEmoji;
  final DateTime createdAt;
  bool isCurrent;

  UserAccount({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarColorIndex = 0,
    this.avatarEmoji = '👤',
    DateTime? createdAt,
    this.isCurrent = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'bio': bio,
        'avatarColorIndex': avatarColorIndex,
        'avatarEmoji': avatarEmoji,
        'createdAt': createdAt.toIso8601String(),
        'isCurrent': isCurrent,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        id: json['id'] as String,
        username: json['username'] as String? ?? 'user',
        displayName: json['displayName'] as String? ?? 'User',
        bio: json['bio'] as String? ?? '',
        avatarColorIndex: json['avatarColorIndex'] as int? ?? 0,
        avatarEmoji: json['avatarEmoji'] as String? ?? '👤',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        isCurrent: json['isCurrent'] as bool? ?? false,
      );

  UserAccount copyWith({
    String? id,
    String? username,
    String? displayName,
    String? bio,
    int? avatarColorIndex,
    String? avatarEmoji,
    DateTime? createdAt,
    bool? isCurrent,
  }) =>
      UserAccount(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
        avatarEmoji: avatarEmoji ?? this.avatarEmoji,
        createdAt: createdAt ?? this.createdAt,
        isCurrent: isCurrent ?? this.isCurrent,
      );
}

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
  bool isPinned;
  String? username;

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
    this.isPinned = false,
    this.username,
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
        'isPinned': isPinned,
        'username': username,
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
        isPinned: json['isPinned'] as bool? ?? false,
        username: json['username'] as String?,
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
    bool? isPinned,
    String? username,
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
      isPinned: isPinned ?? this.isPinned,
      username: username ?? this.username,
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

/// Represents a local group chat coordinated via Host-Relay with resilient backup failover
class GroupChat {
  final String id;
  final String name;
  final String hostId;
  final String hostName;
  final String? backupHostId;
  final String? backupHostName;
  final List<String> memberIds;
  final DateTime createdAt;
  final bool isPinned;

  GroupChat({
    required this.id,
    required this.name,
    required this.hostId,
    required this.hostName,
    this.backupHostId,
    this.backupHostName,
    required this.memberIds,
    required this.createdAt,
    this.isPinned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostId': hostId,
        'hostName': hostName,
        'backupHostId': backupHostId,
        'backupHostName': backupHostName,
        'memberIds': memberIds,
        'createdAt': createdAt.toIso8601String(),
        'isPinned': isPinned,
      };

  factory GroupChat.fromJson(Map<String, dynamic> json) => GroupChat(
        id: json['id'] as String,
        name: json['name'] as String,
        hostId: json['hostId'] as String,
        hostName: json['hostName'] as String? ?? 'Host',
        backupHostId: json['backupHostId'] as String?,
        backupHostName: json['backupHostName'] as String?,
        memberIds: (json['memberIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        isPinned: json['isPinned'] as bool? ?? false,
      );

  GroupChat copyWith({
    String? name,
    String? hostId,
    String? hostName,
    String? backupHostId,
    String? backupHostName,
    List<String>? memberIds,
    DateTime? createdAt,
    bool? isPinned,
  }) =>
      GroupChat(
        id: id,
        name: name ?? this.name,
        hostId: hostId ?? this.hostId,
        hostName: hostName ?? this.hostName,
        backupHostId: backupHostId ?? this.backupHostId,
        backupHostName: backupHostName ?? this.backupHostName,
        memberIds: memberIds ?? this.memberIds,
        createdAt: createdAt ?? this.createdAt,
        isPinned: isPinned ?? this.isPinned,
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
  bool get isSticker => type == MessageType.sticker;

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

/// Represents an individual expressive sticker
class StickerData {
  final String id;
  final String packId;
  final String name;
  final String emoji;
  final String assetPath;

  const StickerData({
    required this.id,
    required this.packId,
    required this.name,
    required this.emoji,
    this.assetPath = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'packId': packId,
        'name': name,
        'emoji': emoji,
        'assetPath': assetPath,
      };

  factory StickerData.fromJson(Map<String, dynamic> json) => StickerData(
        id: json['id'] as String,
        packId: json['packId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        assetPath: json['assetPath'] as String? ?? '',
      );
}

/// Represents a collection of themed stickers
class StickerPack {
  final String id;
  final String name;
  final String icon;
  final List<StickerData> stickers;

  const StickerPack({
    required this.id,
    required this.name,
    required this.icon,
    required this.stickers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'stickers': stickers.map((s) => s.toJson()).toList(),
      };

  factory StickerPack.fromJson(Map<String, dynamic> json) => StickerPack(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        stickers: (json['stickers'] as List<dynamic>?)
                ?.map((s) => StickerData.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Security & App Lock settings
class SecuritySettings {
  final bool isPinEnabled;
  final String pinHash;
  final String pinSalt;
  final int autoLockMinutes; // 0 = immediately, 1, 5, 15, -1 = never
  final bool isBiometricEnabled;

  const SecuritySettings({
    this.isPinEnabled = false,
    this.pinHash = '',
    this.pinSalt = '',
    this.autoLockMinutes = 5,
    this.isBiometricEnabled = false,
  });

  Map<String, dynamic> toJson() => {
        'isPinEnabled': isPinEnabled,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'autoLockMinutes': autoLockMinutes,
        'isBiometricEnabled': isBiometricEnabled,
      };

  factory SecuritySettings.fromJson(Map<String, dynamic> json) =>
      SecuritySettings(
        isPinEnabled: json['isPinEnabled'] as bool? ?? false,
        pinHash: json['pinHash'] as String? ?? '',
        pinSalt: json['pinSalt'] as String? ?? '',
        autoLockMinutes: json['autoLockMinutes'] as int? ?? 5,
        isBiometricEnabled: json['isBiometricEnabled'] as bool? ?? false,
      );

  SecuritySettings copyWith({
    bool? isPinEnabled,
    String? pinHash,
    String? pinSalt,
    int? autoLockMinutes,
    bool? isBiometricEnabled,
  }) =>
      SecuritySettings(
        isPinEnabled: isPinEnabled ?? this.isPinEnabled,
        pinHash: pinHash ?? this.pinHash,
        pinSalt: pinSalt ?? this.pinSalt,
        autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
        isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      );
}

/// Companion or secondary device linked to the primary account
class LinkedDevice {
  final String id;
  final String name;
  final String platform;
  final String publicKey;
  final DateTime linkedAt;
  DateTime lastSeen;

  LinkedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.linkedAt,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'publicKey': publicKey,
        'linkedAt': linkedAt.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory LinkedDevice.fromJson(Map<String, dynamic> json) => LinkedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        platform: json['platform'] as String? ?? 'unknown',
        publicKey: json['publicKey'] as String? ?? '',
        linkedAt: json['linkedAt'] != null
            ? DateTime.parse(json['linkedAt'] as String)
            : DateTime.now(),
        lastSeen: json['lastSeen'] != null
            ? DateTime.parse(json['lastSeen'] as String)
            : DateTime.now(),
      );
}

/// Metadata for Direct Hotspot & Zero-Config pairing
class DirectHotspotInfo {
  final String ssid;
  final String ip;
  final int port;
  final String deviceId;
  final String deviceName;

  const DirectHotspotInfo({
    required this.ssid,
    required this.ip,
    required this.port,
    required this.deviceId,
    required this.deviceName,
  });

  String toUriString() =>
      'ozo://hotspot?id=$deviceId&name=${Uri.encodeComponent(deviceName)}&ip=$ip&port=$port&ssid=${Uri.encodeComponent(ssid)}';

  static DirectHotspotInfo? parse(String input) {
    try {
      final uri = Uri.parse(input.trim());
      if (uri.scheme == 'ozo' && uri.host == 'hotspot') {
        final q = uri.queryParameters;
        return DirectHotspotInfo(
          ssid: q['ssid'] ?? 'OZO-Hotspot',
          ip: q['ip'] ?? '',
          port: int.tryParse(q['port'] ?? '') ?? 45455,
          deviceId: q['id'] ?? '',
          deviceName: q['name'] ?? 'Hotspot Device',
        );
      }
    } catch (_) {}
    return null;
  }
}

/// Short-lived single-use pairing token for QR-based device linking
class PairingToken {
  final String nonce;
  final String deviceId;
  final String deviceName;
  final String publicKey;
  final int timestamp;
  final int expiresAt;
  bool isConsumed;

  PairingToken({
    required this.nonce,
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
    required this.timestamp,
    required this.expiresAt,
    this.isConsumed = false,
  });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
  bool get isValid => !isConsumed && !isExpired;

  PairingToken copyWith({
    String? nonce,
    String? deviceId,
    String? deviceName,
    String? publicKey,
    int? timestamp,
    int? expiresAt,
    bool? isConsumed,
  }) {
    return PairingToken(
      nonce: nonce ?? this.nonce,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      publicKey: publicKey ?? this.publicKey,
      timestamp: timestamp ?? this.timestamp,
      expiresAt: expiresAt ?? this.expiresAt,
      isConsumed: isConsumed ?? this.isConsumed,
    );
  }

  String toUriString() =>
      'ozo://pair?id=$deviceId&name=${Uri.encodeComponent(deviceName)}&token=$nonce&ts=$timestamp&exp=$expiresAt&pk=${Uri.encodeComponent(publicKey)}';

  static PairingToken? parse(String input) {
    try {
      final uri = Uri.parse(input.trim());
      if (uri.scheme == 'ozo' && uri.host == 'pair') {
        final q = uri.queryParameters;
        final ts = int.tryParse(q['ts'] ?? '') ?? 0;
        final exp = int.tryParse(q['exp'] ?? '') ?? (ts + 90000);
        return PairingToken(
          nonce: q['token'] ?? '',
          deviceId: q['id'] ?? '',
          deviceName: q['name'] ?? 'Remote Device',
          publicKey: q['pk'] ?? '',
          timestamp: ts,
          expiresAt: exp,
        );
      }
    } catch (_) {}
    return null;
  }
}

/// Request for primary device user to explicitly approve or reject a companion link
class PairingConfirmationRequest {
  final LinkedDevice device;
  final String tokenNonce;
  final void Function() onConfirm;
  final void Function() onReject;

  const PairingConfirmationRequest({
    required this.device,
    required this.tokenNonce,
    required this.onConfirm,
    required this.onReject,
  });
}


