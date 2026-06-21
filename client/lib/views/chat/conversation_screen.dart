import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:last_project_client/controllers/chat_controller.dart';
import 'package:last_project_client/controllers/channel_controller.dart';
import 'package:last_project_client/services/file_transfer_service.dart';
import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/models/channel_model.dart';
import 'package:last_project_client/views/chat/widgets/message_bubble.dart';
import 'package:last_project_client/views/chat/widgets/chat_input.dart';
import 'package:last_project_client/views/chat/channel_info_dialog.dart';

class ConversationScreen extends StatefulWidget {
  final int peerId;
  final String peerName;

  const ConversationScreen({
    super.key,
    required this.peerId,
    required this.peerName,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _currentPeerName = '';

  @override
  void initState() {
    super.initState();
    _currentPeerName = widget.peerName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatController>().loadHistory(widget.peerId);
    });
  }

  void _loadMore(ChatController chatController) {
    final messages = chatController.getMessages(widget.peerId);
    if (messages.isNotEmpty && messages.first.id != null) {
      chatController.loadHistory(widget.peerId, beforeId: messages.first.id);
    }
  }

  Future<void> _pickAndUpload() async {
    final svc = context.read<FileTransferService>();
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: false, // We stream from path, not memory
    );

    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;

    final file = File(picked.path!);

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      await svc.uploadFile(
        file: file,
        receiverId: widget.peerId,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPeerName),
        actions: [
          if (widget.peerId < 0)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => ChannelInfoDialog(
                    channelId: widget.peerId.abs(),
                    channelName: _currentPeerName,
                  ),
                );
                if (result == "deleted") {
                  nav.pop(); // Close conversation screen
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Upload progress banner
          if (_isUploading)
            LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),

          Expanded(
            child: Consumer<ChatController>(
              builder: (context, chatController, child) {
                final messages = chatController.getMessages(widget.peerId);
                final currentUserId = chatController.currentUserId;

                if (messages.isEmpty) {
                  return const Center(child: Text("No messages yet"));
                }

                // In a reversed ListView, index 0 is at the bottom.
                // Our controller list is [Oldest -> Newest].
                // Reversed view: [Newest -> Oldest].
                final viewMessages = messages.reversed.toList();

                return ListView.builder(
                  reverse: true,
                  itemCount: viewMessages.length + 1, // +1 for "Load More"
                  itemBuilder: (context, index) {
                    if (index == viewMessages.length) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextButton(
                          onPressed: () => _loadMore(chatController),
                          child: const Text("Load older messages"),
                        ),
                      );
                    }

                    final message = viewMessages[index];
                    return MessageBubble(
                      message: message,
                      isMe: message.senderId == currentUserId,
                    );
                  },
                );
              },
            ),
          ),
          Consumer<ChannelController>(
            builder: (context, channelController, child) {
              if (widget.peerId < 0) {
                final channel = channelController.channels.firstWhere(
                  (c) => c.id == widget.peerId,
                  orElse: () => ChannelModel(id: widget.peerId, name: widget.peerName, ownerId: 0, isPublic: false)
                );
                if (!channel.isJoined) {
                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: () {
                        channelController.channelService.joinChannel(widget.peerId.abs());
                      },
                      child: const Text("Join Channel"),
                    ),
                  );
                }
              }

              return ChatInput(
                onSend: (content) {
                  context.read<ChatController>().sendMessage(widget.peerId, content);
                },
                onSendSticker: (stickerId) {
                  context.read<ChatController>().sendMessage(
                    widget.peerId,
                    '', // empty content for stickers as requested
                    msgType: MessageType.sticker,
                    metadata: MessageMetadata(stickerId: stickerId),
                  );
                },
                onSendVoice: (file, durationMs) {
                  context.read<FileTransferService>().uploadFile(
                    file: file,
                    receiverId: widget.peerId,
                    msgType: MessageType.voice,
                    metadata: {
                      'duration_ms': durationMs,
                      'codec': 'm4a',
                    },
                  );
                },
                onAttach: _pickAndUpload,
              );
            },
          ),
        ],
      ),
    );
  }
}
