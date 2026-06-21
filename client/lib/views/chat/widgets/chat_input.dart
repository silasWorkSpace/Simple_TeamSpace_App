import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:last_project_client/services/voice_recording_service.dart';
import 'package:last_project_client/views/chat/widgets/sticker_picker.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final Function(String)? onSendSticker;
  final Function(File, int)? onSendVoice;
  final VoidCallback? onAttach;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onSendSticker,
    this.onSendVoice,
    this.onAttach,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final VoiceRecordingService _voiceService = VoiceRecordingService();
  
  bool _isEmojiShowing = false;
  
  bool _isRecording = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  static const int _maxRecordingSeconds = 60;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored; // Allow newline
        } else {
          _handleSend();
          return KeyEventResult.handled; // Send and prevent newline
        }
      }
      return KeyEventResult.ignored;
    };
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
      setState(() {});
    }
  }

  void _startRecording() async {
    try {
      await _voiceService.startRecording();
      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
        if (_recordingDuration >= _maxRecordingSeconds) {
          _stopAndSendRecording();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recording limit reached (60s).')),
            );
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  void _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    final result = await _voiceService.stopRecording();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });

    if (result != null && widget.onSendVoice != null) {
      final file = result.$1;
      final durationMs = result.$2;
      if (durationMs > 500) { // Minimum 0.5s
        widget.onSendVoice!(file, durationMs);
      }
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    await _voiceService.cancelRecording();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasText = _controller.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -1),
                blurRadius: 4,
              ),
            ],
          ),
          child: SafeArea(
            bottom: !_isEmojiShowing,
            child: Row(
              children: [
                if (!_isRecording) ...[
                  IconButton(
                    icon: Icon(
                      _isEmojiShowing ? Icons.keyboard : Icons.emoji_emotions_outlined,
                      color: colorScheme.primary,
                    ),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _isEmojiShowing = !_isEmojiShowing);
                    },
                  ),
                  if (widget.onAttach != null)
                    IconButton(
                      icon: Icon(Icons.attach_file, color: colorScheme.primary),
                      onPressed: widget.onAttach,
                      tooltip: 'Attach file',
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onTap: () {
                        if (_isEmojiShowing) {
                          setState(() => _isEmojiShowing = false);
                        }
                      },
                      onChanged: (val) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                ] else ...[
                  // Recording State UI
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _cancelRecording,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.mic, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(_recordingDuration),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Send or Mic Button
                if (hasText)
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: colorScheme.primary,
                    onPressed: _handleSend,
                  )
                else if (widget.onSendVoice != null)
                  IconButton(
                    icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic),
                    color: _isRecording ? Colors.red : colorScheme.primary,
                    iconSize: _isRecording ? 32 : 24,
                    onPressed: _isRecording ? _stopAndSendRecording : _startRecording,
                  ),
              ],
            ),
          ),
        ),
        if (_isEmojiShowing && widget.onSendSticker != null && !_isRecording)
          _buildStickerPicker(),
      ],
    );
  }

  Widget _buildStickerPicker() {
    return StickerPicker(
      onStickerSelected: (stickerId) {
        widget.onSendSticker!(stickerId);
        setState(() => _isEmojiShowing = false);
      },
    );
  }
}
