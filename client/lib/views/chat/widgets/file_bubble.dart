import 'dart:io';
import 'package:flutter/material.dart';
import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/services/file_transfer_service.dart';
import 'package:provider/provider.dart';

/// Renders a downloadable file card for [MessageType.file] messages,
/// and also for [MessageType.image] messages that exceed the inline threshold.
class FileBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const FileBubble({super.key, required this.message, required this.isMe});

  @override
  State<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<FileBubble> {
  double? _progress; // null = idle, 0.0–1.0 = downloading
  bool _done = false;
  String? _error;

  String get _filename =>
      widget.message.metadata.filename ?? widget.message.content;
  int get _sizeBytes => widget.message.metadata.sizeBytes ?? 0;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadySaved();
  }

  Future<void> _checkIfAlreadySaved() async {
    final svc = context.read<FileTransferService>();
    final localPath = await svc.getLocalFilePath(widget.message.content, _filename);
    if (localPath != null && mounted) {
      final exists = await File(localPath).exists();
      if (exists && mounted) {
        setState(() => _done = true);
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<void> _download() async {
    if (_progress != null || _done) return;
    setState(() => _progress = 0.0);

    final svc = context.read<FileTransferService>();
    try {
      await svc.downloadFile(
        token: widget.message.content,
        filename: _filename,
        sizeBytes: _sizeBytes,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() { _done = true; _progress = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _progress = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMe = widget.isMe;
    final bg = isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final fg = isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: Radius.circular(isMe ? 12 : 0),
          bottomRight: Radius.circular(isMe ? 0 : 12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: fg, size: 32),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _filename,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatSize(_sizeBytes),
                  style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12),
                ),
                if (_progress != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: _progress),
                  Text(
                    '${(_progress! * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
                if (_error != null)
                  Text('Error', style: TextStyle(color: colorScheme.error, fontSize: 12)),
                if (_done)
                  Text('Saved', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_progress == null && !_done)
            IconButton(
              icon: Icon(Icons.download_outlined, color: fg),
              onPressed: _download,
              tooltip: 'Download',
            ),
        ],
      ),
    );
  }
}
