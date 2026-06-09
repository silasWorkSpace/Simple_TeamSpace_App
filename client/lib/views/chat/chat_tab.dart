import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/chat_controller.dart';
import 'package:last_project_client/views/chat/widgets/conversation_tile.dart';
import 'package:last_project_client/views/chat/conversation_screen.dart';

class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("[CHAT] ChatTab.build() ChatController.hashCode=${Provider.of<ChatController>(context, listen: false).hashCode}");
    return Scaffold(
      body: Consumer<ChatController>(
        builder: (context, chatController, child) {
          final peerIds = chatController.activePeers.toList();
          debugPrint("[CHAT TAB] activePeers=${peerIds.toString()}");

          if (peerIds.isEmpty) {
            return const Center(
              child: Text("No conversations yet"),
            );
          }

          // Sort by last message timestamp (newest first)
          // Defensive: only sort peers who actually have messages
          peerIds.sort((a, b) {
            final messagesA = chatController.getMessages(a);
            final messagesB = chatController.getMessages(b);
            
            if (messagesA.isEmpty && messagesB.isEmpty) return 0;
            if (messagesA.isEmpty) return 1;
            if (messagesB.isEmpty) return -1;
            
            final lastA = messagesA.last.createdAt;
            final lastB = messagesB.last.createdAt;
            return lastB.compareTo(lastA);
          });

          return ListView.builder(
            itemCount: peerIds.length,
            itemBuilder: (context, index) {
              final peerId = peerIds[index];
              final messages = chatController.getMessages(peerId);
              
              // Defensive guard against empty message lists
              if (messages.isEmpty) return const SizedBox.shrink();
              
              final lastMsg = messages.last;
              
              final peerName = chatController.getPeerName(peerId) ?? "User $peerId";

              return ConversationTile(
                peerId: peerId,
                name: peerName,
                lastMessage: lastMsg.content,
                timestamp: lastMsg.createdAt,
                isOnline: chatController.isOnline(peerId),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ConversationScreen(
                        peerId: peerId,
                        peerName: peerName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(context),
        child: const Icon(Icons.add_comment),
      ),
    );
  }

  void _showNewChatDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Chat"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Enter User ID",
            hintText: "e.g. 1, 2, 3",
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final id = int.tryParse(controller.text);
              if (id != null) {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ConversationScreen(
                      peerId: id,
                      peerName: "User $id",
                    ),
                  ),
                );
              }
            },
            child: const Text("Start"),
          ),
        ],
      ),
    );
  }
}
