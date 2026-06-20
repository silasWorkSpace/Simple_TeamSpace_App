import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:last_project_client/core/app_constants.dart';

/// Handles all raw binary I/O on the secondary data port.
///
/// Responsibilities:
/// - Uploading a [File] to the server data socket with progress reporting.
/// - Downloading bytes by token from the server data socket with progress reporting.
///
/// Protocol (matches server data_server.py):
///   First byte : 'U' (upload) or 'D' (download)   — 1 byte ASCII
///   Next 36 bytes: UUID token                       — 36 bytes ASCII
///   Remaining  : raw file bytes (upload only)
///
/// Images under [AppConstants.maxInlineImageBytes] are returned as [Uint8List].
/// All other downloads are streamed directly to disk and return a [File].
class DataSocketClient {
  final String host;

  const DataSocketClient({required this.host});

  /// Uploads [file] to the server using [token].
  ///
  /// [onProgress] receives values from 0.0 to 1.0.
  /// Throws on socket or IO failure.
  Future<void> upload({
    required File file,
    required String token,
    void Function(double progress)? onProgress,
  }) async {
    final socket = await Socket.connect(
      host,
      AppConstants.dataPort,
      timeout: const Duration(seconds: 10),
    );

    try {
      // Protocol header: direction byte + token
      socket.add([_kUpload]);
      socket.add(token.codeUnits);

      final totalBytes = await file.length();
      int sent = 0;

      await for (final chunk in file.openRead()) {
        socket.add(chunk);
        sent += chunk.length;
        if (onProgress != null && totalBytes > 0) {
          onProgress(sent / totalBytes);
        }
      }

      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Downloads the file identified by [token] from the server.
  ///
  /// If the file size declared in [expectedBytes] is ≤ [AppConstants.maxInlineImageBytes],
  /// the bytes are buffered in memory and returned as [Uint8List] via [onBytesReady].
  ///
  /// Otherwise the bytes are streamed to [savePath] on disk and returned via [onFileReady].
  ///
  /// Exactly one of the two callbacks will be invoked on success.
  /// [onProgress] receives values from 0.0 to 1.0.
  Future<void> download({
    required String token,
    required int expectedBytes,
    required String savePath,
    void Function(double progress)? onProgress,
    void Function(Uint8List bytes)? onBytesReady,
    void Function(File file)? onFileReady,
  }) async {
    final socket = await Socket.connect(
      host,
      AppConstants.dataPort,
      timeout: const Duration(seconds: 10),
    );

    try {
      // Protocol header: direction byte + token
      socket.add([_kDownload]);
      socket.add(token.codeUnits);
      await socket.flush();

      final bool inlineMode = expectedBytes <= AppConstants.maxInlineImageBytes;

      if (inlineMode) {
        await _downloadToMemory(
          socket: socket,
          expectedBytes: expectedBytes,
          onProgress: onProgress,
          onBytesReady: onBytesReady,
        );
      } else {
        await _downloadToDisk(
          socket: socket,
          expectedBytes: expectedBytes,
          savePath: savePath,
          onProgress: onProgress,
          onFileReady: onFileReady,
        );
      }
    } finally {
      await socket.close();
    }
  }

  Future<void> _downloadToMemory({
    required Socket socket,
    required int expectedBytes,
    void Function(double)? onProgress,
    void Function(Uint8List)? onBytesReady,
  }) async {
    final builder = BytesBuilder(copy: false);
    int received = 0;

    await for (final chunk in socket) {
      builder.add(chunk);
      received += chunk.length;
      if (onProgress != null && expectedBytes > 0) {
        onProgress((received / expectedBytes).clamp(0.0, 1.0));
      }
    }

    onBytesReady?.call(builder.toBytes());
  }

  Future<void> _downloadToDisk({
    required Socket socket,
    required int expectedBytes,
    required String savePath,
    void Function(double)? onProgress,
    void Function(File)? onFileReady,
  }) async {
    final file = File(savePath);
    final sink = file.openWrite();
    int received = 0;

    try {
      await for (final chunk in socket) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && expectedBytes > 0) {
          onProgress((received / expectedBytes).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    onFileReady?.call(file);
  }

  static const int _kUpload = 0x55;   // ASCII 'U'
  static const int _kDownload = 0x44; // ASCII 'D'
}
