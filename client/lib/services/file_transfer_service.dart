import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:last_project_client/network/tcp_client.dart';
import 'package:last_project_client/network/data_socket_client.dart';

/// Tracks the state of a single active file transfer.
class FileTransferState {
  final String token;
  final String filename;
  final int sizeBytes;
  final bool isUpload;
  double progress; // 0.0 – 1.0

  FileTransferState({
    required this.token,
    required this.filename,
    required this.sizeBytes,
    required this.isUpload,
    this.progress = 0.0,
  });
}

/// High-level service that bridges the JSON signaling channel (TcpClient) and
/// the binary data channel (DataSocketClient) for file transfers.
///
/// Responsibilities:
/// - Sending FILE_UPLOAD_REQ and FILE_DOWNLOAD_REQ over the JSON channel.
/// - Listening for FILE_UPLOAD_RESP and FILE_DOWNLOAD_RESP on the JSON channel.
/// - Delegating all byte movement to [DataSocketClient].
/// - Reporting percentage-only progress via [activeTransfers].
/// - Returning downloaded images as [Uint8List] or large files as [File].
///
/// NOT responsible for:
/// - Message persistence or routing (ChatController handles that).
/// - UI rendering.
class FileTransferService {
  final TcpClient _tcpClient;
  final DataSocketClient _dataSocket;

  /// Active transfers keyed by token. UI can observe this map.
  final Map<String, FileTransferState> activeTransfers = {};

  /// Memory cache for downloaded inline images.
  final Map<String, Uint8List> _imageCache = {};

  FileTransferService({
    required TcpClient tcpClient,
    required DataSocketClient dataSocket,
  })  : _tcpClient = tcpClient,
        _dataSocket = dataSocket;

  // ── Upload ────────────────────────────────────────────────────────────────

  /// Initiates an upload for [file] destined for [receiverId].
  ///
  /// Flow:
  ///   1. Sends FILE_UPLOAD_REQ on the JSON channel.
  ///   2. Waits for FILE_UPLOAD_RESP to receive the token.
  ///   3. Connects to the data port and streams bytes.
  ///   4. The server completes the upload and broadcasts CHAT_RECEIVE automatically.
  ///
  /// [onProgress] receives values from 0.0 to 1.0.
  Future<void> uploadFile({
    required File file,
    required int receiverId,
    String? msgType,
    Map<String, dynamic>? metadata,
    void Function(double)? onProgress,
  }) async {
    final filename = file.uri.pathSegments.last;
    final sizeBytes = await file.length();
    final requestId = 'file_up_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Signal the server over the JSON channel
    final payload = <String, dynamic>{
      'filename': filename,
      'size_bytes': sizeBytes,
      'receiver_id': receiverId,
    };
    
    if (msgType != null) {
      payload['msg_type'] = msgType;
    }
    if (metadata != null) {
      payload['metadata'] = metadata;
    }

    _tcpClient.sendPacket('FILE_UPLOAD_REQ', payload, id: requestId);

    // 2. Wait for FILE_UPLOAD_RESP to get token + data_port confirmation
    final token = await _waitForUploadResp(requestId);

    // 3. Register as an active transfer
    activeTransfers[token] = FileTransferState(
      token: token,
      filename: filename,
      sizeBytes: sizeBytes,
      isUpload: true,
    );

    // 4. Stream bytes over the data socket
    try {
      await _dataSocket.upload(
        file: file,
        token: token,
        onProgress: (p) {
          activeTransfers[token]?.progress = p;
          onProgress?.call(p);
        },
      );
    } finally {
      activeTransfers.remove(token);
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────

  /// Initiates a download for [token].
  ///
  /// Images ≤ 5 MB: returns a [Uint8List] for inline rendering.
  /// All others   : saves to the app documents directory and returns a [File].
  ///
  /// [onProgress] receives values from 0.0 to 1.0.
  Future<({Uint8List? bytes, File? file})> downloadFile({
    required String token,
    required String filename,
    required int sizeBytes,
    void Function(double)? onProgress,
  }) async {
    // Return cached image immediately if available
    if (_imageCache.containsKey(token)) {
      return (bytes: _imageCache[token], file: null);
    }

    // Return file immediately if it already exists on disk
    final localPath = await getLocalFilePath(token, filename);
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) {
        return (bytes: null, file: file);
      }
    }

    final requestId = 'file_dn_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Authorize download over JSON channel
    _tcpClient.sendPacket('FILE_DOWNLOAD_REQ', {
      'token': token,
    }, id: requestId);

    // 2. Wait for server confirmation
    await _waitForDownloadResp(requestId, token);

    // 3. Register as an active transfer
    activeTransfers[token] = FileTransferState(
      token: token,
      filename: filename,
      sizeBytes: sizeBytes,
      isUpload: false,
    );

    // 4. Resolve save path (only used if file goes to disk)
    final docsDir = await getApplicationDocumentsDirectory();
    final savePath = '${docsDir.path}/${token}_$filename';

    Uint8List? resultBytes;
    File? resultFile;

    try {
      await _dataSocket.download(
        token: token,
        expectedBytes: sizeBytes,
        savePath: savePath,
        onProgress: (p) {
          activeTransfers[token]?.progress = p;
          onProgress?.call(p);
        },
        onBytesReady: (bytes) => resultBytes = bytes,
        onFileReady: (file) => resultFile = file,
      );
    } finally {
      activeTransfers.remove(token);
    }

    if (resultBytes != null) {
      // Cache the inline image for future renders
      _imageCache[token] = resultBytes!;
    }

    return (bytes: resultBytes, file: resultFile);
  }

  /// Returns the absolute path where the file would be saved, or null if error.
  Future<String?> getLocalFilePath(String token, String filename) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      return '${docsDir.path}/${token}_$filename';
    } catch (_) {
      return null;
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  Future<String> _waitForUploadResp(String requestId) {
    final completer = Completer<String>();

    late StreamSubscription sub;
    sub = _tcpClient.packetStream.listen((packet) {
      final type = packet['type'] as String?;
      final id = packet['id']?.toString();

      if (id != requestId) return;

      if (type == 'FILE_UPLOAD_RESP') {
        final token = packet['data']?['token'] as String?;
        if (token != null) {
          sub.cancel();
          completer.complete(token);
        }
      } else if (type == 'SYS_ERROR') {
        sub.cancel();
        final msg = packet['data']?['message'] as String? ?? 'Upload request failed';
        completer.completeError(Exception(msg));
      }
    });

    // Timeout guard — if server never responds, unblock the caller
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.completeError(Exception('FILE_UPLOAD_RESP timeout'));
      }
    });

    return completer.future;
  }

  Future<void> _waitForDownloadResp(String requestId, String token) {
    final completer = Completer<void>();

    late StreamSubscription sub;
    sub = _tcpClient.packetStream.listen((packet) {
      final type = packet['type'] as String?;
      final id = packet['id']?.toString();

      if (id != requestId) return;

      if (type == 'FILE_DOWNLOAD_RESP') {
        sub.cancel();
        completer.complete();
      } else if (type == 'SYS_ERROR') {
        sub.cancel();
        final msg = packet['data']?['message'] as String? ?? 'Download request failed';
        completer.completeError(Exception(msg));
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.completeError(Exception('FILE_DOWNLOAD_RESP timeout'));
      }
    });

    return completer.future;
  }
}
