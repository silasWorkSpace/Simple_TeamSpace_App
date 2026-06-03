import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/network/tcp_client.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => TcpClient(host: '127.0.0.1', port: 8888)),
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
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ConnectionTestScreen(),
    );
  }
}

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  String status = "Disconnected";
  String lastPacket = "None";

  void _connect() async {
    final tcp = context.read<TcpClient>();
    try {
      await tcp.connect();
      setState(() => status = "Connected");
      
      tcp.packetStream.listen((packet) {
        setState(() => lastPacket = packet.toString());
      });
    } catch (e) {
      setState(() => status = "Error: $e");
    }
  }

  void _sendPing() {
    context.read<TcpClient>().sendPacket("SYS_PING", {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Milestone 1 Test")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Status: $status", style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 20),
            Text("Last Packet: $lastPacket"),
            const SizedBox(height: 40),
            ElevatedButton(onPressed: _connect, child: const Text("Connect")),
            ElevatedButton(onPressed: _sendPing, child: const Text("Send Ping")),
          ],
        ),
      ),
    );
  }
}
