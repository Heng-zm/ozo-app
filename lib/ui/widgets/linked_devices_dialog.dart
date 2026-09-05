import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class LinkedDevicesDialog extends StatefulWidget {
  const LinkedDevicesDialog({super.key});

  @override
  State<LinkedDevicesDialog> createState() => _LinkedDevicesDialogState();
}

class _LinkedDevicesDialogState extends State<LinkedDevicesDialog> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<ChatProvider>(context);
    final linked = provider.linkedDevices;
    final onlinePeers = provider.discoveredPeers.where((p) => p.isOnline).toList();

    final pairingToken = provider.activePairingToken;
    final pairingUri = pairingToken.toUriString();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icons.devices_rounded,
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
                        'Linked Devices',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Pair laptops, tablets & phones',
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

            // Pending Pairing Confirmation Request Banner
            if (provider.pendingPairingRequest != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.security_rounded, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Device Link Request',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Device "${provider.pendingPairingRequest!.device.name}" (${provider.pendingPairingRequest!.device.platform}) is requesting to link to your OZO account. Authorize?',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: provider.pendingPairingRequest!.onReject,
                          child: const Text('Reject', style: TextStyle(color: Colors.red)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: provider.pendingPairingRequest!.onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TelegramTheme.primaryBlue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Authorize'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            if (_showQr) ...[
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: QrImageView(
                        data: pairingUri,
                        version: QrVersions.auto,
                        size: 170,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: TelegramTheme.primaryBlue),
                          SizedBox(width: 6),
                          Text(
                            'Single-use token • Expires in 90 seconds',
                            style: TextStyle(fontSize: 11, color: TelegramTheme.primaryBlue, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan this QR code from companion device. Primary device will prompt for final confirmation.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() {
                            provider.createPairingToken();
                          }),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Refresh Token', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => setState(() => _showQr = false),
                          child: const Text('Back to List', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Current Device Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: TelegramTheme.primaryBlue.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getPlatformIcon(provider.platform),
                      color: TelegramTheme.primaryBlue,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                provider.deviceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: TelegramTheme.primaryBlue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'This Device',
                                  style: TextStyle(
                                    color: TelegramTheme.primaryBlue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Active now • ${provider.platform.toUpperCase()}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showQr = true),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Link New Device (Show QR)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TelegramTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'COMPANION DEVICES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: linked.isEmpty && onlinePeers.isEmpty
                    ? const Center(
                        child: Text(
                          'No companion devices paired yet.\nLink your laptop or phone for multi-device sync.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        children: [
                          for (final dev in linked)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                child: Icon(
                                  _getPlatformIcon(dev.platform),
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                dev.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Linked ${DateFormat.MMMd().format(dev.linkedAt)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                onPressed: () => provider.removeLinkedDevice(dev.id),
                              ),
                            ),
                          if (onlinePeers.isNotEmpty) ...[
                            const Divider(),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'QUICK PAIR WITH NEARBY PEER',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            for (final peer in onlinePeers)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: TelegramTheme.primaryBlue.withValues(alpha: 0.1),
                                  child: Icon(
                                    _getPlatformIcon(peer.platform),
                                    color: TelegramTheme.primaryBlue,
                                    size: 20,
                                  ),
                                ),
                                title: Text(peer.name, style: const TextStyle(fontSize: 13)),
                                trailing: TextButton(
                                  onPressed: () {
                                    provider.pairWithPeer(peer);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Sent pairing invitation to ${peer.name}!')),
                                    );
                                  },
                                  child: const Text('Pair'),
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('android')) return Icons.android_rounded;
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) {
      return Icons.phone_iphone_rounded;
    }
    if (p.contains('macos') || p.contains('mac')) return Icons.laptop_mac_rounded;
    if (p.contains('windows')) return Icons.laptop_windows_rounded;
    if (p.contains('linux')) return Icons.computer_rounded;
    return Icons.devices_other_rounded;
  }
}
