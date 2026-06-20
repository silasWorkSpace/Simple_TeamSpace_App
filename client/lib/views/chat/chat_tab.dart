import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/chat_controller.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/services/user_service.dart';
import 'package:last_project_client/models/user_model.dart';
import 'package:last_project_client/views/chat/widgets/conversation_tile.dart';
import 'package:last_project_client/views/chat/conversation_screen.dart';
import 'package:last_project_client/views/tasks/user_search_dialog.dart';
import 'package:last_project_client/core/app_constants.dart';

class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Column(
        children: [
          _buildChannelTile(context, AppConstants.channelGeneral, "#General"),
          _buildChannelTile(context, AppConstants.channelBackend, "#Backend"),
          _buildChannelTile(context, AppConstants.channelFrontend, "#Frontend"),
          const Divider(height: 1),
          Expanded(
            child: Consumer<ChatController>(
              builder: (context, chatController, child) {
                final peerIds = chatController.activePeers.toList();


                if (peerIds.isEmpty) {
                  return const Center(
                    child: Text("No direct messages yet"),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(context),
        child: const Icon(Icons.add_comment),
      ),
    );
  }

  Future<void> _showNewChatDialog(BuildContext context) async {
    final userService = Provider.of<UserService>(context, listen: false);
    final authController = Provider.of<AuthController>(context, listen: false);
    final currentUserId = authController.currentUser?.id;

    final result = await showDialog(
      context: context,
      builder: (context) => UserSearchDialog(userService: userService),
    );

    // Explicitly ignore 'clear' or null results.
    if (result is UserModel) {
      if (!context.mounted) return;

      // 1. Prevent self-chat
      if (result.id == currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot start a chat with yourself.')),
        );
        return;
      }

      // 2. Open conversation
      // Since ConversationScreen relies entirely on fetching history by peerId,
      // there is no "Create Chat" API required. Pushing the screen naturally
      // resumes any existing conversation without creating duplicates.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ConversationScreen(
            peerId: result.id,
            peerName: result.displayName,
          ),
        ),
      );
    }
  }

  Widget _buildChannelTile(BuildContext context, int channelId, String name) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.blueGrey,
        child: Icon(Icons.tag, color: Colors.white),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: const Text("Public Channel"),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              peerId: channelId,
              peerName: name,
            ),
          ),
        );
      },
    );
  }
}
