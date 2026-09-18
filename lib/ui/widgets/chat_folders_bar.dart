import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

/// Telegram-style horizontal chat folders bar (All, Personal, Groups, Unread)
class ChatFoldersBar extends StatelessWidget {
  const ChatFoldersBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final folders = [
      _FolderItem(
        folder: ChatFolder.all,
        title: 'All',
        icon: Icons.chat_bubble_outline_rounded,
        badgeCount: provider.database.messages
            .where((m) => m.senderId != provider.deviceId && m.status != MessageStatus.read)
            .length,
      ),
      _FolderItem(
        folder: ChatFolder.personal,
        title: 'Personal',
        icon: Icons.person_outline_rounded,
        badgeCount: provider.database.knownPeers.values.fold<int>(
          0,
          (sum, p) => sum + provider.getUnreadCount(p.id),
        ),
      ),
      _FolderItem(
        folder: ChatFolder.groups,
        title: 'Groups',
        icon: Icons.group_outlined,
        badgeCount: provider.database.groups.fold<int>(
          0,
          (sum, g) => sum + provider.getUnreadCount(g.id),
        ),
      ),
      _FolderItem(
        folder: ChatFolder.unread,
        title: 'Unread',
        icon: Icons.mark_chat_unread_outlined,
        badgeCount: provider.database.messages
            .where((m) => m.senderId != provider.deviceId && m.status != MessageStatus.read)
            .length,
      ),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? TelegramTheme.darkBackground : TelegramTheme.lightSidebar,
        border: Border(
          bottom: BorderSide(
            color: isDark ? IosTheme.hairlineDark : IosTheme.hairlineLight,
            width: 0.5,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isDark ? IosTheme.searchFieldDark : IosTheme.searchFieldLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: folders.map((item) {
            final isSelected = provider.activeFolder == item.folder;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.setFolder(item.folder);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? const Color(0xFF2C2C2E) : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : IosTheme.systemGray,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (item.badgeCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected ? IosTheme.systemRed : IosTheme.systemGray,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FolderItem {
  final ChatFolder folder;
  final String title;
  final IconData icon;
  final int badgeCount;

  _FolderItem({
    required this.folder,
    required this.title,
    required this.icon,
    required this.badgeCount,
  });
}
