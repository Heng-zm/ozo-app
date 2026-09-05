import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../constants.dart';
import '../database/models.dart';

/// UDP Beacon & Probe Discovery Service
/// Discovers other instances on the LAN without cloud servers.
class DiscoveryService {
  final String deviceId;
  final String deviceName;
  final int p2pPort;
  final String publicKey;
  final String platform;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  final _peerDiscoveredController = StreamController<Peer>.broadcast();

  Stream<Peer> get onPeerDiscovered => _peerDiscoveredController.stream;

  DiscoveryService({
    required this.deviceId,
    required this.deviceName,
    required this.p2pPort,
    required this.publicKey,
    required this.platform,
  });

  /// Starts listening for UDP beacons and broadcasts periodic announcements
  Future<void> start() async {
    await stop();

    try {
      // Bind to any IPv4 on the default discovery port
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.defaultDiscoveryPort,
        reuseAddress: true,
      );

      _socket?.broadcastEnabled = true;
      _socket?.multicastLoopback = false;

      try {
        _socket?.joinMulticast(InternetAddress(AppConstants.multicastAddress));
      } catch (_) {
        // Multicast might not be supported on all network interfaces
      }

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });

      // Send immediate probe and beacon
      broadcastBeacon();

      // Periodically broadcast beacon
      _beaconTimer = Timer.periodic(AppConstants.beaconInterval, (_) {
        broadcastBeacon();
      });
    } catch (e) {
      // If port 45454 is already bound by another process without reuseAddress,
      // fallback to ephemeral port for listening & sending probes.
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        _socket?.broadcastEnabled = true;
        _socket?.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handleDatagram(datagram);
            }
          }
        });

        broadcastBeacon();
        _beaconTimer = Timer.periodic(AppConstants.beaconInterval, (_) {
          broadcastBeacon();
        });
      } catch (_) {}
    }
  }

  /// Sends a broadcast beacon packet to the LAN
  void broadcastBeacon() {
    if (_socket == null) return;

    final payload = jsonEncode({
      'proto': AppConstants.protocolVersion,
      'type': 'BEACON',
      'id': deviceId,
      'name': deviceName,
      'port': p2pPort,
      'pubKey': publicKey,
      'platform': platform,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    final data = utf8.encode(payload);

    try {
      // Subnet broadcast
      _socket?.send(
        data,
        InternetAddress('255.255.255.255'),
        AppConstants.defaultDiscoveryPort,
      );
    } catch (_) {}

    try {
      // Multicast broadcast
      _socket?.send(
        data,
        InternetAddress(AppConstants.multicastAddress),
        AppConstants.defaultDiscoveryPort,
      );
    } catch (_) {}
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>;

      if (json['proto'] != AppConstants.protocolVersion) return;

      final remoteDeviceId = json['id'] as String?;
      // Ignore self-broadcasts
      if (remoteDeviceId == null || remoteDeviceId == deviceId) return;

      final peer = Peer(
        id: remoteDeviceId,
        name: json['name'] as String? ?? 'Device',
        ip: datagram.address.address,
        port: json['port'] as int? ?? AppConstants.defaultP2pPort,
        publicKey: json['pubKey'] as String? ?? '',
        platform: json['platform'] as String? ?? 'unknown',
        lastSeen: DateTime.now(),
      );

      _peerDiscoveredController.add(peer);
    } catch (_) {
      // Bad packet or non-JSON data ignored
    }
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stop();
    _peerDiscoveredController.close();
  }
}
