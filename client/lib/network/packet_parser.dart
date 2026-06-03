import 'dart:convert';
import 'package:last_project_client/models/user_model.dart';

class PacketParser {
  /// Version of the protocol.
  static const String version = "1.0";

  /// Converts an object to a JSON string.
  static String encode(String type, Map<String, dynamic> data, {String? id}) {
    return jsonEncode({
      "v": version,
      "id": id ?? "client-id",
      "type": type,
      "data": data,
    });
  }

  /// Converts a JSON string to a Map.
  static Map<String, dynamic> decode(String raw) {
    return jsonDecode(raw);
  }
}
