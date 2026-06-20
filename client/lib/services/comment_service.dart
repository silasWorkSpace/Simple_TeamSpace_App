import 'dart:async';
import 'package:last_project_client/network/tcp_client.dart';

/// Networking service for the comment subsystem (Phase 6A).
///
/// Follows the same pattern as [TaskService]:
/// - Each public method fires a packet and returns the requestId.
/// - [commentStream] is a filtered view of [TcpClient.packetStream] that
///   surfaces only COMMENT_* packets and task-correlated SYS_ERROR packets.
/// - No state is held here — all state lives in TaskController.
class CommentService {
  final TcpClient tcpClient;

  CommentService({required this.tcpClient});

  /// Sends a new comment for [taskId].
  ///
  /// Fires: COMMENT_SEND_REQ { task_id, content }
  /// Expects: COMMENT_SEND_RESP { comment: { id, task_id, user_id, content, created_at } }
  String sendComment({
    required int taskId,
    required String content,
  }) {

    final requestId = 'comment_send_${DateTime.now().millisecondsSinceEpoch}';
    tcpClient.sendPacket(
      'COMMENT_SEND_REQ',
      {
        'task_id': taskId,
        'content': content,
      },
      id: requestId,
    );
    return requestId;
  }

  /// Requests all comments for [taskId] in chronological order.
  ///
  /// Fires: COMMENT_LIST_REQ { task_id }
  /// Expects: COMMENT_LIST_RESP { task_id, comments: [...] }
  String fetchComments(int taskId) {

    final requestId = 'comment_list_${DateTime.now().millisecondsSinceEpoch}';
    tcpClient.sendPacket(
      'COMMENT_LIST_REQ',
      {'task_id': taskId},
      id: requestId,
    );
    return requestId;
  }

  /// Filtered stream of all comment-related packets.
  ///
  /// Forwards:
  /// - Any packet whose type starts with 'COMMENT_'
  ///   (covers COMMENT_SEND_RESP, COMMENT_LIST_RESP, COMMENT_CREATED_EVENT)
  /// - SYS_ERROR packets whose id starts with 'comment_'
  ///   (correlates errors back to a specific comment request)
  Stream<Map<String, dynamic>> get commentStream =>
      tcpClient.packetStream.where((packet) {
        final type = packet['type'] as String;
        final id = packet['id']?.toString() ?? '';

        // 1. Forward all explicit comment packets (including server-push events)
        if (type.startsWith('COMMENT_')) return true;

        // 2. Forward SYS_ERROR only when correlated to a comment request
        if (type == 'SYS_ERROR' && id.startsWith('comment_')) return true;

        return false;
      });
}
