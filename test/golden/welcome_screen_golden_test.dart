import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weldqai_app/features/welcome/welcome_screen.dart';

void main() {
  testWidgets(
    'WelcomeScreen golden',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(),
        ),
      );

      await expectLater(
        find.byType(WelcomeScreen),
        matchesGoldenFile('welcome_screen.png'),
      );
    },
    // Golden file does not exist yet.
    // Generate it with: flutter test --update-goldens test/golden/
    skip: true,
  );
}
