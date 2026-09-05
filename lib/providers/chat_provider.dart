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
import '../core/dsa/bloom_filter.dart';
import '../core/network/discovery_service.dart';
import '../core/network/p2p_client.dart';
import '../core/network/p2p_server.dart';
import '../core/security/security_service.dart';
import '../core/transfers/file_transfer_manager.dart';

/// Central provider orchestrating discovery, messaging, encryption, groups, and transfers
class ChatProvider extends ChangeNotifier {
  final CryptoService cryptoService = CryptoService();
  final AppDatabase database = AppDatabase();
  final SecurityService security = SecurityService();
  final _uuid = const Uuid();

  // High-performance Bloom Filter for packet/message deduplication
  final BloomFilter _incomingPacketBloomFilter = BloomFilter(capacity: 25000, falsePositiveRate: 0.005);
  final Set<String> _seenMessageIds = {};
  BloomFilter get incomingPacketBloomFilter => _incomingPacketBloomFilter;

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

  // Quoted Reply state
  ChatMessage? _replyingToMessage;
  ChatMessage? get replyingToMessage => _replyingToMessage;

  void setReplyingTo(ChatMessage? message) {
    _replyingToMessage = message;
    notifyListeners();
  }

  void cancelReplying() {
    _replyingToMessage = null;
    notifyListeners();
  }

  // Audio Call state
  CallStatus _callStatus = CallStatus.idle;
  Peer? _activeCallPeer;
  String? _currentCallId;
  Duration _callDuration = Duration.zero;
  Timer? _callTimer;
  bool _isCallMuted = false;
  bool _isSpeakerOn = false;

  CallStatus get callStatus => _callStatus;
  Peer? get activeCallPeer => _activeCallPeer;
  String? get currentCallId => _currentCallId;
  Duration get callDuration => _callDuration;
  bool get isCallMuted => _isCallMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get platform => _platform;
  int get serverPort => _serverPort;
  bool get isInitialized => _isInitialized;
  Peer? get activePeer => _activePeer;
  GroupChat? get activeGroup => _activeGroup;
  bool get isGroupSelected => _activeGroup != null;
  List<Peer> get discoveredPeers => database.knownPeers.values.toList();

  bool get isGroupHostOnline {
    if (_activeGroup == null) return true;
    if (_activeGroup!.hostId == _deviceId || _activeGroup!.backupHostId == _deviceId) return true;
    final hostOnline = database.knownPeers[_activeGroup!.hostId]?.isOnline ?? false;
    final backupOnline = _activeGroup!.backupHostId != null && (database.knownPeers[_activeGroup!.backupHostId!]?.isOnline ?? false);
    return hostOnline || backupOnline;
  }

  // Chat Folders
  ChatFolder _activeFolder = ChatFolder.all;
  ChatFolder get activeFolder => _activeFolder;
  void setFolder(ChatFolder folder) {
    _activeFolder = folder;
    notifyListeners();
  }

  // Quick Search
  String _searchQuery = '';
  List<ChatMessage> _searchResults = [];
  List<Peer> _searchPeerResults = [];
  String get searchQuery => _searchQuery;
  List<ChatMessage> get searchResults => _searchResults;
  List<Peer> get searchPeerResults => _searchPeerResults;

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResults = [];
      _searchPeerResults = [];
    } else {
      // Instant O(L) Prefix Trie peer lookup + SQLite FTS search
      _searchPeerResults = database.searchPeers(trimmed);
      _searchResults = await database.searchMessages(query);
    }
    notifyListeners();
  }

  // Multi-Account
  UserAccount? get currentAccount => database.currentAccount;
  List<UserAccount> get accounts => database.accounts;

  int getUnreadCount(String chatId) {
    return database.messages
        .where((m) => m.chatId == chatId && m.senderId != _deviceId && m.status != MessageStatus.read)
        .length;
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

    // 2. Initialize Persistent Database & Security
    await database.initialize();
    await security.initialize();

    // Ensure account exists
    if (database.accounts.isEmpty) {
      final initialAccount = UserAccount(
        id: _deviceId,
        username: 'user_${_deviceId.length >= 4 ? _deviceId.substring(0, 4) : 'me'}',
        displayName: _deviceName,
        bio: 'Hey there! Using ozo-app',
        avatarColorIndex: 0,
        avatarEmoji: '👤',
        isCurrent: true,
      );
      await database.saveAccount(initialAccount);
    } else {
      final active = database.currentAccount;
      if (active != null) {
        _deviceId = active.id;
        _deviceName = active.displayName;
      }
    }

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
    server.onGroupMigrated = _handleGroupMigrated;
    server.onReactionReceived = _handleIncomingReaction;
    server.onMessageDeleted = _handleIncomingMessageDeleted;
    server.onCallSignaling = _handleIncomingCallSignaling;
    server.onDevicePairRequest = _handleDevicePairRequest;
    server.onBackupReceived = _handleBackupReceived;
    server.onMessagePinned = _handleMessagePinned;
    server.onMessageUnpinned = _handleMessageUnpinned;
    server.onPeerAnnouncedViaApi = (peer) async {
      await database.upsertPeer(peer);
      notifyListeners();
    };

    // Hook client duplex callbacks
    client.onDeliveryReceipt = _handleDeliveryReceipt;
    client.onTyping = _handleTyping;
    client.onReactionReceived = _handleIncomingReaction;
    client.onMessageDeleted = _handleIncomingMessageDeleted;
    client.onCallSignaling = _handleIncomingCallSignaling;

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
    final nonHostMembers = memberIds.where((id) => id != _deviceId).toList();
    String? backupId;
    String? backupName;
    if (nonHostMembers.isNotEmpty) {
      backupId = nonHostMembers.first;
      backupName = database.knownPeers[backupId]?.name ?? 'Backup Host';
    }

    final group = GroupChat(
      id: _uuid.v4(),
      name: name,
      hostId: _deviceId,
      hostName: _deviceName,
      backupHostId: backupId,
      backupHostName: backupName,
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
      if (!isGroupHostOnline) return; // Read-only if host & backup are disconnected

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
        bool sent = false;
        if (hostPeer != null && hostPeer.isOnline) {
          sent = await client.sendGroupMessage(hostPeer: hostPeer, group: group, message: msg);
        }

        if (!sent) {
          // Host unreachable! Check failover:
          if (group.backupHostId == _deviceId) {
            // I am the backup host! Step up as the new Host
            final remainingMembers = group.memberIds.where((id) => id != _deviceId && id != group.hostId).toList();
            final nextBackupId = remainingMembers.isNotEmpty ? remainingMembers.first : null;
            final nextBackupName = nextBackupId != null ? database.knownPeers[nextBackupId]?.name : null;

            final promoted = group.copyWith(
              hostId: _deviceId,
              hostName: _deviceName,
              backupHostId: nextBackupId,
              backupHostName: nextBackupName,
            );
            await database.saveGroup(promoted);
            _activeGroup = promoted;

            // Notify all members about migration and relay message
            for (final mId in promoted.memberIds) {
              if (mId == _deviceId) continue;
              final p = database.knownPeers[mId];
              if (p != null && p.isOnline) {
                await client.sendGroupMigration(memberPeer: p, group: promoted);
                await client.relayGroupMessage(memberPeer: p, group: promoted, message: msg);
              }
            }
          } else if (group.backupHostId != null) {
            // Send to backup host
            final backupPeer = database.knownPeers[group.backupHostId!];
            if (backupPeer != null && backupPeer.isOnline) {
              await client.sendGroupMessage(hostPeer: backupPeer, group: group, message: msg);
            }
          }
        }
      }
      return;
    }

    if (_activePeer == null) return;

    final peer = _activePeer!;
    final messageId = _uuid.v4();

    final replyId = _replyingToMessage?.id;
    final replyText = _replyingToMessage?.content;
    final replySender = _replyingToMessage?.senderName;
    _replyingToMessage = null;

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
      replyToId: replyId,
      replyToText: replyText,
      replyToSenderName: replySender,
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

  /// Sends a file to the active peer (used by both picker and desktop drag-and-drop)
  Future<void> sendFile(File file) async {
    if (_activePeer == null) return;
    if (!await file.exists()) return;

    final messageId = _uuid.v4();
    final fileName = file.uri.pathSegments.last;
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

  /// Selects and sends a file attachment to the active peer
  Future<void> pickAndSendFile() async {
    if (_activePeer == null) return;

    final pickedFile = await FilePicker.pickFile();
    if (pickedFile == null || pickedFile.path == null) return;

    await sendFile(File(pickedFile.path!));
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
    // Fast O(1) deduplication check using Bloom filter & exact set
    if (_incomingPacketBloomFilter.mightContain(message.id)) {
      if (_seenMessageIds.contains(message.id)) {
        return; // Duplicate packet dropped
      }
    }
    _incomingPacketBloomFilter.add(message.id);
    _seenMessageIds.add(message.id);
    if (_seenMessageIds.length > 5000) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }

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

    // Fast O(1) deduplication check for group relays
    if (_incomingPacketBloomFilter.mightContain(msg.id)) {
      if (_seenMessageIds.contains(msg.id)) {
        return; // Duplicate group relay dropped!
      }
    }
    _incomingPacketBloomFilter.add(msg.id);
    _seenMessageIds.add(msg.id);
    if (_seenMessageIds.length > 5000) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }

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

  void _handleGroupMigrated(
    String groupId,
    String newHostId,
    String newHostName,
    String? newBackupHostId,
    String? newBackupHostName,
  ) {
    database.updateGroupHost(groupId, newHostId, newHostName, newBackupHostId, newBackupHostName);
    if (_activeGroup?.id == groupId) {
      _activeGroup = database.getGroup(groupId);
    }
    notifyListeners();
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

  PairingToken? _activePairingToken;
  PairingToken get activePairingToken => _activePairingToken ?? createPairingToken();

  PairingConfirmationRequest? _pendingPairingRequest;
  PairingConfirmationRequest? get pendingPairingRequest => _pendingPairingRequest;

  PairingToken createPairingToken() {
    final nonce = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final token = PairingToken(
      nonce: nonce,
      deviceId: _deviceId,
      deviceName: _deviceName,
      publicKey: cryptoService.publicKeyBase64 ?? '',
      timestamp: now,
      expiresAt: now + 90000, // 90-second single-use token
    );
    _activePairingToken = token;
    notifyListeners();
    return token;
  }

  void clearPendingPairingRequest() {
    _pendingPairingRequest = null;
    notifyListeners();
  }

  void _handleDevicePairRequest(LinkedDevice device, String token) {
    if (_activePairingToken == null || !_activePairingToken!.isValid) {
      if (kDebugMode) print('Pairing request rejected: token invalid or expired');
      return;
    }
    if (_activePairingToken!.nonce != token) {
      if (kDebugMode) print('Pairing request rejected: token mismatch');
      return;
    }

    // Invalidate token immediately to prevent replay attacks
    _activePairingToken!.isConsumed = true;

    // Require explicit confirmation from the primary device user
    _pendingPairingRequest = PairingConfirmationRequest(
      device: device,
      tokenNonce: token,
      onConfirm: () async {
        await database.saveLinkedDevice(device);
        _pendingPairingRequest = null;
        notifyListeners();
      },
      onReject: () {
        _pendingPairingRequest = null;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void _handleBackupReceived(Map<String, dynamic> backup) {
    notifyListeners();
  }

  void _handleMessagePinned(String chatId, String messageId) {
    database.pinChatMessage(chatId, messageId);
    notifyListeners();
  }

  void _handleMessageUnpinned(String chatId, [String? messageId]) {
    database.unpinChatMessage(chatId, messageId);
    notifyListeners();
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

  /// Connects to a remote peer via Cloudflare Tunnel URL, invite link, or IP:Port
  Future<bool> connectToRemotePeer(String input) async {
    final link = PeerConnectionLink.parse(input);
    if (link == null) return false;

    final peer = Peer(
      id: link.id,
      name: link.name,
      ip: link.host,
      port: link.port,
      publicKey: link.publicKey,
      platform: link.platform,
      lastSeen: DateTime.now(),
      isRemote: true,
      remoteTunnelUrl: link.isSecure
          ? 'https://${link.host}'
          : (link.port == 443 ? 'https://${link.host}' : 'http://${link.host}:${link.port}'),
    );

    await database.upsertPeer(peer);
    setActivePeer(peer);
    notifyListeners();

    final socket = await client.getOrConnect(peer);
    return socket != null;
  }

  /// Toggles an emoji reaction on a message and broadcasts to peer
  Future<void> toggleReaction(String messageId, String emoji) async {
    final chatMessages = activeMessages;
    final index = chatMessages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;

    final msg = chatMessages[index];
    final list = List<String>.from(msg.reactions[emoji] ?? []);
    if (list.contains(_deviceId)) {
      list.remove(_deviceId);
      if (list.isEmpty) {
        msg.reactions.remove(emoji);
      } else {
        msg.reactions[emoji] = list;
      }
    } else {
      list.add(_deviceId);
      msg.reactions[emoji] = list;
    }

    await database.updateMessageReactions(messageId, msg.reactions);
    notifyListeners();

    if (_activePeer != null) {
      await client.sendReaction(
        peer: _activePeer!,
        messageId: messageId,
        emoji: emoji,
      );
    }
  }

  void _handleIncomingReaction(String messageId, String emoji, String senderId) {
    for (final msg in database.messages) {
      if (msg.id == messageId) {
        final list = List<String>.from(msg.reactions[emoji] ?? []);
        if (!list.contains(senderId)) {
          list.add(senderId);
          msg.reactions[emoji] = list;
          database.updateMessageReactions(messageId, msg.reactions);
          notifyListeners();
        }
        break;
      }
    }
  }

  /// Deletes a message locally and sends a delete packet to the peer
  Future<void> deleteMessageForEveryone(String messageId) async {
    await database.deleteMessage(messageId);
    notifyListeners();

    if (_activePeer != null) {
      await client.sendDeleteMessage(
        peer: _activePeer!,
        messageId: messageId,
      );
    }
  }

  void _handleIncomingMessageDeleted(String messageId) {
    database.deleteMessage(messageId);
    notifyListeners();
  }

  // --- Voice Call Methods ---
  void toggleCallMute() {
    _isCallMuted = !_isCallMuted;
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    notifyListeners();
  }

  Future<void> startCall(Peer peer) async {
    _activeCallPeer = peer;
    _currentCallId = _uuid.v4();
    _callStatus = CallStatus.outgoingCalling;
    _callDuration = Duration.zero;
    _isCallMuted = false;
    _isSpeakerOn = false;
    notifyListeners();

    final signaling = CallSignaling(
      callId: _currentCallId!,
      callerId: _deviceId,
      callerName: _deviceName,
      type: 'CALL_OFFER',
    );

    await client.sendCallSignaling(peer: peer, signaling: signaling);
  }

  Future<void> acceptCall() async {
    if (_activeCallPeer == null || _currentCallId == null) return;
    _callStatus = CallStatus.connected;
    _startCallTimer();
    notifyListeners();

    final signaling = CallSignaling(
      callId: _currentCallId!,
      callerId: _deviceId,
      callerName: _deviceName,
      type: 'CALL_ANSWER',
      accepted: true,
    );

    await client.sendCallSignaling(peer: _activeCallPeer!, signaling: signaling);
  }

  Future<void> declineCall() async {
    if (_activeCallPeer != null && _currentCallId != null) {
      final signaling = CallSignaling(
        callId: _currentCallId!,
        callerId: _deviceId,
        callerName: _deviceName,
        type: 'CALL_REJECT',
        accepted: false,
      );
      await client.sendCallSignaling(peer: _activeCallPeer!, signaling: signaling);
    }
    _endCallInternal();
  }

  Future<void> endCall() async {
    if (_activeCallPeer != null && _currentCallId != null) {
      final signaling = CallSignaling(
        callId: _currentCallId!,
        callerId: _deviceId,
        callerName: _deviceName,
        type: 'CALL_END',
      );
      await client.sendCallSignaling(peer: _activeCallPeer!, signaling: signaling);
    }
    _endCallInternal();
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callDuration = Duration.zero;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _endCallInternal() {
    _callTimer?.cancel();
    _callTimer = null;
    _callStatus = CallStatus.idle;
    _activeCallPeer = null;
    _currentCallId = null;
    _callDuration = Duration.zero;
    notifyListeners();
  }

  void _handleIncomingCallSignaling(CallSignaling signaling) {
    switch (signaling.type) {
      case 'CALL_OFFER':
        if (_callStatus == CallStatus.idle) {
          _currentCallId = signaling.callId;
          final peer = database.knownPeers[signaling.callerId] ??
              Peer(
                id: signaling.callerId,
                name: signaling.callerName,
                ip: '',
                port: 45455,
                publicKey: '',
                platform: 'unknown',
                lastSeen: DateTime.now(),
              );
          _activeCallPeer = peer;
          _callStatus = CallStatus.incomingRinging;
          notifyListeners();
        }
        break;
      case 'CALL_ANSWER':
        if (_callStatus == CallStatus.outgoingCalling &&
            signaling.callId == _currentCallId &&
            signaling.accepted == true) {
          _callStatus = CallStatus.connected;
          _startCallTimer();
          notifyListeners();
        } else {
          _endCallInternal();
        }
        break;
      case 'CALL_REJECT':
      case 'CALL_END':
        if (signaling.callId == _currentCallId) {
          _endCallInternal();
        }
        break;
    }
  }

  // --- Chat Pinning ---
  Future<void> togglePin(String id, bool isGroup) async {
    if (isGroup) {
      await database.toggleGroupPin(id);
      if (_activeGroup?.id == id) {
        _activeGroup = database.getGroup(id);
      }
    } else {
      await database.togglePeerPin(id);
      if (_activePeer?.id == id) {
        _activePeer = database.knownPeers[id];
      }
    }
    notifyListeners();
  }

  // --- Multi-Account Profile Management ---
  Future<void> createAccount({
    required String username,
    required String displayName,
    String bio = '',
    int avatarColorIndex = 0,
    String avatarEmoji = '👤',
  }) async {
    final account = UserAccount(
      id: _uuid.v4(),
      username: username.replaceAll('@', '').trim(),
      displayName: displayName.trim(),
      bio: bio.trim(),
      avatarColorIndex: avatarColorIndex,
      avatarEmoji: avatarEmoji,
      isCurrent: true,
    );
    await database.saveAccount(account);
    _deviceId = account.id;
    _deviceName = account.displayName;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lan_tg_device_id', _deviceId);
    await prefs.setString('lan_tg_device_name', _deviceName);

    if (_isInitialized) {
      discoveryService.updateIdentity(deviceId: _deviceId, deviceName: _deviceName);
    }
    _activePeer = null;
    _activeGroup = null;
    notifyListeners();
  }

  Future<void> switchAccount(String accountId) async {
    await database.switchAccount(accountId);
    final active = database.currentAccount;
    if (active != null) {
      _deviceId = active.id;
      _deviceName = active.displayName;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lan_tg_device_id', _deviceId);
      await prefs.setString('lan_tg_device_name', _deviceName);

      if (_isInitialized) {
        discoveryService.updateIdentity(deviceId: _deviceId, deviceName: _deviceName);
      }
      _activePeer = null;
      _activeGroup = null;
    }
    notifyListeners();
  }

  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    int? avatarColorIndex,
    String? avatarEmoji,
  }) async {
    final active = database.currentAccount;
    if (active == null) return;
    final updated = active.copyWith(
      displayName: displayName,
      username: username?.replaceAll('@', ''),
      bio: bio,
      avatarColorIndex: avatarColorIndex,
      avatarEmoji: avatarEmoji,
    );
    await database.saveAccount(updated);
    if (displayName != null && displayName.isNotEmpty) {
      _deviceName = displayName;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lan_tg_device_name', _deviceName);
      if (_isInitialized) {
        discoveryService.updateIdentity(deviceName: _deviceName);
      }
    }
    notifyListeners();
  }

  Future<void> deleteAccount(String accountId) async {
    await database.deleteAccount(accountId);
    final active = database.currentAccount;
    if (active != null) {
      _deviceId = active.id;
      _deviceName = active.displayName;
      if (_isInitialized) {
        discoveryService.updateIdentity(deviceId: _deviceId, deviceName: _deviceName);
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pinned Messages
  // ---------------------------------------------------------------------------

  ChatMessage? getPinnedMessage(String chatId) => database.getPinnedMessage(chatId);
  List<ChatMessage> getPinnedMessages(String chatId) => database.getPinnedMessages(chatId);
  String? getPinnedMessageId(String chatId) => database.getPinnedMessageId(chatId);
  List<String> getPinnedMessageIds(String chatId) => database.getPinnedMessageIds(chatId);

  Future<void> pinMessage(String chatId, String messageId) async {
    await database.pinChatMessage(chatId, messageId);
    final peer = database.knownPeers[chatId];
    if (peer != null) {
      client.sendPinMessage(peer, chatId: chatId, messageId: messageId);
    }
    notifyListeners();
  }

  Future<void> unpinMessage(String chatId, [String? messageId]) async {
    await database.unpinChatMessage(chatId, messageId);
    final peer = database.knownPeers[chatId];
    if (peer != null) {
      client.sendUnpinMessage(peer, chatId: chatId);
    }
    notifyListeners();
  }

  Future<void> unpinAllMessages(String chatId) async {
    await database.unpinAllChatMessages(chatId);
    final peer = database.knownPeers[chatId];
    if (peer != null) {
      client.sendUnpinMessage(peer, chatId: chatId);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Stickers
  // ---------------------------------------------------------------------------

  Future<void> sendStickerMessage(String recipientId, StickerData sticker) async {
    final messageId = _uuid.v4();
    final message = ChatMessage(
      id: messageId,
      chatId: recipientId,
      senderId: _deviceId,
      senderName: _deviceName,
      recipientId: recipientId,
      content: sticker.emoji,
      type: MessageType.sticker,
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
      isGroup: _activeGroup != null,
      groupId: _activeGroup?.id,
    );

    await database.saveMessage(message);
    notifyListeners();

    if (_activeGroup != null) {
      final group = _activeGroup!;
      if (group.hostId == _deviceId) {
        for (final mId in group.memberIds) {
          if (mId == _deviceId) continue;
          final p = database.knownPeers[mId];
          if (p != null && p.isOnline) {
            await client.relayGroupMessage(memberPeer: p, group: group, message: message);
          }
        }
      } else {
        final hostPeer = database.knownPeers[group.hostId];
        if (hostPeer != null && hostPeer.isOnline) {
          await client.sendGroupMessage(hostPeer: hostPeer, group: group, message: message);
        }
      }
      return;
    }

    final peer = database.knownPeers[recipientId];
    if (peer != null) {
      final sent = await client.sendMessage(
        peer: peer,
        message: message,
      );
      if (sent) {
        message.status = MessageStatus.sent;
        await database.saveMessage(message);
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Routerless Direct Hotspot Info
  // ---------------------------------------------------------------------------

  Future<DirectHotspotInfo> getDirectHotspotInfo() async {
    final ip = await discoveryService.getLocalIpAddress();
    return DirectHotspotInfo(
      ssid: 'OZO-${_deviceName.replaceAll(' ', '_')}',
      ip: ip,
      port: server.port,
      deviceId: _deviceId,
      deviceName: _deviceName,
    );
  }

  // ---------------------------------------------------------------------------
  // Linked Devices
  // ---------------------------------------------------------------------------

  List<LinkedDevice> get linkedDevices => database.linkedDevices;

  Future<void> pairWithPeer(Peer peer, {String? token}) async {
    final dev = LinkedDevice(
      id: peer.id,
      name: peer.name,
      platform: peer.platform,
      publicKey: peer.publicKey,
      linkedAt: DateTime.now(),
    );
    await database.saveLinkedDevice(dev);
    await client.sendDevicePairing(
      peer,
      id: _deviceId,
      name: _deviceName,
      platform: _platform,
      pubKey: cryptoService.publicKeyBase64 ?? '',
      token: token,
    );
    notifyListeners();
  }

  Future<void> removeLinkedDevice(String id) async {
    await database.deleteLinkedDevice(id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Encrypted Backup & Migration
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> exportBackup(String password) async {
    return database.exportEncryptedBackup(password);
  }

  Future<bool> importBackup(Map<String, dynamic> container, String password) async {
    final success = await database.importEncryptedBackup(container, password);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  Future<bool> migrateToPeer(Peer peer, String password) async {
    final backup = await database.exportEncryptedBackup(password);
    return client.sendBackupMigration(peer, backup);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _callTimer?.cancel();
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
