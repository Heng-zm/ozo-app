import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';

/// Telegram-style Voice Note Player with audio waveform and speed controls
class VoiceNotePlayer extends StatefulWidget {
  final ChatMessage message;
  final bool isMe;

  const VoiceNotePlayer({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  double? _dragFraction;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<ChatProvider, bool>((p) => p.playingMessageId == widget.message.id);
    final isPlaying = isCurrent && context.select<ChatProvider, bool>((p) => p.isMessagePlaying(widget.message.id));
    final currentPosition = isCurrent ? context.select<ChatProvider, Duration>((p) => p.playbackPosition) : Duration.zero;
    final playbackSpeed = isCurrent ? context.select<ChatProvider, double>((p) => p.playbackSpeed) : 1.0;

    final totalDuration = Duration(
      milliseconds: ((widget.message.voiceDurationSeconds ?? 0.0) * 1000).toInt(),
    );

    final hasLocalFile = widget.message.fileMetadata?.isCompleted == true &&
        widget.message.fileMetadata?.localPath != null;

    final amplitudes = widget.message.waveformAmplitudes != null &&
            widget.message.waveformAmplitudes!.isNotEmpty
        ? widget.message.waveformAmplitudes!
        : List<double>.generate(28, (i) => ((i % 5) + 2) / 7.0);

    final rawRatio = totalDuration.inMilliseconds > 0
        ? (currentPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final displayProgress = _dragFraction ?? rawRatio;

    final activeColor = widget.isMe ? Colors.white : Theme.of(context).colorScheme.primary;
    final inactiveColor = widget.isMe ? Colors.white.withAlpha(90) : Colors.grey.withAlpha(90);

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
                provider.acceptIncomingFile(widget.message);
              } else if (isPlaying) {
                provider.pauseVoiceNote();
              } else {
                provider.playVoiceNote(widget.message);
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white.withAlpha(50) : activeColor.withAlpha(30),
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
                        _startScrub(details.localPosition, width, totalDuration);
                      },
                      onHorizontalDragStart: (details) {
                        if (!hasLocalFile) return;
                        _startScrub(details.localPosition, width, totalDuration);
                      },
                      onHorizontalDragUpdate: (details) {
                        if (!hasLocalFile) return;
                        _updateScrub(details.localPosition, width);
                      },
                      onHorizontalDragEnd: (details) {
                        _endScrub(totalDuration, context.read<ChatProvider>());
                      },
                      onHorizontalDragCancel: () {
                        setState(() => _dragFraction = null);
                      },
                      child: SizedBox(
                        height: 30,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            amplitudes: amplitudes,
                            progress: displayProgress,
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                            isScrubbing: _dragFraction != null,
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
                      _dragFraction != null
                          ? 'Seek ${_formatDuration(Duration(milliseconds: (totalDuration.inMilliseconds * _dragFraction!).toInt()))}'
                          : (isPlaying
                              ? '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}'
                              : _formatDuration(totalDuration)),
                      style: TextStyle(
                        fontSize: 11,
                        color: _dragFraction != null
                            ? activeColor
                            : (widget.isMe ? Colors.white.withAlpha(200) : Colors.grey.shade700),
                        fontWeight: _dragFraction != null ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    if (hasLocalFile)
                      GestureDetector(
                        onTap: () => context.read<ChatProvider>().togglePlaybackSpeed(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: widget.isMe ? Colors.white.withAlpha(40) : Colors.black.withAlpha(15),
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

  void _startScrub(Offset localPosition, double totalWidth, Duration totalDuration) {
    if (totalWidth <= 0) return;
    final frac = (localPosition.dx / totalWidth).clamp(0.0, 1.0);
    setState(() => _dragFraction = frac);
  }

  void _updateScrub(Offset localPosition, double totalWidth) {
    if (totalWidth <= 0) return;
    final frac = (localPosition.dx / totalWidth).clamp(0.0, 1.0);
    setState(() => _dragFraction = frac);
  }

  void _endScrub(Duration totalDuration, ChatProvider provider) {
    if (_dragFraction != null && totalDuration.inMilliseconds > 0) {
      final seekMs = (totalDuration.inMilliseconds * _dragFraction!).toInt();
      final isCurrent = provider.playingMessageId == widget.message.id;
      if (!isCurrent) {
        provider.playVoiceNote(widget.message);
      }
      provider.seekVoiceNote(Duration(milliseconds: seekMs));
    }
    setState(() => _dragFraction = null);
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool isScrubbing;

  _WaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.isScrubbing = false,
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
    double thumbX = (size.width * progress).clamp(0.0, size.width);

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

    // Draw scrubber playhead thumb when scrubbing or active
    if (isScrubbing || progress > 0.0) {
      final thumbRadius = isScrubbing ? 5.5 : 4.0;
      final thumbPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final center = Offset(thumbX, size.height / 2);
      canvas.drawCircle(center, thumbRadius, thumbPaint);
      canvas.drawCircle(center, thumbRadius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.amplitudes != amplitudes ||
        oldDelegate.isScrubbing != isScrubbing;
  }
}
