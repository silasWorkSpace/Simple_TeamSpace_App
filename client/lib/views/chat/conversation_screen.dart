import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/chat_controller.dart';
import 'package:last_project_client/views/chat/widgets/message_bubble.dart';
import 'package:last_project_client/views/chat/widgets/chat_input.dart';

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
  @override
  void initState() {
    super.initState();
    // Fetch initial history
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerName),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // TODO: Peer info/settings
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
          ChatInput(
            onSend: (content) {
              context.read<ChatController>().sendMessage(widget.peerId, content);
            },
          ),
        ],
      ),
    );
  }
}
