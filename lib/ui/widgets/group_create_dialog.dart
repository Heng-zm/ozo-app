import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class GroupCreateDialog extends StatefulWidget {
  const GroupCreateDialog({super.key});

  @override
  State<GroupCreateDialog> createState() => _GroupCreateDialogState();
}

class _GroupCreateDialogState extends State<GroupCreateDialog> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedPeerIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final peers = provider.database.knownPeers.values
        .where((p) => p.id != provider.deviceId)
        .toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.group_add_rounded, color: TelegramTheme.primaryBlue),
          SizedBox(width: 8),
          Text('Create Group Chat'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g. Project Team LAN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: TelegramTheme.primaryBlue),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Host-Relay model: You will act as Host. Group is read-only if the Host is offline.',
                      style: TextStyle(fontSize: 11, color: TelegramTheme.primaryDarkBlue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select Members:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (peers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No other peers detected on the network yet.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: peers.length,
                  itemBuilder: (context, index) {
                    final p = peers[index];
                    final isChecked = _selectedPeerIds.contains(p.id);
                    return CheckboxListTile(
                      dense: true,
                      value: isChecked,
                      title: Text(p.name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        p.isOnline ? 'Online (${p.ip})' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.isOnline ? TelegramTheme.onlineGreen : Colors.grey,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedPeerIds.add(p.id);
                          } else {
                            _selectedPeerIds.remove(p.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty || _selectedPeerIds.isEmpty
              ? null
              : () async {
                  await provider.createGroup(
                    name: _nameController.text.trim(),
                    memberIds: _selectedPeerIds.toList(),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
