import 'package:flutter/material.dart';
import 'package:last_project_client/core/sticker_catalog.dart';

class StickerPicker extends StatelessWidget {
  final Function(String) onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  Widget build(BuildContext context) {
    final stickers = StickerCatalog.allStickers;

    return Container(
      height: 200,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: GridView.builder(
        padding: const EdgeInsets.all(8.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8.0,
          mainAxisSpacing: 8.0,
        ),
        itemCount: stickers.length,
        itemBuilder: (context, index) {
          final stickerId = stickers[index];
          final assetPath = StickerCatalog.getAssetPath(stickerId);
          
          return InkWell(
            onTap: () => onStickerSelected(stickerId),
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
