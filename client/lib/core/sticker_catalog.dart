class StickerCatalog {
  /// Maps sticker_id to local asset path
  static const Map<String, String> registry = {
    'apple_cry': 'assets/images/stickers/apple_cry.png',
    'apple_laugh': 'assets/images/stickers/apple_laugh.png',
  };

  /// Returns the asset path for a sticker_id, or a fallback if not found.
  static String getAssetPath(String stickerId) {
    return registry[stickerId] ?? 'assets/images/placeholder_sticker.png';
  }

  /// Returns a list of all registered sticker IDs for the picker UI.
  static List<String> get allStickers => registry.keys.toList();
}
