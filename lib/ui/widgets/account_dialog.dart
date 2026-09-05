import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

const List<Color> _avatarColors = [
  Color(0xFF2AABEE), // Telegram Blue
  Color(0xFF8B5CF6), // Purple
  Color(0xFF10B981), // Green
  Color(0xFFF59E0B), // Amber
  Color(0xFFEF4444), // Red
  Color(0xFFEC4899), // Pink
  Color(0xFF06B6D4), // Cyan
  Color(0xFF6366F1), // Indigo
];

const List<String> _avatarEmojis = [
  '👤', '🚀', '⚡', '🦊', '💻', '🔥', '🎯', '💎', '🌟', '🐱'
];

/// Telegram-style multi-account profile and login manager dialog
class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key});

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Edit Profile Controllers
  late TextEditingController _editNameController;
  late TextEditingController _editUsernameController;
  late TextEditingController _editBioController;
  int _editColorIndex = 0;
  String _editEmoji = '👤';

  // New Account Controllers
  final TextEditingController _newNameController = TextEditingController();
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newBioController = TextEditingController();
  int _newColorIndex = 1;
  String _newEmoji = '🚀';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final provider = Provider.of<ChatProvider>(context, listen: false);
    final current = provider.currentAccount;

    _editNameController = TextEditingController(text: current?.displayName ?? provider.deviceName);
    _editUsernameController = TextEditingController(text: current?.username ?? '');
    _editBioController = TextEditingController(text: current?.bio ?? '');
    _editColorIndex = current?.avatarColorIndex ?? 0;
    _editEmoji = current?.avatarEmoji ?? '👤';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _editNameController.dispose();
    _editUsernameController.dispose();
    _editBioController.dispose();
    _newNameController.dispose();
    _newUsernameController.dispose();
    _newBioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final current = provider.currentAccount;
    final accounts = provider.accounts;

    final avatarColor = _avatarColors[
        (current?.avatarColorIndex ?? 0).clamp(0, _avatarColors.length - 1)];

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          children: [
            // Current Account Card Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    avatarColor.withValues(alpha: isDark ? 0.35 : 0.2),
                    theme.colorScheme.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: avatarColor,
                    child: Text(
                      current?.avatarEmoji ?? '👤',
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                current?.displayName ?? provider.deviceName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '@${current?.username ?? 'user'}',
                          style: TextStyle(
                            color: TelegramTheme.primaryBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if ((current?.bio ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              current!.bio,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: TelegramTheme.primaryBlue,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: TelegramTheme.primaryBlue,
              tabs: const [
                Tab(icon: Icon(Icons.people_alt_rounded), text: 'Accounts'),
                Tab(icon: Icon(Icons.edit_rounded), text: 'Edit Profile'),
                Tab(icon: Icon(Icons.person_add_alt_1_rounded), text: 'Add Account'),
              ],
            ),

            // Tab Bar Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Account List & Switcher
                  _buildAccountsTab(context, provider, accounts, isDark),

                  // Tab 2: Edit Profile
                  _buildEditProfileTab(context, provider, isDark),

                  // Tab 3: Create New Account
                  _buildNewAccountTab(context, provider, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsTab(
    BuildContext context,
    ChatProvider provider,
    List<UserAccount> accounts,
    bool isDark,
  ) {
    final current = provider.currentAccount;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Select an account to switch profile, or tap "Add Account" to create a new profile identity.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        ...accounts.map((acc) {
          final isCurrent = acc.id == current?.id;
          final color = _avatarColors[acc.avatarColorIndex.clamp(0, _avatarColors.length - 1)];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? TelegramTheme.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(16),
              border: isCurrent
                  ? Border.all(color: TelegramTheme.primaryBlue.withValues(alpha: 0.6), width: 1.5)
                  : null,
            ),
            child: ListTile(
              onTap: () {
                if (!isCurrent) {
                  provider.switchAccount(acc.id);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Switched to ${acc.displayName} (@${acc.username})')),
                  );
                }
              },
              leading: CircleAvatar(
                backgroundColor: color,
                child: Text(acc.avatarEmoji, style: const TextStyle(fontSize: 20)),
              ),
              title: Text(
                acc.displayName,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                '@${acc.username}${acc.bio.isNotEmpty ? ' • ${acc.bio}' : ''}',
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: isCurrent
                  ? const Icon(Icons.check_circle_rounded, color: TelegramTheme.primaryBlue)
                  : (accounts.length > 1
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                          onPressed: () => provider.deleteAccount(acc.id),
                        )
                      : null),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEditProfileTab(BuildContext context, ChatProvider provider, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Display Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _editNameController,
            decoration: InputDecoration(
              hintText: 'e.g. Alex Rivers',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Username Handle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _editUsernameController,
            decoration: InputDecoration(
              prefixText: '@',
              hintText: 'alex_dev',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Bio / Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _editBioController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. Working from home | Mobile dev',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Avatar Emoji & Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _buildEmojiPicker(
            selectedEmoji: _editEmoji,
            onSelected: (emoji) => setState(() => _editEmoji = emoji),
          ),
          const SizedBox(height: 10),
          _buildColorPicker(
            selectedIndex: _editColorIndex,
            onSelected: (idx) => setState(() => _editColorIndex = idx),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final name = _editNameController.text.trim();
                final username = _editUsernameController.text.trim();
                if (name.isEmpty) return;

                provider.updateProfile(
                  displayName: name,
                  username: username,
                  bio: _editBioController.text.trim(),
                  avatarColorIndex: _editColorIndex,
                  avatarEmoji: _editEmoji,
                );
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully!')),
                );
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save Profile Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TelegramTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewAccountTab(BuildContext context, ChatProvider provider, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Display Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _newNameController,
            decoration: InputDecoration(
              hintText: 'e.g. Charlie',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Username Handle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _newUsernameController,
            decoration: InputDecoration(
              prefixText: '@',
              hintText: 'charlie_work',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Bio / Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _newBioController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. Work Profile',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Avatar Emoji & Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _buildEmojiPicker(
            selectedEmoji: _newEmoji,
            onSelected: (emoji) => setState(() => _newEmoji = emoji),
          ),
          const SizedBox(height: 10),
          _buildColorPicker(
            selectedIndex: _newColorIndex,
            onSelected: (idx) => setState(() => _newColorIndex = idx),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final name = _newNameController.text.trim();
                final username = _newUsernameController.text.trim();
                if (name.isEmpty) return;

                provider.createAccount(
                  displayName: name,
                  username: username.isEmpty ? 'user' : username,
                  bio: _newBioController.text.trim(),
                  avatarColorIndex: _newColorIndex,
                  avatarEmoji: _newEmoji,
                );
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created and logged into account: $name!')),
                );
              },
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Create & Switch to Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TelegramTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker({
    required String selectedEmoji,
    required ValueChanged<String> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _avatarEmojis.map((emoji) {
          final isSelected = selectedEmoji == emoji;
          return GestureDetector(
            onTap: () => onSelected(emoji),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? TelegramTheme.primaryBlue.withValues(alpha: 0.2) : Colors.transparent,
                shape: BoxShape.circle,
                border: isSelected ? Border.all(color: TelegramTheme.primaryBlue, width: 2) : null,
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildColorPicker({
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_avatarColors.length, (idx) {
        final color = _avatarColors[idx];
        final isSelected = selectedIndex == idx;

        return GestureDetector(
          onTap: () => onSelected(idx),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : null,
          ),
        );
      }),
    );
  }
}
