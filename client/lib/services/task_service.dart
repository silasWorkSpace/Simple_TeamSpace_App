import 'dart:async';
import 'package:last_project_client/network/tcp_client.dart';

class TaskService {
  final TcpClient tcpClient;

  TaskService({required this.tcpClient});

  /// Requests all tasks associated with the current user.
  String fetchTasks() {

    final requestId = "task_list_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "TASK_LIST_REQ",
      {},
      id: requestId,
    );
    return requestId;
  }

  /// Creates a new task.
  ///
  /// [dueAt] must be an ISO-8601 UTC string ending in 'Z'
  /// (e.g. "2026-06-30T18:00:00Z"), matching the server's
  /// _validate_due_at() contract in task_service.py.
  /// Pass null or omit to create a task with no due date.
  String createTask({
    required String title,
    String? description,
    int? assigneeId,
    String? dueAt,
  }) {

    final requestId = "task_create_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "TASK_CREATE_REQ",
      {
        "title": title,
        if (description != null) "description": description,
        if (assigneeId != null) "assignee_id": assigneeId,
        if (dueAt != null) "due_at": dueAt,
      },
      id: requestId,
    );
    return requestId;
  }

  /// Updates an existing task.
  /// [updates] can contain: title, description, status, assignee_id.
  String updateTask({
    required int taskId,
    required Map<String, dynamic> updates,
  }) {

    final requestId = "task_update_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "TASK_UPDATE_REQ",
      {
        "task_id": taskId,
        "updates": updates,
      },
      id: requestId,
    );
    return requestId;
  }

  /// Deletes a task by ID.
  String deleteTask(int taskId) {

    final requestId = "task_delete_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "TASK_DELETE_REQ",
      {"task_id": taskId},
      id: requestId,
    );
    return requestId;
  }

  /// Stream of all task-related packets.
  Stream<Map<String, dynamic>> get taskStream => tcpClient.packetStream.where((packet) {
    final type = packet['type'] as String;
    final id = packet['id']?.toString() ?? '';
    
    // 1. Forward all explicit task packets
    if (type.startsWith('TASK_')) return true;
    
    // 2. Forward SYS_ERROR only if they correlate to a task request
    if (type == 'SYS_ERROR' && id.startsWith('task_')) {
      return true;
    }
    
    return false;
  });
}
