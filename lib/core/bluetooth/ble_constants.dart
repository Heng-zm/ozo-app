import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// OZO App Bluetooth Low Energy Constants & UUIDs
class BleConstants {
  /// Base Service UUID for OZO App Mesh / Offline Network
  static final Guid serviceUuid = Guid('0000ff00-0000-1000-8000-00805f9b34fb');

  /// Characteristic for text messages and acknowledgements
  static final Guid chatCharacteristicUuid = Guid('0000ff01-0000-1000-8000-00805f9b34fb');

  /// Characteristic for real-time Walkie-Talkie (PTT) voice chunks
  static final Guid voiceCharacteristicUuid = Guid('0000ff02-0000-1000-8000-00805f9b34fb');

  /// Characteristic for AirDrop-style Magic Pairing & Hotspot Handshake
  static final Guid hotspotCharacteristicUuid = Guid('0000ff03-0000-1000-8000-00805f9b34fb');

  // Packet Types
  static const int packetTypeChat = 0x01;
  static const int packetTypeVoice = 0x02;
  static const int packetTypeHotspotOffer = 0x03;
  static const int packetTypeHotspotAck = 0x04;
  static const int packetTypePing = 0x05;

  // Maximum BLE chunk size (MTU safe fallback)
  static const int defaultChunkSize = 180;
  static const int minMtuPayload = 20;

  // Device advertising local name prefix
  static const String deviceNamePrefix = 'OZO-';
}
