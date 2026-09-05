import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? TelegramTheme.darkSidebar : TelegramTheme.lightSidebar,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: folders.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = folders[index];
          final isSelected = provider.activeFolder == item.folder;

          return GestureDetector(
            onTap: () => provider.setFolder(item.folder),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? TelegramTheme.primaryBlue.withValues(alpha: isDark ? 0.25 : 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(color: TelegramTheme.primaryBlue.withValues(alpha: 0.5))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 16,
                    color: isSelected
                        ? TelegramTheme.primaryBlue
                        : (isDark ? Colors.white60 : Colors.black54),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? TelegramTheme.primaryBlue
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  if (item.badgeCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? TelegramTheme.primaryBlue
                            : (isDark ? Colors.white24 : Colors.black26),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
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
