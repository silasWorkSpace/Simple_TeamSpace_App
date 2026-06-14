import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:last_project_client/models/task_model.dart';
import 'package:last_project_client/services/task_service.dart';

class TaskController extends ChangeNotifier {
  final TaskService _taskService;
  int? _currentUserId;

  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _taskSubscription;

  TaskController({
    required TaskService taskService,
  }) : _taskService = taskService {
    _init();
  }

  // Getters
  List<TaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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

  /// Updates a task's status.
  void updateTaskStatus(int taskId, String newStatus) {
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
    _errorMessage = data['message'] as String? ?? "An error occurred";
    debugPrint("[TASK] Error: $_errorMessage");
    notifyListeners();
  }

  void clear() {
    _tasks.clear();
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    super.dispose();
  }
}
