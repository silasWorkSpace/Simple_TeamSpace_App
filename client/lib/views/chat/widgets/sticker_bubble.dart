import 'package:flutter/material.dart';
import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/core/sticker_catalog.dart';

class StickerBubble extends StatelessWidget {
  final MessageModel message;

  const StickerBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // Extract sticker ID from metadata, or fallback to an unknown value
    final stickerId = message.metadata.stickerId ?? 'unknown';
    
    // Get the local asset path from our centralized catalog
    final assetPath = StickerCatalog.getAssetPath(stickerId);

    return Container(
      padding: const EdgeInsets.all(4.0),
      // Constrain sticker dimensions explicitly as requested
      width: 120,
      height: 120,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Unknown sticker fallback if the file physically doesn't exist
          return const Icon(
            Icons.broken_image,
            size: 64,
            color: Colors.grey,
          );
        },
      ),
    );
  }
}
