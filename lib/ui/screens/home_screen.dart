import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/active_chat_view.dart';
import '../widgets/group_create_dialog.dart';
import '../widgets/peer_list_tile.dart';
import '../widgets/remote_connection_dialog.dart';
import '../widgets/transfer_queue_sheet.dart';

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
        final selectedGroup = chatProvider.activeGroup;

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
                  child: selectedGroup != null
                      ? ActiveChatView(group: selectedGroup)
                      : (selectedPeer != null
                          ? ActiveChatView(peer: selectedPeer)
                          : _buildEmptyState(context)),
                ),
              ],
            ),
          );
        } else {
          // Mobile stack layout
          if (selectedGroup != null) {
            return ActiveChatView(
              group: selectedGroup,
              onBack: () => chatProvider.setActiveGroup(null),
            );
          } else if (selectedPeer != null) {
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
    final groups = provider.database.groups;

    return Container(
      color: isDark ? TelegramTheme.darkSidebar : TelegramTheme.lightSidebar,
      child: Column(
        children: [
          _buildSidebarHeader(context, provider, isDark),
          Expanded(
            child: (knownPeers.isEmpty && groups.isEmpty)
                ? _buildEmptyPeersDiagnostic(context, provider)
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // Group Chats Section
                      if (groups.isNotEmpty) ...[
                        _buildSectionHeader('GROUP CHATS (${groups.length})', isDark),
                        ...groups.map((group) {
                          final isSelected = provider.activeGroup?.id == group.id;
                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: isDark
                                ? TelegramTheme.primaryBlue.withValues(alpha: 0.15)
                                : TelegramTheme.primaryBlue.withValues(alpha: 0.1),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            onTap: () => provider.setActiveGroup(group),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.indigo.shade600,
                              child: const Icon(Icons.group_rounded, color: Colors.white, size: 20),
                            ),
                            title: Text(
                              group.name,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${group.memberIds.length} members • Host: ${group.hostName}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary,
                              ),
                            ),
                          );
                        }),
                        const Divider(height: 16, indent: 16, endIndent: 16),
                      ],
                      // Direct Peers Section
                      if (knownPeers.isNotEmpty) ...[
                        _buildSectionHeader('DISCOVERED PEERS (${knownPeers.length})', isDark),
                        ...knownPeers.map((peer) {
                          final isSelected = provider.activePeer?.id == peer.id;
                          return PeerListTile(
                            peer: peer,
                            isSelected: isSelected,
                            onTap: () => provider.setActivePeer(peer),
                          );
                        }),
                      ],
                    ],
                  ),
          ),
          _buildBottomNodeInfo(context, provider, isDark),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _buildEmptyPeersDiagnostic(BuildContext context, ChatProvider provider) {
    final isUptimeLong = provider.discoveryService.uptime.inSeconds >= 8;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUptimeLong ? Icons.wifi_lock_rounded : Icons.wifi_tethering_rounded,
              size: 48,
              color: isUptimeLong ? Colors.amber.shade700 : TelegramTheme.primaryBlue,
            ),
            const SizedBox(height: 12),
            Text(
              isUptimeLong ? 'No LAN Peers Detected' : 'Scanning LAN for Peers...',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isUptimeLong
                  ? 'If you are connected to guest, hotel, or corporate Wi-Fi, Client/AP Isolation is likely active on the router, preventing devices from communicating directly.'
                  : 'Make sure other devices are running LAN Telegram on the same subnet.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.network_check_rounded, size: 16),
              label: const Text('Network Diagnostics', style: TextStyle(fontSize: 12)),
              onPressed: () => _showDiagnosticsDialog(context, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarHeader(
    BuildContext context,
    ChatProvider provider,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'LAN Telegram',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_sync_outlined, size: 20),
              tooltip: 'Remote P2P / Cloudflare',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const RemoteConnectionDialog(),
                );
              },
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: provider.transferManager.activeTransfers.isNotEmpty,
                label: Text('${provider.transferManager.activeTransfers.length}'),
                child: const Icon(Icons.swap_vert_rounded, size: 20),
              ),
              tooltip: 'Transfer Manager',
              onPressed: () => TransferQueueSheet.show(context),
            ),
            IconButton(
              icon: const Icon(Icons.group_add_outlined, size: 20),
              tooltip: 'New Group Chat',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const GroupCreateDialog(),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Rescan LAN',
              onPressed: () {
                provider.discoveryService.broadcastBeacon();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Broadcast sent to 255.255.255.255 and subnets'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
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
            'Select a discovered peer or group to begin chatting',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  void _showDiagnosticsDialog(BuildContext context, ChatProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.network_check_rounded, color: TelegramTheme.primaryBlue),
            SizedBox(width: 8),
            Text('Network Diagnostics'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LAN Topology & Requirements:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              '1. Both devices must connect to the same Wi-Fi SSID / local subnet.\n'
              '2. Client/AP Isolation must be disabled in your Wi-Fi router settings.\n'
              '3. Broadcast is primary; multicast is soft-optional.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 20),
            Text('Listening P2P Port: ${provider.serverPort}', style: const TextStyle(fontSize: 12)),
            Text('Discovery UDP Port: 45454', style: const TextStyle(fontSize: 12)),
            Text('Device ID: ${provider.deviceId}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text('Platform: ${provider.platform.toUpperCase()}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
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
