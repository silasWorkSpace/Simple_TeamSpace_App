import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:last_project_client/models/comment_model.dart';
import 'package:last_project_client/models/task_model.dart';
import 'package:last_project_client/services/comment_service.dart';
import 'package:last_project_client/services/task_service.dart';
import 'package:last_project_client/controllers/user_controller.dart';

class TaskController extends ChangeNotifier {
  final TaskService _taskService;
  final CommentService _commentService;
  final UserController _userController;
  int? _currentUserId;

  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Track exactly one in-flight moving task (Phase 5A limitation: no packet correlation)
  int? _movingTaskId;
  Timer? _movingTimeout;

  // Phase 6A: Comment state.
  // Key: taskId → chronological list of CommentModel.
  // Populated lazily on first fetchComments() call for each task.
  final Map<int, List<CommentModel>> _taskComments = {};

  StreamSubscription? _taskSubscription;
  StreamSubscription? _commentSubscription;

  TaskController({
    required TaskService taskService,
    required CommentService commentService,
    required UserController userController,
  }) : _taskService = taskService,
       _commentService = commentService,
       _userController = userController {
    _init();
  }

  // --- Getters ---

  List<TaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get movingTaskId => _movingTaskId;

  List<TaskModel> get todoTasks => _tasks.where((t) => t.status == 'TODO').toList();
  List<TaskModel> get doingTasks => _tasks.where((t) => t.status == 'DOING').toList();
  List<TaskModel> get doneTasks => _tasks.where((t) => t.status == 'DONE').toList();

  /// Returns the cached comment list for [taskId].
  /// Returns an empty const list if comments have not yet been fetched.
  List<CommentModel> commentsFor(int taskId) =>
      _taskComments[taskId] ?? const [];

  void _init() {
    _taskSubscription = _taskService.taskStream.listen(_onPacketReceived);
    _commentSubscription = _commentService.commentStream.listen(_onCommentPacket);
  }

  /// Updates the current user context. Clears state on logout or user change.
  void updateCurrentUser(int? userId) {
    debugPrint("[TASK] updateCurrentUser called with userId=$userId");
    if (_currentUserId == userId && _tasks.isNotEmpty) {
      debugPrint("[TASK] userId is identical and tasks already loaded, skipping fetch.");
      return;
    }

    debugPrint("[TASK] User context changed: $_currentUserId -> $userId");
    _currentUserId = userId;
    
    // Always clear state when the user session changes or ends
    clear();

    if (userId != null) {
      debugPrint("[TASK] fetching tasks for new user context");
      fetchTasks();
    }
  }

  /// Fetches all tasks from the server.
  void fetchTasks() {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _taskService.fetchTasks();
  }

  /// Creates a new task.
  void createTask(String title, {String? description, int? assigneeId}) {
    _taskService.createTask(
      title: title,
      description: description,
      assigneeId: assigneeId,
    );
  }

  // ---------------------------------------------------------------------------
  // Phase 6A – Comment API
  // ---------------------------------------------------------------------------

  /// Requests the full comment list for [taskId] from the server.
  /// The result is delivered asynchronously via [_handleCommentListResponse].
  void fetchComments(int taskId) {
    debugPrint('[COMMENT] fetchComments called for task $taskId');
    _commentService.fetchComments(taskId);
  }

  /// Sends a new comment on [taskId].
  /// Trims whitespace and silently ignores empty content.
  /// The persisted comment is delivered back via [_handleCommentReceived].
  void sendComment(int taskId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    debugPrint('[COMMENT] sendComment called for task $taskId');
    _commentService.sendComment(taskId: taskId, content: trimmed);
  }

  /// Updates a task's status with in-flight tracking for Drag & Drop.
  /// Phase 5A: Only one status update can be in-flight at a time.
  void updateTaskStatus(int taskId, String newStatus) {
    if (_movingTaskId != null) {
      debugPrint("[TASK] Rejected updateTaskStatus for $taskId: Task $_movingTaskId is already moving.");
      return;
    }

    _movingTaskId = taskId;
    _errorMessage = null;
    
    // Start timeout recovery timer
    _movingTimeout?.cancel();
    _movingTimeout = Timer(const Duration(seconds: 10), () {
      if (_movingTaskId == taskId) {
        debugPrint("[TASK] Timeout reached for moving task $taskId. Clearing state.");
        _movingTaskId = null;
        _errorMessage = "Update timed out. Please check your connection.";
        notifyListeners();
      }
    });

    notifyListeners();

    _taskService.updateTask(
      taskId: taskId,
      updates: {"status": newStatus},
    );
  }

  /// Updates task details (Creator only).
  /// Supports title, description, status, assignee_id, and due_at.
  ///
  /// Pass [clearDueDate]=true to explicitly remove the due date (sends null
  /// to the server). Pass [dueAt] as an ISO-8601 UTC string (ending in 'Z')
  /// to set a new due date. Omit both to leave the due date unchanged.
  void updateTaskDetails(int taskId, {
    String? title,
    String? description,
    String? status,
    int? assigneeId,
    bool clearAssignee = false,
    String? dueAt,
    bool clearDueDate = false,
  }) {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (status != null) updates['status'] = status;

    if (clearAssignee) {
      updates['assignee_id'] = null;
    } else if (assigneeId != null) {
      updates['assignee_id'] = assigneeId;
    }

    // Phase 6A: due date. clearDueDate sends explicit null to erase.
    if (clearDueDate) {
      updates['due_at'] = null;
    } else if (dueAt != null) {
      updates['due_at'] = dueAt;
    }

    if (updates.isNotEmpty) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      _taskService.updateTask(taskId: taskId, updates: updates);
    }
  }


  /// Deletes a task.
  void deleteTask(int taskId) {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    _taskService.deleteTask(taskId);
  }

  void _onPacketReceived(Map<String, dynamic> packet) {
    final type = packet['type'] as String;
    debugPrint("[TASK] _onPacketReceived type=$type");
    final data = packet['data'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'TASK_LIST_RESP':
        _handleTaskListResponse(data);
        break;
      case 'TASK_CREATE_RESP':
      case 'TASK_CREATED_EVENT':
        _handleTaskCreateResponse(data);
        break;
      case 'TASK_UPDATE_RESP':
      case 'TASK_UPDATED_EVENT':
        _handleTaskUpdateResponse(data);
        break;
      case 'TASK_DELETE_RESP':
      case 'TASK_DELETED_EVENT':
        _handleTaskDeleteResponse(data);
        break;
      case 'SYS_ERROR':
        _handleError(data);
        break;
    }
  }

  void _handleTaskListResponse(Map<String, dynamic> data) {
    final rawTasks = data['tasks'] as List<dynamic>? ?? [];
    _tasks = rawTasks.map((t) => TaskModel.fromJson(t as Map<String, dynamic>)).toList();
    _sortTasks();
    _isLoading = false;
    debugPrint("[TASK] Loaded ${_tasks.length} tasks");

    // Batch resolve user names immediately after receiving the task list
    final Set<int> userIdsToResolve = {};
    for (var task in _tasks) {
      userIdsToResolve.add(task.creatorId);
      if (task.assigneeId != null) {
        userIdsToResolve.add(task.assigneeId!);
      }
    }
    _userController.resolveUsers(userIdsToResolve.toList());

    notifyListeners();
  }

  void _handleTaskCreateResponse(Map<String, dynamic> data) {
    final task = TaskModel.fromJson(data['task'] as Map<String, dynamic>);
    
    // Idempotency guard: Prevent duplicate insertion from EVENT + RESP
    if (_tasks.any((t) => t.id == task.id)) {
      debugPrint("[TASK] Skipping creation of existing task: ${task.id}");
      return;
    }

    _tasks.add(task);
    _sortTasks();
    debugPrint("[TASK] Task created: ${task.id}");
    
    // Resolve user names if they aren't already known
    _userController.resolveUsers([
      task.creatorId,
      if (task.assigneeId != null) task.assigneeId!
    ]);

    notifyListeners();
  }

  void _handleTaskUpdateResponse(Map<String, dynamic> data) {
    final updatedTask = TaskModel.fromJson(data['task'] as Map<String, dynamic>);
    
    // Clear moving state and cancel timeout if this was the moving task
    if (_movingTaskId == updatedTask.id) {
      _movingTaskId = null;
      _movingTimeout?.cancel();
      _movingTimeout = null;
    }
    _isLoading = false;

    final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _sortTasks();
      debugPrint("[TASK] Task updated and re-sorted: ${updatedTask.id}");
      notifyListeners();
    }
  }

  void _handleTaskDeleteResponse(Map<String, dynamic> data) {
    final taskId = data['task_id'] as int;
    _tasks.removeWhere((t) => t.id == taskId);
    debugPrint("[TASK] Task deleted: $taskId");
    notifyListeners();
  }

  void _sortTasks() {
    _tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _handleError(Map<String, dynamic> data) {
    _isLoading = false;
    _movingTaskId = null; // Clear moving state on error
    _movingTimeout?.cancel();
    _movingTimeout = null;
    _errorMessage = data['message'] as String? ?? "An error occurred";
    debugPrint("[TASK] Error: $_errorMessage");
    notifyListeners();
  }

  void clear() {
    _tasks.clear();
    _taskComments.clear(); // Evict all cached comments on session change/logout
    _isLoading = false;
    _errorMessage = null;
    _movingTaskId = null;
    _movingTimeout?.cancel();
    _movingTimeout = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Phase 6A – Comment packet handlers
  // ---------------------------------------------------------------------------

  void _onCommentPacket(Map<String, dynamic> packet) {
    final type = packet['type'] as String;
    debugPrint('[COMMENT] _onCommentPacket type=$type');
    final data = packet['data'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'COMMENT_LIST_RESP':
        _handleCommentListResponse(data);
        break;
      // Both RESP and EVENT carry { "comment": {...} } and are handled identically.
      // The idempotency guard in _handleCommentReceived prevents duplicates.
      case 'COMMENT_SEND_RESP':
      case 'COMMENT_CREATED_EVENT':
        _handleCommentReceived(data);
        break;
      case 'SYS_ERROR':
        _handleError(data);
        break;
    }
  }

  /// Replaces the cached list for the given task with the authoritative server list.
  void _handleCommentListResponse(Map<String, dynamic> data) {
    final taskId = data['task_id'] as int;
    final rawComments = data['comments'] as List<dynamic>? ?? [];
    _taskComments[taskId] = rawComments
        .map((c) => CommentModel.fromJson(c as Map<String, dynamic>))
        .toList();
    debugPrint(
        '[COMMENT] Loaded ${_taskComments[taskId]!.length} comments for task $taskId');
    // Resolve display names for all comment authors in one batch
    final authorIds = _taskComments[taskId]!.map((c) => c.userId).toSet().toList();
    _userController.resolveUsers(authorIds);
    notifyListeners();
  }

  /// Appends a single new comment to the in-memory list.
  ///
  /// Handles both COMMENT_SEND_RESP (from the originating device) and
  /// COMMENT_CREATED_EVENT (pushed to all other visible participants).
  ///
  /// Idempotency guarantee (Phase 5B contract): if a comment with the same
  /// server-assigned [id] already exists in the list — e.g. because the RESP
  /// and the EVENT both arrive before the list is re-fetched — it is silently
  /// dropped to prevent duplicates.
  void _handleCommentReceived(Map<String, dynamic> data) {
    final commentJson = data['comment'] as Map<String, dynamic>?;
    if (commentJson == null) {
      debugPrint('[COMMENT] _handleCommentReceived: missing comment payload');
      return;
    }

    final comment = CommentModel.fromJson(commentJson);
    final list = _taskComments.putIfAbsent(comment.taskId, () => []);

    // Idempotency guard: reject duplicates from concurrent RESP + EVENT delivery
    if (list.any((c) => c.id == comment.id)) {
      debugPrint('[COMMENT] Duplicate comment ${comment.id} dropped');
      return;
    }

    list.add(comment);
    // Resolve the author's display name if not yet cached
    _userController.resolveUsers([comment.userId]);
    debugPrint('[COMMENT] Comment ${comment.id} added to task ${comment.taskId}');
    notifyListeners();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _commentSubscription?.cancel();
    _movingTimeout?.cancel();
    super.dispose();
  }
}
