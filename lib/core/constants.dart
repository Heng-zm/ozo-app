/// LAN Telegram App Constants
class AppConstants {
  static const String protocolVersion = 'lan-tg-v1';
  static const int defaultDiscoveryPort = 45454;
  static const int defaultP2pPort = 45455;
  static const String multicastAddress = '224.0.0.167';

  /// 512 KB per chunk for high throughput & responsive progress on LAN
  static const int defaultChunkSize = 512 * 1024;

  /// Beacon broadcast heartbeat interval
  static const Duration beaconInterval = Duration(seconds: 3);

  /// Time after which a peer is considered offline if no beacon received
  static const Duration peerOfflineThreshold = Duration(seconds: 10);

  /// WebSocket reconnect retry delay
  static const Duration reconnectDelay = Duration(seconds: 4);
}
