import 'package:last_project_client/network/tcp_client.dart';

class UserService {
  final TcpClient tcpClient;

  UserService({required this.tcpClient});

  /// Sends a search request and returns the generated unique requestId.
  String searchUsers(String query) {
    final requestId = "user_search_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "USER_SEARCH_REQ",
      {"query": query},
      id: requestId,
    );
    return requestId;
  }

  /// Sends a request to get multiple users by their IDs.
  String getUsers(List<int> userIds, {String? requestId}) {
    final id = requestId ?? "user_get_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket(
      "USER_GET_REQ",
      {"user_ids": userIds},
      id: id,
    );
    return id;
  }

  /// Stream of all user-related packets.
  Stream<Map<String, dynamic>> get userStream => tcpClient.packetStream.where((packet) {
    final type = packet['type'] as String;
    return type == "USER_SEARCH_RESP" || type == "USER_GET_RESP" || type == "SYS_ERROR";
  });
}
