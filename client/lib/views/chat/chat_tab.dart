import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/chat_controller.dart';
import 'package:last_project_client/views/chat/widgets/conversation_tile.dart';

class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, chatController, child) {
        final peerIds = chatController.activePeers.toList();

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
            
            return ConversationTile(
              peerId: peerId,
              name: chatController.getPeerName(peerId) ?? "User $peerId",
              lastMessage: lastMsg.content,
              timestamp: lastMsg.createdAt,
              isOnline: chatController.isOnline(peerId),
              onTap: () {
                // TODO: Navigate to ConversationScreen
                debugPrint("Tapped conversation with $peerId");
              },
            );
          },
        );
      },
    );
  }
}
