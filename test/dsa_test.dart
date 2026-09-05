import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/app_database.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/dsa/bloom_filter.dart';
import 'package:lan_telegram/core/dsa/lru_cache.dart';
import 'package:lan_telegram/core/dsa/prefix_trie.dart';
import 'package:lan_telegram/providers/chat_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LruCache<K, V> Data Structure Tests', () {
    test('O(1) capacity enforcement and eviction order', () {
      final evictedKeys = <String>[];
      final cache = LruCache<String, int>(
        capacity: 3,
        onEvict: (key, val) => evictedKeys.add(key),
      );

      expect(cache.capacity, equals(3));
      expect(cache.length, equals(0));
      expect(cache.isEmpty, isTrue);

      cache.put('A', 1);
      cache.put('B', 2);
      cache.put('C', 3);

      expect(cache.length, equals(3));
      expect(cache.keys, equals(['C', 'B', 'A']));

      // Access A -> promotes A to head: [A, C, B]
      expect(cache.get('A'), equals(1));
      expect(cache.keys, equals(['A', 'C', 'B']));

      // Insert D -> capacity exceeded, least recently used 'B' must be evicted
      cache.put('D', 4);
      expect(cache.length, equals(3));
      expect(cache.keys, equals(['D', 'A', 'C']));
      expect(cache.containsKey('B'), isFalse);
      expect(cache.get('B'), isNull);
      expect(evictedKeys, equals(['B']));

      // Updating existing key D
      cache.put('D', 40);
      expect(cache.get('D'), equals(40));
      expect(cache.length, equals(3));

      // Remove C
      final removed = cache.remove('C');
      expect(removed, equals(3));
      expect(cache.length, equals(2));
      expect(cache.keys, equals(['D', 'A']));

      // Clear
      cache.clear();
      expect(cache.isEmpty, isTrue);
      expect(cache.length, equals(0));
    });
  });

  group('BloomFilter Data Structure Tests', () {
    test('Zero false negatives and bounded false positive rate', () {
      final bloom = BloomFilter(capacity: 2000, falsePositiveRate: 0.01);

      expect(bloom.bitCount, greaterThan(1000));
      expect(bloom.hashCount, greaterThanOrEqualTo(3));

      final insertedItems = <String>{};
      for (var i = 0; i < 1000; i++) {
        final id = 'msg_packet_nonce_$i';
        insertedItems.add(id);
        bloom.add(id);
      }

      // 1. Strict 0% False Negatives Guarantee
      for (final item in insertedItems) {
        expect(bloom.mightContain(item), isTrue,
            reason: 'Bloom filter must NEVER produce false negatives for added items');
      }

      // 2. Bounded False Positive Rate
      var falsePositives = 0;
      const testCount = 1000;
      for (var i = 0; i < testCount; i++) {
        final uninserted = 'completely_unseen_packet_$i';
        if (bloom.mightContain(uninserted)) {
          falsePositives++;
        }
      }

      final empiricalFpRate = falsePositives / testCount;
      // Allow empirical variation within 3x theoretical limit
      expect(empiricalFpRate, lessThanOrEqualTo(0.03),
          reason: 'Empirical false positive rate ($empiricalFpRate) must remain near target (0.01)');

      // 3. Reset test
      bloom.reset();
      expect(bloom.elementsAdded, equals(0));
      for (final item in insertedItems.take(50)) {
        expect(bloom.mightContain(item), isFalse,
            reason: 'Reset must clear all filter bits');
      }
    });
  });

  group('PrefixTrie<T> Data Structure Tests', () {
    test('O(L) exact search, prefix search, and Unicode support', () {
      final trie = PrefixTrie<String>(caseSensitive: false);

      trie.insert('alice', 'peer_alice_id');
      trie.insert('alexander', 'peer_alex_id');
      trie.insert('alicia', 'peer_alicia_id');
      trie.insert('bob', 'peer_bob_id');
      trie.insert('charlie', 'peer_charlie_id');
      trie.insert('🇰🇭_cambodia', 'cambodia_flag');
      trie.insert('khmer_chat', 'khmer_id');

      expect(trie.wordCount, equals(7));

      // Exact match
      expect(trie.findExact('Alice'), equals(['peer_alice_id']));
      expect(trie.findExact('unknown'), isEmpty);

      // Prefix match
      final alResults = trie.searchPrefix('al');
      expect(alResults.length, equals(3));
      expect(alResults, containsAll(['peer_alice_id', 'peer_alex_id', 'peer_alicia_id']));

      // Case-insensitive prefix
      final capAlResults = trie.searchPrefix('AL');
      expect(capAlResults.length, equals(3));

      // Single match
      final bobResults = trie.searchPrefix('bo');
      expect(bobResults, equals(['peer_bob_id']));

      // Unicode / emoji prefix with astral plane surrogate pairs
      trie.insert('🧑‍💻_developer', 'dev_peer');
      trie.insert('🎉_celebration', 'party_peer');
      expect(trie.findExact('🧑‍💻_developer'), equals(['dev_peer']));
      expect(trie.searchPrefix('🎉'), equals(['party_peer']));

      final emojiResults = trie.searchPrefix('🇰🇭');
      expect(emojiResults, equals(['cambodia_flag']));

      // Key removal
      final removed = trie.remove('alexander');
      expect(removed, isTrue);
      expect(trie.searchPrefix('al'), equals(['peer_alice_id', 'peer_alicia_id']));

      // Clear
      trie.clear();
      expect(trie.wordCount, equals(0));
      expect(trie.searchPrefix('al'), isEmpty);
    });
  });

  group('DSA Integration: AppDatabase & ChatProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AppDatabase LRU caching, authoritative lookups, and cache invalidation on update/delete', () async {
      final db = AppDatabase();

      final peer1 = Peer(
        id: 'peer-alice-01',
        name: 'Alice Wonderland',
        ip: '192.168.1.10',
        port: 45455,
        publicKey: 'PUBKEY_ALICE',
        platform: 'desktop',
        lastSeen: DateTime.now(),
        username: 'alicew',
      );

      final peer2 = Peer(
        id: 'peer-alex-02',
        name: 'Alexander Great',
        ip: '192.168.1.11',
        port: 45455,
        publicKey: 'PUBKEY_ALEX',
        platform: 'desktop',
        lastSeen: DateTime.now(),
        username: 'alexg',
      );

      await db.savePeer(peer1);
      await db.savePeer(peer2);

      // 1. Prefix Trie peer search
      final prefixMatches = db.searchPeers('Al');
      expect(prefixMatches.length, equals(2));
      expect(prefixMatches.map((p) => p.name), containsAll(['Alice Wonderland', 'Alexander Great']));

      final usernameMatches = db.searchPeers('alic');
      expect(usernameMatches.length, equals(1));
      expect(usernameMatches.first.id, equals('peer-alice-01'));

      // 2. LRU Cache & Authoritative checks for messages
      final msg = ChatMessage(
        id: 'dsa_test_msg_99',
        chatId: peer1.id,
        senderId: 'local_device',
        senderName: 'Local User',
        recipientId: peer1.id,
        content: 'Hello DSA World!',
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );

      await db.saveMessage(msg);

      // Authoritative hasMessage check
      expect(db.hasMessage(msg.id), isTrue);
      expect(db.hasMessage('non_existent_msg_id_xyz'), isFalse);

      // Fast O(1) LRU Cache lookup
      final retrieved = db.getMessageById(msg.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.content, equals('Hello DSA World!'));
      expect(db.messageCache.containsKey(msg.id), isTrue);

      // Cache invalidation on status update
      await db.updateMessageStatus(msg.id, MessageStatus.delivered);
      expect(db.getMessageById(msg.id)?.status, equals(MessageStatus.delivered));
      expect(db.messageCache.get(msg.id)?.status, equals(MessageStatus.delivered));

      // Cache invalidation on reactions update
      await db.updateMessageReactions(msg.id, {'👍': ['peer-alice-01']});
      expect(db.getMessageById(msg.id)?.reactions['👍'], contains('peer-alice-01'));
      expect(db.messageCache.get(msg.id)?.reactions['👍'], contains('peer-alice-01'));

      // Cache invalidation on delete
      await db.deleteMessage(msg.id);
      expect(db.hasMessage(msg.id), isFalse);
      expect(db.messageCache.containsKey(msg.id), isFalse);
      expect(db.getMessageById(msg.id), isNull);
    });

    test('ChatProvider uses Bounded LRU Cache for exact 0% false-positive deduplication', () async {
      final provider = ChatProvider();

      final incomingMsg = ChatMessage(
        id: 'relay_packet_exact_123',
        chatId: 'group_456',
        senderId: 'peer_bob',
        senderName: 'Bob',
        recipientId: 'group_456',
        content: 'Group relay unique message',
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        isGroup: true,
        groupId: 'group_456',
      );

      // Initially not seen
      expect(provider.recentMessageIdCache.containsKey(incomingMsg.id), isFalse);
      expect(provider.database.hasMessage(incomingMsg.id), isFalse);

      // Record in LRU cache
      provider.recentMessageIdCache.put(incomingMsg.id, true);
      expect(provider.recentMessageIdCache.containsKey(incomingMsg.id), isTrue);

      // Search queries leverage Prefix Trie
      await provider.setSearchQuery('ali');
      expect(provider.searchQuery, equals('ali'));
    });
  });
}
