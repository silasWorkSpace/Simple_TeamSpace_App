import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/services/file_transfer_service.dart';

class VoiceBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const VoiceBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isDownloaded = false;
  bool _isDownloading = false;
  String? _localPath;
  
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    final durationMs = widget.message.metadata.durationMs ?? 0;
    _duration = Duration(milliseconds: durationMs);

    _checkLocalCache();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });
    
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _isPlaying = false;
        });
      }
    });
  }

  Future<void> _checkLocalCache() async {
    final filename = widget.message.metadata.filename;
    if (filename == null) return;
    
    final fts = context.read<FileTransferService>();
    final path = await fts.getLocalFilePath(widget.message.content, filename);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _localPath = path;
            _isDownloaded = true;
          });
        }
      }
    }
  }

  Future<void> _download() async {
    setState(() {
      _isDownloading = true;
    });
    
    try {
      final fts = context.read<FileTransferService>();
      await fts.downloadFile(
        token: widget.message.content,
        filename: widget.message.metadata.filename ?? 'voice_message.m4a',
        sizeBytes: widget.message.metadata.sizeBytes ?? 0,
      );
      await _checkLocalCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  void _togglePlayPause() async {
    if (_localPath == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(DeviceFileSource(_localPath!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e')),
        );
      }
    }
  }

  void _seek(double value) {
    final position = Duration(milliseconds: value.toInt());
    _audioPlayer.seek(position);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgColor = widget.isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    final bgColor = widget.isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: Radius.circular(widget.isMe ? 12 : 0),
          bottomRight: Radius.circular(widget.isMe ? 0 : 12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Action Button (Download, Spinner, or Play/Pause)
          _buildActionButton(fgColor),
          const SizedBox(width: 8),
          
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                trackHeight: 3,
                activeTrackColor: fgColor,
                inactiveTrackColor: fgColor.withValues(alpha: 0.3),
                thumbColor: fgColor,
              ),
              child: Slider(
                min: 0,
                max: _duration.inMilliseconds.toDouble() > 0 
                    ? _duration.inMilliseconds.toDouble() 
                    : 1.0,
                value: (_position.inMilliseconds.toDouble())
                    .clamp(0.0, _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
                onChanged: _isDownloaded ? _seek : null,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Duration Text
          Text(
            _formatDuration(_position.inMilliseconds > 0 ? _position : _duration),
            style: TextStyle(color: fgColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(Color fgColor) {
    if (_isDownloading) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(fgColor),
          ),
        ),
      );
    }

    if (!_isDownloaded) {
      return IconButton(
        icon: const Icon(Icons.download),
        color: fgColor,
        onPressed: _download,
        tooltip: 'Download Voice Message',
      );
    }

    return IconButton(
      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
      color: fgColor,
      onPressed: _togglePlayPause,
    );
  }
}
