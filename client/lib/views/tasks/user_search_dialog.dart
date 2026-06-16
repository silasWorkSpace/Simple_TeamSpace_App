import 'dart:async';
import 'package:flutter/material.dart';
import 'package:last_project_client/models/user_model.dart';
import 'package:last_project_client/services/user_service.dart';

class UserSearchDialog extends StatefulWidget {
  final UserService userService;

  const UserSearchDialog({super.key, required this.userService});

  @override
  State<UserSearchDialog> createState() => _UserSearchDialogState();
}

class _UserSearchDialogState extends State<UserSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _results = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  Timer? _debounceTimer;
  StreamSubscription? _userSubscription;
  String? _latestRequestId;

  @override
  void initState() {
    super.initState();
    _userSubscription = widget.userService.userStream.listen(_onPacketReceived);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _userSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _isLoading = false;
        _errorMessage = null;
        _latestRequestId = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      _latestRequestId = widget.userService.searchUsers(query.trim());
    });
  }

  void _onPacketReceived(Map<String, dynamic> packet) {
    final packetId = packet['id']?.toString();
    
    // Strict request correlation: Handles both USER_SEARCH_RESP and SYS_ERROR
    if (packetId == null || packetId != _latestRequestId) {
      return;
    }

    final type = packet['type'] as String;
    final data = packet['data'] as Map<String, dynamic>? ?? {};

    if (type == 'USER_SEARCH_RESP' && mounted) {
      final List<dynamic> usersRaw = data['users'] ?? [];
      setState(() {
        _results = usersRaw.map((u) => UserModel.fromJson(u as Map<String, dynamic>)).toList();
        _isLoading = false;
        _errorMessage = null;
      });
    } else if (type == 'SYS_ERROR' && mounted) {
      setState(() {
        _errorMessage = data['message'] ?? "Search failed";
        _isLoading = false;
        _results = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Assign To"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: "Search by name or phone...",
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
              autofocus: true,
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  _errorMessage!, 
                  style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)
                ),
              ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final user = _results[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(user.displayName),
                    onTap: () => Navigator.pop(context, user),
                  );
                },
              ),
            ),
            if (!_isLoading && _results.isEmpty && _searchController.text.trim().length >= 2 && _errorMessage == null)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("No users found.", style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, "clear"),
          child: const Text("Unassign", style: TextStyle(color: Colors.orange)),
        ),
      ],
    );
  }
}
