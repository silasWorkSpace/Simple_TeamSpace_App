/// Holds optional metadata attached to non-text messages.
///
/// For [MessageType.file] and [MessageType.image]:
///   - [filename] is the original file name with extension.
///   - [sizeBytes] is the declared byte count (used for display and progress).
///
/// For [MessageType.sticker]:
///   - [stickerId] is the asset key (e.g. 'sticker_01').
///
///   - [durationMs] is the length of the voice recording in milliseconds.
///   - [codec] is the audio format (e.g. 'm4a').
///
/// All fields are nullable so a single model covers every current and future type.
class MessageMetadata {
  final String? filename;
  final int? sizeBytes;
  final String? stickerId;
  final int? durationMs;
  final String? codec;

  /// Open-ended escape hatch for future message types.
  /// Any unrecognized server field lands here without a model refactor.
  final Map<String, dynamic> extra;

  const MessageMetadata({
    this.filename,
    this.sizeBytes,
    this.stickerId,
    this.durationMs,
    this.codec,
    this.extra = const {},
  });

  factory MessageMetadata.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MessageMetadata();

    // Known fields parsed explicitly; everything else goes into extra.
    const knownKeys = {'filename', 'size_bytes', 'sticker_id', 'duration_ms', 'codec'};
    final extraFields = {
      for (final e in json.entries)
        if (!knownKeys.contains(e.key)) e.key: e.value,
    };

    return MessageMetadata(
      filename: json['filename'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      stickerId: json['sticker_id'] as String?,
      durationMs: json['duration_ms'] as int?,
      codec: json['codec'] as String?,
      extra: extraFields,
    );
  }

  Map<String, dynamic> toJson() => {
    if (filename != null) 'filename': filename,
    if (sizeBytes != null) 'size_bytes': sizeBytes,
    if (stickerId != null) 'sticker_id': stickerId,
    if (durationMs != null) 'duration_ms': durationMs,
    if (codec != null) 'codec': codec,
    ...extra,
  };

  @override
  String toString() =>
      'MessageMetadata(filename: $filename, sizeBytes: $sizeBytes, '
      'stickerId: $stickerId, durationMs: $durationMs, codec: $codec, extra: $extra)';
}
