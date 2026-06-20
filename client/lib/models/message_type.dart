/// Defines every message type the application supports.
///
/// Kept as a top-level class of string constants rather than an enum so that
/// unknown types from future server versions degrade gracefully to [unknown]
/// without throwing a parse error.
class MessageType {
  const MessageType._();

  static const String text = 'text';
  static const String image = 'image';
  static const String file = 'file';
  static const String sticker = 'sticker';
  static const String voice = 'voice';

  /// Fallback for any server-defined type not yet handled on the client.
  static const String unknown = 'unknown';

  /// All types that should render as inline media (not a bubble).
  static const Set<String> inlineMedia = {image, sticker};

  /// All types that require a secondary data-socket download.
  static const Set<String> requiresDownload = {image, file, voice};
}
