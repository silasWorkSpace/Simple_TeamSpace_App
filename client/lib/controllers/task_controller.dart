import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:last_project_client/models/task_model.dart';
import 'package:last_project_client/services/task_service.dart';
import 'package:last_project_client/controllers/user_controller.dart';

class TaskController extends ChangeNotifier {
  final TaskService _taskService;
  final UserController _userController;
  int? _currentUserId;

  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Track exactly one in-flight moving task (Phase 5A limitation: no packet correlation)
  int? _movingTaskId;
  Timer? _movingTimeout;

  StreamSubscription? _taskSubscription;

  TaskController({
    required TaskService taskService,
    required UserController userController,
  }) : _taskService = taskService,
       _userController = userController {
    _init();
  }

  // Getters
  List<TaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get movingTaskId => _movingTaskId;

  List<TaskModel> get todoTasks => _tasks.where((t) => t.status == 'TODO').toList();
  List<TaskModel> get doingTasks => _tasks.where((t) => t.status == 'DOING').toList();
  List<TaskModel> get doneTasks => _tasks.where((t) => t.status == 'DONE').toList();

  void _init() {
    _taskSubscription = _taskService.taskStream.listen(_onPacketReceived);
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
  /// Supports title, description, status, and assignee_id.
  void updateTaskDetails(int taskId, {
    String? title, 
    String? description, 
    String? status,
    int? assigneeId,
    bool clearAssignee = false,
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
        _handleTaskCreateResponse(data);
        break;
      case 'TASK_UPDATE_RESP':
        _handleTaskUpdateResponse(data);
        break;
      case 'TASK_DELETE_RESP':
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
    _tasks.add(task);
    _sortTasks();
    debugPrint("[TASK] Task created: ${task.id}");
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
    _isLoading = false;
    _errorMessage = null;
    _movingTaskId = null;
    _movingTimeout?.cancel();
    _movingTimeout = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _movingTimeout?.cancel();
    super.dispose();
  }
}
