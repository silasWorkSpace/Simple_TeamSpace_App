import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:last_project_client/services/channel_service.dart';
import 'package:last_project_client/models/channel_model.dart';

class ChannelController extends ChangeNotifier {
  final ChannelService channelService;
  StreamSubscription? _subscription;
  
  List<ChannelModel> _channels = [];
  List<ChannelModel> get channels => _channels;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  ChannelController({required this.channelService}) {
    _subscription = channelService.channelStream.listen(_onPacketReceived);
  }

  void fetchChannels() {
    _isLoading = true;
    notifyListeners();
    channelService.fetchChannelList();
  }

  void createChannel(String name, {bool isPublic = false}) {
    channelService.createChannel(name, isPublic: isPublic);
  }

  void _onPacketReceived(Map<String, dynamic> packet) {
    final type = packet['type'] as String;
    final data = packet['data'] as Map<String, dynamic>;

    if (type == 'CHANNEL_LIST_RESP') {
      final list = data['channels'] as List<dynamic>;
      _channels = list.map((c) => ChannelModel.fromJson(c as Map<String, dynamic>)).toList();
      _isLoading = false;
      notifyListeners();
    } else if (type == 'CHANNEL_CREATE_RESP') {
      final c = ChannelModel.fromJson(data['channel'] as Map<String, dynamic>);
      _channels.add(c);
      notifyListeners();
    } else if (type == 'CHANNEL_LIST_UPDATED') {
      fetchChannels();
    } else if (type == 'CHANNEL_JOIN_RESP' || type == 'CHANNEL_LEAVE_RESP') {
      // The server also broadcasts CHANNEL_LIST_UPDATED, so fetchChannels() will be called naturally.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
