import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../database/models.dart';
import 'discovery_service.dart';

/// Manages the list and state of discovered network peers
class PeerManager extends ChangeNotifier {
  final DiscoveryService discoveryService;
  final AppDatabase database;

  final Map<String, Peer> _peers = {};
  StreamSubscription<Peer>? _sub;
  Timer? _cleanupTimer;

  List<Peer> get peers => _peers.values.toList()
    ..sort((a, b) {
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;
      return b.lastSeen.compareTo(a.lastSeen);
    });

  List<Peer> get onlinePeers => peers.where((p) => p.isOnline).toList();

  PeerManager({
    required this.discoveryService,
    required this.database,
  }) {
    // Populate with known peers from DB
    _peers.addAll(database.knownPeers);

    _sub = discoveryService.onPeerDiscovered.listen(_onPeerDiscovered);

    // Check periodically for offline peers
    _cleanupTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      notifyListeners();
    });
  }

  void _onPeerDiscovered(Peer peer) {
    final existing = _peers[peer.id];
    if (existing == null ||
        existing.ip != peer.ip ||
        existing.port != peer.port ||
        existing.name != peer.name ||
        !existing.isOnline) {
      _peers[peer.id] = peer;
      database.savePeer(peer);
      notifyListeners();
    } else {
      existing.lastSeen = DateTime.now();
    }
  }

  Peer? getPeer(String id) => _peers[id];

  @override
  void dispose() {
    _sub?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}
