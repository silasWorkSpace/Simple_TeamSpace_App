import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/channel_controller.dart';
import 'package:last_project_client/services/user_service.dart';
import 'package:last_project_client/models/user_model.dart';
import 'package:last_project_client/views/tasks/user_search_dialog.dart';
import 'package:last_project_client/controllers/auth_controller.dart';

class ChannelInfoDialog extends StatefulWidget {
  final int channelId; // This is the positive DB ID (abs(peerId))
  final String channelName;

  const ChannelInfoDialog({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<ChannelInfoDialog> createState() => _ChannelInfoDialogState();
}

class _ChannelInfoDialogState extends State<ChannelInfoDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _members = [];
  StreamSubscription? _streamSub;

  @override
  void initState() {
    super.initState();
    _fetchInfo();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  void _fetchInfo() {
    final controller = context.read<ChannelController>();

    controller.channelService.fetchMembers(widget.channelId);

    // Cancel any previous subscription before creating a new one (prevents leak)
    _streamSub?.cancel();
    _streamSub = controller.channelService.channelStream.listen((packet) {
      if (!mounted) return;
      final type = packet['type'] as String;

      if (type == 'CHANNEL_MEMBERS_RESP') {
        setState(() {
          _members = packet['data']['members'] as List<dynamic>;
          _isLoading = false;
          _errorMessage = null;
        });
      } else if (type == 'CHANNEL_ADD_MEMBER_RESP' ||
                 type == 'CHANNEL_REMOVE_MEMBER_RESP' ||
                 type == 'CHANNEL_KICK_RESP' ||
                 type == 'CHANNEL_ROLE_UPDATE_RESP') {
        // Any membership or role change → re-fetch the full member list
        controller.channelService.fetchMembers(widget.channelId);
      } else if (type == 'CHANNEL_LIST_UPDATED') {
        // Owner or target received a server-push refresh → re-fetch members
        controller.channelService.fetchMembers(widget.channelId);
      } else if (type == 'CHANNEL_RENAME_RESP') {
        final nav = Navigator.of(context);
        nav.pop(true);
      } else if (type == 'SYS_ERROR') {
        setState(() {
          _isLoading = false;
          if (packet['data']['code'] == 403) {
            _errorMessage = "You must join this channel to view its members.";
          } else {
            _errorMessage = packet['data']['message'] ?? "An error occurred.";
          }
        });
      }
    });
  }

  void _addMember() async {
    final userService = context.read<UserService>();
    final result = await showDialog(
      context: context,
      builder: (_) => UserSearchDialog(userService: userService),
    );
    if (result is UserModel && mounted) {
      context.read<ChannelController>().channelService.addMember(widget.channelId, result.id);
    }
  }

  void _renameChannel() {
    final tc = TextEditingController(text: widget.channelName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename Channel"),
        content: TextField(controller: tc),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              if (tc.text.isNotEmpty) {
                context.read<ChannelController>().channelService.renameChannel(widget.channelId, tc.text);
                Navigator.pop(context);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _deleteChannel() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Channel"),
        content: const Text("Are you sure you want to delete this channel? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              context.read<ChannelController>().channelService.deleteChannel(widget.channelId);
              Navigator.pop(context); // Close confirm dialog
              Navigator.pop(context, "deleted"); // Close info dialog
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _kickMember(int userId) {
    context.read<ChannelController>().channelService.removeMember(widget.channelId, userId);
  }

  void _updateRole(int userId, String newRole) {
    final requestId = "chan_role_${DateTime.now().millisecondsSinceEpoch}";
    context.read<ChannelController>().channelService.tcpClient.sendPacket("CHANNEL_ROLE_UPDATE_REQ", {
      "channel_id": widget.channelId,
      "user_id": userId,
      "role": newRole,
    }, id: requestId);
  }

  void _leaveChannel() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Leave Channel"),
        content: const Text("Are you sure you want to leave this channel?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              context.read<ChannelController>().channelService.leaveChannel(widget.channelId);
              Navigator.pop(context); // Close confirm dialog
              Navigator.pop(context, "deleted"); // Close info dialog (triggers screen close)
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Leave"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthController>().currentUser?.id;
    final myMemberState = _members.firstWhere((m) => m['id'] == currentUserId, orElse: () => null);
    final myRole = myMemberState?['role'];
    final isOwner = myRole == 'owner';
    final isAdmin = myRole == 'admin' || isOwner;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(widget.channelName),
          if (isOwner)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: _renameChannel,
                  tooltip: "Rename Channel",
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _deleteChannel,
                  tooltip: "Delete Channel",
                ),
              ],
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Members", style: TextStyle(fontWeight: FontWeight.bold)),
                if (isAdmin)
                  TextButton.icon(
                    onPressed: _addMember,
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text("Add"),
                  ),
              ],
            ),
            const Divider(),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              )
            else if (_members.isEmpty)
              const Text("No members found")
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final m = _members[index];
                    final targetRole = m['role'] ?? 'member';
                    final isTargetOwner = targetRole == 'owner';
                    final canKick = isAdmin && !isTargetOwner && m['id'] != currentUserId;
                    
                    return ListTile(
                      leading: Icon(m['is_online'] == 1 ? Icons.circle : Icons.circle_outlined, 
                        color: m['is_online'] == 1 ? Colors.green : Colors.grey, size: 12),
                      title: Text("${m['display_name']} ($targetRole)"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOwner && !isTargetOwner && m['id'] != currentUserId)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.manage_accounts, size: 20),
                              onSelected: (val) => _updateRole(m['id'], val),
                              itemBuilder: (context) => [
                                if (targetRole == 'member') const PopupMenuItem(value: 'admin', child: Text("Promote to Admin")),
                                if (targetRole == 'admin') const PopupMenuItem(value: 'member', child: Text("Demote to Member")),
                              ],
                            ),
                          if (canKick)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                              onPressed: () => _kickMember(m['id']),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (myMemberState != null && myRole != 'owner')
          TextButton(
            onPressed: _leaveChannel,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Leave Channel"),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
