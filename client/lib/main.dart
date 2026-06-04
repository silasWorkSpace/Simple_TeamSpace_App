import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/network/tcp_client.dart';
import 'package:last_project_client/services/auth_service.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/views/auth/login_screen.dart';

void main() {
  final tcpClient = TcpClient(host: '127.0.0.1', port: 8888);
  final authService = AuthService(tcpClient: tcpClient);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: tcpClient),
        Provider.value(value: authService),
        ChangeNotifierProvider(
          create: (_) => AuthController(
            authService: authService,
            tcpClient: tcpClient,
          ),
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
      return Scaffold(
        appBar: AppBar(
          title: Text("Welcome, ${auth.currentUser?.displayName}"),
          actions: [
            IconButton(
              onPressed: () => context.read<AuthController>().logout(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Login Successful!", style: TextStyle(fontSize: 24)),
              const SizedBox(height: 16),
              Text("User ID: ${auth.currentUser?.id}"),
              Text("Phone: ${auth.currentUser?.phone}"),
            ],
          ),
        ),
      );
    }
    
    return const LoginScreen();
  }
}
