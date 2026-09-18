import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'safety_number_dialog.dart';
import 'bluetooth_discovery_sheet.dart';

class ChatDetailsSheet extends StatelessWidget {
  final Peer? peer;
  final GroupChat? group;
  final VoidCallback? onSearchTap;

  const ChatDetailsSheet({
    super.key,
    this.peer,
    this.group,
    this.onSearchTap,
  }) : assert(peer != null || group != null);

  static void show(
    BuildContext context, {
    Peer? peer,
    GroupChat? group,
    VoidCallback? onSearchTap,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChatDetailsSheet(
        peer: peer,
        group: group,
        onSearchTap: onSearchTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<ChatProvider>();
    final isGroup = group != null;

    final name = isGroup ? group!.name : peer!.name;
    final isOnline = isGroup ? provider.isGroupHostOnline : peer!.isOnline;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (ctx, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              color: isDark ? const Color(0xF018222D) : Colors.white.withValues(alpha: 0.96),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black26,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Avatar & Title Header
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundColor: isGroup
                              ? Colors.indigo.shade600
                              : TelegramTheme.primaryBlue,
                          child: Text(
                            isGroup
                                ? '👥'
                                : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
                            style: TextStyle(
                              fontSize: isGroup ? 36 : 38,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        // Subtitle: Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isOnline ? TelegramTheme.onlineGreen : Colors.grey)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isGroup
                                ? '${group!.memberIds.length} members • Host: ${group!.hostName}'
                                : (isOnline
                                    ? (peer!.isRemote
                                        ? 'Cloudflare Remote Tunnel'
                                        : 'LAN Online • ${peer!.ip}:${peer!.port}')
                                    : 'Offline • Last seen recently'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isOnline ? TelegramTheme.onlineGreen : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Action Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (!isGroup)
                        _buildActionCircle(
                          context,
                          icon: CupertinoIcons.phone_fill,
                          label: 'Call',
                          color: TelegramTheme.primaryBlue,
                          onTap: () {
                            Navigator.of(context).pop();
                            provider.startCall(peer!);
                          },
                        ),
                      _buildActionCircle(
                        context,
                        icon: CupertinoIcons.search,
                        label: 'Search',
                        color: const Color(0xFF6366F1),
                        onTap: () {
                          Navigator.of(context).pop();
                          onSearchTap?.call();
                        },
                      ),
                      if (!isGroup)
                        _buildActionCircle(
                          context,
                          icon: peer!.hasIdentityConflict
                              ? CupertinoIcons.exclamationmark_shield_fill
                              : CupertinoIcons.shield_fill,
                          label: 'Encryption',
                          color: peer!.hasIdentityConflict
                              ? Colors.orange
                              : TelegramTheme.onlineGreen,
                          onTap: () {
                            Navigator.of(context).pop();
                            showDialog(
                              context: context,
                              builder: (_) => SafetyNumberDialog(peer: peer!),
                            );
                          },
                        ),
                      _buildActionCircle(
                        context,
                        icon: CupertinoIcons.timer_fill,
                        label: 'Timer',
                        color: const Color(0xFFE11D48),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showTimerDialog(context, provider);
                        },
                      ),
                      _buildActionCircle(
                        context,
                        icon: CupertinoIcons.waveform_circle_fill,
                        label: 'Walkie',
                        color: const Color(0xFF0284C7),
                        onTap: () {
                          Navigator.of(context).pop();
                          BluetoothDiscoverySheet.show(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Content Sections
                  if (!isGroup) ...[
                    _buildSectionHeader('CRYPTOGRAPHIC IDENTITY (TOFU)', isDark),
                    _buildCard(
                      isDark: isDark,
                      children: [
                        _buildInfoTile(
                          icon: CupertinoIcons.lock_shield_fill,
                          iconColor: TelegramTheme.onlineGreen,
                          title: 'Safety Fingerprint',
                          subtitle: peer!.safetyFingerprint,
                          trailing: IconButton(
                            icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                            tooltip: 'Copy Fingerprint',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: peer!.safetyFingerprint));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Safety fingerprint copied'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ),
                        Divider(height: 1, indent: 48, color: isDark ? Colors.white12 : Colors.black12),
                        _buildInfoTile(
                          icon: CupertinoIcons.device_phone_portrait,
                          iconColor: TelegramTheme.primaryBlue,
                          title: 'Platform & Address',
                          subtitle: '${peer!.platform.toUpperCase()} • ${peer!.ip}:${peer!.port}',
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildSectionHeader('GROUP HOST & FAILOVER', isDark),
                    _buildCard(
                      isDark: isDark,
                      children: [
                        _buildInfoTile(
                          icon: CupertinoIcons.person_badge_plus_fill,
                          iconColor: TelegramTheme.primaryBlue,
                          title: 'Primary Host',
                          subtitle: group!.hostName,
                        ),
                        if (group!.backupHostName != null) ...[
                          Divider(height: 1, indent: 48, color: isDark ? Colors.white12 : Colors.black12),
                          _buildInfoTile(
                            icon: CupertinoIcons.shield_lefthalf_fill,
                            iconColor: Colors.amber.shade700,
                            title: 'Backup Failover Host',
                            subtitle: group!.backupHostName!,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionHeader('MEMBERS (${group!.memberIds.length})', isDark),
                    _buildCard(
                      isDark: isDark,
                      children: group!.memberIds.map((mId) {
                        final mPeer = provider.database.knownPeers[mId];
                        final isHost = mId == group!.hostId;
                        final isMe = mId == provider.deviceId;
                        final mName = isMe
                            ? '${provider.deviceName} (You)'
                            : (mPeer?.name ?? (isHost ? group!.hostName : 'Member'));

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isHost
                                ? TelegramTheme.primaryBlue
                                : (isDark ? Colors.white12 : Colors.black12),
                            child: Text(
                              mName.isNotEmpty ? mName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 13,
                                color: isHost ? Colors.white : null,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            mName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          trailing: isHost
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: TelegramTheme.primaryBlue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Host',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: TelegramTheme.primaryBlue,
                                    ),
                                  ),
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Pin & Management Tile
                  _buildCard(
                    isDark: isDark,
                    children: [
                      ListTile(
                        leading: Icon(
                          (isGroup ? group!.isPinned : peer!.isPinned)
                              ? CupertinoIcons.pin_slash_fill
                              : CupertinoIcons.pin_fill,
                          color: TelegramTheme.primaryBlue,
                        ),
                        title: Text(
                          (isGroup ? group!.isPinned : peer!.isPinned)
                              ? 'Unpin from Top'
                              : 'Pin to Top',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          provider.togglePin(isGroup ? group!.id : peer!.id, isGroup);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildActionCircle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
    );
  }

  static Widget _buildCard({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  static Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: trailing,
    );
  }

  void _showTimerDialog(BuildContext context, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Disappearing Messages',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ...[
                    (null, 'Off', Icons.timer_off_rounded),
                    (10, '10 Seconds (Test)', Icons.local_fire_department_rounded),
                    (60, '1 Minute', Icons.timer_rounded),
                    (3600, '1 Hour', Icons.timer_rounded),
                    (86400, '24 Hours', Icons.timer_rounded),
                  ].map((item) {
                    final isSelected = provider.activeChatEphemeralSeconds == item.$1;
                    return ListTile(
                      leading: Icon(item.$3, color: isSelected ? TelegramTheme.primaryBlue : null),
                      title: Text(item.$2),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: TelegramTheme.primaryBlue)
                          : null,
                      onTap: () {
                        provider.setChatEphemeralSeconds(item.$1);
                        Navigator.of(ctx).pop();
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
