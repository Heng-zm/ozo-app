/// A high-performance Trie (Prefix Tree) supporting O(L) prefix search,
/// autocomplete, and keyword indexing across Unicode strings.
class PrefixTrie<T> {
  final bool caseSensitive;
  final _TrieNode<T> _root = _TrieNode<T>();
  int _wordCount = 0;

  PrefixTrie({this.caseSensitive = false});

  /// Total number of distinct words/keys stored in the Trie.
  int get wordCount => _wordCount;

  /// Inserts a [key] and associates it with [value].
  /// Multiple values can be associated with the same key.
  void insert(String key, T value) {
    final normalized = caseSensitive ? key : key.toLowerCase();
    if (normalized.isEmpty) return;

    var current = _root;
    for (final rune in normalized.runes) {
      current = current.children.putIfAbsent(rune, () => _TrieNode<T>());
    }

    if (!current.isTerminal) {
      current.isTerminal = true;
      _wordCount++;
    }
    current.values.add(value);
  }

  /// Searches for all items whose indexed keys start with [prefix].
  /// Returns at most [limit] items.
  List<T> searchPrefix(String prefix, {int limit = 50}) {
    final normalized = caseSensitive ? prefix : prefix.toLowerCase();
    if (normalized.isEmpty) return [];

    var current = _root;
    for (final rune in normalized.runes) {
      final next = current.children[rune];
      if (next == null) return [];
      current = next;
    }

    // Collect all values in the subtree
    final results = <T>[];
    final seen = <T>{};
    _collectSubtreeValues(current, results, seen, limit);
    return results;
  }

  /// Searches for items that match [key] exactly.
  List<T> findExact(String key) {
    final normalized = caseSensitive ? key : key.toLowerCase();
    if (normalized.isEmpty) return [];

    var current = _root;
    for (final rune in normalized.runes) {
      final next = current.children[rune];
      if (next == null) return [];
      current = next;
    }

    return current.isTerminal ? List.unmodifiable(current.values) : [];
  }

  /// Checks if any word in the trie begins with [prefix].
  bool containsPrefix(String prefix) {
    final normalized = caseSensitive ? prefix : prefix.toLowerCase();
    if (normalized.isEmpty) return false;

    var current = _root;
    for (final rune in normalized.runes) {
      final next = current.children[rune];
      if (next == null) return false;
      current = next;
    }
    return true;
  }

  /// Removes a key, or a specific value under [key].
  bool remove(String key, [T? value]) {
    final normalized = caseSensitive ? key : key.toLowerCase();
    if (normalized.isEmpty) return false;

    final stack = <_TrieEntry<T>>[];
    var current = _root;

    for (final rune in normalized.runes) {
      final next = current.children[rune];
      if (next == null) return false;
      stack.add(_TrieEntry(rune: rune, parent: current, node: next));
      current = next;
    }

    if (!current.isTerminal) return false;

    if (value != null) {
      final removed = current.values.remove(value);
      if (!removed) return false;
      if (current.values.isNotEmpty) return true;
    } else {
      current.values.clear();
    }

    current.isTerminal = false;
    _wordCount--;

    // Prune unneeded nodes up the tree
    for (var i = stack.length - 1; i >= 0; i--) {
      final entry = stack[i];
      if (entry.node.children.isEmpty && !entry.node.isTerminal) {
        entry.parent.children.remove(entry.rune);
      } else {
        break;
      }
    }

    return true;
  }

  /// Clears the Trie completely.
  void clear() {
    _root.children.clear();
    _root.values.clear();
    _root.isTerminal = false;
    _wordCount = 0;
  }

  void _collectSubtreeValues(
    _TrieNode<T> node,
    List<T> results,
    Set<T> seen,
    int limit,
  ) {
    if (results.length >= limit) return;

    if (node.isTerminal) {
      for (final val in node.values) {
        if (seen.add(val)) {
          results.add(val);
          if (results.length >= limit) return;
        }
      }
    }

    for (final child in node.children.values) {
      _collectSubtreeValues(child, results, seen, limit);
      if (results.length >= limit) return;
    }
  }
}

class _TrieNode<T> {
  final Map<int, _TrieNode<T>> children = {};
  final List<T> values = [];
  bool isTerminal = false;
}

class _TrieEntry<T> {
  final int rune;
  final _TrieNode<T> parent;
  final _TrieNode<T> node;

  _TrieEntry({required this.rune, required this.parent, required this.node});
}
