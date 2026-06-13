import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/views/chat/chat_tab.dart';
import 'package:last_project_client/views/tasks/kanban_tab.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/controllers/task_controller.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  static final List<Widget> _tabs = [
    const ChatTab(),
    const KanbanTab(),
    const Center(child: Text("Storage - Future Milestone")),
    const Center(child: Text("Voice Calls - Future Milestone")),
  ];

  static const List<String> _titles = [
    "Messages",
    "Kanban",
    "Storage",
    "Voice Calls",
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
        actions: [
          IconButton(
            onPressed: () => context.read<AuthController>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      floatingActionButton: _selectedIndex == 1
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
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: "Chat",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: "Tasks",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_open_outlined),
            activeIcon: Icon(Icons.folder),
            label: "Files",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.call_outlined),
            activeIcon: Icon(Icons.call),
            label: "Calls",
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
