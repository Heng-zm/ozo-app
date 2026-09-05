import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../dsa/bloom_filter.dart';
import '../dsa/lru_cache.dart';
import '../dsa/prefix_trie.dart';
import 'models.dart';

/// Persistent local storage backed by high-performance SQLite with WAL mode,
/// Full-Text Search (FTS), TOFU key pinning, groups failover, and multi-account support.
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  sqflite.Database? _db;

  final List<ChatMessage> _messages = [];
  final Map<String, int> _messageIndexById = {};
  final LruCache<String, ChatMessage> _messageLruCache = LruCache(capacity: 1000);
  final BloomFilter _messageBloomFilter = BloomFilter(capacity: 25000, falsePositiveRate: 0.01);
  final PrefixTrie<Peer> _peerTrie = PrefixTrie<Peer>();

  final Map<String, Peer> _knownPeers = {};
  final Map<String, String> _pinnedKeys = {}; // deviceId -> originalPublicKey
  final Map<String, GroupChat> _groups = {};
  final List<UserAccount> _accounts = [];
  final Map<String, List<String>> _pinnedChatMessages = {}; // chatId -> list of messageIds
  final List<LinkedDevice> _linkedDevices = [];

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  LruCache<String, ChatMessage> get messageCache => _messageLruCache;
  BloomFilter get messageBloomFilter => _messageBloomFilter;
  PrefixTrie<Peer> get peerTrie => _peerTrie;
  Map<String, Peer> get knownPeers => Map.unmodifiable(_knownPeers);
  Map<String, String> get pinnedKeys => Map.unmodifiable(_pinnedKeys);
  List<GroupChat> get groups => _groups.values.toList()
    ..sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  List<UserAccount> get accounts => List.unmodifiable(_accounts);
  Map<String, List<String>> get pinnedChatMessages => Map.unmodifiable(_pinnedChatMessages);
  List<LinkedDevice> get linkedDevices => List.unmodifiable(_linkedDevices);

  UserAccount? get currentAccount {
    try {
      return _accounts.firstWhere((a) => a.isCurrent);
    } catch (_) {
      return _accounts.isNotEmpty ? _accounts.first : null;
    }
  }

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

    // Initialize FFI on desktop platforms (Windows, Linux, macOS)
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      sqflite.databaseFactory = databaseFactoryFfi;
    }

    final dbPath = p.join(dbDir.path, 'lan_telegram.db');
    _db = await sqflite.openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Enable WAL mode for high concurrency read/write
    try {
      await _db!.execute('PRAGMA journal_mode=WAL;');
      await _db!.execute('PRAGMA synchronous=NORMAL;');
    } catch (_) {}

    // Ensure auxiliary tables exist
    await _createAuxiliaryTables(_db!);

    // Load in-memory caches from SQLite
    await _loadAccountsFromDb();
    await _loadPinnedKeysFromDb();
    await _loadPeersFromDb();
    await _loadGroupsFromDb();
    await _loadMessagesFromDb();
    await _loadPinnedChatMessagesFromDb();
    await _loadLinkedDevicesFromDb();

    // Check if legacy JSON files exist and import them if SQLite is fresh
    await _migrateLegacyJsonIfPresent(dbDir);
  }

  Future<void> _createAuxiliaryTables(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_pinned_messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        pinned_at INTEGER NOT NULL,
        pin_order INTEGER NOT NULL,
        UNIQUE(chat_id, message_id)
      );
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pinned_chat_order ON chat_pinned_messages(chat_id, pin_order ASC);');
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS linked_devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        platform TEXT,
        public_key TEXT,
        linked_at INTEGER NOT NULL,
        last_seen INTEGER NOT NULL
      );
    ''');
  }

  Future<void> _onUpgrade(sqflite.Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_pinned_messages_v2 (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            pinned_at INTEGER NOT NULL,
            pin_order INTEGER NOT NULL,
            UNIQUE(chat_id, message_id)
          );
        ''');
        final oldRows = await db.query('chat_pinned_messages');
        int order = 0;
        for (final row in oldRows) {
          final chatId = row['chat_id'] as String;
          final msgId = row['message_id'] as String;
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.insert(
            'chat_pinned_messages_v2',
            {
              'id': '${chatId}_$msgId',
              'chat_id': chatId,
              'message_id': msgId,
              'pinned_at': now,
              'pin_order': order++,
            },
            conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
          );
        }
        await db.execute('DROP TABLE IF EXISTS chat_pinned_messages;');
        await db.execute('ALTER TABLE chat_pinned_messages_v2 RENAME TO chat_pinned_messages;');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pinned_chat_order ON chat_pinned_messages(chat_id, pin_order ASC);');
      } catch (_) {
        await _createAuxiliaryTables(db);
      }
    }
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await _createAuxiliaryTables(db);
    // Accounts Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        bio TEXT,
        avatar_color_index INTEGER DEFAULT 0,
        avatar_emoji TEXT DEFAULT '👤',
        created_at INTEGER NOT NULL,
        is_current INTEGER DEFAULT 0
      );
    ''');

    // Peers Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        public_key TEXT,
        platform TEXT,
        last_seen INTEGER NOT NULL,
        is_remote INTEGER DEFAULT 0,
        remote_tunnel_url TEXT,
        is_pinned INTEGER DEFAULT 0,
        username TEXT
      );
    ''');

    // TOFU Pinned Keys Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pinned_keys (
        device_id TEXT PRIMARY KEY,
        public_key TEXT NOT NULL
      );
    ''');

    // Groups Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        host_id TEXT NOT NULL,
        host_name TEXT NOT NULL,
        backup_host_id TEXT,
        backup_host_name TEXT,
        member_ids_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_pinned INTEGER DEFAULT 0
      );
    ''');

    // Messages Table with indexes
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        recipient_id TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        file_metadata_json TEXT,
        is_group INTEGER DEFAULT 0,
        group_id TEXT,
        voice_duration REAL,
        waveform_json TEXT,
        reply_to_id TEXT,
        reply_to_text TEXT,
        reply_to_sender_name TEXT,
        reactions_json TEXT
      );
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_msg_chat_time ON messages(chat_id, timestamp DESC);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_msg_content ON messages(content);');

    // Full-Text Search (FTS5) table
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
          id UNINDEXED,
          chat_id UNINDEXED,
          content
        );
      ''');
    } catch (_) {
      // If FTS5 is unsupported on older platforms, fallback cleanly to standard indexed LIKE query
    }
  }

  // ---------------------------------------------------------------------------
  // Account Management
  // ---------------------------------------------------------------------------

  Future<void> _loadAccountsFromDb() async {
    if (_db == null) return;
    final rows = await _db!.query('accounts', orderBy: 'created_at ASC');
    _accounts.clear();
    for (final row in rows) {
      _accounts.add(UserAccount(
        id: row['id'] as String,
        username: row['username'] as String,
        displayName: row['display_name'] as String,
        bio: row['bio'] as String? ?? '',
        avatarColorIndex: row['avatar_color_index'] as int? ?? 0,
        avatarEmoji: row['avatar_emoji'] as String? ?? '👤',
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        isCurrent: (row['is_current'] as int? ?? 0) == 1,
      ));
    }
  }

  Future<void> saveAccount(UserAccount account) async {
    if (_db == null) return;

    if (account.isCurrent) {
      await _db!.update('accounts', {'is_current': 0});
      for (final a in _accounts) {
        a.isCurrent = false;
      }
    }

    await _db!.insert(
      'accounts',
      {
        'id': account.id,
        'username': account.username,
        'display_name': account.displayName,
        'bio': account.bio,
        'avatar_color_index': account.avatarColorIndex,
        'avatar_emoji': account.avatarEmoji,
        'created_at': account.createdAt.millisecondsSinceEpoch,
        'is_current': account.isCurrent ? 1 : 0,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );

    final idx = _accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      _accounts[idx] = account;
    } else {
      _accounts.add(account);
    }
  }

  Future<void> switchAccount(String accountId) async {
    if (_db == null) return;
    await _db!.update('accounts', {'is_current': 0});
    await _db!.update('accounts', {'is_current': 1}, where: 'id = ?', whereArgs: [accountId]);
    for (final a in _accounts) {
      a.isCurrent = (a.id == accountId);
    }
  }

  Future<void> deleteAccount(String accountId) async {
    if (_db == null) return;
    await _db!.delete('accounts', where: 'id = ?', whereArgs: [accountId]);
    _accounts.removeWhere((a) => a.id == accountId);
    if (_accounts.isNotEmpty && currentAccount == null) {
      await switchAccount(_accounts.first.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Pinned Keys (TOFU)
  // ---------------------------------------------------------------------------

  Future<void> _loadPinnedKeysFromDb() async {
    if (_db == null) return;
    final rows = await _db!.query('pinned_keys');
    _pinnedKeys.clear();
    for (final row in rows) {
      _pinnedKeys[row['device_id'] as String] = row['public_key'] as String;
    }
  }

  Future<void> _persistPinnedKey(String deviceId, String publicKey) async {
    if (_db == null) return;
    await _db!.insert(
      'pinned_keys',
      {'device_id': deviceId, 'public_key': publicKey},
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // Peers
  // ---------------------------------------------------------------------------

  Future<void> _loadPeersFromDb() async {
    if (_db == null) return;
    final rows = await _db!.query('peers');
    _knownPeers.clear();
    _peerTrie.clear();
    for (final row in rows) {
      final peer = Peer(
        id: row['id'] as String,
        name: row['name'] as String,
        ip: row['ip'] as String,
        port: row['port'] as int,
        publicKey: row['public_key'] as String? ?? '',
        platform: row['platform'] as String? ?? 'unknown',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(row['last_seen'] as int),
        isRemote: (row['is_remote'] as int? ?? 0) == 1,
        remoteTunnelUrl: row['remote_tunnel_url'] as String?,
        isPinned: (row['is_pinned'] as int? ?? 0) == 1,
        username: row['username'] as String?,
      );

      if (_pinnedKeys.containsKey(peer.id) &&
          _pinnedKeys[peer.id] != peer.publicKey &&
          peer.publicKey.isNotEmpty) {
        peer.hasIdentityConflict = true;
      }
      _knownPeers[peer.id] = peer;
      _peerTrie.insert(peer.name, peer);
      if (peer.username != null && peer.username!.isNotEmpty) {
        _peerTrie.insert(peer.username!, peer);
      }
    }
  }

  Future<void> savePeer(Peer peer) async {
    if (peer.publicKey.isNotEmpty) {
      if (!_pinnedKeys.containsKey(peer.id)) {
        _pinnedKeys[peer.id] = peer.publicKey;
        await _persistPinnedKey(peer.id, peer.publicKey);
      } else if (_pinnedKeys[peer.id] != peer.publicKey) {
        peer.hasIdentityConflict = true;
      }
    }

    _knownPeers[peer.id] = peer;
    _peerTrie.insert(peer.name, peer);
    if (peer.username != null && peer.username!.isNotEmpty) {
      _peerTrie.insert(peer.username!, peer);
    }

    if (_db != null) {
      await _db!.insert(
        'peers',
        {
          'id': peer.id,
          'name': peer.name,
          'ip': peer.ip,
          'port': peer.port,
          'public_key': peer.publicKey,
          'platform': peer.platform,
          'last_seen': peer.lastSeen.millisecondsSinceEpoch,
          'is_remote': peer.isRemote ? 1 : 0,
          'remote_tunnel_url': peer.remoteTunnelUrl,
          'is_pinned': peer.isPinned ? 1 : 0,
          'username': peer.username,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
  }

  /// O(L) fast prefix search over known peers using in-memory Prefix Trie.
  List<Peer> searchPeers(String prefix, {int limit = 20}) {
    return _peerTrie.searchPrefix(prefix, limit: limit);
  }

  Future<void> upsertPeer(Peer peer) => savePeer(peer);

  Future<void> togglePeerPin(String peerId) async {
    final peer = _knownPeers[peerId];
    if (peer == null) return;
    peer.isPinned = !peer.isPinned;
    if (_db != null) {
      await _db!.update(
        'peers',
        {'is_pinned': peer.isPinned ? 1 : 0},
        where: 'id = ?',
        whereArgs: [peerId],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Groups & Resilient Failover
  // ---------------------------------------------------------------------------

  Future<void> _loadGroupsFromDb() async {
    if (_db == null) return;
    final rows = await _db!.query('groups');
    _groups.clear();
    for (final row in rows) {
      final members = (jsonDecode(row['member_ids_json'] as String) as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      final group = GroupChat(
        id: row['id'] as String,
        name: row['name'] as String,
        hostId: row['host_id'] as String,
        hostName: row['host_name'] as String,
        backupHostId: row['backup_host_id'] as String?,
        backupHostName: row['backup_host_name'] as String?,
        memberIds: members,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        isPinned: (row['is_pinned'] as int? ?? 0) == 1,
      );
      _groups[group.id] = group;
    }
  }

  Future<void> saveGroup(GroupChat group) async {
    _groups[group.id] = group;
    if (_db != null) {
      await _db!.insert(
        'groups',
        {
          'id': group.id,
          'name': group.name,
          'host_id': group.hostId,
          'host_name': group.hostName,
          'backup_host_id': group.backupHostId,
          'backup_host_name': group.backupHostName,
          'member_ids_json': jsonEncode(group.memberIds),
          'created_at': group.createdAt.millisecondsSinceEpoch,
          'is_pinned': group.isPinned ? 1 : 0,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
  }

  GroupChat? getGroup(String id) => _groups[id];

  Future<void> updateGroupHost(
    String groupId,
    String newHostId,
    String newHostName,
    String? newBackupHostId,
    String? newBackupHostName,
  ) async {
    final existing = _groups[groupId];
    if (existing == null) return;
    final updated = existing.copyWith(
      hostId: newHostId,
      hostName: newHostName,
      backupHostId: newBackupHostId,
      backupHostName: newBackupHostName,
    );
    await saveGroup(updated);
  }

  Future<void> toggleGroupPin(String groupId) async {
    final group = _groups[groupId];
    if (group == null) return;
    final updated = group.copyWith(isPinned: !group.isPinned);
    await saveGroup(updated);
  }

  // ---------------------------------------------------------------------------
  // Messages & Full-Text Search (FTS)
  // ---------------------------------------------------------------------------

  Future<void> _loadMessagesFromDb() async {
    if (_db == null) return;
    final rows = await _db!.query('messages', orderBy: 'timestamp ASC');
    _messages.clear();
    _messageIndexById.clear();
    _messageLruCache.clear();
    _messageBloomFilter.reset();
    for (final row in rows) {
      final msg = _rowToChatMessage(row);
      _messageIndexById[msg.id] = _messages.length;
      _messages.add(msg);
      _messageLruCache.put(msg.id, msg);
      _messageBloomFilter.add(msg.id);
    }
  }

  ChatMessage _rowToChatMessage(Map<String, dynamic> row) {
    Map<String, List<String>> reactions = {};
    if (row['reactions_json'] != null) {
      try {
        final decoded = jsonDecode(row['reactions_json'] as String) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val is List) {
            reactions[key] = val.map((e) => e.toString()).toList();
          }
        });
      } catch (_) {}
    }

    FileMetadata? fileMetadata;
    if (row['file_metadata_json'] != null) {
      try {
        fileMetadata = FileMetadata.fromJson(
            jsonDecode(row['file_metadata_json'] as String) as Map<String, dynamic>);
      } catch (_) {}
    }

    List<double>? waveform;
    if (row['waveform_json'] != null) {
      try {
        waveform = (jsonDecode(row['waveform_json'] as String) as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
      } catch (_) {}
    }

    return ChatMessage(
      id: row['id'] as String,
      chatId: row['chat_id'] as String,
      senderId: row['sender_id'] as String,
      senderName: row['sender_name'] as String,
      recipientId: row['recipient_id'] as String,
      content: row['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == row['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == row['status'],
        orElse: () => MessageStatus.delivered,
      ),
      fileMetadata: fileMetadata,
      isGroup: (row['is_group'] as int? ?? 0) == 1,
      groupId: row['group_id'] as String?,
      voiceDurationSeconds: (row['voice_duration'] as num?)?.toDouble(),
      waveformAmplitudes: waveform,
      replyToId: row['reply_to_id'] as String?,
      replyToText: row['reply_to_text'] as String?,
      replyToSenderName: row['reply_to_sender_name'] as String?,
      reactions: reactions,
    );
  }

  Map<String, dynamic> _chatMessageToRow(ChatMessage message) {
    return {
      'id': message.id,
      'chat_id': message.chatId,
      'sender_id': message.senderId,
      'sender_name': message.senderName,
      'recipient_id': message.recipientId,
      'content': message.content,
      'type': message.type.name,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'status': message.status.name,
      'file_metadata_json':
          message.fileMetadata != null ? jsonEncode(message.fileMetadata!.toJson()) : null,
      'is_group': message.isGroup ? 1 : 0,
      'group_id': message.groupId,
      'voice_duration': message.voiceDurationSeconds,
      'waveform_json': message.waveformAmplitudes != null
          ? jsonEncode(message.waveformAmplitudes)
          : null,
      'reply_to_id': message.replyToId,
      'reply_to_text': message.replyToText,
      'reply_to_sender_name': message.replyToSenderName,
      'reactions_json':
          message.reactions.isNotEmpty ? jsonEncode(message.reactions) : null,
    };
  }

  Future<void> saveMessage(ChatMessage message) async {
    _messageBloomFilter.add(message.id);
    _messageLruCache.put(message.id, message);

    final idx = _messageIndexById[message.id];
    if (idx != null && idx < _messages.length && _messages[idx].id == message.id) {
      _messages[idx] = message;
    } else {
      _messageIndexById[message.id] = _messages.length;
      _messages.add(message);
    }

    if (_db != null) {
      final row = _chatMessageToRow(message);
      await _db!.insert('messages', row, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      try {
        await _db!.execute(
          'INSERT OR REPLACE INTO messages_fts (id, chat_id, content) VALUES (?, ?, ?);',
          [message.id, message.chatId, message.content],
        );
      } catch (_) {}
    }
  }

  /// Checks authoritatively whether a message with [id] is already stored.
  bool hasMessage(String id) {
    if (_messageLruCache.containsKey(id)) return true;
    final idx = _messageIndexById[id];
    return idx != null && idx < _messages.length && _messages[idx].id == id;
  }

  /// Authoritative retrieval leveraging LRU Cache and in-memory index map.
  ChatMessage? getMessageById(String id) {
    final cached = _messageLruCache.get(id);
    if (cached != null) return cached;

    final idx = _messageIndexById[id];
    if (idx != null && idx < _messages.length && _messages[idx].id == id) {
      final msg = _messages[idx];
      _messageLruCache.put(id, msg);
      return msg;
    }
    return null;
  }

  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final idx = _messageIndexById[messageId];
    if (idx != null && idx < _messages.length && _messages[idx].id == messageId) {
      final updated = _messages[idx].copyWith(status: status);
      _messages[idx] = updated;
      _messageLruCache.put(messageId, updated);
    }

    if (_db != null) {
      await _db!.update(
        'messages',
        {'status': status.name},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    }
  }

  Future<void> markFileCompleted(String transferId, String localPath) async {
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      if (msg.fileMetadata?.transferId == transferId) {
        msg.fileMetadata?.localPath = localPath;
        msg.fileMetadata?.isCompleted = true;
        msg.status = MessageStatus.delivered;
        await saveMessage(msg);
      }
    }
  }

  Future<void> deleteMessage(String messageId) async {
    _messageLruCache.remove(messageId);
    _messageIndexById.remove(messageId);
    _messages.removeWhere((m) => m.id == messageId);
    // Re-index remaining messages
    _messageIndexById.clear();
    for (int i = 0; i < _messages.length; i++) {
      _messageIndexById[_messages[i].id] = i;
    }

    if (_db != null) {
      await _db!.delete('messages', where: 'id = ?', whereArgs: [messageId]);
      try {
        await _db!.delete('messages_fts', where: 'id = ?', whereArgs: [messageId]);
      } catch (_) {}
    }
  }

  Future<void> updateMessageReactions(String messageId, Map<String, List<String>> reactions) async {
    final idx = _messageIndexById[messageId];
    if (idx != null && idx < _messages.length && _messages[idx].id == messageId) {
      final updated = _messages[idx].copyWith(reactions: reactions);
      _messages[idx] = updated;
      _messageLruCache.put(messageId, updated);
      if (_db != null) {
        await _db!.update(
          'messages',
          {'reactions_json': jsonEncode(reactions)},
          where: 'id = ?',
          whereArgs: [messageId],
        );
      }
    }
  }

  List<ChatMessage> getMessagesForChat(String chatId) {
    return _messages.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Paginated message loading for large chats (e.g. 100,000+ messages)
  Future<List<ChatMessage>> getMessagesForChatPaged(
    String chatId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (_db == null) {
      final all = getMessagesForChat(chatId);
      final start = offset.clamp(0, all.length);
      final end = (start + limit).clamp(start, all.length);
      return all.sublist(start, end);
    }

    final rows = await _db!.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => _rowToChatMessage(r)).toList().reversed.toList();
  }

  /// Instant Full-Text Search across all conversation histories
  Future<List<ChatMessage>> searchMessages(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    if (_db == null) {
      final q = trimmed.toLowerCase();
      return _messages
          .where((m) => m.content.toLowerCase().contains(q))
          .take(50)
          .toList();
    }

    final sanitizedFts = trimmed.replaceAll(RegExp(r'["*^:()\[\]{}]'), ' ').trim();
    if (sanitizedFts.isNotEmpty) {
      try {
        // First try FTS5 virtual table
        final ftsRows = await _db!.rawQuery(
          '''
          SELECT m.* FROM messages m
          JOIN messages_fts fts ON m.id = fts.id
          WHERE messages_fts MATCH ?
          ORDER BY m.timestamp DESC LIMIT 50;
          ''',
          ['"$sanitizedFts"*'],
        );
        if (ftsRows.isNotEmpty) {
          return ftsRows.map((r) => _rowToChatMessage(r)).toList();
        }
      } catch (_) {
        // Fallback to indexed LIKE query
      }
    }

    final rows = await _db!.query(
      'messages',
      where: 'content LIKE ?',
      whereArgs: ['%$trimmed%'],
      orderBy: 'timestamp DESC',
      limit: 50,
    );
    return rows.map((r) => _rowToChatMessage(r)).toList();
  }

  // ---------------------------------------------------------------------------
  // Migration from Legacy JSON
  // ---------------------------------------------------------------------------

  Future<void> _migrateLegacyJsonIfPresent(Directory dbDir) async {
    try {
      final messagesFile = File(p.join(dbDir.path, 'messages.json'));
      final peersFile = File(p.join(dbDir.path, 'peers.json'));
      final pinnedKeysFile = File(p.join(dbDir.path, 'pinned_keys.json'));
      final groupsFile = File(p.join(dbDir.path, 'groups.json'));

      // If database has 0 messages and legacy messages.json exists, import it
      if (_messages.isEmpty && await messagesFile.exists()) {
        final content = await messagesFile.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          for (final item in list) {
            final msg = ChatMessage.fromJson(item as Map<String, dynamic>);
            await saveMessage(msg);
          }
        }
      }

      if (_knownPeers.isEmpty && await peersFile.exists()) {
        final content = await peersFile.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          for (final item in list) {
            final peer = Peer.fromJson(item as Map<String, dynamic>);
            await savePeer(peer);
          }
        }
      }

      if (_groups.isEmpty && await groupsFile.exists()) {
        final content = await groupsFile.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          for (final item in list) {
            final group = GroupChat.fromJson(item as Map<String, dynamic>);
            await saveGroup(group);
          }
        }
      }

      if (_pinnedKeys.isEmpty && await pinnedKeysFile.exists()) {
        final content = await pinnedKeysFile.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> map = jsonDecode(content);
          map.forEach((k, v) async {
            await _persistPinnedKey(k, v.toString());
            _pinnedKeys[k] = v.toString();
          });
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Pinned Chat Messages
  // ---------------------------------------------------------------------------

  Future<void> _loadPinnedChatMessagesFromDb() async {
    if (_db == null) return;
    try {
      final rows = await _db!.query('chat_pinned_messages', orderBy: 'pin_order ASC, pinned_at DESC');
      _pinnedChatMessages.clear();
      for (final row in rows) {
        final chatId = row['chat_id'] as String;
        final msgId = row['message_id'] as String;
        _pinnedChatMessages.putIfAbsent(chatId, () => []).add(msgId);
      }
    } catch (_) {}
  }

  List<ChatMessage> getPinnedMessages(String chatId) {
    final msgIds = _pinnedChatMessages[chatId];
    if (msgIds == null || msgIds.isEmpty) return [];
    final res = <ChatMessage>[];
    for (final id in msgIds) {
      try {
        final found = _messages.firstWhere((m) =>
            m.id == id &&
            (m.chatId == chatId || (m.isGroup && m.groupId == chatId)));
        res.add(found);
      } catch (_) {}
    }
    return res;
  }

  ChatMessage? getPinnedMessage(String chatId) {
    final list = getPinnedMessages(chatId);
    return list.isNotEmpty ? list.first : null;
  }

  String? getPinnedMessageId(String chatId) {
    final msgIds = _pinnedChatMessages[chatId];
    return (msgIds != null && msgIds.isNotEmpty) ? msgIds.first : null;
  }

  List<String> getPinnedMessageIds(String chatId) =>
      List.unmodifiable(_pinnedChatMessages[chatId] ?? []);

  Future<void> pinChatMessage(String chatId, String messageId) async {
    final list = _pinnedChatMessages.putIfAbsent(chatId, () => []);
    if (!list.contains(messageId)) {
      list.insert(0, messageId);
    }
    if (_db != null && _db!.isOpen) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db!.insert(
        'chat_pinned_messages',
        {
          'id': '${chatId}_$messageId',
          'chat_id': chatId,
          'message_id': messageId,
          'pinned_at': now,
          'pin_order': 0,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> unpinChatMessage(String chatId, [String? messageId]) async {
    if (messageId != null) {
      _pinnedChatMessages[chatId]?.remove(messageId);
      if (_db != null && _db!.isOpen) {
        await _db!.delete(
          'chat_pinned_messages',
          where: 'chat_id = ? AND message_id = ?',
          whereArgs: [chatId, messageId],
        );
      }
    } else {
      _pinnedChatMessages.remove(chatId);
      if (_db != null && _db!.isOpen) {
        await _db!.delete(
          'chat_pinned_messages',
          where: 'chat_id = ?',
          whereArgs: [chatId],
        );
      }
    }
  }

  Future<void> unpinAllChatMessages(String chatId) => unpinChatMessage(chatId);

  // ---------------------------------------------------------------------------
  // Linked Devices
  // ---------------------------------------------------------------------------

  Future<void> _loadLinkedDevicesFromDb() async {
    if (_db == null) return;
    try {
      final rows =
          await _db!.query('linked_devices', orderBy: 'last_seen DESC');
      _linkedDevices.clear();
      for (final row in rows) {
        _linkedDevices.add(LinkedDevice(
          id: row['id'] as String,
          name: row['name'] as String,
          platform: row['platform'] as String? ?? 'unknown',
          publicKey: row['public_key'] as String? ?? '',
          linkedAt:
              DateTime.fromMillisecondsSinceEpoch(row['linked_at'] as int),
          lastSeen:
              DateTime.fromMillisecondsSinceEpoch(row['last_seen'] as int),
        ));
      }
    } catch (_) {}
  }

  Future<void> saveLinkedDevice(LinkedDevice device) async {
    _linkedDevices.removeWhere((d) => d.id == device.id);
    _linkedDevices.insert(0, device);
    if (_db != null && _db!.isOpen) {
      await _db!.insert(
        'linked_devices',
        {
          'id': device.id,
          'name': device.name,
          'platform': device.platform,
          'public_key': device.publicKey,
          'linked_at': device.linkedAt.millisecondsSinceEpoch,
          'last_seen': device.lastSeen.millisecondsSinceEpoch,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deleteLinkedDevice(String id) async {
    _linkedDevices.removeWhere((d) => d.id == id);
    if (_db != null && _db!.isOpen) {
      await _db!.delete(
        'linked_devices',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Encrypted Backup & Restore
  // ---------------------------------------------------------------------------

  static final _backupPbkdf2 = crypto_pkg.Pbkdf2(
    macAlgorithm: crypto_pkg.Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  Future<Map<String, dynamic>> exportEncryptedBackup(String password) async {
    final backupData = {
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'accounts': _accounts.map((a) => a.toJson()).toList(),
      'peers': _knownPeers.values.map((p) => p.toJson()).toList(),
      'groups': _groups.values.map((g) => g.toJson()).toList(),
      'pinned_keys': _pinnedKeys,
      'pinned_chat_messages': _pinnedChatMessages,
      'messages': _messages.map((m) => m.toJson()).toList(),
      'linked_devices': _linkedDevices.map((d) => d.toJson()).toList(),
    };

    final rawJson = jsonEncode(backupData);
    final rawBytes = utf8.encode(rawJson);
    final checksum = sha256.convert(rawBytes).toString();

    final rand = Random.secure();
    final saltBytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final secretKey = await _backupPbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: saltBytes,
    );
    final keyBytes = await secretKey.extractBytes();
    final encryptedBytes = _encryptBackupBytes(rawBytes, keyBytes);

    return {
      'format': 'ozobackup',
      'version': 2,
      'kdf': 'pbkdf2-hmac-sha256-100k',
      'salt': base64Encode(saltBytes),
      'checksum': checksum,
      'payload': base64Encode(encryptedBytes),
    };
  }

  Future<bool> importEncryptedBackup(
      Map<String, dynamic> container, String password) async {
    try {
      if (container['format'] != 'ozobackup') return false;
      final version = container['version'] as int? ?? 1;
      final saltStr = container['salt'] as String? ?? 'ozo_vault_salt_v1';
      final expectedChecksum = container['checksum'] as String;
      final payloadBase64 = container['payload'] as String;

      List<int> keyBytes;
      if (version >= 2) {
        final saltBytes = base64Decode(saltStr);
        final secretKey = await _backupPbkdf2.deriveKeyFromPassword(
          password: password,
          nonce: saltBytes,
        );
        keyBytes = await secretKey.extractBytes();
      } else {
        keyBytes = sha256.convert(utf8.encode('$password:$saltStr')).bytes;
      }

      final encryptedBytes = base64Decode(payloadBase64);
      final decryptedBytes = _decryptBackupBytes(encryptedBytes, keyBytes);

      final actualChecksum = sha256.convert(decryptedBytes).toString();
      if (actualChecksum != expectedChecksum) {
        return false;
      }

      final jsonStr = utf8.decode(decryptedBytes);
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      if (data['accounts'] is List) {
        for (final a in data['accounts']) {
          await saveAccount(UserAccount.fromJson(a as Map<String, dynamic>));
        }
      }

      if (data['peers'] is List) {
        for (final p in data['peers']) {
          await savePeer(Peer.fromJson(p as Map<String, dynamic>));
        }
      }

      if (data['groups'] is List) {
        for (final g in data['groups']) {
          await saveGroup(GroupChat.fromJson(g as Map<String, dynamic>));
        }
      }

      if (data['pinned_keys'] is Map) {
        final Map<String, dynamic> pk = data['pinned_keys'];
        for (final entry in pk.entries) {
          await _persistPinnedKey(entry.key, entry.value.toString());
          _pinnedKeys[entry.key] = entry.value.toString();
        }
      }

      if (data['pinned_chat_messages'] is Map) {
        final Map<String, dynamic> pcm = data['pinned_chat_messages'];
        for (final entry in pcm.entries) {
          if (entry.value is List) {
            for (final msgId in entry.value) {
              await pinChatMessage(entry.key, msgId.toString());
            }
          } else {
            await pinChatMessage(entry.key, entry.value.toString());
          }
        }
      }

      if (data['messages'] is List) {
        for (final m in data['messages']) {
          await saveMessage(ChatMessage.fromJson(m as Map<String, dynamic>));
        }
      }

      if (data['linked_devices'] is List) {
        for (final d in data['linked_devices']) {
          await saveLinkedDevice(
              LinkedDevice.fromJson(d as Map<String, dynamic>));
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _encryptBackupBytes(List<int> input, List<int> key) {
    final out = Uint8List(input.length);
    var blockIndex = 0;
    var keystream = <int>[];
    for (var i = 0; i < input.length; i++) {
      final subIndex = i % 32;
      if (subIndex == 0) {
        keystream = sha256.convert([
          ...key,
          blockIndex >> 24,
          blockIndex >> 16,
          blockIndex >> 8,
          blockIndex & 0xFF
        ]).bytes;
        blockIndex++;
      }
      out[i] = input[i] ^ keystream[subIndex];
    }
    return out;
  }

  static Uint8List _decryptBackupBytes(List<int> input, List<int> key) {
    return _encryptBackupBytes(input, key);
  }

  /// Closes database connection and releases file locks
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
