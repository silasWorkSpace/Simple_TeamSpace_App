import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/core/app_constants.dart';
import 'package:last_project_client/views/chat/widgets/file_bubble.dart';
import 'package:last_project_client/views/chat/widgets/image_bubble.dart';
import 'package:last_project_client/views/chat/widgets/sticker_bubble.dart';
import 'package:last_project_client/views/chat/widgets/voice_bubble.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    // Dispatch to the correct bubble renderer based on msgType.
    if (message.isSticker) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: StickerBubble(message: message),
      );
    }
    
    if (message.isVoice) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: VoiceBubble(message: message, isMe: isMe),
      );
    }

    // Images over the inline threshold are treated as downloadable files.
    if (message.isImage &&
        (message.metadata.sizeBytes ?? 0) <= AppConstants.maxInlineImageBytes) {
      return ImageBubble(message: message, isMe: isMe);
    }

    if (message.isFile || message.isImage) {
      // isImage lands here only when sizeBytes > maxInlineImageBytes
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: FileBubble(message: message, isMe: isMe),
      );
    }

    // Default: plain text bubble (also handles unknown/sticker fallback)
    return _TextBubble(message: message, isMe: isMe);
  }
}

class _TextBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const _TextBubble({required this.message, required this.isMe});

  String _formatTime(DateTime dateTime) => DateFormat('HH:mm').format(dateTime);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    color: (isMe
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant)
                        .withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(colorScheme),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme colorScheme) {
    IconData icon;
    Color color = colorScheme.onPrimary.withValues(alpha: 0.7);

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        break;
      case MessageStatus.error:
        icon = Icons.error_outline;
        color = colorScheme.error;
        break;
    }

    return Icon(icon, size: 14, color: color);
  }
}
