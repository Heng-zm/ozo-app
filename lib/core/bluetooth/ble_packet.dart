import 'dart:async';
import 'dart:typed_data';

/// BLE Packet header and chunking protocol for OZO App
class BlePacket {
  final int packetType;
  final int messageId;
  final int totalChunks;
  final int chunkIndex;
  final Uint8List payload;

  static const int headerSize = 11;

  BlePacket({
    required this.packetType,
    required this.messageId,
    required this.totalChunks,
    required this.chunkIndex,
    required this.payload,
  });

  /// Serializes the packet into binary format:
  /// [0] Type (1 byte)
  /// [1..4] Message ID (uint32 big-endian, 4 bytes)
  /// [5..6] Total chunks (uint16 big-endian, 2 bytes)
  /// [7..8] Chunk index (uint16 big-endian, 2 bytes)
  /// [9..10] Payload length (uint16 big-endian, 2 bytes)
  /// [11..N] Payload bytes
  Uint8List toBytes() {
    final byteData = ByteData(headerSize + payload.length);
    byteData.setUint8(0, packetType);
    byteData.setUint32(1, messageId);
    byteData.setUint16(5, totalChunks);
    byteData.setUint16(7, chunkIndex);
    byteData.setUint16(9, payload.length);

    final result = byteData.buffer.asUint8List();
    result.setRange(headerSize, headerSize + payload.length, payload);
    return result;
  }

  /// Parses binary data into a BlePacket
  static BlePacket? fromBytes(Uint8List data) {
    if (data.length < headerSize) return null;
    final byteData = ByteData.sublistView(data);
    final packetType = byteData.getUint8(0);
    final messageId = byteData.getUint32(1);
    final totalChunks = byteData.getUint16(5);
    final chunkIndex = byteData.getUint16(7);
    final payloadLen = byteData.getUint16(9);

    if (data.length < headerSize + payloadLen) return null;

    final payload = Uint8List.sublistView(data, headerSize, headerSize + payloadLen);
    return BlePacket(
      packetType: packetType,
      messageId: messageId,
      totalChunks: totalChunks,
      chunkIndex: chunkIndex,
      payload: payload,
    );
  }

  /// Slices a full payload into multiple MTU-friendly BLE packets
  static List<BlePacket> slice(
    int packetType,
    int messageId,
    Uint8List fullPayload, {
    int chunkSize = 180,
  }) {
    if (fullPayload.isEmpty) {
      return [
        BlePacket(
          packetType: packetType,
          messageId: messageId,
          totalChunks: 1,
          chunkIndex: 0,
          payload: Uint8List(0),
        )
      ];
    }

    final totalChunks = (fullPayload.length / chunkSize).ceil();
    final packets = <BlePacket>[];

    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > fullPayload.length) ? fullPayload.length : start + chunkSize;
      final chunkPayload = Uint8List.sublistView(fullPayload, start, end);

      packets.add(
        BlePacket(
          packetType: packetType,
          messageId: messageId,
          totalChunks: totalChunks,
          chunkIndex: i,
          payload: chunkPayload,
        ),
      );
    }
    return packets;
  }
}

/// Reassembles fragmented BLE packets into a single complete payload
class BleReassembler {
  final Map<int, Map<int, Uint8List>> _buffers = {};
  final Map<int, int> _expectedTotals = {};
  final Map<int, int> _packetTypes = {};
  final Map<int, DateTime> _timestamps = {};
  Timer? _cleanupTimer;

  BleReassembler() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) => _cleanupStale());
  }

  /// Adds a packet. If all chunks for messageId are received, returns the complete packet with merged payload.
  BlePacket? addPacket(BlePacket packet) {
    // Single chunk message
    if (packet.totalChunks <= 1) {
      return packet;
    }

    final id = packet.messageId;
    _timestamps[id] = DateTime.now();
    _expectedTotals[id] = packet.totalChunks;
    _packetTypes[id] = packet.packetType;

    _buffers.putIfAbsent(id, () => {})[packet.chunkIndex] = packet.payload;

    final receivedMap = _buffers[id]!;
    if (receivedMap.length == packet.totalChunks) {
      // Reassemble in order
      final totalBytes = receivedMap.values.fold<int>(0, (sum, item) => sum + item.length);
      final completeData = Uint8List(totalBytes);
      int offset = 0;

      for (int i = 0; i < packet.totalChunks; i++) {
        final chunk = receivedMap[i];
        if (chunk != null) {
          completeData.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
      }

      // Cleanup buffer
      _buffers.remove(id);
      _expectedTotals.remove(id);
      _timestamps.remove(id);
      final type = _packetTypes.remove(id) ?? packet.packetType;

      return BlePacket(
        packetType: type,
        messageId: id,
        totalChunks: 1,
        chunkIndex: 0,
        payload: completeData,
      );
    }

    return null;
  }

  void _cleanupStale() {
    final now = DateTime.now();
    _timestamps.removeWhere((id, timestamp) {
      if (now.difference(timestamp).inSeconds > 60) {
        _buffers.remove(id);
        _expectedTotals.remove(id);
        _packetTypes.remove(id);
        return true;
      }
      return false;
    });
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _buffers.clear();
    _expectedTotals.clear();
    _timestamps.clear();
  }
}
