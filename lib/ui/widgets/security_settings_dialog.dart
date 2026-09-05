import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class SecuritySettingsDialog extends StatefulWidget {
  const SecuritySettingsDialog({super.key});

  @override
  State<SecuritySettingsDialog> createState() => _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends State<SecuritySettingsDialog> {
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  String? _error;
  bool _isSettingPin = false;

  @override
  void dispose() {
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _savePin(ChatProvider provider) async {
    final pin = _newPinController.text.trim();
    final confirm = _confirmPinController.text.trim();

    if (pin.length < 4 || pin.length > 6) {
      setState(() => _error = 'Passcode must be 4 to 6 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Passcodes do not match');
      return;
    }

    await provider.security.setPin(pin);
    setState(() {
      _isSettingPin = false;
      _error = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode lock configured!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<ChatProvider>(context);
    final sec = provider.security;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    Icons.lock_outline_rounded,
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
                        'Passcode & Security',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Protect your local conversations',
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
            const SizedBox(height: 20),

            if (_isSettingPin) ...[
              const Text(
                'Set New Passcode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Enter 4-6 digit passcode',
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Confirm passcode',
                  counterText: '',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isSettingPin = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _savePin(provider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TelegramTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Passcode'),
                  ),
                ],
              ),
            ] else ...[
              // Passcode toggle row
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Passcode Lock', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  sec.isPinConfigured ? 'Enabled' : 'Disabled',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: sec.isPinConfigured,
                activeThumbColor: TelegramTheme.primaryBlue,
                onChanged: (val) {
                  if (val) {
                    setState(() {
                      _isSettingPin = true;
                      _newPinController.clear();
                      _confirmPinController.clear();
                      _error = null;
                    });
                  } else {
                    sec.disablePin();
                  }
                },
              ),
              const Divider(),

              if (sec.isPinConfigured) ...[
                // Auto-lock dropdown
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-Lock Timeout', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Lock app after inactivity', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: DropdownButton<int>(
                    value: sec.settings.autoLockMinutes,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Immediately')),
                      DropdownMenuItem(value: 1, child: Text('1 minute')),
                      DropdownMenuItem(value: 5, child: Text('5 minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                      DropdownMenuItem(value: -1, child: Text('Never')),
                    ],
                    onChanged: (val) {
                      if (val != null) sec.setAutoLockMinutes(val);
                    },
                  ),
                ),
                const Divider(),

                // Biometrics toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlock with Biometrics', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Fingerprint / Face Unlock', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  value: sec.settings.isBiometricEnabled,
                  activeThumbColor: TelegramTheme.primaryBlue,
                  onChanged: (val) => sec.setBiometricEnabled(val),
                ),
                const Divider(),

                // Change PIN button
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isSettingPin = true;
                      _newPinController.clear();
                      _confirmPinController.clear();
                      _error = null;
                    });
                  },
                  icon: const Icon(Icons.lock_reset_rounded, size: 18),
                  label: const Text('Change Passcode'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
