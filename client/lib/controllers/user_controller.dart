import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:last_project_client/models/user_model.dart';
import 'package:last_project_client/services/user_service.dart';

class UserController extends ChangeNotifier {
  final UserService _userService;
  
  // Cache of user IDs to display names
  final Map<int, String> _userNameCache = {};
  
  // Track which IDs were requested in which packet ID: { requestId: Set<userIds> }
  final Map<String, Set<int>> _inflightRequests = {};
  
  // Flattened set for quick lookup of what is currently pending
  final Set<int> _allPendingIds = {};
  
  StreamSubscription? _userSubscription;

  UserController({required UserService userService}) : _userService = userService {
    _init();
  }

  void _init() {
    _userSubscription = _userService.userStream.listen(_onPacketReceived);
  }

  // Getters
  Map<int, String> get userNameCache => _userNameCache;

  /// Returns the display name for a user ID, or "User #$id" if not cached.
  String getName(int id) {
    return _userNameCache[id] ?? "User #$id";
  }

  /// Adds a user to the cache (e.g., after login or search).
  void updateCache(UserModel user) {
    _userNameCache[user.id] = user.displayName;
    notifyListeners();
  }

  /// Resolves a list of user IDs into display names.
  /// Only requests IDs that are NOT already in the cache or pending.
  void resolveUsers(List<int> ids) {
    final toResolve = ids.where((id) => 
      !_userNameCache.containsKey(id) && !_allPendingIds.contains(id)
    ).toList();
    
    if (toResolve.isEmpty) return;

    // Generate a predictable ID to match what UserService will send
    final requestId = "user_get_${DateTime.now().millisecondsSinceEpoch}_${toResolve.hashCode}";
    
    // MANDATE: Register tracking state BEFORE the network call
    _inflightRequests[requestId] = toResolve.toSet();
    _allPendingIds.addAll(toResolve);



    // Dispatch the network call via UserService (stateless)
    _userService.getUsers(toResolve, requestId: requestId);
  }

  void _onPacketReceived(Map<String, dynamic> packet) {
    final requestId = packet['id']?.toString();
    final type = packet['type'] as String;
    
    // Strict correlation filter: Only process packets we explicitly sent
    if (requestId == null || !_inflightRequests.containsKey(requestId)) {
      return;
    }

    final data = packet['data'] as Map<String, dynamic>? ?? {};

    if (type == 'USER_GET_RESP') {
      final List<dynamic> usersRaw = data['users'] ?? [];
      for (final userJson in usersRaw) {
        final id = userJson['id'] as int;
        final name = userJson['display_name'] as String;
        _userNameCache[id] = name;
      }
      
      // Cleanup: Remove IDs in this specific batch from pending
      final resolvedSet = _inflightRequests.remove(requestId);
      if (resolvedSet != null) {
        _allPendingIds.removeAll(resolvedSet);
      }
      

      notifyListeners();
    } 
    else if (type == 'SYS_ERROR') {
      // Surgical Error Recovery: Only clear IDs associated with THIS failed requestId
      final failedSet = _inflightRequests.remove(requestId);
      if (failedSet != null) {
        _allPendingIds.removeAll(failedSet);

      }
    }
  }

  void clearCache() {
    _userNameCache.clear();
    _inflightRequests.clear();
    _allPendingIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }
}
