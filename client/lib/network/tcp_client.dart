import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';

enum TcpConnectionState { initial, connecting, connected, disconnected }

class TcpClient {
  Socket? _socket;
  final String host;
  final int port;

  final _packetController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get packetStream => _packetController.stream;

  final ValueNotifier<TcpConnectionState> connectionState = 
      ValueNotifier<TcpConnectionState>(TcpConnectionState.initial);

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  TcpClient({required this.host, required this.port});

  /// Establishes connection to the server.
  Future<void> connect() async {
    connectionState.value = TcpConnectionState.connecting;
    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _isConnected = true;
      connectionState.value = TcpConnectionState.connected;
      debugPrint("[TCP] Connected to $host:$port");

      _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint("[TCP] Connection failed: $e");
      _isConnected = false;
      connectionState.value = TcpConnectionState.disconnected;
      rethrow;
    }
  }

  /// Internal buffer for handling fragmented TCP packets.
  final BytesBuilder _buffer = BytesBuilder();

  void _onData(Uint8List data) {
    _buffer.add(data);
    _processBuffer();
  }

  void _processBuffer() {
    while (_buffer.length >= 4) {
      final bytes = _buffer.toBytes();
      
      // Read 4-byte length prefix (Big-Endian)
      final lengthData = bytes.sublist(0, 4);
      final byteData = ByteData.view(lengthData.buffer);
      final length = byteData.getUint32(0, Endian.big);

      if (_buffer.length < 4 + length) {
        // Full packet not received yet
        break;
      }

      // Extract JSON payload
      final payloadData = bytes.sublist(4, 4 + length);
      final payloadStr = utf8.decode(payloadData);
      
      try {
        final packet = jsonDecode(payloadStr);
        _packetController.add(packet);
      } catch (e) {
        debugPrint("[TCP] JSON Decode Error: $e");
      }

      // Remove processed packet from buffer
      final remaining = bytes.sublist(4 + length);
      _buffer.clear();
      _buffer.add(remaining);
    }
  }

  /// Sends a packet with 4-byte length prefix.
  void sendPacket(String type, Map<String, dynamic> data, {String id = "client-req"}) {
    debugPrint("[TCP] sendPacket type=$type connected=$_isConnected socket=${_socket != null}");
    if (_socket == null || !_isConnected) return;

    final payload = {
      "v": "1.0",
      "id": id,
      "type": type,
      "data": data,
    };

    final jsonStr = jsonEncode(payload);
    final jsonBytes = utf8.encode(jsonStr);
    
    final header = Uint8List(4);
    final byteData = ByteData.view(header.buffer);
    byteData.setUint32(0, jsonBytes.length, Endian.big);

    _socket!.add(header);
    _socket!.add(jsonBytes);
    debugPrint("[TCP] Sent $type");
  }

  void _onError(error) {
    debugPrint("[TCP] Socket Error: $error");
    _isConnected = false;
    connectionState.value = TcpConnectionState.disconnected;
  }

  void _onDone() {
    debugPrint("[TCP] Socket Closed");
    _isConnected = false;
    connectionState.value = TcpConnectionState.disconnected;
    _socket?.destroy();
  }

  /// Closes the current connection without closing the packet stream.
  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _isConnected = false;
    connectionState.value = TcpConnectionState.disconnected;
    debugPrint("[TCP] Disconnected");
  }

  void dispose() {
    _socket?.destroy();
    _packetController.close();
  }
}
