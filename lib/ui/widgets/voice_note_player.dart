import 'dart:io';
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
    final provider = context.watch<ChatProvider>();
    final isPlaying = provider.isMessagePlaying(message.id);
    final isCurrent = provider.playingMessageId == message.id;

    final totalDuration = Duration(
      milliseconds: ((message.voiceDurationSeconds ?? 0.0) * 1000).toInt(),
    );
    final currentPosition = isCurrent ? provider.playbackPosition : Duration.zero;

    final hasLocalFile = message.fileMetadata?.localPath != null &&
        File(message.fileMetadata!.localPath!).existsSync();

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
                // Waveform bars
                GestureDetector(
                  onTapDown: (details) {
                    if (!hasLocalFile || totalDuration.inMilliseconds == 0) return;
                    final box = details.localPosition;
                    // Seek based on horizontal tap offset
                    final fraction = (box.dx / 170.0).clamp(0.0, 1.0);
                    final seekMs = (totalDuration.inMilliseconds * fraction).toInt();
                    provider.seekVoiceNote(Duration(milliseconds: seekMs));
                  },
                  child: SizedBox(
                    height: 26,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        amplitudes: amplitudes,
                        progress: progressRatio,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                      ),
                      size: const Size(double.infinity, 26),
                    ),
                  ),
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
                        onTap: () => provider.togglePlaybackSpeed(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.white.withAlpha(40) : Colors.black.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${provider.playbackSpeed == 1.0 ? '1' : provider.playbackSpeed}x',
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
    if (amplitudes.isEmpty) return;

    final barWidth = 3.0;
    final spacing = 2.5;
    final totalBars = amplitudes.length;
    final activeIndex = (totalBars * progress).floor();

    final paintActive = Paint()
      ..color = activeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final paintInactive = Paint()
      ..color = inactiveColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    double x = 0;
    for (int i = 0; i < totalBars; i++) {
      final amp = amplitudes[i].clamp(0.1, 1.0);
      final barHeight = (size.height * amp).clamp(4.0, size.height);
      final yTop = (size.height - barHeight) / 2;
      final yBottom = yTop + barHeight;

      final paint = (i <= activeIndex) ? paintActive : paintInactive;
      canvas.drawLine(Offset(x, yTop), Offset(x, yBottom), paint);
      x += barWidth + spacing;
      if (x > size.width) break;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.amplitudes != amplitudes;
  }
}
