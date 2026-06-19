import 'dart:async';
import 'package:last_project_client/network/tcp_client.dart';

class ActivityService {
  final TcpClient tcpClient;

  ActivityService({required this.tcpClient});

  /// Requests the activity history for a specific task.
  String fetchActivities(int taskId) {
    final requestId = 'act_${DateTime.now().millisecondsSinceEpoch}';
    tcpClient.sendPacket(
      'ACTIVITY_LIST_REQ',
      {'task_id': taskId},
      id: requestId,
    );
    return requestId;
  }

  /// Filtered stream of all activity-related packets.
  Stream<Map<String, dynamic>> get activityStream =>
      tcpClient.packetStream.where((packet) {
        final type = packet['type'] as String;
        final id = packet['id']?.toString() ?? '';

        if (type.startsWith('ACTIVITY_')) return true;
        if (type == 'SYS_ERROR' && id.startsWith('act_')) return true;

        return false;
      });
}
