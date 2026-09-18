import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AttachmentAction {
  photo,
  file,
  location,
  stickers,
  timer,
  walkieTalkie,
}

class AttachmentActionSheet extends StatelessWidget {
  final ValueChanged<AttachmentAction> onActionSelected;
  final bool isGroup;
  final int? currentEphemeralSeconds;

  const AttachmentActionSheet({
    super.key,
    required this.onActionSelected,
    this.isGroup = false,
    this.currentEphemeralSeconds,
  });

  static Future<AttachmentAction?> show(
    BuildContext context, {
    bool isGroup = false,
    int? currentEphemeralSeconds,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<AttachmentAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AttachmentActionSheet(
        isGroup: isGroup,
        currentEphemeralSeconds: currentEphemeralSeconds,
        onActionSelected: (action) {
          Navigator.of(ctx).pop(action);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xEB1E293B)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pull handle
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),
                // Grid of 6 action tiles
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.88,
                  children: [
                    _buildTile(
                      context,
                      icon: CupertinoIcons.photo_fill_on_rectangle_fill,
                      label: 'Photos',
                      gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      action: AttachmentAction.photo,
                    ),
                    _buildTile(
                      context,
                      icon: CupertinoIcons.folder_fill,
                      label: 'Documents',
                      gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                      action: AttachmentAction.file,
                    ),
                    _buildTile(
                      context,
                      icon: CupertinoIcons.location_solid,
                      label: 'Location',
                      gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                      action: AttachmentAction.location,
                    ),
                    _buildTile(
                      context,
                      icon: CupertinoIcons.smiley_fill,
                      label: 'Stickers',
                      gradient: const [Color(0xFFEC4899), Color(0xFFDB2777)],
                      action: AttachmentAction.stickers,
                    ),
                    _buildTile(
                      context,
                      icon: CupertinoIcons.timer_fill,
                      label: currentEphemeralSeconds != null
                          ? '${currentEphemeralSeconds}s Timer'
                          : 'Timer',
                      gradient: const [Color(0xFFE11D48), Color(0xFFBE123C)],
                      action: AttachmentAction.timer,
                    ),
                    _buildTile(
                      context,
                      icon: CupertinoIcons.waveform_circle_fill,
                      label: 'Walkie-Talkie',
                      gradient: const [Color(0xFF0284C7), Color(0xFF2563EB)],
                      action: AttachmentAction.walkieTalkie,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required AttachmentAction action,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onActionSelected(action);
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
