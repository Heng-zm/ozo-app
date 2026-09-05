import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models.dart';

/// Persistent local storage for messages, peers, and transfers
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  File? _messagesFile;
  File? _peersFile;

  final List<ChatMessage> _messages = [];
  final Map<String, Peer> _knownPeers = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Map<String, Peer> get knownPeers => Map.unmodifiable(_knownPeers);

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

    await _loadPeers();
    await _loadMessages();
  }

  Future<void> _loadPeers() async {
    try {
      if (await _peersFile!.exists()) {
        final content = await _peersFile!.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          for (final item in jsonList) {
            final peer = Peer.fromJson(item as Map<String, dynamic>);
            _knownPeers[peer.id] = peer;
          }
        }
      }
    } catch (e) {
      // Ignored or corrupted file recovery
    }
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
    } catch (e) {
      // Recover cleanly
    }
  }

  Future<void> savePeer(Peer peer) async {
    _knownPeers[peer.id] = peer;
    await _persistPeers();
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
