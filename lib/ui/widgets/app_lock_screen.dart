import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class AppLockScreen extends StatefulWidget {
  final Widget child;

  const AppLockScreen({
    super.key,
    required this.child,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with WidgetsBindingObserver {
  String _enteredPin = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      provider.security.checkAutoLock();
    } else if (state == AppLifecycleState.paused) {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      provider.security.updateActivity();
    }
  }

  void _onKeyPress(String val, ChatProvider provider) {
    if (_enteredPin.length >= 6) return;
    setState(() {
      _errorMessage = null;
      _enteredPin += val;
    });

    if (_enteredPin.length >= 4) {
      // Check PIN
      final verified = provider.security.verifyPin(_enteredPin);
      if (verified) {
        provider.security.unlock(_enteredPin);
        setState(() {
          _enteredPin = '';
          _errorMessage = null;
        });
      } else if (_enteredPin.length == 4 || _enteredPin.length == 6) {
        setState(() {
          _errorMessage = 'Incorrect Passcode';
          _enteredPin = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final isLocked = provider.security.isLocked && provider.security.isPinConfigured;

    if (!isLocked) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E1621) : const Color(0xFFF4F4F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: TelegramTheme.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_rounded,
                      size: 40,
                      color: TelegramTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Enter Passcode',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'Passcode is required to unlock OZO App',
                  style: TextStyle(
                    fontSize: 13,
                    color: _errorMessage != null
                        ? Colors.redAccent
                        : (isDark ? Colors.white60 : Colors.black54),
                    fontWeight: _errorMessage != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 32),

                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isFilled = index < _enteredPin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled
                            ? TelegramTheme.primaryBlue
                            : Colors.transparent,
                        border: Border.all(
                          color: isFilled
                              ? TelegramTheme.primaryBlue
                              : (isDark ? Colors.white38 : Colors.black38),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                const Spacer(),

                // Number keypad
                Column(
                  children: [
                    for (var row = 0; row < 3; row++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (var col = 1; col <= 3; col++)
                              _buildKeypadButton(
                                '${row * 3 + col}',
                                isDark,
                                () => _onKeyPress(
                                    '${row * 3 + col}', provider),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (provider.security.settings.isBiometricEnabled)
                            IconButton(
                              icon: const Icon(
                                Icons.fingerprint_rounded,
                                size: 36,
                                color: TelegramTheme.primaryBlue,
                              ),
                              onPressed: () {
                                provider.security.unlockBiometric();
                              },
                            )
                          else
                            const SizedBox(width: 72),
                          _buildKeypadButton(
                            '0',
                            isDark,
                            () => _onKeyPress('0', provider),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.backspace_outlined,
                              size: 28,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            onPressed: _onBackspace,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadButton(
      String label, bool isDark, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
