import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/active_chat_view.dart';
import '../widgets/peer_list_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    if (!chatProvider.isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: TelegramTheme.primaryBlue),
              SizedBox(height: 16),
              Text(
                'Starting LAN Telegram Node...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;
        final selectedPeer = chatProvider.activePeer;

        if (isDesktop) {
          // Desktop 2-column Telegram layout
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 320,
                  child: _buildSidebar(context, chatProvider),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: selectedPeer != null
                      ? ActiveChatView(peer: selectedPeer)
                      : _buildEmptyState(context),
                ),
              ],
            ),
          );
        } else {
          // Mobile stack layout
          if (selectedPeer != null) {
            return ActiveChatView(
              peer: selectedPeer,
              onBack: () => chatProvider.setActivePeer(null),
            );
          } else {
            return Scaffold(
              body: _buildSidebar(context, chatProvider),
            );
          }
        }
      },
    );
  }

  Widget _buildSidebar(BuildContext context, ChatProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final knownPeers = provider.database.knownPeers.values.toList()
      ..sort((a, b) {
        if (a.isOnline && !b.isOnline) return -1;
        if (!a.isOnline && b.isOnline) return 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });

    return Container(
      color: isDark ? TelegramTheme.darkSidebar : TelegramTheme.lightSidebar,
      child: Column(
        children: [
          _buildSidebarHeader(context, provider, isDark),
          Expanded(
            child: knownPeers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_tethering_rounded,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Searching for peers on LAN...',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Open the app on another device connected to the same Wi-Fi or subnet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: knownPeers.length,
                    itemBuilder: (context, index) {
                      final peer = knownPeers[index];
                      final isSelected = provider.activePeer?.id == peer.id;
                      return PeerListTile(
                        peer: peer,
                        isSelected: isSelected,
                        onTap: () => provider.setActivePeer(peer),
                      );
                    },
                  ),
          ),
          _buildBottomNodeInfo(context, provider, isDark),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(
    BuildContext context,
    ChatProvider provider,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? TelegramTheme.darkSidebar : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: TelegramTheme.primaryBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: TelegramTheme.primaryBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'LAN Telegram',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Rescan LAN',
              onPressed: () {
                provider.discoveryService.broadcastBeacon();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sent discovery broadcast to LAN'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Device Settings',
              onPressed: () => _showSettingsDialog(context, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNodeInfo(
    BuildContext context,
    ChatProvider provider,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.circle,
            color: TelegramTheme.onlineGreen,
            size: 10,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${provider.deviceName} (Port ${provider.serverPort})',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? TelegramTheme.darkChatBg : TelegramTheme.lightChatBg,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Select a discovered device to begin chatting',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, ChatProvider provider) {
    final controller = TextEditingController(text: provider.deviceName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Node Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Device Name (shown to LAN peers)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Platform: ${provider.platform.toUpperCase()}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'P2P Server Port: ${provider.serverPort}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your Public Key Fingerprint (E2EE):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    provider.cryptoService.publicKeyBase64 ?? 'N/A',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: provider.cryptoService.publicKeyBase64 ?? ''),
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Public key copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.updateDeviceName(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
