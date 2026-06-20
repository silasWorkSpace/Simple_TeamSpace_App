import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecordingService {
  final AudioRecorder _record = AudioRecorder();
  String? _currentPath;
  DateTime? _startTime;

  Future<void> startRecording() async {
    if (await _record.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      _currentPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _startTime = DateTime.now();

      await _record.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: _currentPath!,
      );
    } else {
      throw Exception('Microphone permission denied.');
    }
  }

  /// Returns a tuple of (File, duration_ms) if successful, or null if failed/cancelled.
  Future<(File, int)?> stopRecording() async {
    final path = await _record.stop();
    if (path != null && _currentPath != null && _startTime != null) {
      final durationMs = DateTime.now().difference(_startTime!).inMilliseconds;
      return (File(path), durationMs);
    }
    return null;
  }

  Future<void> cancelRecording() async {
    final path = await _record.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentPath = null;
    _startTime = null;
  }

  Future<void> dispose() async {
    await _record.dispose();
  }
}
