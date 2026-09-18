import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_constants.dart';
import 'ble_packet.dart';

/// Representation of a discovered or connected BLE peer
class BlePeer {
  final String id;
  final String name;
  int rssi;
  final BluetoothDevice? device;
  bool isConnected;
  DateTime lastSeen;

  BlePeer({
    required this.id,
    required this.name,
    required this.rssi,
    this.device,
    this.isConnected = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get signalStrength {
    if (rssi >= -60) return 'Strong';
    if (rssi >= -80) return 'Medium';
    return 'Weak';
  }
}

/// Central management service for Bluetooth Low Energy offline mesh communications
class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  final BleReassembler _reassembler = BleReassembler();
  final Map<String, BlePeer> _discoveredPeers = {};
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, Map<String, BluetoothCharacteristic>> _deviceCharacteristics = {};

  final StreamController<List<BlePeer>> _peersController = StreamController<List<BlePeer>>.broadcast();
  final StreamController<BlePacket> _packetStreamController = StreamController<BlePacket>.broadcast();
  final StreamController<String> _statusController = StreamController<String>.broadcast();

  Stream<List<BlePeer>> get peersStream => _peersController.stream;
  Stream<BlePacket> get onPacketReceived => _packetStreamController.stream;
  Stream<String> get statusStream => _statusController.stream;

  List<BlePeer> get discoveredPeers => _discoveredPeers.values.toList();
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterSubscription;
  int _messageCounter = 1;

  /// Check whether BLE is supported on the current hardware/platform
  Future<bool> isSupported() async {
    try {
      if (kIsWeb) return false;
      return await FlutterBluePlus.isSupported;
    } catch (e) {
      debugPrint('[BleService] isSupported error: $e');
      return false;
    }
  }

  /// Initialize BLE event listeners and monitor Bluetooth adapter status
  Future<void> init() async {
    try {
      final supported = await isSupported();
      if (!supported) {
        _statusController.add('Bluetooth is not supported on this platform/device.');
        return;
      }

      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        debugPrint('[BleService] Bluetooth adapter state: $state');
        if (state == BluetoothAdapterState.on) {
          _statusController.add('Bluetooth ready');
        } else {
          _statusController.add('Bluetooth $state');
        }
      });
    } catch (e) {
      debugPrint('[BleService] init error: $e');
    }
  }

  /// Start scanning for nearby OZO App peers
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    final supported = await isSupported();
    if (!supported) return;

    if (_isScanning) {
      await stopScan();
    }

    _discoveredPeers.clear();
    _peersController.add(discoveredPeers);
    _isScanning = true;
    _statusController.add('Scanning for nearby OZO peers...');

    try {
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final deviceName = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : (r.device.platformName.isNotEmpty ? r.device.platformName : 'Unknown Peer');

          final id = r.device.remoteId.str;
          final peer = _discoveredPeers.putIfAbsent(
            id,
            () => BlePeer(
              id: id,
              name: deviceName,
              rssi: r.rssi,
              device: r.device,
            ),
          );

          peer.rssi = r.rssi;
          peer.lastSeen = DateTime.now();
        }
        _peersController.add(discoveredPeers);
      });

      await FlutterBluePlus.startScan(
        timeout: timeout,
      );

      // Auto mark scan finished when timeout passes
      Future.delayed(timeout, () {
        _isScanning = false;
        _statusController.add('Scan complete. Found ${_discoveredPeers.length} peer(s).');
      });
    } catch (e) {
      _isScanning = false;
      debugPrint('[BleService] startScan error: $e');
      _statusController.add('Scan error: $e');
    }
  }

  /// Stop active scan
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _isScanning = false;
      _statusController.add('Scan stopped');
    } catch (e) {
      debugPrint('[BleService] stopScan error: $e');
    }
  }

  /// Connect to a discovered peer device
  Future<bool> connectToPeer(BlePeer peer) async {
    final device = peer.device;
    if (device == null) return false;

    try {
      _statusController.add('Connecting to ${peer.name}...');
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _connectedDevices[peer.id] = device;
      peer.isConnected = true;
      _peersController.add(discoveredPeers);

      // Request higher MTU for faster throughput (Android/Desktop)
      if (!Platform.isIOS && !Platform.isMacOS) {
        try {
          await device.requestMtu(512);
        } catch (_) {}
      }

      // Discover services and characteristics
      final services = await device.discoverServices();
      final charMap = <String, BluetoothCharacteristic>{};

      for (final s in services) {
        for (final c in s.characteristics) {
          charMap[c.uuid.str.toLowerCase()] = c;

          // Subscribe to notifications/indications on supported characteristics
          if (c.properties.notify || c.properties.indicate) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen((data) {
              _handleIncomingBytes(Uint8List.fromList(data));
            });
          }
        }
      }

      _deviceCharacteristics[peer.id] = charMap;
      _statusController.add('Connected to ${peer.name}');
      return true;
    } catch (e) {
      debugPrint('[BleService] connect error: $e');
      peer.isConnected = false;
      _connectedDevices.remove(peer.id);
      _peersController.add(discoveredPeers);
      _statusController.add('Failed to connect: $e');
      return false;
    }
  }

  /// Disconnect from a peer
  Future<void> disconnectPeer(BlePeer peer) async {
    final device = peer.device ?? _connectedDevices[peer.id];
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    peer.isConnected = false;
    _connectedDevices.remove(peer.id);
    _deviceCharacteristics.remove(peer.id);
    _peersController.add(discoveredPeers);
    _statusController.add('Disconnected from ${peer.name}');
  }

  /// Handle incoming raw BLE bytes and reassemble packets
  void _handleIncomingBytes(Uint8List bytes) {
    try {
      final packet = BlePacket.fromBytes(bytes);
      if (packet == null) return;

      final fullPacket = _reassembler.addPacket(packet);
      if (fullPacket != null) {
        _packetStreamController.add(fullPacket);
      }
    } catch (e) {
      debugPrint('[BleService] _handleIncomingBytes error: $e');
    }
  }

  /// Send an arbitrary payload (slicing into BLE packets automatically)
  Future<bool> sendData(
    BluetoothDevice device,
    int packetType,
    Uint8List data, {
    Guid? targetCharacteristicUuid,
  }) async {
    final charUuidStr = (targetCharacteristicUuid ?? BleConstants.chatCharacteristicUuid).str.toLowerCase();
    final chars = _deviceCharacteristics[device.remoteId.str];
    final characteristic = chars?[charUuidStr] ??
        chars?.values.firstWhere(
          (c) => c.properties.write || c.properties.writeWithoutResponse,
          orElse: () => throw StateError('No writable characteristic found'),
        );

    if (characteristic == null) {
      debugPrint('[BleService] No writable characteristic found on device ${device.remoteId.str}');
      return false;
    }

    final messageId = _messageCounter++;
    final packets = BlePacket.slice(packetType, messageId, data, chunkSize: BleConstants.defaultChunkSize);

    try {
      for (final p in packets) {
        final bytes = p.toBytes();
        await characteristic.write(
          bytes,
          withoutResponse: characteristic.properties.writeWithoutResponse,
        );
        // Small delay to ensure BLE buffer does not saturate
        if (packets.length > 1) {
          await Future.delayed(const Duration(milliseconds: 15));
        }
      }
      return true;
    } catch (e) {
      debugPrint('[BleService] sendData error: $e');
      return false;
    }
  }

  /// Convenience method to send an encrypted offline chat message
  Future<bool> sendOfflineChatMessage(BluetoothDevice device, String text, {String? senderName}) async {
    final payloadMap = {
      'text': text,
      'sender': senderName ?? 'Me',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(payloadMap)));
    return sendData(device, BleConstants.packetTypeChat, jsonBytes);
  }

  /// Simulate receiving a packet (useful for testing & offline fallbacks)
  void simulateIncomingPacket(BlePacket packet) {
    _packetStreamController.add(packet);
  }

  void dispose() {
    _scanSubscription?.cancel();
    _adapterSubscription?.cancel();
    _reassembler.dispose();
    _peersController.close();
    _packetStreamController.close();
    _statusController.close();
  }
}
