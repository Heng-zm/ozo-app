import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';

/// Telegram-style Voice Note Player with audio waveform and speed controls
class VoiceNotePlayer extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const VoiceNotePlayer({
    super.key,
    required this.message,
    required this.isMe,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<ChatProvider, bool>((p) => p.playingMessageId == message.id);
    final isPlaying = isCurrent && context.select<ChatProvider, bool>((p) => p.isMessagePlaying(message.id));
    final currentPosition = isCurrent ? context.select<ChatProvider, Duration>((p) => p.playbackPosition) : Duration.zero;
    final playbackSpeed = isCurrent ? context.select<ChatProvider, double>((p) => p.playbackSpeed) : 1.0;

    final totalDuration = Duration(
      milliseconds: ((message.voiceDurationSeconds ?? 0.0) * 1000).toInt(),
    );

    final hasLocalFile = message.fileMetadata?.isCompleted == true &&
        message.fileMetadata?.localPath != null;

    final amplitudes = message.waveformAmplitudes != null &&
            message.waveformAmplitudes!.isNotEmpty
        ? message.waveformAmplitudes!
        : List<double>.generate(28, (i) => ((i % 5) + 2) / 7.0);

    final progressRatio = totalDuration.inMilliseconds > 0
        ? (currentPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final activeColor = isMe ? Colors.white : Theme.of(context).colorScheme.primary;
    final inactiveColor = isMe ? Colors.white.withAlpha(90) : Colors.grey.withAlpha(90);

    return Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause / Download button
          GestureDetector(
            onTap: () {
              final provider = context.read<ChatProvider>();
              if (!hasLocalFile) {
                provider.acceptIncomingFile(message);
              } else if (isPlaying) {
                provider.pauseVoiceNote();
              } else {
                provider.playVoiceNote(message);
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withAlpha(50) : activeColor.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                !hasLocalFile
                    ? Icons.download_rounded
                    : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                color: activeColor,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Waveform & Timers
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform bars with drag and tap scrub
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        if (!hasLocalFile) return;
                        _handleSeek(details.localPosition, width, totalDuration, context.read<ChatProvider>());
                      },
                      onHorizontalDragUpdate: (details) {
                        if (!hasLocalFile) return;
                        _handleSeek(details.localPosition, width, totalDuration, context.read<ChatProvider>());
                      },
                      child: SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            amplitudes: amplitudes,
                            progress: progressRatio,
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),

                // Timers and Speed toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isPlaying
                          ? '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}'
                          : _formatDuration(totalDuration),
                      style: TextStyle(
                        fontSize: 11,
                        color: isMe ? Colors.white.withAlpha(200) : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (hasLocalFile)
                      GestureDetector(
                        onTap: () => context.read<ChatProvider>().togglePlaybackSpeed(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.white.withAlpha(40) : Colors.black.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${playbackSpeed == 1.0 ? '1' : playbackSpeed}x',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: activeColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleSeek(
    Offset localPosition,
    double totalWidth,
    Duration totalDuration,
    ChatProvider provider,
  ) {
    if (totalDuration.inMilliseconds == 0 || totalWidth <= 0) return;
    final fraction = (localPosition.dx / totalWidth).clamp(0.0, 1.0);
    final seekMs = (totalDuration.inMilliseconds * fraction).toInt();
    provider.seekVoiceNote(Duration(milliseconds: seekMs));
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0) return;

    const barWidth = 3.0;
    const minSpacing = 2.0;
    final maxBarsPossible = (size.width / (barWidth + minSpacing)).floor();
    final barsCount = amplitudes.length.clamp(1, maxBarsPossible);
    final spacing = (size.width - (barsCount * barWidth)) / (barsCount > 1 ? barsCount - 1 : 1);

    final activeIndex = (barsCount * progress).floor();

    final paintActive = Paint()..color = activeColor;
    final paintInactive = Paint()..color = inactiveColor;

    double x = 0;
    for (int i = 0; i < barsCount; i++) {
      final amp = amplitudes[i % amplitudes.length].clamp(0.12, 1.0);
      final barHeight = (size.height * amp).clamp(4.0, size.height);
      final yTop = (size.height - barHeight) / 2;

      final paint = (i <= activeIndex) ? paintActive : paintInactive;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, yTop, barWidth, barHeight),
        const Radius.circular(2.0),
      );
      canvas.drawRRect(rrect, paint);
      x += barWidth + spacing;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.amplitudes != amplitudes;
  }
}
