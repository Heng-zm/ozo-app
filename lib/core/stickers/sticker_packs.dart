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
    StickerPack(
      id: 'crypto_devs',
      name: 'Crypto Devs',
      icon: '💻',
      stickers: [
        StickerData(
          id: 'dev_terminal',
          packId: 'crypto_devs',
          name: 'Terminal Mode',
          emoji: '💻⚡',
        ),
        StickerData(
          id: 'dev_coffee',
          packId: 'crypto_devs',
          name: 'Coffee Fueled',
          emoji: '☕⌨️',
        ),
        StickerData(
          id: 'dev_git',
          packId: 'crypto_devs',
          name: 'Git Push Master',
          emoji: '🐙🚀',
        ),
        StickerData(
          id: 'dev_bug',
          packId: 'crypto_devs',
          name: 'Squashing Bugs',
          emoji: '🐛🔨',
        ),
        StickerData(
          id: 'dev_lock',
          packId: 'crypto_devs',
          name: 'Zero Trust',
          emoji: '🔒🛡️',
        ),
        StickerData(
          id: 'dev_success',
          packId: 'crypto_devs',
          name: 'Build Green',
          emoji: '✨🟢',
        ),
        StickerData(
          id: 'dev_fire',
          packId: 'crypto_devs',
          name: 'Prod on Fire',
          emoji: '🚨🔥',
        ),
        StickerData(
          id: 'dev_chill',
          packId: 'crypto_devs',
          name: 'Works on My Machine',
          emoji: '🏖️💻',
        ),
      ],
    ),
    StickerPack(
      id: 'party_vibes',
      name: 'Party Vibes',
      icon: '🎉',
      stickers: [
        StickerData(
          id: 'party_disco',
          packId: 'party_vibes',
          name: 'Disco Time',
          emoji: '🪩✨',
        ),
        StickerData(
          id: 'party_popper',
          packId: 'party_vibes',
          name: 'Confetti Burst',
          emoji: '🎉🎊',
        ),
        StickerData(
          id: 'party_cocktail',
          packId: 'party_vibes',
          name: 'Cheers',
          emoji: '🥂🍸',
        ),
        StickerData(
          id: 'party_music',
          packId: 'party_vibes',
          name: 'Feel the Bass',
          emoji: '🎧🎶',
        ),
        StickerData(
          id: 'party_dance',
          packId: 'party_vibes',
          name: 'Dance Floor',
          emoji: '💃🕺',
        ),
        StickerData(
          id: 'party_balloon',
          packId: 'party_vibes',
          name: 'Celebration',
          emoji: '🎈🥳',
        ),
        StickerData(
          id: 'party_crown',
          packId: 'party_vibes',
          name: 'VIP Status',
          emoji: '👑✨',
        ),
        StickerData(
          id: 'party_spark',
          packId: 'party_vibes',
          name: 'Sparklers',
          emoji: '🎇🎆',
        ),
      ],
    ),
    StickerPack(
      id: 'animals_wild',
      name: 'Wild Animals',
      icon: '🦊',
      stickers: [
        StickerData(
          id: 'animal_fox',
          packId: 'animals_wild',
          name: 'Clever Fox',
          emoji: '🦊',
        ),
        StickerData(
          id: 'animal_wolf',
          packId: 'animals_wild',
          name: 'Lone Wolf',
          emoji: '🐺🌕',
        ),
        StickerData(
          id: 'animal_lion',
          packId: 'animals_wild',
          name: 'King Lion',
          emoji: '🦁👑',
        ),
        StickerData(
          id: 'animal_panda',
          packId: 'animals_wild',
          name: 'Chilled Panda',
          emoji: '🐼🎋',
        ),
        StickerData(
          id: 'animal_owl',
          packId: 'animals_wild',
          name: 'Night Owl',
          emoji: '🦉⭐',
        ),
        StickerData(
          id: 'animal_koala',
          packId: 'animals_wild',
          name: 'Cozy Koala',
          emoji: '🐨🌿',
        ),
        StickerData(
          id: 'animal_tiger',
          packId: 'animals_wild',
          name: 'Stealth Tiger',
          emoji: '🐯🐾',
        ),
        StickerData(
          id: 'animal_unicorn',
          packId: 'animals_wild',
          name: 'Magic Unicorn',
          emoji: '🦄🌈',
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

  /// Searches stickers across all packs by name or emoji
  static List<StickerData> searchStickers(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final results = <StickerData>[];
    for (final pack in packs) {
      for (final s in pack.stickers) {
        if (s.name.toLowerCase().contains(q) || s.emoji.contains(q) || s.id.toLowerCase().contains(q)) {
          results.add(s);
        }
      }
    }
    return results;
  }
}
