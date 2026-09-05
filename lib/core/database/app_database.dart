import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models.dart';

/// Persistent local storage with TOFU key pinning, groups, and message history
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  File? _messagesFile;
  File? _peersFile;
  File? _pinnedKeysFile;
  File? _groupsFile;

  final List<ChatMessage> _messages = [];
  final Map<String, Peer> _knownPeers = {};
  final Map<String, String> _pinnedKeys = {}; // deviceId -> originalPublicKey
  final Map<String, GroupChat> _groups = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Map<String, Peer> get knownPeers => Map.unmodifiable(_knownPeers);
  Map<String, String> get pinnedKeys => Map.unmodifiable(_pinnedKeys);
  List<GroupChat> get groups => _groups.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> initialize({Directory? customDirectory}) async {
    Directory dbDir;
    if (customDirectory != null) {
      dbDir = Directory(p.join(customDirectory.path, 'lan_telegram_data'));
    } else {
      try {
        final dir = await getApplicationSupportDirectory();
        dbDir = Directory(p.join(dir.path, 'lan_telegram_data'));
      } catch (_) {
        dbDir = Directory(p.join(Directory.systemTemp.path, 'lan_telegram_data'));
      }
    }
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    _messagesFile = File(p.join(dbDir.path, 'messages.json'));
    _peersFile = File(p.join(dbDir.path, 'peers.json'));
    _pinnedKeysFile = File(p.join(dbDir.path, 'pinned_keys.json'));
    _groupsFile = File(p.join(dbDir.path, 'groups.json'));

    await _loadPinnedKeys();
    await _loadPeers();
    await _loadGroups();
    await _loadMessages();
  }

  Future<void> _loadPinnedKeys() async {
    try {
      if (await _pinnedKeysFile!.exists()) {
        final content = await _pinnedKeysFile!.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> jsonMap = jsonDecode(content);
          jsonMap.forEach((key, value) {
            _pinnedKeys[key] = value.toString();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadGroups() async {
    try {
      if (await _groupsFile!.exists()) {
        final content = await _groupsFile!.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          for (final item in jsonList) {
            final group = GroupChat.fromJson(item as Map<String, dynamic>);
            _groups[group.id] = group;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPeers() async {
    try {
      if (await _peersFile!.exists()) {
        final content = await _peersFile!.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          for (final item in jsonList) {
            final peer = Peer.fromJson(item as Map<String, dynamic>);
            // Check against pinned key
            if (_pinnedKeys.containsKey(peer.id) &&
                _pinnedKeys[peer.id] != peer.publicKey &&
                peer.publicKey.isNotEmpty) {
              peer.hasIdentityConflict = true;
            }
            _knownPeers[peer.id] = peer;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      if (await _messagesFile!.exists()) {
        final content = await _messagesFile!.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          _messages.clear();
          for (final item in jsonList) {
            _messages.add(ChatMessage.fromJson(item as Map<String, dynamic>));
          }
        }
      }
    } catch (_) {}
  }

  /// Saves or updates peer while enforcing Trust-On-First-Use (TOFU) key pinning
  Future<void> savePeer(Peer peer) async {
    if (peer.publicKey.isNotEmpty) {
      if (!_pinnedKeys.containsKey(peer.id)) {
        // First contact: Pin this public key
        _pinnedKeys[peer.id] = peer.publicKey;
        await _persistPinnedKeys();
      } else if (_pinnedKeys[peer.id] != peer.publicKey) {
        // Conflict detected! The device public key changed.
        peer.hasIdentityConflict = true;
      }
    }

    _knownPeers[peer.id] = peer;
    await _persistPeers();
  }

  Future<void> saveGroup(GroupChat group) async {
    _groups[group.id] = group;
    await _persistGroups();
  }

  GroupChat? getGroup(String id) => _groups[id];

  Future<void> _persistPinnedKeys() async {
    if (_pinnedKeysFile == null) return;
    await _pinnedKeysFile!.writeAsString(jsonEncode(_pinnedKeys));
  }

  Future<void> _persistGroups() async {
    if (_groupsFile == null) return;
    final jsonList = _groups.values.map((g) => g.toJson()).toList();
    await _groupsFile!.writeAsString(jsonEncode(jsonList));
  }

  Future<void> _persistPeers() async {
    if (_peersFile == null) return;
    final jsonList = _knownPeers.values.map((p) => p.toJson()).toList();
    await _peersFile!.writeAsString(jsonEncode(jsonList));
  }

  Future<void> saveMessage(ChatMessage message) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      _messages[index] = message;
    } else {
      _messages.add(message);
    }
    await _persistMessages();
  }

  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      _messages[index].status = status;
      await _persistMessages();
    }
  }

  Future<void> markFileCompleted(String transferId, String localPath) async {
    for (final msg in _messages) {
      if (msg.fileMetadata?.transferId == transferId) {
        msg.fileMetadata?.localPath = localPath;
        msg.fileMetadata?.isCompleted = true;
        msg.status = MessageStatus.delivered;
      }
    }
    await _persistMessages();
  }

  Future<void> _persistMessages() async {
    if (_messagesFile == null) return;
    final jsonList = _messages.map((m) => m.toJson()).toList();
    await _messagesFile!.writeAsString(jsonEncode(jsonList));
  }

  List<ChatMessage> getMessagesForChat(String chatId) {
    return _messages.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }
}
