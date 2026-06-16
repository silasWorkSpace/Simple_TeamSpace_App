class UserModel {
  final int id;
  final String phone;
  final String displayName;
  final bool isOnline;

  UserModel({
    required this.id,
    required this.phone,
    required this.displayName,
    this.isOnline = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? json['user_id'] ?? 0,
      phone: json['phone'] ?? '',
      displayName: json['display_name'] ?? 'Unknown',
      isOnline: json['is_online'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'display_name': displayName,
      'is_online': isOnline ? 1 : 0,
    };
  }
}
