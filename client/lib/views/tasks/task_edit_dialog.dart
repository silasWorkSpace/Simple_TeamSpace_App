import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:last_project_client/controllers/task_controller.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/controllers/user_controller.dart';
import 'package:last_project_client/models/comment_model.dart';
import 'package:last_project_client/models/activity_model.dart';
import 'package:last_project_client/models/task_model.dart';
import 'package:last_project_client/models/user_model.dart';
import 'package:last_project_client/services/user_service.dart';
import 'package:last_project_client/views/tasks/user_search_dialog.dart';

class TaskEditDialog extends StatefulWidget {
  final TaskModel task;

  const TaskEditDialog({super.key, required this.task});

  @override
  State<TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<TaskEditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  /// Compose field for the comment thread section.
  final TextEditingController _commentInputController = TextEditingController();

  late String _status;
  int? _selectedAssigneeId;
  String? _selectedAssigneeName;
  bool _clearAssignee = false;

  // ── Phase 6A: due date local state ────────────────────────────────────────
  //
  // _selectedDueAt is stored as *local* time (mirrors TaskModel.dueAt which
  // calls .toLocal() in fromJson). It is converted back to UTC on save.
  DateTime? _selectedDueAt;

  // True when the user explicitly clicked "Clear" — sends null to the server.
  bool _clearDueDate = false;

  final _formKey = GlobalKey<FormState>();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController =
        TextEditingController(text: widget.task.description ?? '');
    _status = widget.task.status;
    _selectedAssigneeId = widget.task.assigneeId;

    // dueAt is already local time from TaskModel.fromJson(.toLocal())
    _selectedDueAt = widget.task.dueAt;

    // Fetch comments once the widget is mounted and in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TaskController>().fetchComments(widget.task.id);
        context.read<TaskController>().fetchActivities(widget.task.id);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _commentInputController.dispose();
    super.dispose();
  }

  // ── Due-date helpers ───────────────────────────────────────────────────────

  // Note: no BuildContext parameter — we use State's own `context` so the
  // `mounted` guard on lines below satisfies use_build_context_synchronously.
  Future<void> _selectDueDate() async {
    final now = DateTime.now();
    final initial = _selectedDueAt ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    // mounted guard: ensures State.context is still valid after the async gap.
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context, // safe: guarded by mounted check above
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedDueAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _clearDueDate = false;
    });
  }

  void _clearDueDateAction() {
    setState(() {
      _selectedDueAt = null;
      _clearDueDate = true;
    });
  }

  /// Color for the due-date label based on urgency.
  Color _dueDateColor() {
    if (_selectedDueAt == null) return Colors.grey.shade600;
    final now = DateTime.now();
    if (_selectedDueAt!.isBefore(now) && widget.task.status != 'DONE') {
      return Colors.red.shade700;
    }
    if (_selectedDueAt!.difference(now).inHours < 24) {
      return Colors.orange.shade700;
    }
    return Colors.black87;
  }

  // ── Save / delete ──────────────────────────────────────────────────────────

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
        assigneeId: _clearAssignee ? null : _selectedAssigneeId,
        clearAssignee: _clearAssignee,
        // Convert local DateTime → UTC ISO-8601 ending in 'Z' (server contract).
        dueAt: _clearDueDate
            ? null
            : _selectedDueAt?.toUtc().toIso8601String(),
        clearDueDate: _clearDueDate,
      );
    } else {
      // Assignees can only move the status column.
      controller.updateTaskStatus(widget.task.id, _status);
    }
  }

  void _showUserSearch(BuildContext context) async {
    final userService = Provider.of<UserService>(context, listen: false);
    final userController =
        Provider.of<UserController>(context, listen: false);

    final result = await showDialog(
      context: context,
      builder: (context) => UserSearchDialog(userService: userService),
    );

    if (result == 'clear') {
      setState(() {
        _selectedAssigneeId = null;
        _selectedAssigneeName = null;
        _clearAssignee = true;
      });
    } else if (result is UserModel) {
      userController.updateCache(result);
      setState(() {
        _selectedAssigneeId = result.id;
        _selectedAssigneeName = result.displayName;
        _clearAssignee = false;
      });
    }
  }

  void _confirmDelete(BuildContext context, TaskController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text(
            'Are you sure you want to delete this task? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // close confirmation
              controller.deleteTask(widget.task.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Comment helpers ────────────────────────────────────────────────────────

  void _sendComment(TaskController controller) {
    final content = _commentInputController.text.trim();
    if (content.isEmpty) return;
    controller.sendComment(widget.task.id, content);
    _commentInputController.clear();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskController>(
      builder: (context, controller, child) {
        // ── Auto-close guards ──────────────────────────────────────────────
        final taskExists =
            controller.tasks.any((t) => t.id == widget.task.id);
        final currentTask = taskExists
            ? controller.tasks.firstWhere((t) => t.id == widget.task.id)
            : null;

        // Task was deleted remotely or locally.
        if (!taskExists &&
            !controller.isLoading &&
            controller.errorMessage == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }

        // Task was successfully saved — updatedAt advanced by the server.
        // Comment events do NOT change updatedAt, so this won't fire on comments.
        if (currentTask != null &&
            currentTask.updatedAt.isAfter(widget.task.updatedAt) &&
            !controller.isLoading &&
            controller.errorMessage == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }

        // ── Role checks ────────────────────────────────────────────────────
        final authController =
            Provider.of<AuthController>(context, listen: false);
        final currentUserId = authController.currentUser?.id;
        final isCreator = widget.task.creatorId == currentUserId;
        final isAssignee = widget.task.assigneeId == currentUserId;
        final canEditFull = isCreator;
        final canChangeStatus = isCreator || isAssignee;

        final comments = controller.commentsFor(widget.task.id);
        final activities = controller.activitiesFor(widget.task.id);

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Task Details'),
              if (isCreator)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete task',
                  onPressed: controller.isLoading
                      ? null
                      : () => _confirmDelete(context, controller),
                ),
            ],
          ),
          // SizedBox forces the dialog to expand to the full available width so
          // the comment list renders correctly.
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Error banner ─────────────────────────────────────────
                    if (controller.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          controller.errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),

                    // ── Title ────────────────────────────────────────────────
                    if (canEditFull)
                      TextFormField(
                        controller: _titleController,
                        decoration:
                            const InputDecoration(labelText: 'Title'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Title is required'
                                : null,
                        enabled: !controller.isLoading,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          widget.task.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Description ──────────────────────────────────────────
                    if (canEditFull)
                      TextFormField(
                        controller: _descriptionController,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 3,
                        enabled: !controller.isLoading,
                      )
                    else if (widget.task.description != null &&
                        widget.task.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          widget.task.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Status ───────────────────────────────────────────────
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration:
                          const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                            value: 'TODO', child: Text('TODO')),
                        DropdownMenuItem(
                            value: 'DOING', child: Text('DOING')),
                        DropdownMenuItem(
                            value: 'DONE', child: Text('DONE')),
                      ],
                      onChanged: (canChangeStatus && !controller.isLoading)
                          ? (val) => setState(() => _status = val!)
                          : null,
                    ),

                    const SizedBox(height: 16),

                    // ── Creator info ─────────────────────────────────────────
                    Consumer<UserController>(
                      builder: (context, userControl, _) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Created By',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        subtitle: Text(
                            userControl.getName(widget.task.creatorId)),
                      ),
                    ),

                    // ── Assignee ─────────────────────────────────────────────
                    Consumer<UserController>(
                      builder: (context, userControl, _) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Assignee',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        subtitle: Text(
                          _clearAssignee
                              ? 'Unassigned'
                              : (_selectedAssigneeName ??
                                  userControl.getName(
                                      _selectedAssigneeId ?? -1)),
                          style: const TextStyle(
                              fontSize: 16, color: Colors.black87),
                        ),
                        trailing: isCreator
                            ? const Icon(Icons.edit, size: 20)
                            : null,
                        onTap: (isCreator && !controller.isLoading)
                            ? () => _showUserSearch(context)
                            : null,
                      ),
                    ),

                    // ── Phase 6A: Due Date (creator only) ────────────────────
                    if (canEditFull) ...[
                      const Divider(height: 24),
                      _buildDueDateSection(context, controller),
                    ],

                    // ── Phase 6A: Comments ───────────────────────────────────
                    const Divider(height: 24),
                    _buildCommentSection(context, controller, comments),

                    // ── Phase 6B: Activity ───────────────────────────────────
                    const Divider(height: 24),
                    _buildActivitySection(context, controller, activities),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  controller.isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (canChangeStatus)
              ElevatedButton(
                onPressed: controller.isLoading
                    ? null
                    : () => _onSave(context, controller),
                child: controller.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
          ],
        );
      },
    );
  }

  // ── Due-date section widget ────────────────────────────────────────────────

  Widget _buildDueDateSection(
      BuildContext context, TaskController controller) {
    final dateFormat = DateFormat('MMM dd, yyyy  HH:mm');
    final hasDueDate = _selectedDueAt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Due Date',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: _dueDateColor(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hasDueDate
                    ? dateFormat.format(_selectedDueAt!)
                    : 'No due date set',
                style: TextStyle(
                  fontSize: 14,
                  color: _dueDateColor(),
                ),
              ),
            ),
            // "Clear" button — only visible when a date is already set
            if (hasDueDate)
              TextButton.icon(
                onPressed:
                    controller.isLoading ? null : _clearDueDateAction,
                icon: const Icon(Icons.cancel_outlined, size: 15),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            // Calendar picker trigger
            IconButton(
              icon: Icon(Icons.edit_calendar,
                  size: 20, color: Colors.blue.shade600),
              tooltip: 'Set due date',
              onPressed: controller.isLoading
                  ? null
                  : _selectDueDate,
            ),
          ],
        ),
      ],
    );
  }

  // ── Comment thread widget ──────────────────────────────────────────────────

  Widget _buildCommentSection(
    BuildContext context,
    TaskController controller,
    List<CommentModel> comments,
  ) {
    return Consumer<UserController>(
      builder: (context, userControl, _) {
        final timeFormat = DateFormat('MMM dd, HH:mm');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.comment_outlined,
                    size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Comments (${comments.length})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── List ─────────────────────────────────────────────────────────
            if (comments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No comments yet. Be the first!',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final c = comments[index];
                    return _CommentTile(
                      authorName: userControl.getName(c.userId),
                      content: c.content,
                      timestamp:
                          timeFormat.format(c.createdAt.toLocal()),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),

            // ── Compose row ───────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentInputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Add a comment…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(Icons.send_rounded,
                      color: Colors.blue.shade600),
                  tooltip: 'Send comment',
                  onPressed: () => _sendComment(controller),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── Activity log widget ────────────────────────────────────────────────────

  Widget _buildActivitySection(
    BuildContext context,
    TaskController controller,
    List<ActivityModel> activities,
  ) {
    return Consumer<UserController>(
      builder: (context, userControl, _) {
        final timeFormat = DateFormat('MMM dd, HH:mm');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.history, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Activity (${activities.length})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // List
            if (activities.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No activity yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: activities.length,
                  itemBuilder: (context, index) {
                    final a = activities[index];
                    final description = a.buildDescription(userControl.getName);
                    final userName = a.userId != null
                        ? userControl.getName(a.userId!)
                        : 'System';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.circle, size: 6, color: Colors.grey.shade400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                                children: [
                                  TextSpan(
                                    text: '$userName ',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(text: '$description '),
                                  TextSpan(
                                    text: timeFormat.format(a.createdAt),
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Private comment tile ───────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final String authorName;
  final String content;
  final String timestamp;

  const _CommentTile({
    required this.authorName,
    required this.content,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.blue.shade50,
            child: Text(
              authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author + timestamp on one line
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timestamp,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Comment content
                Text(content, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
