import 'package:last_project_client/network/tcp_client.dart';

class ChannelService {
  final TcpClient tcpClient;

  ChannelService({required this.tcpClient});

  String fetchChannelList() {
    final requestId = "chan_list_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_LIST_REQ", {}, id: requestId);
    return requestId;
  }

  String createChannel(String name, {bool isPublic = false}) {
    final requestId = "chan_create_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_CREATE_REQ", {
      "name": name,
      "is_public": isPublic,
    }, id: requestId);
    return requestId;
  }

  String renameChannel(int channelId, String newName) {
    final requestId = "chan_rename_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_RENAME_REQ", {
      "channel_id": channelId,
      "name": newName,
    }, id: requestId);
    return requestId;
  }

  String addMember(int channelId, int userId) {
    final requestId = "chan_add_mem_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_ADD_MEMBER_REQ", {
      "channel_id": channelId,
      "user_id": userId,
    }, id: requestId);
    return requestId;
  }

  String removeMember(int channelId, int userId) {
    final requestId = "chan_rem_mem_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_REMOVE_MEMBER_REQ", {
      "channel_id": channelId,
      "user_id": userId,
    }, id: requestId);
    return requestId;
  }

  String fetchMembers(int channelId) {
    final requestId = "chan_mems_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_MEMBERS_REQ", {
      "channel_id": channelId,
    }, id: requestId);
    return requestId;
  }

  String deleteChannel(int channelId) {
    final requestId = "chan_del_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_DELETE_REQ", {
      "channel_id": channelId,
    }, id: requestId);
    return requestId;
  }

  String joinChannel(int channelId) {
    final requestId = "chan_join_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_JOIN_REQ", {
      "channel_id": channelId,
    }, id: requestId);
    return requestId;
  }

  String leaveChannel(int channelId) {
    final requestId = "chan_leave_${DateTime.now().millisecondsSinceEpoch}";
    tcpClient.sendPacket("CHANNEL_LEAVE_REQ", {
      "channel_id": channelId,
    }, id: requestId);
    return requestId;
  }

  Stream<Map<String, dynamic>> get channelStream => tcpClient.packetStream.where((packet) {
    final type = packet['type'] as String;
    final id = packet['id']?.toString() ?? '';
    
    if (type.startsWith('CHANNEL_')) return true;
    if (type == 'SYS_ERROR' && id.startsWith('chan_')) return true;
    
    return false;
  });
}
