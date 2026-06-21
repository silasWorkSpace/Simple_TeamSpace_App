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

import 'package:last_project_client/controllers/channel_controller.dart';
import 'package:last_project_client/models/channel_model.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChannelController>().fetchChannels();
    });
  }

  @override
  Widget build(BuildContext context) {

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(kTextTabBarHeight),
          child: TabBar(
            tabs: [
              Tab(text: "Direct Messages"),
              Tab(text: "Channels"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // DIRECT MESSAGES TAB
            Consumer<ChatController>(
              builder: (context, chatController, child) {
                final peerIds = chatController.activePeers.where((id) => id > 0).toList();

                if (peerIds.isEmpty) {
                  return const Center(
                    child: Text("No direct messages yet"),
                  );
                }

                // Sort by last message timestamp (newest first)
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
            
            // CHANNELS TAB
            Consumer<ChannelController>(
              builder: (context, channelController, child) {
                if (channelController.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final joinedChannels = channelController.channels.where((c) => c.isJoined).toList();
                final discoverChannels = channelController.channels.where((c) => !c.isJoined).toList();

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add, color: Colors.blue),
                      title: const Text("Create Channel", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      onTap: () => _showCreateChannelDialog(context),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        children: [
                          if (joinedChannels.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Text("Joined Channels", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            ),
                            ...joinedChannels.map((c) => _buildChannelTile(context, c)),
                          ],
                          if (discoverChannels.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Text("Discover Channels", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            ),
                            ...discoverChannels.map((c) => _buildChannelTile(context, c)),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showNewChatDialog(context),
          child: const Icon(Icons.add_comment),
        ),
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

  void _showCreateChannelDialog(BuildContext context) {
    final nameController = TextEditingController();
    bool isPublic = false;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Create Channel"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Channel Name"),
                  ),
                  CheckboxListTile(
                    title: const Text("Public Channel"),
                    value: isPublic,
                    onChanged: (val) {
                      setState(() {
                        isPublic = val ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      context.read<ChannelController>().createChannel(name, isPublic: isPublic);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildChannelTile(BuildContext context, ChannelModel channel) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blueGrey,
        child: Icon(channel.isPublic ? Icons.tag : Icons.lock, color: Colors.white, size: 20),
      ),
      title: Text(channel.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(channel.isPublic ? "Public Channel" : "Private Channel"),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              peerId: channel.id, // Channel ID is already negative
              peerName: channel.name,
            ),
          ),
        );
      },
    );
  }
}
