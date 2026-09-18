import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bluetooth/ble_service.dart';
import '../../core/bluetooth/bluetooth_hotspot_service.dart';
import '../../core/bluetooth/bluetooth_walkie_talkie.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

/// Bottom sheet dialog for Bluetooth Low Energy mesh discovery, walkie-talkie, and magic pairing
class BluetoothDiscoverySheet extends StatefulWidget {
  const BluetoothDiscoverySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const BluetoothDiscoverySheet(),
    );
  }

  @override
  State<BluetoothDiscoverySheet> createState() => _BluetoothDiscoverySheetState();
}

class _BluetoothDiscoverySheetState extends State<BluetoothDiscoverySheet> {
  StreamSubscription? _peersSub;
  StreamSubscription? _hotspotOfferSub;
  List<BlePeer> _peers = [];
  bool _isScanning = false;
  String _statusText = 'Ready';

  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<ChatProvider>();
    _isScanning = provider.bleService.isScanning;
    _peers = provider.bleService.discoveredPeers;

    _peersSub = provider.bleService.peersStream.listen((peers) {
      if (mounted) {
        setState(() {
          _peers = peers;
        });
      }
    });

    provider.bleService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _statusText = status;
        });
      }
    });

    // Listen for incoming Magic Pairing / Hotspot offers
    _hotspotOfferSub = provider.hotspotService.onHotspotOfferReceived.listen((offer) {
      if (!mounted) return;
      _showIncomingHotspotOfferDialog(offer);
    });

    // Auto start scan when sheet opens
    provider.bleService.startScan();
    _isScanning = true;
  }

  void _showIncomingHotspotOfferDialog(HotspotOffer offer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(CupertinoIcons.wifi, color: TelegramTheme.primaryBlue),
            const SizedBox(width: 8),
            Text('AirDrop Hotspot: ${offer.senderName}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${offer.senderName} wants to share a high-speed Wi-Fi hotspot for fast file transfers:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SSID: ${offer.ssid}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Password: ${offer.password}'),
                  const SizedBox(height: 4),
                  Text('Host: ${offer.ip}:${offer.port}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Connecting to ${offer.ssid} (${offer.ip}:${offer.port})...'),
                  backgroundColor: TelegramTheme.primaryBlue,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: TelegramTheme.primaryBlue),
            child: const Text('Connect & Transfer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _startSharingHotspot(BlePeer peer) {
    final provider = context.read<ChatProvider>();
    _ssidController.text = 'OZO-Hotspot-${provider.deviceName}';
    _passwordController.text = 'ozo123456';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Magic Pairing: Share Hotspot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Beam your Wi-Fi Hotspot credentials to peer via Bluetooth for instant high-speed file transfers:'),
            const SizedBox(height: 12),
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(labelText: 'Hotspot SSID', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password (WPA2)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final offer = HotspotOffer(
                ssid: _ssidController.text.trim(),
                password: _passwordController.text.trim(),
                ip: '192.168.43.1', // Default standard mobile hotspot gateway
                port: provider.serverPort,
                senderName: provider.deviceName,
              );
              final ok = await provider.hotspotService.sendOffer(provider.bleService, peer, offer);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Hotspot offer sent over Bluetooth!' : 'Failed to send offer'),
                    backgroundColor: ok ? TelegramTheme.onlineGreen : Colors.redAccent,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: TelegramTheme.primaryBlue),
            child: const Text('Beam Credentials', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _hotspotOfferSub?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.bluetooth, color: Color(0xFF007AFF), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bluetooth Offline Mesh',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isScanning ? CupertinoIcons.stop_circle : CupertinoIcons.arrow_clockwise,
                    color: TelegramTheme.primaryBlue,
                  ),
                  onPressed: () {
                    if (_isScanning) {
                      provider.bleService.stopScan();
                      setState(() => _isScanning = false);
                    } else {
                      provider.bleService.startScan();
                      setState(() => _isScanning = true);
                    }
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Real-time Walkie-Talkie (PTT) Mini Controller
          _buildWalkieTalkieBanner(provider, isDark),

          const Divider(height: 1),

          // Discovered Peers List
          Expanded(
            child: _peers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isScanning)
                          const CupertinoActivityIndicator(radius: 14)
                        else
                          Icon(CupertinoIcons.bluetooth, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          _isScanning ? 'Scanning for nearby BLE devices...' : 'No Bluetooth peers found yet',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _peers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
                    itemBuilder: (ctx, idx) {
                      final peer = _peers[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: peer.isConnected
                              ? TelegramTheme.onlineGreen.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.2),
                          child: Icon(
                            peer.isConnected ? CupertinoIcons.antenna_radiowaves_left_right : CupertinoIcons.bluetooth,
                            color: peer.isConnected ? TelegramTheme.onlineGreen : Colors.grey,
                            size: 20,
                          ),
                        ),
                        title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('RSSI: ${peer.rssi} dBm (${peer.signalStrength})'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(CupertinoIcons.wifi, color: TelegramTheme.primaryBlue),
                              tooltip: 'Beam Hotspot',
                              onPressed: () => _startSharingHotspot(peer),
                            ),
                            if (!peer.isConnected)
                              ElevatedButton(
                                onPressed: () async {
                                  final ok = await provider.bleService.connectToPeer(peer);
                                  if (ok) {
                                    provider.setSelectedBlePeer(peer);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TelegramTheme.primaryBlue,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                ),
                                child: const Text('Connect', style: TextStyle(color: Colors.white, fontSize: 12)),
                              )
                            else
                              OutlinedButton(
                                onPressed: () => provider.bleService.disconnectPeer(peer),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                ),
                                child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalkieTalkieBanner(ChatProvider provider, bool isDark) {
    return StreamBuilder<WalkieTalkieState>(
      stream: provider.walkieTalkie.stateStream,
      initialData: provider.walkieTalkie.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? WalkieTalkieState.idle;
        final isRecording = state == WalkieTalkieState.recording;
        final isTransmitting = state == WalkieTalkieState.transmitting;
        final isPlaying = state == WalkieTalkieState.playing;

        Color bannerColor = TelegramTheme.primaryBlue;
        String statusText = 'Hold PTT button below to speak';
        if (isRecording) {
          bannerColor = Colors.redAccent;
          statusText = 'Recording Voice... Speak now!';
        } else if (isTransmitting) {
          bannerColor = Colors.orange;
          statusText = 'Transmitting Voice over BLE...';
        } else if (isPlaying) {
          bannerColor = TelegramTheme.onlineGreen;
          statusText = 'Receiving Walkie-Talkie Audio...';
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bannerColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    isRecording
                        ? CupertinoIcons.mic_fill
                        : (isPlaying ? CupertinoIcons.volume_up : CupertinoIcons.radiowaves_right),
                    color: bannerColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bluetooth Walkie-Talkie (PTT)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          statusText,
                          style: TextStyle(fontSize: 12, color: bannerColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Push to talk big button
              GestureDetector(
                onTapDown: (_) => provider.walkieTalkie.startTalking(),
                onTapUp: (_) => provider.walkieTalkie.stopTalkingAndTransmit(
                  provider.bleService,
                  provider.selectedBlePeer ?? (_peers.isNotEmpty ? _peers.first : null),
                ),
                onTapCancel: () => provider.walkieTalkie.cancelTalking(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isRecording ? Colors.redAccent : bannerColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (isRecording ? Colors.redAccent : bannerColor).withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isRecording ? CupertinoIcons.waveform : CupertinoIcons.mic_fill,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isRecording ? 'RELEASE TO SEND VOICE' : 'PUSH TO TALK (PTT)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
