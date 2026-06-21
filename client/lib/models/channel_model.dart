class ChannelModel {
  final int id; // Corresponds to negative peerId in UI
  final String name;
  final int ownerId;
  final bool isPublic;
  final bool isJoined;

  ChannelModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isPublic,
    this.isJoined = false,
  });

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['id'] as int,
      name: json['name'] as String,
      ownerId: json['owner_id'] as int,
      isPublic: json['is_public'] as bool? ?? false,
      isJoined: json['is_joined'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'is_public': isPublic,
      'is_joined': isJoined,
    };
  }
}
