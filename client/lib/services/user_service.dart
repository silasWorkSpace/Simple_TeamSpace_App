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

  /// Stream of all user-related packets.
  /// Note: SYS_ERROR is included but MUST be filtered by id in the UI layer.
  Stream<Map<String, dynamic>> get userSearchStream => tcpClient.packetStream.where((packet) {
    final type = packet['type'] as String;
    return type == "USER_SEARCH_RESP" || type == "SYS_ERROR";
  });
}
