import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
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
  final Map<String, Timer> _typingTimers = {};

  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  Duration _recordedDuration = Duration.zero;
  final List<double> _liveAmplitudes = [];
  String? _currentRecordingPath;

  bool get isRecordingVoice => _isRecordingVoice;
  Duration get recordedDuration => _recordedDuration;
  List<double> get liveAmplitudes => _liveAmplitudes;

  // Voice playback state
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingMessageId;
  PlayerState _playerState = PlayerState.stopped;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackTotal = Duration.zero;
  double _playbackSpeed = 1.0;

  String? get playingMessageId => _playingMessageId;
  bool isMessagePlaying(String msgId) =>
      _playingMessageId == msgId && _playerState == PlayerState.playing;
  Duration get playbackPosition => _playbackPosition;
  Duration get playbackTotal => _playbackTotal;
  double get playbackSpeed => _playbackSpeed;

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

    // Hook client duplex callbacks
    client.onDeliveryReceipt = _handleDeliveryReceipt;
    client.onTyping = _handleTyping;

    // Hook Audio Player listeners
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _playerState = state;
      notifyListeners();
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      _playbackPosition = pos;
      notifyListeners();
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      _playbackTotal = dur;
      notifyListeners();
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      _playerState = PlayerState.stopped;
      _playbackPosition = Duration.zero;
      _playingMessageId = null;
      notifyListeners();
    });

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

    if (peer != null) {
      // Mark all unread incoming messages as read & send read receipts
      final unread = database
          .getMessagesForChat(peer.id)
          .where((m) => m.senderId == peer.id && m.status != MessageStatus.read)
          .toList();
      for (final msg in unread) {
        msg.status = MessageStatus.read;
        database.saveMessage(msg);
        client.sendReadReceipt(peer, msg.id);
        server.sendReadReceipt(peer.id, msg.id);
      }
      if (unread.isNotEmpty) {
        notifyListeners();
      }
    }
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

    final pickedFile = await FilePicker.pickFile();
    if (pickedFile == null || pickedFile.path == null) return;

    final file = File(pickedFile.path!);
    final messageId = _uuid.v4();
    final fileName = pickedFile.name;
    final fileSize = await file.length();

    final ext = fileName.toLowerCase();
    final isImg = ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.bmp');
    final msgType = isImg ? MessageType.image : MessageType.file;

    final chatMessage = ChatMessage(
      id: messageId,
      chatId: _activePeer!.id,
      senderId: _deviceId,
      senderName: _deviceName,
      recipientId: _activePeer!.id,
      content: isImg ? 'Sent an image: $fileName' : 'Sent a file: $fileName',
      type: msgType,
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

  /// Starts push-to-talk voice recording with live amplitude monitoring
  Future<void> startVoiceRecording() async {
    if (_activePeer == null) return;
    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) return;

    final tempDir = await getTemporaryDirectory();
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentRecordingPath = p.join(tempDir.path, fileName);
    _liveAmplitudes.clear();
    _recordedDuration = Duration.zero;
    _recordingStartTime = DateTime.now();
    _isRecordingVoice = true;

    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _currentRecordingPath!,
    );

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_recordingStartTime != null) {
        _recordedDuration = DateTime.now().difference(_recordingStartTime!);
      }
      try {
        final amp = await _audioRecorder.getAmplitude();
        final currentDb = amp.current.clamp(-60.0, 0.0);
        final normalized = ((currentDb + 60.0) / 60.0).clamp(0.1, 1.0);
        _liveAmplitudes.add(normalized);
        if (_liveAmplitudes.length > 40) {
          _liveAmplitudes.removeAt(0);
        }
      } catch (_) {}
      notifyListeners();
    });

    notifyListeners();
  }

  /// Stops voice recording and sends voice note to active peer
  Future<void> stopAndSendVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _isRecordingVoice = false;

    final path = await _audioRecorder.stop();
    if (path == null || _currentRecordingPath == null) {
      notifyListeners();
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      notifyListeners();
      return;
    }

    final durationSeconds = _recordedDuration.inMilliseconds / 1000.0;
    if (durationSeconds < 0.5) {
      // Discard accidental clicks / recordings under 0.5s
      try {
        await file.delete();
      } catch (_) {}
      notifyListeners();
      return;
    }

    final sampledAmplitudes = List<double>.from(_liveAmplitudes);
    _liveAmplitudes.clear();
    _recordedDuration = Duration.zero;
    notifyListeners();

    await _sendVoiceMessage(file, durationSeconds, sampledAmplitudes);
  }

  /// Cancels voice recording without sending
  Future<void> cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _isRecordingVoice = false;
    _liveAmplitudes.clear();
    _recordedDuration = Duration.zero;

    try {
      await _audioRecorder.stop();
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    _currentRecordingPath = null;
    notifyListeners();
  }

  Future<void> _sendVoiceMessage(
    File file,
    double duration,
    List<double> amplitudes,
  ) async {
    if (_activePeer == null) return;
    final messageId = _uuid.v4();
    final fileName = p.basename(file.path);
    final fileSize = await file.length();

    final chatMessage = ChatMessage(
      id: messageId,
      chatId: _activePeer!.id,
      senderId: _deviceId,
      senderName: _deviceName,
      recipientId: _activePeer!.id,
      content: 'Voice message (${duration.toStringAsFixed(1)}s)',
      type: MessageType.voice,
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
      voiceDurationSeconds: duration,
      waveformAmplitudes: amplitudes,
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
      await client.sendMessage(peer: _activePeer!, message: chatMessage);
    } else {
      chatMessage.status = MessageStatus.failed;
    }
    await database.saveMessage(chatMessage);
    notifyListeners();
  }

  /// Plays a voice note file
  Future<void> playVoiceNote(ChatMessage message) async {
    final path = message.fileMetadata?.localPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;

    if (_playingMessageId == message.id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
      return;
    }

    _playingMessageId = message.id;
    await _audioPlayer.stop();
    await _audioPlayer.setPlaybackRate(_playbackSpeed);
    await _audioPlayer.play(DeviceFileSource(path));
    notifyListeners();
  }

  /// Pauses currently playing voice note
  Future<void> pauseVoiceNote() async {
    await _audioPlayer.pause();
    notifyListeners();
  }

  /// Seeks currently playing voice note
  Future<void> seekVoiceNote(Duration position) async {
    await _audioPlayer.seek(position);
  }

  /// Toggles playback speed (1.0x -> 1.5x -> 2.0x -> 1.0x)
  void togglePlaybackSpeed() {
    if (_playbackSpeed == 1.0) {
      _playbackSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      _playbackSpeed = 2.0;
    } else {
      _playbackSpeed = 1.0;
    }
    _audioPlayer.setPlaybackRate(_playbackSpeed);
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
    server.sendTypingIndicator(_activePeer!.id, isTyping);
  }

  void _handleIncomingMessage(ChatMessage message) {
    // If we have active chat open with the sender, mark as read immediately
    if (_activePeer?.id == message.senderId) {
      message.status = MessageStatus.read;
      client.sendReadReceipt(_activePeer!, message.id);
      server.sendReadReceipt(_activePeer!.id, message.id);
    }
    database.saveMessage(message);
    notifyListeners();
  }

  void _handleIncomingFileOffer(FileMetadata fileMeta, Peer sender) {
    database.savePeer(sender);

    final ext = fileMeta.fileName.toLowerCase();
    final isImg = ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.bmp');
    final msgType = isImg ? MessageType.image : MessageType.file;

    final msg = ChatMessage(
      id: _uuid.v4(),
      chatId: sender.id,
      senderId: sender.id,
      senderName: sender.name,
      recipientId: _deviceId,
      content: isImg
          ? 'Offered an image: ${fileMeta.fileName}'
          : 'Offered a file: ${fileMeta.fileName}',
      type: msgType,
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
    _typingTimers[peerId]?.cancel();
    _typingPeers[peerId] = isTyping;
    notifyListeners();

    if (isTyping) {
      _typingTimers[peerId] = Timer(const Duration(seconds: 4), () {
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
    _recordingTimer?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    if (_isInitialized) {
      discoveryService.dispose();
      server.stop();
      client.close();
      transferManager.dispose();
    }
    super.dispose();
  }
}
