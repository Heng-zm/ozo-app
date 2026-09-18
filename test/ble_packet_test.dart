import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/bluetooth/ble_constants.dart';
import 'package:lan_telegram/core/bluetooth/ble_packet.dart';
import 'package:lan_telegram/core/bluetooth/bluetooth_hotspot_service.dart';

void main() {
  group('BlePacket Protocol & Reassembly', () {
    test('Single packet serialization and deserialization', () {
      final payload = Uint8List.fromList(utf8.encode('Hello Offline BLE!'));
      final packet = BlePacket(
        packetType: BleConstants.packetTypeChat,
        messageId: 42,
        totalChunks: 1,
        chunkIndex: 0,
        payload: payload,
      );

      final bytes = packet.toBytes();
      final decoded = BlePacket.fromBytes(bytes);

      expect(decoded, isNotNull);
      expect(decoded!.packetType, equals(BleConstants.packetTypeChat));
      expect(decoded.messageId, equals(42));
      expect(decoded.totalChunks, equals(1));
      expect(decoded.chunkIndex, equals(0));
      expect(utf8.decode(decoded.payload), equals('Hello Offline BLE!'));
    });

    test('Multi-chunk slicing and in-order reassembly', () {
      // 500 bytes of repetitive test text
      final longText = 'OZO-APP-OFFLINE-MESH-' * 25;
      final fullBytes = Uint8List.fromList(utf8.encode(longText));

      final chunks = BlePacket.slice(
        BleConstants.packetTypeChat,
        1001,
        fullBytes,
        chunkSize: 180,
      );

      expect(chunks.length, equals(3)); // 525 / 180 = 3 chunks

      final reassembler = BleReassembler();
      BlePacket? completed;

      for (final chunk in chunks) {
        completed = reassembler.addPacket(chunk);
      }

      expect(completed, isNotNull);
      expect(completed!.payload.length, equals(fullBytes.length));
      expect(utf8.decode(completed.payload), equals(longText));
    });

    test('Out-of-order packet arrival reassembly', () {
      final text = 'Testing Out-Of-Order BLE Packet Reassembly!';
      final fullBytes = Uint8List.fromList(utf8.encode(text));

      final chunks = BlePacket.slice(
        BleConstants.packetTypeChat,
        2002,
        fullBytes,
        chunkSize: 10,
      );

      expect(chunks.length, greaterThan(2));

      final reassembler = BleReassembler();
      BlePacket? completed;

      // Feed chunks in reverse order
      for (final chunk in chunks.reversed) {
        completed = reassembler.addPacket(chunk);
      }

      expect(completed, isNotNull);
      expect(utf8.decode(completed!.payload), equals(text));
    });

    test('HotspotOffer serialization & deserialization', () {
      final offer = HotspotOffer(
        ssid: 'OZO-Hotspot-Test',
        password: 'supersecretkey',
        ip: '192.168.43.1',
        port: 45455,
        senderName: 'Alice iPhone',
      );

      final bytes = offer.toBytes();
      final parsed = HotspotOffer.fromBytes(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.ssid, equals('OZO-Hotspot-Test'));
      expect(parsed.password, equals('supersecretkey'));
      expect(parsed.ip, equals('192.168.43.1'));
      expect(parsed.port, equals(45455));
      expect(parsed.senderName, equals('Alice iPhone'));
    });
  });
}
