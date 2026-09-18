import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Notification event model for the in-app floating banner
class InAppNotificationItem {
  final String title;
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Duration duration;

  InAppNotificationItem({
    required this.title,
    required this.message,
    this.icon,
    this.iconColor,
    this.onTap,
    this.duration = const Duration(seconds: 4),
  });
}

/// Floating Dynamic Island / Pill style in-app notification banner
class InAppNotificationBanner {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    IconData? icon,
    Color? iconColor,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    dismiss();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _currentEntry = OverlayEntry(
      builder: (ctx) => _DynamicIslandBannerWidget(
        title: title,
        message: message,
        icon: icon ?? CupertinoIcons.chat_bubble_2_fill,
        iconColor: iconColor ?? const Color(0xFF007AFF),
        onTap: () {
          dismiss();
          if (onTap != null) onTap();
        },
        onDismiss: dismiss,
      ),
    );

    overlay.insert(_currentEntry!);

    _dismissTimer = Timer(duration, () {
      dismiss();
    });
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (_currentEntry?.mounted == true) {
      _currentEntry?.remove();
    }
    _currentEntry = null;
  }
}

class _DynamicIslandBannerWidget extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _DynamicIslandBannerWidget({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_DynamicIslandBannerWidget> createState() => _DynamicIslandBannerWidgetState();
}

class _DynamicIslandBannerWidgetState extends State<_DynamicIslandBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    _animController.forward();
  }

  void _dismissWithAnim() async {
    try {
      await _animController.reverse();
    } catch (_) {}
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                _dismissWithAnim();
              }
            },
            onTap: widget.onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.iconColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.iconColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                decoration: TextDecoration.none,
                                fontFamily: '.SF Pro Text',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                                color: isDark ? Colors.white70 : Colors.black54,
                                decoration: TextDecoration.none,
                                fontFamily: '.SF Pro Text',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black26,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
