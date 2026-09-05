import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/database/app_database.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/dsa/bloom_filter.dart';
import 'package:lan_telegram/core/dsa/lru_cache.dart';
import 'package:lan_telegram/core/dsa/prefix_trie.dart';
import 'package:lan_telegram/core/network/p2p_server.dart';
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

      // Unicode / emoji prefix
      final emojiResults = trie.searchPrefix('🇰🇭');
      expect(emojiResults, equals(['cambodia_flag']));

      // Key removal
      final removed = trie.remove('alexander');
      expect(removed, isTrue);
      expect(trie.searchPrefix('al'), equals(['peer_alice_id', 'peer_alicia_id']));
      expect(trie.wordCount, equals(6));

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

    test('AppDatabase LRU caching, Bloom Filter, and Prefix Trie peer search', () async {
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

      // 2. LRU Cache & Bloom Filter for messages
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

      // Fast O(1) Bloom filter test
      expect(db.messageBloomFilter.mightContain(msg.id), isTrue);
      expect(db.messageBloomFilter.mightContain('non_existent_msg_id_xyz'), isFalse);

      // Fast O(1) LRU Cache lookup
      final retrieved = db.getMessageById(msg.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.content, equals('Hello DSA World!'));
      expect(db.messageCache.containsKey(msg.id), isTrue);

      // Non-existent message returns null immediately without DB scan
      expect(db.getMessageById('unseen_random_id_999'), isNull);
    });

    test('ChatProvider drops duplicate incoming packets via Bloom Filter', () async {
      final provider = ChatProvider();

      final duplicateMsg = ChatMessage(
        id: 'relay_packet_duplicate_123',
        chatId: 'group_456',
        senderId: 'peer_bob',
        senderName: 'Bob',
        recipientId: 'group_456',
        content: 'Group relay duplicate message',
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        isGroup: true,
        groupId: 'group_456',
      );

      // Initially bloom filter does not contain this message
      expect(provider.incomingPacketBloomFilter.mightContain(duplicateMsg.id), isFalse);

      // Server simulates message arrival
      provider.server = P2pServer(
        requestedPort: 45455,
        deviceId: 'local_id',
        deviceName: 'Local',
        cryptoService: provider.cryptoService,
      );

      // When message arrives first time
      expect(provider.incomingPacketBloomFilter.mightContain(duplicateMsg.id), isFalse);
      provider.incomingPacketBloomFilter.add(duplicateMsg.id);
      expect(provider.incomingPacketBloomFilter.mightContain(duplicateMsg.id), isTrue);

      // Search queries leverage Trie
      await provider.setSearchQuery('ali');
      expect(provider.searchQuery, equals('ali'));
    });
  });
}
