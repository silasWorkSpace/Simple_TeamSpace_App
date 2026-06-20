import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/services/file_transfer_service.dart';
import 'package:last_project_client/core/app_constants.dart';
import 'package:provider/provider.dart';

/// Renders an inline image preview for [MessageType.image] messages
/// where sizeBytes ≤ [AppConstants.maxInlineImageBytes].
///
/// Downloads and caches the image bytes on first render.
/// Falls back to a loading spinner during download and an error icon on failure.
class ImageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const ImageBubble({super.key, required this.message, required this.isMe});

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  Uint8List? _bytes;
  double? _progress; // null = not yet started
  bool _started = false;
  String? _error;

  int get _sizeBytes => widget.message.metadata.sizeBytes ?? 0;

  @override
  void initState() {
    super.initState();
    // Auto-download inline images immediately upon rendering
    _download();
  }

  Future<void> _download() async {
    if (_started) return;
    _started = true;
    setState(() => _progress = 0.0);

    final svc = context.read<FileTransferService>();
    try {
      final result = await svc.downloadFile(
        token: widget.message.content,
        filename: widget.message.metadata.filename ?? 'image',
        sizeBytes: _sizeBytes,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() {
          _bytes = result.bytes;
          _progress = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _progress = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    Widget content;

    if (_bytes != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _bytes!,
          fit: BoxFit.cover,
          width: maxWidth,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
        ),
      );
    } else if (_error != null) {
      content = SizedBox(
        width: 120,
        height: 80,
        child: Center(
          child: Icon(Icons.broken_image, color: colorScheme.error, size: 40),
        ),
      );
    } else {
      // Loading state — show progress
      content = SizedBox(
        width: maxWidth,
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              value: (_progress != null && _progress! > 0) ? _progress : null,
            ),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              Text(
                '${(_progress! * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: widget.isMe
              ? colorScheme.primary.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(widget.isMe ? 12 : 0),
            bottomRight: Radius.circular(widget.isMe ? 0 : 12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: content,
        ),
      ),
    );
  }
}
