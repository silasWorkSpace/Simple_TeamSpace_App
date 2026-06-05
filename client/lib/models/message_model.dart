import 'package:flutter/foundation.dart';

enum MessageStatus { sending, sent, delivered, error }

@immutable
class MessageModel {
  final int? id; // server_msg_id
  final String clientMsgId;
  final int senderId;
  final int receiverId;
  final String content;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final MessageStatus status;

  const MessageModel({
    this.id,
    required this.clientMsgId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.deliveredAt,
    this.status = MessageStatus.sending,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int?,
      clientMsgId: json['client_msg_id'] as String,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      deliveredAt: json['delivered_at'] != null 
          ? DateTime.parse(json['delivered_at'] as String) 
          : null,
      status: json['delivered_at'] != null 
          ? MessageStatus.delivered 
          : MessageStatus.sent,
    );
  }

  MessageModel copyWith({
    int? id,
    DateTime? deliveredAt,
    MessageStatus? status,
  }) {
    return MessageModel(
      id: id ?? this.id,
      clientMsgId: clientMsgId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      createdAt: createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'MessageModel(id: $id, clientMsgId: $clientMsgId, status: $status)';
  }
}
