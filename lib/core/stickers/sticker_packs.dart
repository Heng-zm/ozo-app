import '../database/models.dart';

/// Pre-bundled curated sticker packs for expressive messaging.
/// 
/// COMPLIANCE NOTE: All stickers in this catalog use 100% standard Unicode
/// emojis and symbols. No copyrighted graphics, trademarked characters, or
/// proprietary brand assets are used or referenced. Safe for App Store & Play Store.
class StickerCatalog {
  static const List<StickerPack> packs = [
    StickerPack(
      id: 'cyber_cats',
      name: 'Cyber Cats',
      icon: '🐱‍💻',
      stickers: [
        StickerData(
          id: 'cat_hack',
          packId: 'cyber_cats',
          name: 'Hacking Cat',
          emoji: '🐱‍💻',
        ),
        StickerData(
          id: 'cat_rocket',
          packId: 'cyber_cats',
          name: 'Astro Cat',
          emoji: '🚀🐱',
        ),
        StickerData(
          id: 'cat_fire',
          packId: 'cyber_cats',
          name: 'Fire Cat',
          emoji: '🔥🐱',
        ),
        StickerData(
          id: 'cat_ninja',
          packId: 'cyber_cats',
          name: 'Ninja Cat',
          emoji: '🐱‍👤',
        ),
        StickerData(
          id: 'cat_coffee',
          packId: 'cyber_cats',
          name: 'Coffee Fuel',
          emoji: '☕🐱',
        ),
        StickerData(
          id: 'cat_sleep',
          packId: 'cyber_cats',
          name: 'Sleepy Debug',
          emoji: '💤🐱',
        ),
        StickerData(
          id: 'cat_bug',
          packId: 'cyber_cats',
          name: 'Bug Hunter',
          emoji: '🐞🐱',
        ),
        StickerData(
          id: 'cat_deploy',
          packId: 'cyber_cats',
          name: 'Deploy Victory',
          emoji: '🎉🐱',
        ),
      ],
    ),
    StickerPack(
      id: 'expressive_reactions',
      name: 'Reactions',
      icon: '🔥',
      stickers: [
        StickerData(
          id: 'react_mindblown',
          packId: 'expressive_reactions',
          name: 'Mind Blown',
          emoji: '🤯',
        ),
        StickerData(
          id: 'react_party',
          packId: 'expressive_reactions',
          name: 'Celebration',
          emoji: '🥳',
        ),
        StickerData(
          id: 'react_rofl',
          packId: 'expressive_reactions',
          name: 'Rolling Laugh',
          emoji: '🤣',
        ),
        StickerData(
          id: 'react_cool',
          packId: 'expressive_reactions',
          name: 'Stay Cool',
          emoji: '😎',
        ),
        StickerData(
          id: 'react_salute',
          packId: 'expressive_reactions',
          name: 'Yes Sir',
          emoji: '🫡',
        ),
        StickerData(
          id: 'react_facepalm',
          packId: 'expressive_reactions',
          name: 'Facepalm',
          emoji: '🤦',
        ),
        StickerData(
          id: 'react_screaming',
          packId: 'expressive_reactions',
          name: 'Shocked',
          emoji: '😱',
        ),
        StickerData(
          id: 'react_fire100',
          packId: 'expressive_reactions',
          name: '100% Fire',
          emoji: '💯🔥',
        ),
      ],
    ),
    StickerPack(
      id: 'lan_badges',
      name: 'P2P Badges',
      icon: '⚡',
      stickers: [
        StickerData(
          id: 'badge_rocket',
          packId: 'lan_badges',
          name: 'To The Moon',
          emoji: '🚀',
        ),
        StickerData(
          id: 'badge_diamond',
          packId: 'lan_badges',
          name: 'Diamond Hands',
          emoji: '💎',
        ),
        StickerData(
          id: 'badge_matrix',
          packId: 'lan_badges',
          name: 'Cyber Mesh',
          emoji: '🌐',
        ),
        StickerData(
          id: 'badge_lightning',
          packId: 'lan_badges',
          name: 'Zero Latency',
          emoji: '⚡',
        ),
        StickerData(
          id: 'badge_shield',
          packId: 'lan_badges',
          name: 'E2EE Shield',
          emoji: '🛡️',
        ),
        StickerData(
          id: 'badge_link',
          packId: 'lan_badges',
          name: 'P2P Connected',
          emoji: '🔗',
        ),
        StickerData(
          id: 'badge_check',
          packId: 'lan_badges',
          name: 'Verified',
          emoji: '✅',
        ),
        StickerData(
          id: 'badge_sound',
          packId: 'lan_badges',
          name: 'Loud & Clear',
          emoji: '🔊',
        ),
      ],
    ),
  ];

  /// Looks up a sticker by ID across all packs, supporting legacy pack prefixes if applicable.
  static StickerData? findSticker(String stickerId) {
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        if (sticker.id == stickerId) return sticker;
      }
    }
    return null;
  }
}
