import 'package:flutter/material.dart';
import 'package:last_project_client/models/user_model.dart';
import 'package:last_project_client/services/auth_service.dart';
import 'package:last_project_client/network/tcp_client.dart';

class AuthController extends ChangeNotifier {
  final AuthService _authService;
  final TcpClient _tcpClient;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  AuthController({
    required AuthService authService,
    required TcpClient tcpClient,
  })  : _authService = authService,
        _tcpClient = tcpClient;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;

  Future<void> login(String phone, String password) async {
    _setLoading(true);
    _error = null;
    try {
      if (!_tcpClient.isConnected) {
        await _tcpClient.connect();
      }
      _currentUser = await _authService.login(phone: phone, password: password);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> register(String phone, String password, String displayName) async {
    _setLoading(true);
    _error = null;
    try {
      if (!_tcpClient.isConnected) {
        await _tcpClient.connect();
      }
      _currentUser = await _authService.register(
        phone: phone,
        password: password,
        displayName: displayName,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  void logout() {
    _currentUser = null;
    _tcpClient.dispose(); // Simple logout for now: close connection
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
