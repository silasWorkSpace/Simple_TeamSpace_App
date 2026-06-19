class TaskModel {
  final int id;
  final String title;
  final String? description;
  final String status;
  final int creatorId;
  final int? assigneeId;
  final DateTime? dueAt;
  final int commentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  TaskModel({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.creatorId,
    this.assigneeId,
    this.dueAt,
    this.commentCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: json['status'] as String,
      creatorId: json['creator_id'] as int,
      assigneeId: json['assignee_id'] as int?,
      // due_at arrives as an ISO-8601 UTC string (e.g. "2026-06-30T18:00:00Z")
      // or null when no due date is set.
      dueAt: json['due_at'] != null
          ? DateTime.parse(json['due_at'] as String).toLocal()
          : null,
      // comment_count is injected by the server-side SQL subquery.
      // Defaults to 0 for forward-compatibility with any cached payloads
      // that pre-date the Phase 6A schema migration.
      commentCount: json['comment_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'creator_id': creatorId,
      'assignee_id': assigneeId,
      // Serialize back to UTC ISO-8601 with 'Z' suffix — required by the
      // server's _validate_due_at() check in task_service.py.
      'due_at': dueAt?.toUtc().toIso8601String(),
      'comment_count': commentCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  TaskModel copyWith({
    int? id,
    String? title,
    String? description,
    String? status,
    int? creatorId,
    int? assigneeId,
    // Use Object? sentinel to distinguish "set to null" from "not provided".
    Object? dueAt = _sentinel,
    int? commentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = _sentinel,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      creatorId: creatorId ?? this.creatorId,
      assigneeId: assigneeId ?? this.assigneeId,
      dueAt: dueAt == _sentinel ? this.dueAt : dueAt as DateTime?,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt == _sentinel ? this.completedAt : completedAt as DateTime?,
    );
  }
}

// Private sentinel object used by copyWith to distinguish between
// "caller passed null explicitly" and "caller did not pass the argument".
// This is the standard Dart pattern for nullable copyWith parameters.
const Object _sentinel = Object();
