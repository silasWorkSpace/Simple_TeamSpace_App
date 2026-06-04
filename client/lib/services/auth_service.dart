import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:last_project_client/network/tcp_client.dart';
import 'package:last_project_client/models/user_model.dart';

class AuthService {
  final TcpClient tcpClient;

  AuthService({required this.tcpClient});

  /// Sends a registration request and waits for AUTH_SUCCESS or SYS_ERROR.
  Future<UserModel> register({
    required String phone,
    required String password,
    required String displayName,
  }) async {
    final requestId = "reg_${DateTime.now().millisecondsSinceEpoch}";
    final completer = Completer<UserModel>();

    StreamSubscription? subscription;
    subscription = tcpClient.packetStream.listen((packet) {
      if (packet['id'] == requestId) {
        if (packet['type'] == 'AUTH_SUCCESS') {
          completer.complete(UserModel.fromJson(packet['data']));
          subscription?.cancel();
        } else if (packet['type'] == 'SYS_ERROR') {
          completer.completeError(packet['data']['message'] ?? 'Registration failed');
          subscription?.cancel();
        }
      }
    });

    tcpClient.sendPacket(
      "AUTH_REGISTER",
      {
        "phone": phone,
        "password": password,
        "display_name": displayName,
      },
      id: requestId,
    );

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        subscription?.cancel();
        throw TimeoutException("Registration timed out");
      },
    );
  }

  /// Sends a login request and waits for AUTH_SUCCESS or SYS_ERROR.
  Future<UserModel> login({
    required String phone,
    required String password,
  }) async {
    final requestId = "login_${DateTime.now().millisecondsSinceEpoch}";
    final completer = Completer<UserModel>();

    StreamSubscription? subscription;
    subscription = tcpClient.packetStream.listen((packet) {
      if (packet['id'] == requestId) {
        if (packet['type'] == 'AUTH_SUCCESS') {
          completer.complete(UserModel.fromJson(packet['data']));
          subscription?.cancel();
        } else if (packet['type'] == 'SYS_ERROR') {
          completer.completeError(packet['data']['message'] ?? 'Login failed');
          subscription?.cancel();
        }
      }
    });

    tcpClient.sendPacket(
      "AUTH_LOGIN",
      {
        "phone": phone,
        "password": password,
      },
      id: requestId,
    );

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        subscription?.cancel();
        throw TimeoutException("Login timed out");
      },
    );
  }
}
