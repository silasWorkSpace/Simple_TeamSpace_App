import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/task_controller.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/models/task_model.dart';

class TaskEditDialog extends StatefulWidget {
  final TaskModel task;

  const TaskEditDialog({super.key, required this.task});

  @override
  State<TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<TaskEditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late String _status;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(text: widget.task.description ?? "");
    _status = widget.task.status;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onSave(BuildContext context, TaskController controller) {
    if (!_formKey.currentState!.validate()) return;

    final authController = Provider.of<AuthController>(context, listen: false);
    final currentUserId = authController.currentUser?.id;
    final isCreator = widget.task.creatorId == currentUserId;

    if (isCreator) {
      controller.updateTaskDetails(
        widget.task.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
      );
    } else {
      controller.updateTaskStatus(widget.task.id, _status);
    }
  }

  void _confirmDelete(BuildContext context, TaskController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Task?"),
        content: const Text("Are you sure you want to delete this task? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close confirmation
              controller.deleteTask(widget.task.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskController>(
      builder: (context, controller, child) {
        // Close dialog on success
        // Logic: if we were loading and now we aren't, and there's no error,
        // it means the operation (Update or Delete) succeeded.
        // But we need to be careful not to close it if it was just a background fetch.
        // A better way is to check if the task still exists (for update) or is gone (for delete).
        
        final taskExists = controller.tasks.any((t) => t.id == widget.task.id);
        final currentTask = taskExists 
            ? controller.tasks.firstWhere((t) => t.id == widget.task.id)
            : null;

        // If task is deleted, close dialog
        if (!taskExists && !controller.isLoading && controller.errorMessage == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
        
        // If task is updated (updatedAt changed) and no longer loading/error, close dialog
        if (currentTask != null && 
            currentTask.updatedAt.isAfter(widget.task.updatedAt) && 
            !controller.isLoading && 
            controller.errorMessage == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }

        final authController = Provider.of<AuthController>(context, listen: false);
        final currentUserId = authController.currentUser?.id;
        final isCreator = widget.task.creatorId == currentUserId;
        final isAssignee = widget.task.assigneeId == currentUserId;
        final canEditFull = isCreator;
        final canChangeStatus = isCreator || isAssignee;

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Task Details"),
              if (isCreator)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: controller.isLoading ? null : () => _confirmDelete(context, controller),
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        controller.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  
                  if (canEditFull)
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: "Title"),
                      validator: (value) => (value == null || value.trim().isEmpty) ? "Title is required" : null,
                      enabled: !controller.isLoading,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        widget.task.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  if (canEditFull)
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(labelText: "Description"),
                      maxLines: 3,
                      enabled: !controller.isLoading,
                    )
                  else if (widget.task.description != null && widget.task.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        widget.task.description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: "Status"),
                    items: const [
                      DropdownMenuItem(value: "TODO", child: Text("TODO")),
                      DropdownMenuItem(value: "DOING", child: Text("DOING")),
                      DropdownMenuItem(value: "DONE", child: Text("DONE")),
                    ],
                    onChanged: (canChangeStatus && !controller.isLoading) 
                        ? (val) => setState(() => _status = val!) 
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: controller.isLoading ? null : () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            if (canChangeStatus)
              ElevatedButton(
                onPressed: controller.isLoading ? null : () => _onSave(context, controller),
                child: controller.isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Save"),
              ),
          ],
        );
      },
    );
  }
}
