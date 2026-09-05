import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class DirectHotspotDialog extends StatefulWidget {
  const DirectHotspotDialog({super.key});

  @override
  State<DirectHotspotDialog> createState() => _DirectHotspotDialogState();
}

class _DirectHotspotDialogState extends State<DirectHotspotDialog> {
  DirectHotspotInfo? _info;
  bool _isLoading = true;
  int _selectedPlatformTab = 0; // 0: iOS, 1: Android, 2: PC/Mac

  @override
  void initState() {
    super.initState();
    _loadHotspotInfo();
  }

  Future<void> _loadHotspotInfo() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final info = await provider.getDirectHotspotInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _isLoading = false;
      });
    }
  }

  String _detectNetworkType(String? ip) {
    if (ip == null || ip.isEmpty) return 'Detecting...';
    if (ip.startsWith('172.20.10.')) return 'iOS Personal Hotspot';
    if (ip.startsWith('192.168.43.') || ip.startsWith('192.168.49.')) {
      return 'Android Portable Hotspot';
    }
    if (ip.startsWith('127.')) return 'Loopback / Offline';
    return 'Wi-Fi / Local Area Network';
  }

  Color _getNetworkBadgeColor(String? ip) {
    if (ip == null) return Colors.grey;
    if (ip.startsWith('172.20.10.') ||
        ip.startsWith('192.168.43.') ||
        ip.startsWith('192.168.49.')) {
      return const Color(0xFF10B981); // Emerald Green for active direct hotspot
    }
    return TelegramTheme.primaryBlue;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final networkType = _detectNetworkType(_info?.ip);
    final badgeColor = _getNetworkBadgeColor(_info?.ip);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
        child: _isLoading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                            Icons.wifi_tethering_rounded,
                            color: TelegramTheme.primaryBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Routerless Hotspot Mode',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Direct P2P • No Internet Required',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Refresh IP',
                          onPressed: _loadHotspotInfo,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Active Network Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sensors_rounded, size: 14, color: badgeColor),
                          const SizedBox(width: 6),
                          Text(
                            networkType,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // QR Code
                    if (_info != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: _info!.toUriString(),
                          version: QrVersions.auto,
                          size: 160,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Network details card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Local IP', _info?.ip ?? 'Unknown'),
                          const SizedBox(height: 4),
                          _buildDetailRow('P2P Port', '${_info?.port ?? 45455}'),
                          const SizedBox(height: 4),
                          _buildDetailRow('Suggested SSID', _info?.ssid ?? 'OZO-Hotspot'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Platform Honest Guidance Tabs
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          _buildPlatformTab(0, 'iOS (Apple)'),
                          _buildPlatformTab(1, 'Android'),
                          _buildPlatformTab(2, 'PC / Mac'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Setup instructions based on selected tab
                    _buildPlatformInstructions(isDark),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (_info != null) {
                                Clipboard.setData(
                                    ClipboardData(text: _info!.toUriString()));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Hotspot link copied to clipboard!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy Link'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TelegramTheme.primaryBlue,
                              side: const BorderSide(color: TelegramTheme.primaryBlue),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TelegramTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPlatformTab(int index, String label) {
    final isSelected = _selectedPlatformTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlatformTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? TelegramTheme.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformInstructions(bool isDark) {
    String note = '';
    List<String> steps = [];

    if (_selectedPlatformTab == 0) {
      note = 'iOS Limitation: Apple blocks 3rd-party apps from creating hotspots programmatically. You must enable it manually in Settings:';
      steps = [
        'Open iOS Settings > Personal Hotspot.',
        'Turn on "Allow Others to Join" (set any password).',
        'Have peer devices connect to your iPhone Wi-Fi.',
        'Peers will join subnet 172.20.10.x and can scan this QR code.',
      ];
    } else if (_selectedPlatformTab == 1) {
      note = 'Android Portable Hotspot setup:';
      steps = [
        'Open Settings > Network & Internet > Hotspot & Tethering.',
        'Enable "Portable Wi-Fi Hotspot" (or use Quick Settings toggle).',
        'Have peer devices join your hotspot Wi-Fi (usually 192.168.43.x).',
        'Peers scan this QR code or tap the link to pair immediately.',
      ];
    } else {
      note = 'Desktop / Laptop setup:';
      steps = [
        'Turn on "Mobile Hotspot" in Windows Settings or macOS Internet Sharing.',
        'Connect your phone or other computers to this Wi-Fi network.',
        'Both devices can now chat and transfer files with full local speed.',
      ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _selectedPlatformTab == 0 ? Colors.amber.shade700 : TelegramTheme.primaryBlue,
            ),
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
