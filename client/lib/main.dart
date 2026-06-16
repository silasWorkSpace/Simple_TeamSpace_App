import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/network/tcp_client.dart';
import 'package:last_project_client/services/auth_service.dart';
import 'package:last_project_client/services/chat_service.dart';
import 'package:last_project_client/services/task_service.dart';
import 'package:last_project_client/services/user_service.dart';
import 'package:last_project_client/controllers/chat_controller.dart';
import 'package:last_project_client/controllers/task_controller.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/controllers/user_controller.dart';
import 'package:last_project_client/views/auth/login_screen.dart';
import 'package:last_project_client/views/home/main_layout.dart';

void main() {
  final tcpClient = TcpClient(host: '127.0.0.1', port: 8888);
  final authService = AuthService(tcpClient: tcpClient);
  final chatService = ChatService(tcpClient: tcpClient);
  final taskService = TaskService(tcpClient: tcpClient);
  final userService = UserService(tcpClient: tcpClient);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: tcpClient),
        Provider.value(value: authService),
        Provider.value(value: chatService),
        Provider.value(value: taskService),
        Provider.value(value: userService),
        ChangeNotifierProvider(
          create: (_) => UserController(
            userService: userService,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthController(
            authService: authService,
            tcpClient: tcpClient,
          ),
        ),
        ChangeNotifierProxyProvider<AuthController, ChatController>(
          create: (context) => ChatController(
            chatService: context.read<ChatService>(),
          ),
          update: (context, auth, chatController) => chatController!
            ..updateCurrentUser(auth.currentUser?.id),
        ),
        ChangeNotifierProxyProvider2<AuthController, UserController, TaskController>(
          create: (context) => TaskController(
            taskService: context.read<TaskService>(),
            userController: context.read<UserController>(),
          ),
          update: (context, auth, user, taskController) {
            // Update cache with current user info
            if (auth.currentUser != null) {
              user.updateCache(auth.currentUser!);
            }
            return taskController!..updateCurrentUser(auth.currentUser?.id);
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LTM Last Project',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch auth state to switch between Login and Home
    final auth = context.watch<AuthController>();
    
    if (auth.isAuthenticated) {
      return const MainLayout();
    }
    
    return const LoginScreen();
  }
}
