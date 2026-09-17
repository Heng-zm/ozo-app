import 'package:flutter/material.dart';
import '../../core/database/models.dart';
import '../../core/stickers/sticker_packs.dart';
import '../theme/app_theme.dart';

class StickerPickerSheet extends StatefulWidget {
  final ValueChanged<StickerData> onStickerSelected;

  const StickerPickerSheet({
    super.key,
    required this.onStickerSelected,
  });

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static final List<StickerData> _recentStickers = [
    if (StickerCatalog.packs.isNotEmpty && StickerCatalog.packs[0].stickers.isNotEmpty)
      StickerCatalog.packs[0].stickers[0],
    if (StickerCatalog.packs.isNotEmpty && StickerCatalog.packs[0].stickers.length > 1)
      StickerCatalog.packs[0].stickers[1],
    if (StickerCatalog.packs.length > 1 && StickerCatalog.packs[1].stickers.isNotEmpty)
      StickerCatalog.packs[1].stickers[0],
    if (StickerCatalog.packs.length > 2 && StickerCatalog.packs[2].stickers.isNotEmpty)
      StickerCatalog.packs[2].stickers[0],
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: StickerCatalog.packs.length + 1,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectSticker(StickerData sticker) {
    setState(() {
      _recentStickers.removeWhere((s) => s.id == sticker.id);
      _recentStickers.insert(0, sticker);
      if (_recentStickers.length > 20) {
        _recentStickers.removeLast();
      }
    });
    Navigator.of(context).pop();
    widget.onStickerSelected(sticker);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Pack tabs with Recent tab at index 0
          TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: TelegramTheme.primaryBlue,
            indicatorWeight: 2.5,
            labelColor: TelegramTheme.primaryBlue,
            unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
            tabs: [
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🕒', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 6),
                    Text(
                      'Recent',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ...StickerCatalog.packs.map((pack) {
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(pack.icon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        pack.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
          const Divider(height: 1, thickness: 0.5),

          // Sticker grids
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Recent tab view
                _recentStickers.isEmpty
                    ? Center(
                        child: Text(
                          'No recent stickers yet',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _recentStickers.length,
                        itemBuilder: (context, index) {
                          final sticker = _recentStickers[index];
                          return _StickerTile(
                            sticker: sticker,
                            isDark: isDark,
                            onTap: () => _selectSticker(sticker),
                          );
                        },
                      ),
                // Catalog pack views
                ...StickerCatalog.packs.map((pack) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: pack.stickers.length,
                    itemBuilder: (context, index) {
                      final sticker = pack.stickers[index];
                      return _StickerTile(
                        sticker: sticker,
                        isDark: isDark,
                        onTap: () => _selectSticker(sticker),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerTile extends StatefulWidget {
  final StickerData sticker;
  final VoidCallback onTap;
  final bool isDark;

  const _StickerTile({
    required this.sticker,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<_StickerTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.sticker.emoji,
                style: const TextStyle(fontSize: 34),
              ),
              const SizedBox(height: 4),
              Text(
                widget.sticker.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: widget.isDark ? Colors.white70 : Colors.black54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
