import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Full-featured in-app video streaming player for MP4 / MOV files
class VideoPlayerViewer extends StatefulWidget {
  final String videoPath;
  final String? title;

  const VideoPlayerViewer({
    super.key,
    required this.videoPath,
    this.title,
  });

  @override
  State<VideoPlayerViewer> createState() => _VideoPlayerViewerState();
}

class _VideoPlayerViewerState extends State<VideoPlayerViewer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  Timer? _controlsTimer;
  double _playbackSpeed = 1.0;
  bool _isLandscape = false;
  String? _seekOverlayText;
  Timer? _seekOverlayTimer;
  String? _errorMessage;

  final List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.videoPath);
      final VideoPlayerController controller;
      if (await file.exists()) {
        controller = VideoPlayerController.file(file);
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoPath));
      }
      _controller = controller;

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _isInitialized = true;
        _errorMessage = null;
      });
      controller.play();
      _startControlsTimer();

      controller.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      debugPrint('[VideoPlayerViewer] initialize error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load video: $e';
        });
      }
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    }
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
        _controlsTimer?.cancel();
      } else {
        controller.play();
        _startControlsTimer();
      }
    });
  }

  void _seekRelative(Duration delta) {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    final current = controller.value.position;
    final total = controller.value.duration;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    controller.seekTo(target);

    final seconds = delta.inSeconds;
    final text = seconds > 0 ? '+$seconds s' : '$seconds s';

    setState(() {
      _seekOverlayText = text;
      _showControls = true;
    });

    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _seekOverlayText = null;
        });
      }
    });

    _startControlsTimer();
  }

  void _cycleSpeed() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    final currentIndex = _speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speeds.length;
    final nextSpeed = _speeds[nextIndex];
    controller.setPlaybackSpeed(nextSpeed);
    setState(() {
      _playbackSpeed = nextSpeed;
    });
  }

  void _toggleOrientation() {
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    setState(() {
      _isLandscape = !_isLandscape;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _seekOverlayTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isLandscape,
        bottom: !_isLandscape,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video Surface
            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                          color: Colors.amber, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                            _isInitialized = false;
                          });
                          _initPlayer();
                        },
                        icon: const Icon(CupertinoIcons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_isInitialized && _controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              const Center(
                child: CupertinoActivityIndicator(radius: 16, color: Colors.white),
              ),

            // Double Tap Seeking Hitboxes
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _seekRelative(const Duration(seconds: -10)),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _seekRelative(const Duration(seconds: 10)),
                  ),
                ),
              ],
            ),

            // Seek Indicator Overlay
            if (_seekOverlayText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _seekOverlayText!.startsWith('+')
                          ? CupertinoIcons.goforward_10
                          : CupertinoIcons.gobackward_10,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _seekOverlayText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Controls Overlay
            if (_showControls)
              Container(
                color: Colors.black38,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Text(
                              widget.title ?? 'Video Player',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _cycleSpeed,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_playbackSpeed}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isLandscape
                                  ? CupertinoIcons.device_phone_portrait
                                  : CupertinoIcons.device_phone_landscape,
                              color: Colors.white,
                            ),
                            onPressed: _toggleOrientation,
                          ),
                        ],
                      ),
                    ),

                    // Center Play / Pause button
                    IconButton(
                      iconSize: 64,
                      icon: Icon(
                        (_controller?.value.isPlaying ?? false)
                            ? CupertinoIcons.pause_circle_fill
                            : CupertinoIcons.play_circle_fill,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      onPressed: _togglePlayPause,
                    ),

                    // Bottom Bar with Scrubber
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isInitialized && _controller != null)
                            VideoProgressIndicator(
                              _controller!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFF007AFF),
                                bufferedColor: Colors.white30,
                                backgroundColor: Colors.white12,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(_controller?.value.position ?? Duration.zero),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                _formatDuration(_controller?.value.duration ?? Duration.zero),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
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
