import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:last_project_client/models/message_model.dart';
import 'package:last_project_client/services/chat_service.dart';

class ChatController extends ChangeNotifier {
  final ChatService _chatService;
  int? _currentUserId;

  // State: Conversation Messages keyed by Peer ID
  final Map<int, List<MessageModel>> _messages = {};
  
  // State: Peer Display Names keyed by Peer ID
  final Map<int, String> _peerNames = {};

  // State: Scoped Server IDs for deduplication
  final Map<int, Set<int>> _conversationMsgIds = {};

  // State: Online Status keyed by User ID
  final Map<int, bool> _onlineStatus = {};

  // State: Pending requests (requestId -> clientMsgId)
  final Map<String, String> _pendingRequests = {};

  // State: Timeouts (clientMsgId -> Timer)
  final Map<String, Timer> _timeoutTimers = {};

  // State: Early ACKs (clientMsgId -> deliveredAt)
  final Map<String, DateTime> _earlyDeliveredAcks = {};

  StreamSubscription? _chatSubscription;

  ChatController({
    required ChatService chatService,
    int? currentUserId,
  })  : _chatService = chatService,
        _currentUserId = currentUserId {
    _init();
  }

  // Getters
  int? get currentUserId => _currentUserId;
  List<MessageModel> getMessages(int peerId) => _messages[peerId] ?? [];
  bool isOnline(int userId) => _onlineStatus[userId] ?? false;
  String? getPeerName(int peerId) => _peerNames[peerId];
  Iterable<int> get activePeers => _messages.keys;

  void _init() {
    _chatSubscription = _chatService.chatStream.listen(_onPacketReceived);
  }

  /// Updates the current user context. Clears state on logout or user change.
  void updateCurrentUser(int? userId) {
    if (_currentUserId == userId) return;

    debugPrint("[CHAT] User context changed: $_currentUserId -> $userId");
    _currentUserId = userId;
    
    // Always clear state when the user session changes or ends
    clear();
  }

  /// Sends a new message.
  void sendMessage(int receiverId, String content) {
    if (_currentUserId == null) return;

    final clientMsgId = "${DateTime.now().millisecondsSinceEpoch}_$_currentUserId";
    
    final newMessage = MessageModel(
      clientMsgId: clientMsgId,
      senderId: _currentUserId!,
      receiverId: receiverId,
      content: content,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );

    // 1. Update UI
    _addMessageLocally(receiverId, newMessage);

    // 2. Start Timeout
    _startTimeout(clientMsgId);

    // 3. Send via service
    final requestId = _chatService.sendMessage(
      clientMsgId: clientMsgId,
      receiverId: receiverId,
      content: content,
    );
    _pendingRequests[requestId] = clientMsgId;
  }

  /// Retries a failed message.
  void retryMessage(MessageModel message) {
    if (_currentUserId == null || message.status != MessageStatus.error) return;

    // Reset status to sending
    final retriedMessage = message.copyWith(status: MessageStatus.sending);
    _updateMessageInList(message.receiverId, retriedMessage);

    _startTimeout(message.clientMsgId);

    final requestId = _chatService.sendMessage(
      clientMsgId: message.clientMsgId,
      receiverId: message.receiverId,
      content: message.content,
    );
    _pendingRequests[requestId] = message.clientMsgId;
  }

  /// Fetches history for a peer.
  void loadHistory(int peerId, {int? beforeId}) {
    _chatService.fetchHistory(peerId: peerId, beforeId: beforeId);
  }

  void _onPacketReceived(Map<String, dynamic> packet) {
    final type = packet['type'] as String;
    final id = packet['id']?.toString();
    final data = packet['data'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'CHAT_SENT':
        _handleChatSent(id, data);
        break;
      case 'CHAT_RECEIVE':
        _handleChatReceive(data);
        break;
      case 'CHAT_DELIVERED':
        _handleChatDelivered(data);
        break;
      case 'CHAT_HIST_RESP':
        _handleHistoryResponse(data);
        break;
      case 'CHAT_LIST_RESP':
        _handleChatListResponse(data);
        break;
      case 'USER_ONLINE':
        _setOnlineStatus(data['user_id'], true);
        break;
      case 'USER_OFFLINE':
        _setOnlineStatus(data['user_id'], false);
        break;
      case 'SYS_ERROR':
        _handleError(id);
        break;
    }
  }

  void _handleChatSent(String? requestId, Map<String, dynamic> data) {
    final clientMsgId = _pendingRequests.remove(requestId);
    if (clientMsgId == null) return;

    _cancelTimeout(clientMsgId);

    final peerId = data['receiver_id'] as int;
    final serverId = data['server_msg_id'] as int;

    final existing = _findInList(peerId, clientMsgId);
    if (existing != null) {
      var updated = existing.copyWith(
        id: serverId,
        status: MessageStatus.sent,
      );

      // Check for early ACK
      if (_earlyDeliveredAcks.containsKey(clientMsgId)) {
        updated = updated.copyWith(
          status: MessageStatus.delivered,
          deliveredAt: _earlyDeliveredAcks.remove(clientMsgId),
        );
      }

      _updateMessageInList(peerId, updated);
      _markIdAsSeen(peerId, serverId);
    }
  }

  void _handleChatReceive(Map<String, dynamic> data) {
    final message = MessageModel.fromJson(data);
    final peerId = message.senderId;

    // Metadata Bootstrap
    if (data.containsKey('sender_display_name')) {
      _peerNames[peerId] = data['sender_display_name'] as String;
    }

    if (_serverMsgIdSet(peerId).contains(message.id)) return;

    _addMessageLocally(peerId, message);
    _markIdAsSeen(peerId, message.id!);

    // Auto-ACK to server
    _chatService.sendReceivedAck(message.id!);
  }

  void _handleChatDelivered(Map<String, dynamic> data) {
    final clientMsgId = data['client_msg_id'] as String;
    final serverId = data['server_msg_id'] as int;
    final deliveredAt = DateTime.parse(data['delivered_at'] as String);

    // Find message locally
    bool found = false;
    for (final peerId in _messages.keys) {
      final msg = _findInList(peerId, clientMsgId);
      if (msg != null) {
        final updated = msg.copyWith(
          status: MessageStatus.delivered,
          deliveredAt: deliveredAt,
        );
        _updateMessageInList(peerId, updated);
        found = true;
        break;
      }
    }

    if (!found) {
      _earlyDeliveredAcks[clientMsgId] = deliveredAt;
      if (_earlyDeliveredAcks.length > 100) {
        _earlyDeliveredAcks.remove(_earlyDeliveredAcks.keys.first);
      }
    }
  }

  void _handleHistoryResponse(Map<String, dynamic> data) {
    final rawMessages = data['messages'] as List<dynamic>? ?? [];
    if (rawMessages.isEmpty) return;

    final List<MessageModel> newMessages = [];
    int? peerId;

    for (var raw in rawMessages) {
      final msg = MessageModel.fromJson(raw as Map<String, dynamic>);
      peerId ??= (msg.senderId == _currentUserId ? msg.receiverId : msg.senderId);

      if (!_serverMsgIdSet(peerId).contains(msg.id)) {
        newMessages.add(msg);
        _markIdAsSeen(peerId, msg.id!);
      }
    }

    if (peerId != null && newMessages.isNotEmpty) {
      // History is newest-first from server. Reverse to chronological before prepending.
      final chronological = newMessages.reversed.toList();
      _messages[peerId] = [...chronological, ...(_messages[peerId] ?? [])];
      notifyListeners();
    }
  }

  void _handleChatListResponse(Map<String, dynamic> data) {
    final conversations = data['conversations'] as List<dynamic>? ?? [];
    if (conversations.isEmpty) return;

    bool stateChanged = false;

    for (var conv in conversations) {
      final peerId = conv['peer_id'] as int;
      final isOnline = conv['is_online'] as bool;
      final lastMsgData = conv['last_message'] as Map<String, dynamic>;

      // Update Peer Metadata
      if (conv.containsKey('display_name') && _peerNames[peerId] != conv['display_name']) {
        _peerNames[peerId] = conv['display_name'] as String;
        stateChanged = true;
      }

      // 1. Update online status (Always authoritative)
      if (_onlineStatus[peerId] != isOnline) {
        _onlineStatus[peerId] = isOnline;
        stateChanged = true;
      }

      // 2. Initialize conversation ONLY if empty
      if (_messages[peerId] == null || _messages[peerId]!.isEmpty) {
        final lastMsg = MessageModel.fromJson(lastMsgData);
        
        if (!_serverMsgIdSet(peerId).contains(lastMsg.id)) {
          _messages[peerId] = [lastMsg];
          _markIdAsSeen(peerId, lastMsg.id!);
          stateChanged = true;
        }
      }
    }

    if (stateChanged) {
      notifyListeners();
    }
  }

  void _handleError(String? requestId) {
    final clientMsgId = _pendingRequests.remove(requestId);
    if (clientMsgId == null) return;

    _cancelTimeout(clientMsgId);

    for (final peerId in _messages.keys) {
      final msg = _findInList(peerId, clientMsgId);
      if (msg != null) {
        _updateMessageInList(peerId, msg.copyWith(status: MessageStatus.error));
        break;
      }
    }
  }

  void _setOnlineStatus(int userId, bool isOnline) {
    _onlineStatus[userId] = isOnline;
    notifyListeners();
  }

  // Helpers
  void _addMessageLocally(int peerId, MessageModel msg) {
    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }

  void _updateMessageInList(int peerId, MessageModel updated) {
    final list = _messages[peerId];
    if (list == null) return;

    final index = list.indexWhere((m) => m.clientMsgId == updated.clientMsgId);
    if (index != -1) {
      list[index] = updated;
      notifyListeners();
    }
  }

  MessageModel? _findInList(int peerId, String clientMsgId) {
    final list = _messages[peerId];
    if (list == null) return null;
    try {
      return list.firstWhere((m) => m.clientMsgId == clientMsgId);
    } catch (_) {
      return null;
    }
  }

  Set<int> _serverMsgIdSet(int peerId) {
    return _conversationMsgIds.putIfAbsent(peerId, () => <int>{});
  }

  void _markIdAsSeen(int peerId, int serverId) {
    _serverMsgIdSet(peerId).add(serverId);
  }

  void _startTimeout(String clientMsgId) {
    _timeoutTimers[clientMsgId]?.cancel();
    _timeoutTimers[clientMsgId] = Timer(const Duration(seconds: 10), () {
      _onTimeout(clientMsgId);
    });
  }

  void _cancelTimeout(String clientMsgId) {
    _timeoutTimers.remove(clientMsgId)?.cancel();
  }

  void _onTimeout(String clientMsgId) {
    _timeoutTimers.remove(clientMsgId);
    
    _pendingRequests.removeWhere((key, value) => value == clientMsgId);

    for (final peerId in _messages.keys) {
      final msg = _findInList(peerId, clientMsgId);
      if (msg != null && msg.status == MessageStatus.sending) {
        _updateMessageInList(peerId, msg.copyWith(status: MessageStatus.error));
        break;
      }
    }
  }

  void clear() {
    _messages.clear();
    _peerNames.clear();
    _conversationMsgIds.clear();
    _onlineStatus.clear();
    _pendingRequests.clear();
    _earlyDeliveredAcks.clear();
    for (var timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    clear();
    _chatSubscription?.cancel();
    super.dispose();
  }
}
