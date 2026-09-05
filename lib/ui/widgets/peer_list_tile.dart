import 'package:flutter/material.dart';
import '../../core/database/models.dart';
import '../theme/app_theme.dart';

class PeerListTile extends StatelessWidget {
  final Peer peer;
  final bool isSelected;
  final VoidCallback onTap;

  const PeerListTile({
    super.key,
    required this.peer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = peer.isOnline;

    return ListTile(
      selected: isSelected,
      selectedTileColor: isDark
          ? TelegramTheme.primaryBlue.withValues(alpha: 0.15)
          : TelegramTheme.primaryBlue.withValues(alpha: 0.1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _getColorForName(peer.name),
            child: Text(
              peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: isOnline ? TelegramTheme.onlineGreen : TelegramTheme.offlineGrey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? TelegramTheme.darkSidebar : Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              peer.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (peer.hasIdentityConflict) ...[
            const Tooltip(
              message: 'Identity changed! Possible impersonation attempt.',
              child: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
            ),
            const SizedBox(width: 4),
          ],
          _buildPlatformBadge(peer.platform),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          isOnline ? '${peer.ip}:${peer.port}' : 'Last seen ${_formatLastSeen(peer.lastSeen)}',
          style: TextStyle(
            fontSize: 12,
            color: isOnline
                ? TelegramTheme.onlineGreen
                : (isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformBadge(String platform) {
    IconData icon;
    switch (platform.toLowerCase()) {
      case 'windows':
        icon = Icons.window;
        break;
      case 'macos':
      case 'ios':
        icon = Icons.apple;
        break;
      case 'android':
        icon = Icons.android;
        break;
      case 'linux':
        icon = Icons.computer;
        break;
      default:
        icon = Icons.devices;
    }

    return Icon(icon, size: 14, color: Colors.grey.shade500);
  }

  Color _getColorForName(String name) {
    final colors = [
      Colors.blue.shade600,
      Colors.teal.shade600,
      Colors.purple.shade600,
      Colors.orange.shade600,
      Colors.pink.shade600,
      Colors.indigo.shade600,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
