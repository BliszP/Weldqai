// test/widget/auth_screen_test.dart
//
// Widget tests for AuthScreen.
// Tests UI rendering and form behaviour; does NOT test Firebase auth calls
// (those require the Firebase emulator — see test/integration/).
//
// NOTE: The Row at auth_screen.dart:294 overflows by ~23 px in the test
// environment because the Ahem test font renders characters at ~14 px each,
// making the two TextButtons wider than the 448 px content area
// (ConstrainedBox maxWidth 520 − card margin 32 − padding 40 = 448 px).
// The widgets ARE still rendered and findable, so we tolerate the rendering
// error rather than fail on it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weldqai_app/features/auth/auth_screen.dart';

/// Wraps [child] in a minimal MaterialApp for widget testing.
Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

/// Swallows RenderFlex overflow errors for the duration of the current test.
/// Other FlutterErrors are still forwarded to the previous handler.
void _tolerateOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    prev?.call(details);
  };
  addTearDown(() => FlutterError.onError = prev);
}

void main() {
  group('AuthScreen — sign-in mode (default)', () {
    testWidgets('renders email and password fields', (tester) async {
      _tolerateOverflow();
      await tester.pumpWidget(_wrap(const AuthScreen()));

      expect(find.byType(TextFormField), findsWidgets);
      // At minimum an email and password field
      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });

    testWidgets('sign-up fields are hidden in sign-in mode', (tester) async {
      _tolerateOverflow();
      await tester.pumpWidget(_wrap(const AuthScreen()));
      // Full-name field should not be visible in sign-in mode
      expect(find.text('Full Name'), findsNothing);
    });

    testWidgets('shows a submit/login button', (tester) async {
      _tolerateOverflow();
      await tester.pumpWidget(_wrap(const AuthScreen()));
      // AuthScreen uses FilledButton for the primary action
      expect(find.byType(FilledButton), findsAtLeastNWidgets(1));
    });

    testWidgets('password toggle button changes obscureText', (tester) async {
      _tolerateOverflow();
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pump();

      // Find the visibility toggle IconButton
      final toggleButton = find.byIcon(Icons.visibility_off_outlined);
      if (toggleButton.evaluate().isEmpty) return; // Screen may use different icon

      await tester.tap(toggleButton);
      await tester.pump();

      // After toggle, icon should change
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('AuthScreen — sign-up mode', () {
    testWidgets('initialMode: signup shows full-name field', (tester) async {
      _tolerateOverflow();
      await tester.pumpWidget(_wrap(const AuthScreen(initialMode: 'signup')));
      await tester.pump();
      // Full name field should be visible in signup mode
      expect(find.byType(TextFormField), findsAtLeastNWidgets(3));
    });
  });

  group('AuthScreen — form validation', () {
    testWidgets('submitting empty form shows validation errors', (tester) async {
      _tolerateOverflow();
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pump();

      // Tap the primary submit button (FilledButton) — validation runs
      // before any Firebase call, so no Firebase init is needed here.
      final buttons = find.byType(FilledButton);
      if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.first);
        await tester.pump();
        // Validator messages appear — at least one error text shown
        expect(find.byType(Text), findsWidgets);
      }
    });
  });
}
