import 'dart:async';
import 'package:last_project_client/network/tcp_client.dart';

class ChatService {
  final TcpClient tcpClient;

  ChatService({required this.tcpClient});

  /// Sends a new message and returns its request ID for reconciliation.
  String sendMessage({
    required String clientMsgId,
    required int receiverId,
    required String content,
    String? msgType,
    Map<String, dynamic>? metadata,
  }) {
    final requestId = "chat_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "CHAT_SEND",
      {
        "client_msg_id": clientMsgId,
        "receiver_id": receiverId,
        "content": content,
        if (msgType != null) "msg_type": msgType,
        if (metadata != null) "metadata": metadata,
      },
      id: requestId,
    );
    return requestId;
  }

  /// Confirms receipt of CHAT_RECEIVE.
  void sendReceivedAck(int serverMsgId) {
    tcpClient.sendPacket(
      "CHAT_RECEIVED",
      {"server_msg_id": serverMsgId},
      id: "system",
    );
  }

  /// Requests paginated chat history and returns its request ID.
  String fetchHistory({required int peerId, int? limit, int? beforeId}) {
    final requestId = "hist_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "CHAT_HIST_REQ",
      {
        "peer_id": peerId,
        "limit": limit ?? 50,
        if (beforeId != null) "before_id": beforeId,
      },
      id: requestId,
    );
    return requestId;
  }

  /// Requests the list of existing conversations.
  String fetchConversationList() {

    final requestId = "list_${DateTime.now().millisecondsSinceEpoch}";

    tcpClient.sendPacket(
      "CHAT_LIST_REQ",
      {},
      id: requestId,
    );
    return requestId;
  }

  /// Stream of all chat-related packets, including relevant system errors.
  Stream<Map<String, dynamic>> get chatStream => tcpClient.packetStream.where((packet) {
    final type = packet['type'] as String;
    final id = packet['id']?.toString() ?? '';
    
    // 1. Forward all explicit chat, user presence, and file packets
    if (type.startsWith('CHAT_') || type.startsWith('USER_') || type.startsWith('FILE_')) return true;
    
    // 2. Forward SYS_ERROR only if they correlate to a chat, history, or file request
    if (type == 'SYS_ERROR' &&
        (id.startsWith('chat_') || id.startsWith('hist_') ||
         id.startsWith('file_up_') || id.startsWith('file_dn_'))) {
      return true;
    }
    
    return false;
  });
}
