import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/crypto/crypto_service.dart';
import '../core/database/app_database.dart';
import '../core/database/models.dart';
import '../core/network/discovery_service.dart';
import '../core/network/p2p_client.dart';
import '../core/network/p2p_server.dart';
import '../core/transfers/file_transfer_manager.dart';

/// Central provider orchestrating discovery, messaging, encryption, groups, and transfers
class ChatProvider extends ChangeNotifier {
  final CryptoService cryptoService = CryptoService();
  final AppDatabase database = AppDatabase();
  final _uuid = const Uuid();

  late DiscoveryService discoveryService;
  late P2pServer server;
  late P2pClient client;
  late FileTransferManager transferManager;

  String _deviceId = '';
  String _deviceName = '';
  String _platform = 'unknown';
  int _serverPort = AppConstants.defaultP2pPort;
  bool _isInitialized = false;

  // Selected chat target
  Peer? _activePeer;
  GroupChat? _activeGroup;
  final Map<String, bool> _typingPeers = {};

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get platform => _platform;
  int get serverPort => _serverPort;
  bool get isInitialized => _isInitialized;
  Peer? get activePeer => _activePeer;
  GroupChat? get activeGroup => _activeGroup;
  bool get isGroupSelected => _activeGroup != null;

  bool get isGroupHostOnline {
    if (_activeGroup == null) return true;
    if (_activeGroup!.hostId == _deviceId) return true;
    return database.knownPeers[_activeGroup!.hostId]?.isOnline ?? false;
  }

  List<ChatMessage> get activeMessages {
    if (_activeGroup != null) {
      return database.getMessagesForChat(_activeGroup!.id);
    }
    if (_activePeer != null) {
      return database.getMessagesForChat(_activePeer!.id);
    }
    return [];
  }

  bool isPeerTyping(String peerId) => _typingPeers[peerId] ?? false;

  Future<void> initialize({int? customPort, String? customDeviceName}) async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();

    // Resolve device ID
    _deviceId = prefs.getString('lan_tg_device_id') ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _uuid.v4();
      await prefs.setString('lan_tg_device_id', _deviceId);
    }

    // Resolve device name
    if (customDeviceName != null && customDeviceName.isNotEmpty) {
      _deviceName = customDeviceName;
    } else {
      _deviceName = prefs.getString('lan_tg_device_name') ?? '';
      if (_deviceName.isEmpty) {
        _deviceName = _generateDefaultDeviceName();
        await prefs.setString('lan_tg_device_name', _deviceName);
      }
    }

    // Resolve platform string
    if (Platform.isWindows) {
      _platform = 'windows';
    } else if (Platform.isMacOS) {
      _platform = 'macos';
    } else if (Platform.isLinux) {
      _platform = 'linux';
    } else if (Platform.isAndroid) {
      _platform = 'android';
    } else if (Platform.isIOS) {
      _platform = 'ios';
    }

    // 1. Initialize Cryptography
    await cryptoService.initialize();

    // 2. Initialize Persistent Database
    await database.initialize();

    // 3. Start Embedded P2P Server
    server = P2pServer(
      requestedPort: customPort ?? AppConstants.defaultP2pPort,
      deviceId: _deviceId,
      deviceName: _deviceName,
      cryptoService: cryptoService,
    );
    _serverPort = await server.start();

    // 4. Initialize P2P Client
    client = P2pClient(
      deviceId: _deviceId,
      deviceName: _deviceName,
      cryptoService: cryptoService,
    );

    // 5. Initialize File Transfer Manager
    transferManager = FileTransferManager(
      server: server,
      client: client,
      database: database,
    );

    // 6. Hook Server Callbacks
    server.onMessageReceived = _handleIncomingMessage;
    server.onFileOffered = _handleIncomingFileOffer;
    server.onDeliveryReceipt = _handleDeliveryReceipt;
    server.onTyping = _handleTyping;
    server.onGroupInvite = _handleIncomingGroupInvite;
    server.onGroupMessage = _handleIncomingGroupMessage;

    // 7. Start UDP LAN Discovery Service (Broadcast-first)
    discoveryService = DiscoveryService(
      deviceId: _deviceId,
      deviceName: _deviceName,
      p2pPort: _serverPort,
      publicKey: cryptoService.publicKeyBase64 ?? '',
      platform: _platform,
    );
    await discoveryService.start();

    _isInitialized = true;
    notifyListeners();
  }

  void setActivePeer(Peer? peer) {
    _activePeer = peer;
    _activeGroup = null;
    notifyListeners();
  }

  void setActiveGroup(GroupChat? group) {
    _activeGroup = group;
    _activePeer = null;
    notifyListeners();
  }

  /// Creates a new Group Chat where this node is Host
  Future<GroupChat> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final allMembers = {...memberIds, _deviceId}.toList();
    final group = GroupChat(
      id: _uuid.v4(),
      name: name,
      hostId: _deviceId,
      hostName: _deviceName,
      memberIds: allMembers,
      createdAt: DateTime.now(),
    );

    await database.saveGroup(group);

    // Send invitations to all members
    for (final memberId in memberIds) {
      final peer = database.knownPeers[memberId];
      if (peer != null) {
        client.sendGroupInvite(peer: peer, group: group);
      }
    }

    setActiveGroup(group);
    return group;
  }

  /// Sends a text message to active peer or active group
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (_activeGroup != null) {
      final group = _activeGroup!;
      if (!isGroupHostOnline) return; // Read-only if host is disconnected

      final messageId = _uuid.v4();
      final msg = ChatMessage(
        id: messageId,
        chatId: group.id,
        senderId: _deviceId,
        senderName: _deviceName,
        recipientId: group.id,
        content: text.trim(),
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        isGroup: true,
        groupId: group.id,
      );

      await database.saveMessage(msg);
      notifyListeners();

      if (group.hostId == _deviceId) {
        // I am host: relay to all other members
        for (final memberId in group.memberIds) {
          if (memberId == _deviceId) continue;
          final peer = database.knownPeers[memberId];
          if (peer != null && peer.isOnline) {
            client.relayGroupMessage(memberPeer: peer, group: group, message: msg);
          }
        }
      } else {
        // I am member: send to host
        final hostPeer = database.knownPeers[group.hostId];
        if (hostPeer != null && hostPeer.isOnline) {
          client.sendGroupMessage(hostPeer: hostPeer, group: group, message: msg);
        }
      }
      return;
    }

    if (_activePeer == null) return;

    final peer = _activePeer!;
    final messageId = _uuid.v4();

    final message = ChatMessage(
      id: messageId,
      chatId: peer.id,
      senderId: _deviceId,
      senderName: _deviceName,
      recipientId: peer.id,
      content: text.trim(),
      type: MessageType.text,
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
    );

    // Save locally first (optimistic UI)
    await database.saveMessage(message);
    notifyListeners();

    // Send over WebSocket to peer
    final sent = await client.sendMessage(
      peer: peer,
      message: message,
    );

    if (sent) {
      message.status = MessageStatus.sent;
    } else {
      message.status = MessageStatus.failed;
    }
    await database.saveMessage(message);
    notifyListeners();
  }

  /// Selects and sends a file attachment to the active peer
  Future<void> pickAndSendFile() async {
    if (_activePeer == null) return;

    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final messageId = _uuid.v4();
    final fileName = result.files.single.name;
    final fileSize = await file.length();

    final chatMessage = ChatMessage(
      id: messageId,
      chatId: _activePeer!.id,
      senderId: _deviceId,
      senderName: _deviceName,
      recipientId: _activePeer!.id,
      content: 'Sent a file: $fileName',
      type: MessageType.file,
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
      fileMetadata: FileMetadata(
        transferId: '',
        fileName: fileName,
        fileSize: fileSize,
        sha256: '',
        localPath: file.path,
        isCompleted: true,
      ),
    );

    await database.saveMessage(chatMessage);
    notifyListeners();

    final transferId = await transferManager.offerFile(
      peer: _activePeer!,
      file: file,
      messageId: messageId,
      myPlatform: _platform,
    );

    if (transferId != null) {
      chatMessage.fileMetadata?.isCompleted = true;
      chatMessage.status = MessageStatus.sent;
    } else {
      chatMessage.status = MessageStatus.failed;
    }
    await database.saveMessage(chatMessage);
    notifyListeners();
  }

  /// Accepts an incoming file transfer offer
  Future<void> acceptIncomingFile(ChatMessage message) async {
    if (message.fileMetadata == null) return;

    final senderPeer = database.knownPeers[message.senderId] ??
        Peer(
          id: message.senderId,
          name: message.senderName,
          ip: '127.0.0.1',
          port: AppConstants.defaultP2pPort,
          publicKey: '',
          platform: 'unknown',
          lastSeen: DateTime.now(),
        );

    await transferManager.acceptAndDownload(
      metadata: message.fileMetadata!,
      sender: senderPeer,
      messageId: message.id,
    );
    notifyListeners();
  }

  void sendTypingIndicator(bool isTyping) {
    if (_activePeer == null) return;
    client.sendTyping(_activePeer!, isTyping);
  }

  void _handleIncomingMessage(ChatMessage message) {
    database.saveMessage(message);
    notifyListeners();
  }

  void _handleIncomingFileOffer(FileMetadata fileMeta, Peer sender) {
    database.savePeer(sender);

    final msg = ChatMessage(
      id: _uuid.v4(),
      chatId: sender.id,
      senderId: sender.id,
      senderName: sender.name,
      recipientId: _deviceId,
      content: 'Offered a file: ${fileMeta.fileName}',
      type: MessageType.file,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      fileMetadata: fileMeta,
    );

    database.saveMessage(msg);
    notifyListeners();
  }

  void _handleIncomingGroupInvite(GroupChat group) {
    database.saveGroup(group);
    notifyListeners();
  }

  void _handleIncomingGroupMessage(ChatMessage msg, String groupId) {
    final group = database.getGroup(groupId);
    if (group == null) return;

    database.saveMessage(msg);
    notifyListeners();

    // If I am host, relay to other members
    if (group.hostId == _deviceId) {
      for (final memberId in group.memberIds) {
        if (memberId == _deviceId || memberId == msg.senderId) continue;
        final peer = database.knownPeers[memberId];
        if (peer != null && peer.isOnline) {
          client.relayGroupMessage(memberPeer: peer, group: group, message: msg);
        }
      }
    }
  }

  void _handleDeliveryReceipt(String messageId, MessageStatus status) {
    database.updateMessageStatus(messageId, status);
    notifyListeners();
  }

  void _handleTyping(String peerId, bool isTyping) {
    _typingPeers[peerId] = isTyping;
    notifyListeners();

    if (isTyping) {
      Timer(const Duration(seconds: 3), () {
        _typingPeers[peerId] = false;
        notifyListeners();
      });
    }
  }

  Future<void> updateDeviceName(String newName) async {
    if (newName.trim().isEmpty) return;
    _deviceName = newName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lan_tg_device_name', _deviceName);
    discoveryService.broadcastBeacon();
    notifyListeners();
  }

  String _generateDefaultDeviceName() {
    final host = Platform.localHostname;
    if (host.isNotEmpty) return host;
    return '${_platform.toUpperCase()} User';
  }

  @override
  void dispose() {
    discoveryService.dispose();
    server.stop();
    client.close();
    transferManager.dispose();
    super.dispose();
  }
}
