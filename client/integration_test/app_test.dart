import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:last_project_client/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end login flow audit', (WidgetTester tester) async {
    // Start the app
    app.main();
    await tester.pumpAndSettle();

    // Enter credentials
    await tester.enterText(find.byType(TextFormField).at(0), '0987654321');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.pumpAndSettle();

    // Tap Register (go to register screen)
    await tester.tap(find.text("Don't have an account? Register"));
    await tester.pumpAndSettle();

    // Enter registration details
    final ts = DateTime.now().millisecondsSinceEpoch;
    await tester.enterText(find.byType(TextFormField).at(0), '0987654321_$ts');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'Test User $ts');
    await tester.pumpAndSettle();

    // Tap Register
    await tester.tap(find.byType(ElevatedButton));
    
    // Pump frames to let network and UI run
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    
    // Tap Logout if we made it to the main layout
    if (find.byIcon(Icons.logout).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.logout));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      
      // Login AGAIN
      await tester.enterText(find.byType(TextFormField).at(0), '0987654321_$ts');
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.byType(ElevatedButton));
      
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    
    fail("DUMP LOGS");
  });
}
