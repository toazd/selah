import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('phrase summary does not wrap when the phrase has enough width',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: StrongsSearchScreen(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'G2411');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('Phrase Summary'));
    await _waitForFinder(tester, find.text('that the temple'));

    final phraseFinder = find.text('that the temple');
    final renderParagraph = tester.renderObject<RenderParagraph>(phraseFinder);
    final lineBoxes = renderParagraph.getBoxesForSelection(
      const TextSelection(
          baseOffset: 0, extentOffset: 'that the temple'.length),
    );
    final phraseText = tester.widget<Text>(phraseFinder);
    final phraseContext = tester.element(phraseFinder);
    final rawTextPainter = TextPainter(
      text: TextSpan(text: 'that the temple', style: phraseText.style),
      textDirection: Directionality.of(phraseContext),
      textScaler: MediaQuery.textScalerOf(phraseContext),
    )..layout();

    expect(lineBoxes, hasLength(1));
    expect(renderParagraph.size.width,
        greaterThanOrEqualTo(rawTextPainter.width.ceilToDouble() + 3.0));
  });

  testWidgets('phrase summary wraps when the phrase is width constrained',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: StrongsSearchScreen(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'G2411');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('Phrase Summary'));
    await _waitForFinder(tester, find.text('that the temple'));

    final phraseFinder = find.text('that the temple');
    final renderParagraph = tester.renderObject<RenderParagraph>(phraseFinder);
    final lineBoxes = renderParagraph.getBoxesForSelection(
      const TextSelection(
          baseOffset: 0, extentOffset: 'that the temple'.length),
    );

    expect(lineBoxes.length, greaterThan(1));
  });
}
