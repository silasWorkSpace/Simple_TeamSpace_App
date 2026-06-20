import 'package:flutter/foundation.dart';
import 'package:last_project_client/models/message_type.dart';
import 'package:last_project_client/models/message_metadata.dart';

export 'package:last_project_client/models/message_type.dart';
export 'package:last_project_client/models/message_metadata.dart';

enum MessageStatus { sending, sent, delivered, error }

@immutable
class MessageModel {
  final int? id; // server_msg_id
  final String clientMsgId;
  final int senderId;
  final int receiverId;
  final String content; // text body OR file token for file/image types
  final String msgType;  // MessageType constant; defaults to 'text'
  final MessageMetadata metadata;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final MessageStatus status;

  const MessageModel({
    this.id,
    required this.clientMsgId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.msgType = MessageType.text,
    this.metadata = const MessageMetadata(),
    required this.createdAt,
    this.deliveredAt,
    this.status = MessageStatus.sending,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final rawType = json['msg_type'] as String? ?? MessageType.text;
    // Degrade unknown types gracefully instead of throwing.
    final resolvedType = _knownTypes.contains(rawType) ? rawType : MessageType.unknown;

    return MessageModel(
      id: json['id'] as int?,
      clientMsgId: json['client_msg_id'] as String? ?? '',
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      content: json['content'] as String? ?? '',
      msgType: resolvedType,
      metadata: MessageMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>?,
      ),
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
    MessageMetadata? metadata,
  }) {
    return MessageModel(
      id: id ?? this.id,
      clientMsgId: clientMsgId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      msgType: msgType,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
    );
  }

  /// Convenience checks for the UI layer.
  bool get isText => msgType == MessageType.text;
  bool get isImage => msgType == MessageType.image;
  bool get isFile => msgType == MessageType.file;
  bool get isSticker => msgType == MessageType.sticker;
  bool get isVoice => msgType == MessageType.voice;
  bool get requiresDownload => MessageType.requiresDownload.contains(msgType);

  @override
  String toString() =>
      'MessageModel(id: $id, clientMsgId: $clientMsgId, type: $msgType, status: $status)';

  static const Set<String> _knownTypes = {
    MessageType.text,
    MessageType.image,
    MessageType.file,
    MessageType.sticker,
    MessageType.voice,
  };
}
