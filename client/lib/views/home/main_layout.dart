import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/views/chat/chat_tab.dart';
import 'package:last_project_client/views/tasks/kanban_tab.dart';
import 'package:last_project_client/views/home/profile_tab.dart';
import 'package:last_project_client/controllers/task_controller.dart';
import 'package:last_project_client/network/tcp_client.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  late final TcpClient _tcpClient;
  bool _wasDisconnected = false;

  @override
  void initState() {
    super.initState();
    _tcpClient = context.read<TcpClient>();
    _tcpClient.connectionState.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    _tcpClient.connectionState.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    final state = _tcpClient.connectionState.value;
    if (state == TcpConnectionState.disconnected) {
      _wasDisconnected = true;
    } else if (state == TcpConnectionState.connected && _wasDisconnected) {
      _wasDisconnected = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connected"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  static final List<Widget> _tabs = [
    const KanbanTab(),
    const ChatTab(),
    const ProfileTab(),
  ];

  static const List<String> _titles = [
    "Tasks",
    "Messages",
    "Profile",
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showCreateTaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CreateTaskDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
      ),
      body: Column(
        children: [
          ValueListenableBuilder<TcpConnectionState>(
            valueListenable: context.read<TcpClient>().connectionState,
            builder: (context, state, child) {
              if (state == TcpConnectionState.disconnected) {
                return Container(
                  width: double.infinity,
                  color: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: const Text(
                    'Connection lost. Some actions may be unavailable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _tabs,
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () => _showCreateTaskDialog(context),
              child: const Icon(Icons.add_task),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: "Tasks",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: "Chat",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog();

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create New Task"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: "Title"),
            autofocus: true,
          ),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(labelText: "Description (Optional)"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isNotEmpty) {
              final desc = _descController.text.trim();
              context.read<TaskController>().createTask(
                    title,
                    description: desc.isEmpty ? null : desc,
                  );
              Navigator.pop(context);
            }
          },
          child: const Text("Create"),
        ),
      ],
    );
  }
}
