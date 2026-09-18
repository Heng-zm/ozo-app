import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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
import 'package:flutter/cupertino.dart';
import '../widgets/bluetooth_discovery_sheet.dart';
import '../widgets/in_app_notification_banner.dart';
import '../widgets/security_settings_dialog.dart';
import '../widgets/transfer_queue_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<InAppNotificationItem>? _notifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ChatProvider>();
      _notifSub = provider.inAppNotificationStream.listen((item) {
        if (!mounted) return;
        InAppNotificationBanner.show(
          context,
          title: item.title,
          message: item.message,
          icon: item.icon,
          iconColor: item.iconColor,
          duration: item.duration,
        );
      });
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

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
          final screenWidth = constraints.maxWidth;
          final isDesktop = screenWidth >= 1100;
          final isWideScreen = screenWidth >= 768;
          final selectedPeer = chatProvider.activePeer;
          final selectedGroup = chatProvider.activeGroup;

          if (isWideScreen) {
            // Multi-tier Tablet & Desktop 2-column layout with adaptive sidebar width
            final sidebarWidth = isDesktop
                ? 360.0
                : (screenWidth * 0.36).clamp(280.0, 330.0);

            return Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: sidebarWidth,
                    child: _buildSidebar(context, chatProvider),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(selectedGroup?.id ?? selectedPeer?.id ?? 'empty'),
                        child: selectedGroup != null
                            ? ActiveChatView(group: selectedGroup)
                            : (selectedPeer != null
                                ? ActiveChatView(peer: selectedPeer)
                                : _buildEmptyState(context)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else {
            // Mobile stack layout with iOS slide & fade transitions and edge-swipe back
            final hasActiveChat = selectedGroup != null || selectedPeer != null;

            return PopScope(
              canPop: !hasActiveChat,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (hasActiveChat) {
                  HapticFeedback.lightImpact();
                  chatProvider.setActiveGroup(null);
                  chatProvider.setActivePeer(null);
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final isChat = child.key == const ValueKey('active_chat_pane');
                  if (isChat) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1.0, 0.0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(
                        opacity: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
                        child: child,
                      ),
                    );
                  } else {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(-0.25, 0.0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  }
                },
                child: hasActiveChat
                    ? _IosSwipeBackDetector(
                        key: const ValueKey('active_chat_pane'),
                        onBack: () {
                          HapticFeedback.lightImpact();
                          chatProvider.setActiveGroup(null);
                          chatProvider.setActivePeer(null);
                        },
                        child: selectedGroup != null
                            ? ActiveChatView(
                                group: selectedGroup,
                                onBack: () {
                                  HapticFeedback.lightImpact();
                                  chatProvider.setActiveGroup(null);
                                },
                              )
                            : ActiveChatView(
                                peer: selectedPeer!,
                                onBack: () {
                                  HapticFeedback.lightImpact();
                                  chatProvider.setActivePeer(null);
                                },
                              ),
                      )
                    : Scaffold(
                        key: const ValueKey('sidebar_pane'),
                        body: _buildSidebar(context, chatProvider),
                      ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, ChatProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? TelegramTheme.darkSidebar : TelegramTheme.lightSidebar,
      child: Column(
        children: [
          _buildSidebarHeader(context, provider, isDark),
          if (provider.pendingBackupMigration != null)
            _buildPendingMigrationBanner(context, provider, isDark),
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

  Widget _buildPendingMigrationBanner(
    BuildContext context,
    ChatProvider provider,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TelegramTheme.primaryBlue.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_download_rounded,
                color: TelegramTheme.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Incoming Backup Migration',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => provider.clearPendingBackupMigration(),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A peer sent an encrypted account backup. Tap to restore.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: TelegramTheme.primaryBlue,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                final payload = provider.pendingBackupMigration;
                if (payload != null) {
                  showDialog(
                    context: context,
                    builder: (_) => BackupDialog(
                      initialTabIndex: 1,
                      initialPayload: jsonEncode(payload),
                    ),
                  );
                }
              },
              child: const Text('Restore Backup', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ChatProvider provider, bool isDark) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: TextField(
        onChanged: (val) => provider.setSearchQuery(val),
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: const TextStyle(
            fontSize: 14,
            color: IosTheme.systemGray,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 19,
            color: IosTheme.systemGray,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: provider.searchQuery.isNotEmpty
              ? IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.cancel_rounded, size: 16, color: IosTheme.systemGray),
                  onPressed: () => provider.setSearchQuery(''),
                )
              : null,
          filled: true,
          fillColor: isDark ? IosTheme.searchFieldDark : IosTheme.searchFieldLight,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
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

    // Sort groups: pinned first, then by createdAt (newest first)
    groups.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        // Group Chats Section
        if (groups.isNotEmpty) ...[
          _buildSectionHeader('GROUPS', isDark),
          ...groups.map((group) {
            final isSelected = provider.activeGroup?.id == group.id;
            final unread = provider.getUnreadCount(group.id);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PressScaleTile(
                  child: ListTile(
                    selected: isSelected,
                    selectedTileColor: isDark
                        ? TelegramTheme.primaryBlue.withValues(alpha: 0.15)
                        : TelegramTheme.primaryBlue.withValues(alpha: 0.1),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      provider.setActiveGroup(group);
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      _showChatActionDialog(context, provider, group.id, group.name, group.isPinned, true);
                    },
                    leading: CircleAvatar(
                      radius: 24,
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
                              fontSize: 15,
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
                        fontSize: 12,
                        color: isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: TelegramTheme.primaryBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: isSelected
                              ? TelegramTheme.primaryBlue
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 76,
                  endIndent: 0,
                  color: isDark ? IosTheme.hairlineDark : IosTheme.hairlineLight,
                ),
              ],
            );
          }),
        ],

        // Direct Peers Section
        if (peers.isNotEmpty) ...[
          _buildSectionHeader('CHATS', isDark),
          ...peers.map((peer) {
            final isSelected = provider.activePeer?.id == peer.id;
            return GestureDetector(
              onSecondaryTap: () => _showChatActionDialog(context, provider, peer.id, peer.name, peer.isPinned, false),
              onLongPress: () {
                HapticFeedback.mediumImpact();
                _showChatActionDialog(context, provider, peer.id, peer.name, peer.isPinned, false);
              },
              child: PeerListTile(
                peer: peer,
                isSelected: isSelected,
                unreadCount: provider.getUnreadCount(peer.id),
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
                  HapticFeedback.lightImpact();
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
                  HapticFeedback.lightImpact();
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
    final activeTransfersCount = provider.transferManager.activeTransfers.length;
    final onlinePeersCount = provider.database.knownPeers.values.where((p) => p.isOnline).length;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC17212B) : Colors.white.withValues(alpha: 0.85),
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
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: TelegramTheme.primaryBlue,
                        child: Text(
                          provider.currentAccount?.avatarEmoji ?? '👤',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C853),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? const Color(0xFF17212B) : Colors.white,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                          onlinePeersCount > 0
                              ? '$onlinePeersCount peer${onlinePeersCount == 1 ? '' : 's'} online'
                              : 'Offline / Scanning',
                          style: TextStyle(
                            fontSize: 11,
                            color: onlinePeersCount > 0 ? const Color(0xFF00C853) : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Compose '+' popup menu
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: TelegramTheme.primaryBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_rounded, size: 20, color: TelegramTheme.primaryBlue),
                  ),
                  tooltip: 'New Chat / Connect',
                  onSelected: (val) {
                    switch (val) {
                      case 'group':
                        showDialog(
                          context: context,
                          builder: (_) => const GroupCreateDialog(),
                        );
                        break;
                      case 'remote':
                        showDialog(
                          context: context,
                          builder: (_) => const RemoteConnectionDialog(),
                        );
                        break;
                      case 'hotspot':
                        showDialog(
                          context: context,
                          builder: (_) => const DirectHotspotDialog(),
                        );
                        break;
                      case 'rescan':
                        provider.discoveryService.broadcastBeacon();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Broadcast sent to 255.255.255.255 and subnets'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'group',
                      child: Row(
                        children: [
                          Icon(Icons.group_add_outlined, size: 18, color: TelegramTheme.primaryBlue),
                          SizedBox(width: 10),
                          Text('New Group Chat'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'remote',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_sync_outlined, size: 18, color: TelegramTheme.primaryBlue),
                          SizedBox(width: 10),
                          Text('Remote P2P / Cloudflare'),
                        ],
                      ),
                    ),
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
                      value: 'rescan',
                      child: Row(
                        children: [
                          Icon(Icons.refresh_rounded, size: 18, color: TelegramTheme.primaryBlue),
                          SizedBox(width: 10),
                          Text('Rescan LAN Beacons'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                // Hub '...' popup menu
                PopupMenuButton<String>(
                  icon: Badge(
                    isLabelVisible: activeTransfersCount > 0,
                    label: Text('$activeTransfersCount'),
                    child: const Icon(Icons.more_vert_rounded, size: 20),
                  ),
                  tooltip: 'Hub & Settings',
                  onSelected: (val) {
                    switch (val) {
                      case 'transfers':
                        TransferQueueSheet.show(context);
                        break;
                      case 'bluetooth':
                        BluetoothDiscoverySheet.show(context);
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
                    PopupMenuItem(
                      value: 'transfers',
                      child: Row(
                        children: [
                          const Icon(Icons.swap_vert_rounded, size: 18, color: TelegramTheme.primaryBlue),
                          const SizedBox(width: 10),
                          Text(activeTransfersCount > 0
                              ? 'Transfers ($activeTransfersCount active)'
                              : 'Transfer Manager'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'bluetooth',
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.bluetooth,
                            size: 18,
                            color: provider.selectedBlePeer != null
                                ? TelegramTheme.primaryBlue
                                : const Color(0xFF007AFF),
                          ),
                          const SizedBox(width: 10),
                          const Text('Bluetooth Offline Mesh'),
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

/// Detects edge swipe from left border on iOS mobile to pop active chat
class _IosSwipeBackDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onBack;

  const _IosSwipeBackDetector({
    super.key,
    required this.child,
    required this.onBack,
  });

  @override
  State<_IosSwipeBackDetector> createState() => _IosSwipeBackDetectorState();
}

class _IosSwipeBackDetectorState extends State<_IosSwipeBackDetector> {
  double _dragStartX = 0;
  bool _isEligibleSwipe = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        if (details.globalPosition.dx <= 36) {
          _dragStartX = details.globalPosition.dx;
          _isEligibleSwipe = true;
        } else {
          _isEligibleSwipe = false;
        }
      },
      onHorizontalDragUpdate: (details) {
        if (!_isEligibleSwipe) return;
        if (details.globalPosition.dx - _dragStartX > 70) {
          _isEligibleSwipe = false;
          widget.onBack();
        }
      },
      onHorizontalDragEnd: (_) {
        _isEligibleSwipe = false;
      },
      onHorizontalDragCancel: () {
        _isEligibleSwipe = false;
      },
      child: widget.child,
    );
  }
}

/// Springy scale feedback tile on touch
class _PressScaleTile extends StatefulWidget {
  final Widget child;
  const _PressScaleTile({required this.child});

  @override
  State<_PressScaleTile> createState() => _PressScaleTileState();
}

class _PressScaleTileState extends State<_PressScaleTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: widget.child,
      ),
    );
  }
}

