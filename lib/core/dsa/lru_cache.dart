/// An O(1) Least Recently Used (LRU) Cache backed by a hash map and doubly linked list.
class LruCache<K, V> {
  final int capacity;
  final void Function(K key, V value)? onEvict;

  final Map<K, _LruNode<K, V>> _map = {};
  late final _LruNode<K, V> _head;
  late final _LruNode<K, V> _tail;

  LruCache({required this.capacity, this.onEvict}) : assert(capacity > 0, 'Capacity must be greater than 0') {
    // Sentinel nodes to avoid edge-case checks for null pointers
    _head = _LruNode<K, V>._sentinel();
    _tail = _LruNode<K, V>._sentinel();
    _head.next = _tail;
    _tail.prev = _head;
  }

  /// Current number of elements in the cache.
  int get length => _map.length;

  /// Whether the cache is empty.
  bool get isEmpty => _map.isEmpty;

  /// Whether the cache is not empty.
  bool get isNotEmpty => _map.isNotEmpty;

  /// Whether the cache contains the specified key.
  /// NOTE: This does NOT update the recency of the key.
  bool containsKey(K key) => _map.containsKey(key);

  /// Retrieves a value by key and promotes it to most recently used.
  /// Returns `null` if the key is not present.
  V? get(K key) {
    final node = _map[key];
    if (node == null) return null;
    _moveToHead(node);
    return node.value;
  }

  /// Inserts or updates a key-value pair, promoting it to most recently used.
  /// If inserting exceeds [capacity], the least recently used item is evicted.
  void put(K key, V value) {
    final existing = _map[key];
    if (existing != null) {
      existing.value = value;
      _moveToHead(existing);
      return;
    }

    if (_map.length >= capacity) {
      _evictOldest();
    }

    final newNode = _LruNode<K, V>(key: key, value: value);
    _map[key] = newNode;
    _attachToHead(newNode);
  }

  /// Removes an entry by key. Returns the removed value or `null` if not found.
  V? remove(K key) {
    final node = _map.remove(key);
    if (node == null) return null;
    _detach(node);
    return node.value;
  }

  /// Clears all entries from the cache.
  void clear() {
    _map.clear();
    _head.next = _tail;
    _tail.prev = _head;
  }

  /// Returns an iterable of all cached values in order from most recently used to least recently used.
  List<V> get values {
    final list = <V>[];
    var curr = _head.next;
    while (curr != null && curr != _tail) {
      list.add(curr.value as V);
      curr = curr.next;
    }
    return list;
  }

  /// Returns an iterable of all cached keys in order from most recently used to least recently used.
  List<K> get keys {
    final list = <K>[];
    var curr = _head.next;
    while (curr != null && curr != _tail) {
      list.add(curr.key as K);
      curr = curr.next;
    }
    return list;
  }

  void _attachToHead(_LruNode<K, V> node) {
    node.prev = _head;
    node.next = _head.next;
    _head.next?.prev = node;
    _head.next = node;
  }

  void _detach(_LruNode<K, V> node) {
    node.prev?.next = node.next;
    node.next?.prev = node.prev;
    node.prev = null;
    node.next = null;
  }

  void _moveToHead(_LruNode<K, V> node) {
    _detach(node);
    _attachToHead(node);
  }

  void _evictOldest() {
    final oldest = _tail.prev;
    if (oldest == null || oldest == _head) return;

    _detach(oldest);
    _map.remove(oldest.key);
    if (oldest.key != null && oldest.value != null) {
      onEvict?.call(oldest.key as K, oldest.value as V);
    }
  }
}

class _LruNode<K, V> {
  final K? key;
  V? value;
  _LruNode<K, V>? prev;
  _LruNode<K, V>? next;

  _LruNode({required this.key, required this.value});
  _LruNode._sentinel()
      : key = null,
        value = null;
}
