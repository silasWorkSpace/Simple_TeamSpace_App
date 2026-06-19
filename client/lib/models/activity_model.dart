import 'package:intl/intl.dart';

class ActivityModel {
  final int id;
  final int taskId;
  final int? userId; // System actions might have null user
  final String actionType;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  const ActivityModel({
    required this.id,
    required this.taskId,
    this.userId,
    required this.actionType,
    required this.details,
    required this.createdAt,
  });

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      id: json['id'] as int,
      taskId: json['task_id'] as int,
      userId: json['user_id'] as int?,
      actionType: json['action_type'] as String,
      details: json['details'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  /// Builds a human-readable description for the UI.
  /// Takes a resolver function to convert user IDs into display names.
  String buildDescription(String Function(int) userNameResolver) {
    switch (actionType) {
      case 'TASK_CREATED':
        return 'created the task';
        
      case 'STATUS_CHANGED':
        final from = details['from'] ?? 'None';
        final to = details['to'] ?? 'None';
        return 'changed status from $from to $to';
        
      case 'ASSIGNEE_CHANGED':
        final fromId = details['from'] as int?;
        final toId = details['to'] as int?;
        final fromName = fromId != null ? userNameResolver(fromId) : 'Unassigned';
        final toName = toId != null ? userNameResolver(toId) : 'Unassigned';
        return 'changed assignee from $fromName to $toName';
        
      case 'DUE_DATE_CHANGED':
        final fromStr = details['from'] as String?;
        final toStr = details['to'] as String?;
        final format = DateFormat('MMM dd, HH:mm');
        
        final fromName = fromStr != null ? format.format(DateTime.parse(fromStr).toLocal()) : 'None';
        final toName = toStr != null ? format.format(DateTime.parse(toStr).toLocal()) : 'None';
        return 'changed due date from $fromName to $toName';
        
      case 'COMMENT_ADDED':
        final preview = details['preview'] as String? ?? '...';
        return 'added a comment: "$preview"';
        
      default:
        return 'performed an action: $actionType';
    }
  }
}
