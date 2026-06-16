import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selah/screens/strongs_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }

  fail('Timed out waiting for $finder');
}

void main() {
  testWidgets('ambassage word search completes with two Strong results',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: StrongsSearchScreen(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ambassage');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('2 matches in 2 verses'));

    expect(find.textContaining('Maximum search time exceeded'), findsNothing);
  });
}
