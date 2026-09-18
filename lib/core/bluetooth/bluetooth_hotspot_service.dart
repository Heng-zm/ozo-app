import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ble_constants.dart';
import 'ble_packet.dart';
import 'ble_service.dart';

/// Data payload for Magic Pairing & Auto-Hotspot handshake
class HotspotOffer {
  final String ssid;
  final String password;
  final String ip;
  final int port;
  final String senderName;
  final String? transferNote;

  HotspotOffer({
    required this.ssid,
    required this.password,
    required this.ip,
    required this.port,
    required this.senderName,
    this.transferNote,
  });

  Map<String, dynamic> toJson() => {
        'ssid': ssid,
        'password': password,
        'ip': ip,
        'port': port,
        'senderName': senderName,
        'transferNote': transferNote,
      };

  factory HotspotOffer.fromJson(Map<String, dynamic> json) => HotspotOffer(
        ssid: json['ssid'] as String? ?? '',
        password: json['password'] as String? ?? '',
        ip: json['ip'] as String? ?? '',
        port: json['port'] as int? ?? 8080,
        senderName: json['senderName'] as String? ?? 'Peer',
        transferNote: json['transferNote'] as String?,
      );

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static HotspotOffer? fromBytes(Uint8List bytes) {
    try {
      final str = utf8.decode(bytes);
      final json = jsonDecode(str) as Map<String, dynamic>;
      return HotspotOffer.fromJson(json);
    } catch (e) {
      debugPrint('[HotspotOffer] parse error: $e');
      return null;
    }
  }
}

/// Service managing AirDrop-style Magic Pairing over Bluetooth Low Energy
class BluetoothHotspotService {
  static final BluetoothHotspotService _instance = BluetoothHotspotService._internal();
  factory BluetoothHotspotService() => _instance;
  BluetoothHotspotService._internal();

  final StreamController<HotspotOffer> _offerController = StreamController<HotspotOffer>.broadcast();
  final StreamController<bool> _ackController = StreamController<bool>.broadcast();

  Stream<HotspotOffer> get onHotspotOfferReceived => _offerController.stream;
  Stream<bool> get onHotspotAckReceived => _ackController.stream;

  StreamSubscription<BlePacket>? _bleSubscription;

  void init(BleService bleService) {
    _bleSubscription?.cancel();
    _bleSubscription = bleService.onPacketReceived.listen((packet) {
      if (packet.packetType == BleConstants.packetTypeHotspotOffer) {
        final offer = HotspotOffer.fromBytes(packet.payload);
        if (offer != null) {
          _offerController.add(offer);
        }
      } else if (packet.packetType == BleConstants.packetTypeHotspotAck) {
        final accepted = packet.payload.isNotEmpty && packet.payload[0] == 1;
        _ackController.add(accepted);
      }
    });
  }

  /// Sends AirDrop-style Wi-Fi credentials to a discovered BLE peer
  Future<bool> sendOffer(BleService bleService, BlePeer peer, HotspotOffer offer) async {
    final device = peer.device;
    if (device == null) return false;

    return bleService.sendData(
      device,
      BleConstants.packetTypeHotspotOffer,
      offer.toBytes(),
      targetCharacteristicUuid: BleConstants.hotspotCharacteristicUuid,
    );
  }

  /// Sends acceptance or rejection of a received Hotspot Offer
  Future<bool> sendAck(BleService bleService, BlePeer peer, bool accepted) async {
    final device = peer.device;
    if (device == null) return false;

    final payload = Uint8List.fromList([accepted ? 1 : 0]);
    return bleService.sendData(
      device,
      BleConstants.packetTypeHotspotAck,
      payload,
      targetCharacteristicUuid: BleConstants.hotspotCharacteristicUuid,
    );
  }

  void dispose() {
    _bleSubscription?.cancel();
    _offerController.close();
    _ackController.close();
  }
}
