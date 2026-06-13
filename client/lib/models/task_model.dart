class TaskModel {
  final int id;
  final String title;
  final String? description;
  final String status;
  final int creatorId;
  final int? assigneeId;
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
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      creatorId: creatorId ?? this.creatorId,
      assigneeId: assigneeId ?? this.assigneeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
