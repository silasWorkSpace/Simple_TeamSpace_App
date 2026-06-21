import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  testWidgets('Find m4a files', (WidgetTester tester) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      print('Documents Directory: ${dir.path}');
      
      final files = dir.listSync().where((e) => e.path.endsWith('.m4a'));
      for (final f in files) {
        print('Found: ${f.path}');
        final file = File(f.path);
        print('Size: ${await file.length()} bytes');
      }
    } catch (e) {
      print('Error: $e');
    }
  });
}
