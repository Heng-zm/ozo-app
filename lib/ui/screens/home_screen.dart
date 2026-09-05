import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/account_dialog.dart';
import '../widgets/active_chat_view.dart';
import '../widgets/app_lock_screen.dart';
import '../widgets/backup_dialog.dart';
import '../widgets/chat_folders_bar.dart';
import '../widgets/direct_hotspot_dialog.dart';
import '../widgets/group_create_dialog.dart';
import '../widgets/linked_devices_dialog.dart';
import '../widgets/peer_list_tile.dart';
import '../widgets/remote_connection_dialog.dart';
import '../widgets/security_settings_dialog.dart';
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

    return AppLockScreen(
      child: LayoutBuilder(
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
    ));
  }

  Widget _buildSidebar(BuildContext context, ChatProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? TelegramTheme.darkSidebar : TelegramTheme.lightSidebar,
      child: Column(
        children: [
          _buildSidebarHeader(context, provider, isDark),
          _buildSearchBar(context, provider, isDark),
          const ChatFoldersBar(),
          Expanded(
            child: provider.searchQuery.isNotEmpty
                ? _buildSearchResults(context, provider, isDark)
                : _buildChatsList(context, provider, isDark),
          ),
          _buildBottomNodeInfo(context, provider, isDark),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ChatProvider provider, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        onChanged: (val) => provider.setSearchQuery(val),
        decoration: InputDecoration(
          hintText: 'Search chats or messages...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: provider.searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () => provider.setSearchQuery(''),
                )
              : null,
          filled: true,
          fillColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildChatsList(BuildContext context, ChatProvider provider, bool isDark) {
    final folder = provider.activeFolder;
    var peers = provider.database.knownPeers.values.toList();
    var groups = provider.database.groups;

    if (folder == ChatFolder.personal) {
      groups = [];
    } else if (folder == ChatFolder.groups) {
      peers = [];
    } else if (folder == ChatFolder.unread) {
      peers = peers.where((p) => provider.getUnreadCount(p.id) > 0).toList();
      groups = groups.where((g) => provider.getUnreadCount(g.id) > 0).toList();
    }

    // Sort peers: pinned first, then online first, then by lastSeen
    peers.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;
      return b.lastSeen.compareTo(a.lastSeen);
    });

    // Sort groups: pinned first, then by createdAt
    groups.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });

    if (peers.isEmpty && groups.isEmpty) {
      if (folder == ChatFolder.unread) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done_all_rounded, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text('No unread messages', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        );
      }
      return _buildEmptyPeersDiagnostic(context, provider);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Group Chats Section
        if (groups.isNotEmpty) ...[
          _buildSectionHeader('GROUP CHATS (${groups.length})', isDark),
          ...groups.map((group) {
            final isSelected = provider.activeGroup?.id == group.id;
            final unread = provider.getUnreadCount(group.id);

            return ListTile(
              selected: isSelected,
              selectedTileColor: isDark
                  ? TelegramTheme.primaryBlue.withValues(alpha: 0.15)
                  : TelegramTheme.primaryBlue.withValues(alpha: 0.1),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              onTap: () => provider.setActiveGroup(group),
              onLongPress: () => _showChatActionDialog(context, provider, group.id, group.name, group.isPinned, true),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.indigo.shade600,
                child: const Icon(Icons.group_rounded, color: Colors.white, size: 20),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (group.isPinned)
                    const Icon(Icons.push_pin_rounded, size: 14, color: TelegramTheme.primaryBlue),
                ],
              ),
              subtitle: Text(
                '${group.memberIds.length} members • Host: ${group.hostName}${group.backupHostName != null ? ' (Backup: ${group.backupHostName})' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: unread > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: TelegramTheme.primaryBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    )
                  : null,
            );
          }),
          const Divider(height: 16, indent: 16, endIndent: 16),
        ],

        // Direct Peers Section
        if (peers.isNotEmpty) ...[
          _buildSectionHeader('DISCOVERED PEERS (${peers.length})', isDark),
          ...peers.map((peer) {
            final isSelected = provider.activePeer?.id == peer.id;
            return GestureDetector(
              onSecondaryTap: () => _showChatActionDialog(context, provider, peer.id, peer.name, peer.isPinned, false),
              onLongPress: () => _showChatActionDialog(context, provider, peer.id, peer.name, peer.isPinned, false),
              child: PeerListTile(
                peer: peer,
                isSelected: isSelected,
                onTap: () => provider.setActivePeer(peer),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context, ChatProvider provider, bool isDark) {
    final query = provider.searchQuery.toLowerCase();
    final matchingPeers = provider.searchPeerResults.isNotEmpty
        ? provider.searchPeerResults
        : provider.database.knownPeers.values.where((p) =>
            p.name.toLowerCase().contains(query) || (p.username ?? '').toLowerCase().contains(query)).toList();
    final matchingGroups = provider.database.groups.where((g) =>
        g.name.toLowerCase().contains(query)).toList();
    final messageResults = provider.searchResults;

    if (matchingPeers.isEmpty && matchingGroups.isEmpty && messageResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No matches for "$query"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try searching with a different keyword or username',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (matchingGroups.isNotEmpty || matchingPeers.isNotEmpty) ...[
          _buildSectionHeader('CHATS & CONTACTS', isDark),
          ...matchingGroups.map((g) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade600,
                  child: const Icon(Icons.group_rounded, color: Colors.white, size: 20),
                ),
                title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Group • ${g.memberIds.length} members', style: const TextStyle(fontSize: 12)),
                onTap: () {
                  provider.setActiveGroup(g);
                  provider.setSearchQuery('');
                },
              )),
          ...matchingPeers.map((p) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: TelegramTheme.primaryBlue,
                  child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(p.isOnline ? 'Online' : 'Last seen recently', style: const TextStyle(fontSize: 12)),
                onTap: () {
                  provider.setActivePeer(p);
                  provider.setSearchQuery('');
                },
              )),
          const Divider(height: 16, indent: 16, endIndent: 16),
        ],
        if (messageResults.isNotEmpty) ...[
          _buildSectionHeader('MESSAGES (${messageResults.length} found)', isDark),
          ...messageResults.map((msg) {
            final chatName = msg.isGroup
                ? (provider.database.getGroup(msg.chatId)?.name ?? 'Group')
                : (provider.database.knownPeers[msg.chatId]?.name ?? msg.senderName);

            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                child: Icon(
                  msg.type == MessageType.voice
                      ? Icons.mic_rounded
                      : (msg.type == MessageType.file ? Icons.attach_file_rounded : Icons.chat_bubble_outline_rounded),
                  size: 16,
                  color: TelegramTheme.primaryBlue,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(chatName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  Text(
                    '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              subtitle: Text(
                '${msg.senderName}: ${msg.content}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                if (msg.isGroup) {
                  final grp = provider.database.getGroup(msg.chatId);
                  if (grp != null) provider.setActiveGroup(grp);
                } else {
                  final p = provider.database.knownPeers[msg.chatId];
                  if (p != null) provider.setActivePeer(p);
                }
                provider.setSearchQuery('');
              },
            );
          }),
        ],
      ],
    );
  }

  void _showChatActionDialog(
    BuildContext context,
    ChatProvider provider,
    String id,
    String name,
    bool isPinned,
    bool isGroup,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  color: TelegramTheme.primaryBlue,
                ),
                title: Text(isPinned ? 'Unpin from Top' : 'Pin to Top'),
                onTap: () {
                  Navigator.of(context).pop();
                  provider.togglePin(id, isGroup);
                },
              ),
            ],
          ),
        );
      },
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
                  ? 'We broadcasted UDP beacons to your local subnet, but no other devices replied yet.\n\nEnsure both devices are on the same Wi-Fi/LAN, or use "Remote P2P" to connect across different networks.'
                  : 'Listening for broadcasts on UDP port ${provider.discoveryService.p2pPort}...',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => const AccountDialog(),
                );
              },
              child: Tooltip(
                message: 'Account Profiles & Login',
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: TelegramTheme.primaryBlue,
                  child: Text(
                    provider.currentAccount?.avatarEmoji ?? '👤',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => const AccountDialog(),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      provider.currentAccount?.displayName ?? provider.deviceName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${provider.currentAccount?.username ?? 'user'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: TelegramTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              tooltip: 'More Features',
              onSelected: (val) {
                switch (val) {
                  case 'hotspot':
                    showDialog(
                      context: context,
                      builder: (_) => const DirectHotspotDialog(),
                    );
                    break;
                  case 'linked':
                    showDialog(
                      context: context,
                      builder: (_) => const LinkedDevicesDialog(),
                    );
                    break;
                  case 'backup':
                    showDialog(
                      context: context,
                      builder: (_) => const BackupDialog(),
                    );
                    break;
                  case 'security':
                    showDialog(
                      context: context,
                      builder: (_) => const SecuritySettingsDialog(),
                    );
                    break;
                  case 'lock':
                    provider.security.lock();
                    break;
                  case 'settings':
                    _showSettingsDialog(context, provider);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'hotspot',
                  child: Row(
                    children: [
                      Icon(Icons.wifi_tethering_rounded, size: 18, color: TelegramTheme.primaryBlue),
                      SizedBox(width: 10),
                      Text('Direct Hotspot Mode'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'linked',
                  child: Row(
                    children: [
                      Icon(Icons.devices_rounded, size: 18, color: TelegramTheme.primaryBlue),
                      SizedBox(width: 10),
                      Text('Linked Devices'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'backup',
                  child: Row(
                    children: [
                      Icon(Icons.security_update_good_rounded, size: 18, color: TelegramTheme.primaryBlue),
                      SizedBox(width: 10),
                      Text('Encrypted Backup & Vault'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'security',
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: TelegramTheme.primaryBlue),
                      SizedBox(width: 10),
                      Text('Passcode & Security'),
                    ],
                  ),
                ),
                if (provider.security.isPinConfigured)
                  const PopupMenuItem(
                    value: 'lock',
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, size: 18, color: Colors.orange),
                        SizedBox(width: 10),
                        Text('Lock App Now'),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Device Settings'),
                    ],
                  ),
                ),
              ],
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
