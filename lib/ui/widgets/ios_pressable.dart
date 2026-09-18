import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Ultra-modern tactile spring-physics pressable container inspired by next-gen iOS.
/// Provides smooth scale depression (0.94x), fluid elastic rebound, and haptic feedback.
class IosPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;
  final bool enableHaptics;
  final HitTestBehavior behavior;

  const IosPressable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.pressedScale = 0.93,
    this.duration = const Duration(milliseconds: 110),
    this.enableHaptics = true,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<IosPressable> createState() => _IosPressableState();
}

class _IosPressableState extends State<IosPressable> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 240),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
        reverseCurve: Curves.easeOutBack,
      ),
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed == null && widget.onLongPress == null) return;
    if (widget.enableHaptics) HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onPressed == null) return;
    _controller.reverse();
    widget.onPressed!();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress != null
          ? () {
              if (widget.enableHaptics) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Frosted glass and gradient icon button with specular hairline border and iOS 26 tactile feedback
class IosIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Gradient? gradient;
  final Color? iconColor;
  final String? tooltip;
  final bool isGlass;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry padding;

  const IosIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 38,
    this.backgroundColor,
    this.gradient,
    this.iconColor,
    this.tooltip,
    this.isGlass = true,
    this.shape = BoxShape.circle,
    this.borderRadius,
    this.shadows,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBg = backgroundColor ??
        (isDark
            ? const Color(0x33FFFFFF)
            : const Color(0x14000000));

    final effectiveRadius = shape == BoxShape.circle
        ? null
        : (borderRadius ?? BorderRadius.circular(size * 0.32));

    final effectiveBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.65);

    Widget content = Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? effectiveBg : null,
        gradient: gradient,
        shape: shape,
        borderRadius: effectiveRadius,
        border: Border.all(color: effectiveBorderColor, width: 0.75),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
      ),
      child: Center(
        child: IconTheme(
          data: IconThemeData(
            color: iconColor ?? (isDark ? Colors.white : Colors.black87),
            size: size * 0.52,
          ),
          child: icon,
        ),
      ),
    );

    if (isGlass) {
      content = ClipRRect(
        borderRadius: effectiveRadius ?? BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: content,
        ),
      );
    }

    Widget result = IosPressable(
      onPressed: onPressed,
      child: content,
    );

    if (tooltip != null) {
      result = Tooltip(
        message: tooltip!,
        child: result,
      );
    }

    return result;
  }
}

/// Vibrant or Translucent iOS 26 Pill Button with specular rim and spring tactile response
class IosPillButton extends StatelessWidget {
  final Widget? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final Color? customColor;
  final Gradient? customGradient;
  final double height;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const IosPillButton({
    super.key,
    this.icon,
    required this.label,
    this.onPressed,
    this.isPrimary = true,
    this.customColor,
    this.customGradient,
    this.height = 42,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.fontSize = 14.5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBlue = isDark ? TelegramTheme.primaryDarkBlue : TelegramTheme.primaryBlue;

    final defaultPrimaryGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryBlue.withValues(alpha: 0.95),
        isDark ? const Color(0xFF0062CC) : const Color(0xFF0051B3),
      ],
    );

    final defaultSecondaryBg = isDark
        ? const Color(0x28FFFFFF)
        : const Color(0x10000000);

    final effectiveBg = isPrimary
        ? (customColor ?? primaryBlue)
        : (customColor ?? defaultSecondaryBg);

    final effectiveGradient = isPrimary
        ? (customGradient ?? defaultPrimaryGradient)
        : customGradient;

    final textColor = isPrimary
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    final borderColor = isPrimary
        ? Colors.white.withValues(alpha: 0.25)
        : (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08));

    return IosPressable(
      onPressed: onPressed,
      child: Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: effectiveGradient == null ? effectiveBg : null,
          gradient: effectiveGradient,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: borderColor, width: 0.75),
          boxShadow: [
            if (isPrimary)
              BoxShadow(
                color: (customColor ?? primaryBlue).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: IconThemeData(color: textColor, size: fontSize + 3),
                child: icon!,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
