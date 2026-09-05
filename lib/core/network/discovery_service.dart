import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../constants.dart';
import '../database/models.dart';

/// Broadcast-First UDP Beacon & Probe Discovery Service
/// Prioritizes subnet broadcast and directed-broadcast addresses;
/// treats multicast as an optional, soft-failing enhancement.
class DiscoveryService {
  String deviceId;
  String deviceName;
  final int p2pPort;
  final String publicKey;
  final String platform;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  final _peerDiscoveredController = StreamController<Peer>.broadcast();

  final List<String> _directedBroadcastAddresses = [];
  DateTime? _lastPeerDiscoveredAt;
  final DateTime _startedAt = DateTime.now();

  Stream<Peer> get onPeerDiscovered => _peerDiscoveredController.stream;
  DateTime? get lastPeerDiscoveredAt => _lastPeerDiscoveredAt;
  bool get hasDiscoveredAnyPeer => _lastPeerDiscoveredAt != null;
  Duration get uptime => DateTime.now().difference(_startedAt);

  DiscoveryService({
    required this.deviceId,
    required this.deviceName,
    required this.p2pPort,
    required this.publicKey,
    required this.platform,
  });

  void updateIdentity({String? deviceId, String? deviceName}) {
    if (deviceId != null) this.deviceId = deviceId;
    if (deviceName != null) this.deviceName = deviceName;
  }

  /// Starts listening for UDP beacons and broadcasts periodic announcements
  Future<void> start() async {
    await stop();
    await _resolveDirectedBroadcastAddresses();

    try {
      // Primary: Bind to any IPv4 on default discovery port
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.defaultDiscoveryPort,
        reuseAddress: true,
      );

      _socket?.broadcastEnabled = true;
      _socket?.multicastLoopback = false;

      // Soft-fail multicast enhancement only
      try {
        _socket?.joinMulticast(InternetAddress(AppConstants.multicastAddress));
      } catch (_) {
        // Silently ignore multicast denial on iOS/Android
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
      // Ephemeral fallback port if default is bound
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

  /// Discovers local network interfaces and computes directed subnet broadcasts (e.g. 192.168.1.255)
  Future<void> _resolveDirectedBroadcastAddresses() async {
    _directedBroadcastAddresses.clear();
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              // Standard /24 broadcast address
              final directed = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              if (!_directedBroadcastAddresses.contains(directed)) {
                _directedBroadcastAddresses.add(directed);
              }
            }
          }
        }
      }

      // Add direct routerless hotspot subnets (Android, iOS, Windows, Wi-Fi Direct)
      const directHotspotSubnets = [
        '192.168.43.255',  // Android Mobile Hotspot
        '172.20.10.255',   // iOS Personal Hotspot
        '192.168.137.255', // Windows Mobile Hotspot
        '192.168.49.255',  // Android Wi-Fi Direct
        '10.0.0.255',      // Ad-hoc portable hotspot
      ];
      for (final subnet in directHotspotSubnets) {
        if (!_directedBroadcastAddresses.contains(subnet)) {
          _directedBroadcastAddresses.add(subnet);
        }
      }
    } catch (_) {}
  }

  /// Retrieves the active local IP address for Hotspot & Direct connect
  Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Sends a broadcast beacon packet across all broadcast channels
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

    // 1. Primary universal broadcast
    try {
      _socket?.send(
        data,
        InternetAddress('255.255.255.255'),
        AppConstants.defaultDiscoveryPort,
      );
    } catch (_) {}

    // 2. Interface-directed subnet broadcasts (e.g. 192.168.1.255)
    for (final directedIp in _directedBroadcastAddresses) {
      try {
        _socket?.send(
          data,
          InternetAddress(directedIp),
          AppConstants.defaultDiscoveryPort,
        );
      } catch (_) {}
    }

    // 3. Optional multicast enhancement (soft-fail)
    try {
      _socket?.send(
        data,
        InternetAddress(AppConstants.multicastAddress),
        AppConstants.defaultDiscoveryPort,
      );
    } catch (_) {}

    // 4. Local loopback broadcast (for 2+ instances running on same PC)
    try {
      _socket?.send(
        data,
        InternetAddress.loopbackIPv4,
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

      _lastPeerDiscoveredAt = DateTime.now();

      final peer = Peer(
        id: remoteDeviceId,
        name: json['name'] as String? ?? 'Device',
        ip: datagram.address.address,
        port: json['port'] as int? ?? AppConstants.defaultP2pPort,
        publicKey: json['pubKey'] as String? ?? '',
        platform: json['platform'] as String? ?? 'unknown',
        lastSeen: DateTime.now(),
      );

      if (!_peerDiscoveredController.isClosed) {
        _peerDiscoveredController.add(peer);
      }
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
