import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// A space-efficient, probabilistic data structure for set membership testing.
///
/// False positive matches are possible with bounded probability [falsePositiveRate],
/// but false negatives are impossible (0% false negative rate).
///
/// Uses Kirsch-Mitzenmacher double-hashing optimization:
/// g_i(x) = (h1(x) + i * h2(x)) mod m
class BloomFilter {
  final int capacity;
  final double falsePositiveRate;

  late final int _bitCount;
  late final int _hashCount;
  late final Uint32List _bitArray;
  int _elementsAdded = 0;

  BloomFilter({
    this.capacity = 10000,
    this.falsePositiveRate = 0.01,
  })  : assert(capacity > 0, 'Capacity must be greater than 0'),
        assert(
          falsePositiveRate > 0 && falsePositiveRate < 1.0,
          'False positive rate must be between 0 and 1.0',
        ) {
    // Optimal number of bits: m = - (n * ln(p)) / (ln(2)^2)
    final ln2 = math.ln2;
    final m = (-1.0 * capacity * math.log(falsePositiveRate) / (ln2 * ln2)).ceil();
    _bitCount = math.max(64, m);

    // Optimal number of hash functions: k = (m / n) * ln(2)
    final k = ((_bitCount / capacity) * ln2).round();
    _hashCount = math.max(1, k);

    // Number of 32-bit unsigned integers required to hold _bitCount bits
    final words = (_bitCount + 31) ~/ 32;
    _bitArray = Uint32List(words);
  }

  /// Total number of bits allocated in the filter.
  int get bitCount => _bitCount;

  /// Number of independent hash functions simulated via double hashing.
  int get hashCount => _hashCount;

  /// Approximate count of items added so far.
  int get elementsAdded => _elementsAdded;

  /// Adds a string item (e.g. message ID, packet hash, peer ID) to the Bloom filter.
  void add(String item) {
    final bytes = utf8.encode(item);
    final h1 = _fnv1a32(bytes);
    final h2 = _jenkins32(bytes);

    for (var i = 0; i < _hashCount; i++) {
      final combined = (h1 + (i * h2)) & 0x7FFFFFFF;
      final bitIndex = combined % _bitCount;
      _setBit(bitIndex);
    }
    _elementsAdded++;
  }

  /// Tests whether [item] might be in the set.
  ///
  /// - Returns `false` with 100% mathematical certainty if the item was NEVER added.
  /// - Returns `true` if the item is probably in the set (with <= [falsePositiveRate] chance of false positive).
  bool mightContain(String item) {
    final bytes = utf8.encode(item);
    final h1 = _fnv1a32(bytes);
    final h2 = _jenkins32(bytes);

    for (var i = 0; i < _hashCount; i++) {
      final combined = (h1 + (i * h2)) & 0x7FFFFFFF;
      final bitIndex = combined % _bitCount;
      if (!_isBitSet(bitIndex)) {
        return false;
      }
    }
    return true;
  }

  /// Clears all bits in the filter.
  void reset() {
    _bitArray.fillRange(0, _bitArray.length, 0);
    _elementsAdded = 0;
  }

  /// Estimates the number of distinct items added based on the population of set bits.
  int get estimatedCount {
    var setBits = 0;
    for (var i = 0; i < _bitArray.length; i++) {
      var w = _bitArray[i];
      // Hamming weight (popcount)
      while (w != 0) {
        setBits += w & 1;
        w >>= 1;
      }
    }
    if (setBits == 0) return 0;
    if (setBits >= _bitCount) return capacity;

    final ratio = 1.0 - (setBits / _bitCount);
    if (ratio <= 0.0) return capacity;
    final estimated = -(_bitCount / _hashCount) * math.log(ratio);
    return estimated.round().clamp(0, capacity * 2);
  }

  void _setBit(int bitIndex) {
    final wordIndex = bitIndex >> 5; // bitIndex ~/ 32
    final bitOffset = bitIndex & 31; // bitIndex % 32
    _bitArray[wordIndex] |= (1 << bitOffset);
  }

  bool _isBitSet(int bitIndex) {
    final wordIndex = bitIndex >> 5;
    final bitOffset = bitIndex & 31;
    return (_bitArray[wordIndex] & (1 << bitOffset)) != 0;
  }

  /// 32-bit FNV-1a Hash
  static int _fnv1a32(List<int> bytes) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < bytes.length; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// 32-bit Jenkins One-at-a-time Hash
  static int _jenkins32(List<int> bytes) {
    var hash = 0;
    for (var i = 0; i < bytes.length; i++) {
      hash = (hash + bytes[i]) & 0xFFFFFFFF;
      hash = (hash + ((hash << 10) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      hash ^= (hash >> 6);
    }
    hash = (hash + ((hash << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    hash ^= (hash >> 11);
    hash = (hash + ((hash << 15) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    return hash == 0 ? 1 : hash; // Prevent 0 stride in double hashing
  }
}
