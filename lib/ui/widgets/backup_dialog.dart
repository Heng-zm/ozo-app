import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class BackupDialog extends StatefulWidget {
  const BackupDialog({super.key});

  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _exportPasswordController = TextEditingController();
  final TextEditingController _importPasswordController = TextEditingController();
  final TextEditingController _importPayloadController = TextEditingController();
  final TextEditingController _migratePasswordController = TextEditingController();

  String? _exportedPayload;
  bool _isProcessing = false;
  String? _statusMessage;
  Peer? _selectedPeerForMigration;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _exportPasswordController.dispose();
    _importPasswordController.dispose();
    _importPayloadController.dispose();
    _migratePasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    final pwd = _exportPasswordController.text.trim();
    if (pwd.isEmpty) {
      setState(() => _statusMessage = 'Please enter a backup password');
      return;
    }
    if (pwd.length < 8) {
      setState(() => _statusMessage = 'Password must be at least 8 characters for PBKDF2 vault encryption');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final backup = await provider.exportBackup(pwd);
      setState(() {
        _exportedPayload = jsonEncode(backup);
        _isProcessing = false;
        _statusMessage = 'Backup created successfully! Encrypted with PBKDF2 (100k rounds) & Counter-Mode cipher.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Export failed: $e';
      });
    }
  }

  Future<void> _handleImport() async {
    final pwd = _importPasswordController.text.trim();
    final payload = _importPayloadController.text.trim();

    if (pwd.isEmpty || payload.isEmpty) {
      setState(() => _statusMessage = 'Please provide both password and backup data');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final container = jsonDecode(payload) as Map<String, dynamic>;
      final success = await provider.importBackup(container, pwd);
      setState(() {
        _isProcessing = false;
        _statusMessage = success
            ? 'Backup restored successfully into SQLite database!'
            : 'Failed: Incorrect password or corrupted backup file.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Import error: Invalid format or corrupt payload';
      });
    }
  }

  Future<void> _handleMigration() async {
    final pwd = _migratePasswordController.text.trim();
    if (pwd.isEmpty || _selectedPeerForMigration == null) {
      setState(() => _statusMessage = 'Please select a peer and enter a password');
      return;
    }
    if (pwd.length < 8) {
      setState(() => _statusMessage = 'Password must be at least 8 characters for PBKDF2 vault encryption');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final sent = await provider.migrateToPeer(_selectedPeerForMigration!, pwd);
      setState(() {
        _isProcessing = false;
        _statusMessage = sent
            ? 'Migration backup transmitted to ${_selectedPeerForMigration!.name}!'
            : 'Failed to send backup to peer. Please check peer connection.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Migration error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<ChatProvider>(context);
    final onlinePeers = provider.discoveredPeers.where((p) => p.isOnline).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TelegramTheme.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_update_good_rounded,
                    color: TelegramTheme.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encrypted Vault & Backup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'AES/ChaCha20 Zero-Knowledge Storage',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
            const SizedBox(height: 16),

            TabBar(
              controller: _tabController,
              indicatorColor: TelegramTheme.primaryBlue,
              labelColor: TelegramTheme.primaryBlue,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              tabs: const [
                Tab(text: 'Export'),
                Tab(text: 'Restore'),
                Tab(text: 'Migrate'),
              ],
            ),
            const SizedBox(height: 16),

            if (_statusMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _statusMessage!.contains('success') || _statusMessage!.contains('transmitted')
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusMessage!.contains('success') || _statusMessage!.contains('transmitted')
                        ? Colors.green
                        : Colors.orangeAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Export
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create an encrypted offline archive of your accounts, contacts, groups, and message history.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _exportPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Set Backup Password (min 8 chars)',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.shield_outlined, size: 18, color: TelegramTheme.primaryBlue),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Protected by PBKDF2 (100,000 rounds) + 32-byte per-archive salt. Backup strength depends on your password. Use at least 8 characters.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _handleExport,
                            icon: const Icon(Icons.archive_rounded),
                            label: Text(_isProcessing ? 'Encrypting...' : 'Export Encrypted Backup'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TelegramTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        if (_exportedPayload != null) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _exportedPayload!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Backup payload copied to clipboard!')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy Encrypted Payload'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TelegramTheme.primaryBlue,
                              side: const BorderSide(color: TelegramTheme.primaryBlue),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Tab 2: Restore
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paste your encrypted backup JSON payload and enter the password used during export.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _importPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Backup Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _importPayloadController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Paste Backup Payload JSON',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _handleImport,
                            icon: const Icon(Icons.unarchive_rounded),
                            label: Text(_isProcessing ? 'Decrypting...' : 'Restore into SQLite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TelegramTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 3: Migrate
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Direct P2P Migration: Stream your entire encrypted vault to another device over the local network.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 14),
                        if (onlinePeers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orangeAccent),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'No online peers discovered on local network. Ensure target device is running OZO.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownButtonFormField<Peer>(
                            initialValue: _selectedPeerForMigration,
                            decoration: InputDecoration(
                              labelText: 'Select Destination Device',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: onlinePeers.map((p) {
                              return DropdownMenuItem(
                                value: p,
                                child: Text('${p.name} (${p.platform})'),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedPeerForMigration = val),
                          ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _migratePasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Transfer Encryption Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing || onlinePeers.isEmpty ? null : _handleMigration,
                            icon: const Icon(Icons.send_to_mobile_rounded),
                            label: Text(_isProcessing ? 'Migrating...' : 'Start P2P Migration'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TelegramTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
