import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/models.dart';
import '../theme/app_theme.dart';

/// "Verify Device" / Safety Number Dialog for Anti-Spoofing & TOFU verification
class SafetyNumberDialog extends StatelessWidget {
  final Peer peer;

  const SafetyNumberDialog({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            peer.hasIdentityConflict ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
            color: peer.hasIdentityConflict ? Colors.orange : TelegramTheme.onlineGreen,
          ),
          const SizedBox(width: 8),
          const Text('Verify Device Identity'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (peer.hasIdentityConflict) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade400),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'WARNING: This device previously used a different cryptographic key. This may indicate an app re-install or an impersonation / spoofing attempt on the network!',
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Compare this safety number with the one displayed on the other device in person:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: TelegramTheme.primaryBlue.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  peer.safetyFingerprint,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    fontFamily: 'monospace',
                    color: TelegramTheme.primaryBlue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Device Name: ${peer.name}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('Device ID: ${peer.id}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text('Network IP: ${peer.ip}:${peer.port}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            const Text('Full Public Key (X25519):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    peer.publicKey,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: peer.publicKey));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Public key copied')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
