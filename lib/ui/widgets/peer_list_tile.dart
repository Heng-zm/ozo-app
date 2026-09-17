import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/models.dart';
import '../theme/app_theme.dart';

class PeerListTile extends StatefulWidget {
  final Peer peer;
  final bool isSelected;
  final int unreadCount;
  final VoidCallback onTap;

  const PeerListTile({
    super.key,
    required this.peer,
    required this.isSelected,
    this.unreadCount = 0,
    required this.onTap,
  });

  @override
  State<PeerListTile> createState() => _PeerListTileState();
}

class _PeerListTileState extends State<PeerListTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = widget.peer.isOnline;

    return AnimatedScale(
      scale: _isPressed ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: ListTile(
          selected: widget.isSelected,
          selectedTileColor: isDark
              ? TelegramTheme.primaryBlue.withValues(alpha: 0.15)
              : TelegramTheme.primaryBlue.withValues(alpha: 0.1),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _getColorForName(widget.peer.name),
                child: Text(
                  widget.peer.name.isNotEmpty ? widget.peer.name[0].toUpperCase() : '?',
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
                child: isOnline
                    ? _PulsingOnlineDot(isDark: isDark)
                    : Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: TelegramTheme.offlineGrey,
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
                  widget.peer.name,
                  style: TextStyle(
                    fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.peer.isRemote) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_rounded, size: 12, color: Colors.purple),
                      SizedBox(width: 4),
                      Text('Remote', style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.peer.hasIdentityConflict) ...[
                const Tooltip(
                  message: 'Identity changed! Possible impersonation attempt.',
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                ),
                const SizedBox(width: 4),
              ],
              _buildPlatformBadge(widget.peer.platform),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              widget.peer.isRemote
                  ? 'Remote Cloudflare Tunnel'
                  : (isOnline ? '${widget.peer.ip}:${widget.peer.port}' : 'Last seen ${_formatLastSeen(widget.peer.lastSeen)}'),
              style: TextStyle(
                fontSize: 12,
                color: (isOnline || widget.peer.isRemote)
                    ? (widget.peer.isRemote ? Colors.purple : TelegramTheme.onlineGreen)
                    : (isDark ? TelegramTheme.darkTextSecondary : TelegramTheme.lightTextSecondary),
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.peer.isPinned)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.push_pin_rounded, size: 14, color: TelegramTheme.primaryBlue),
                ),
              if (widget.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: TelegramTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: widget.isSelected
                    ? TelegramTheme.primaryBlue
                    : (isDark ? Colors.white24 : Colors.black26),
              ),
            ],
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

/// Pulsing breathing glow for online peers
class _PulsingOnlineDot extends StatefulWidget {
  final bool isDark;
  const _PulsingOnlineDot({required this.isDark});

  @override
  State<_PulsingOnlineDot> createState() => _PulsingOnlineDotState();
}

class _PulsingOnlineDotState extends State<_PulsingOnlineDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 15,
          height: 15,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 * _pulseAnimation.value,
                height: 10 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  color: TelegramTheme.onlineGreen.withValues(
                    alpha: (1.5 - _pulseAnimation.value).clamp(0.0, 0.6),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: TelegramTheme.onlineGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isDark ? TelegramTheme.darkSidebar : Colors.white,
                    width: 2,
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
