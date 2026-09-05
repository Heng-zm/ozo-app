import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';

/// Full-screen Telegram-style Call Screen with live audio controls and call timer
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final peer = provider.activeCallPeer;
    final status = provider.callStatus;

    if (status == CallStatus.idle || peer == null) {
      return const SizedBox.shrink();
    }

    String statusText;
    Color statusColor = Colors.white70;

    switch (status) {
      case CallStatus.outgoingCalling:
        statusText = 'Calling...';
        break;
      case CallStatus.incomingRinging:
        statusText = 'Incoming call...';
        break;
      case CallStatus.connected:
        statusText = _formatDuration(provider.callDuration);
        statusColor = const Color(0xFF4CAF50);
        break;
      case CallStatus.ended:
        statusText = 'Call ended';
        break;
      case CallStatus.idle:
        statusText = '';
        break;
    }

    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.96),
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded, color: Color(0xFF4CAF50), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'E2EE P2P Audio',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => provider.endCall(),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Pulsating Avatar Center
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: status == CallStatus.connected ? 1.0 : _pulseAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 54,
                      backgroundColor: const Color(0xFF2563EB),
                      child: Text(
                        peer.name.isNotEmpty ? peer.name[0].toUpperCase() : 'P',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Peer Name
            Text(
              peer.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),

            const SizedBox(height: 8),

            // Call Status / Duration
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(),

            // Controls
            if (status == CallStatus.incomingRinging) ...[
              // Accept / Decline row for incoming
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.redAccent,
                      label: 'Decline',
                      onTap: () => provider.declineCall(),
                    ),
                    _CallActionButton(
                      icon: Icons.call_rounded,
                      color: Colors.green,
                      label: 'Accept',
                      onTap: () => provider.acceptCall(),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // In-call / Outgoing controls
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: provider.isCallMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: provider.isCallMuted ? Colors.white24 : Colors.white12,
                      iconColor: provider.isCallMuted ? Colors.redAccent : Colors.white,
                      label: provider.isCallMuted ? 'Muted' : 'Mute',
                      onTap: () => provider.toggleCallMute(),
                    ),
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.redAccent,
                      label: 'End',
                      onTap: () => provider.endCall(),
                    ),
                    _CallActionButton(
                      icon: provider.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                      color: provider.isSpeakerOn ? const Color(0xFF2563EB) : Colors.white12,
                      label: 'Speaker',
                      onTap: () => provider.toggleSpeaker(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    this.iconColor = Colors.white,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
