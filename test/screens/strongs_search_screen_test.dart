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

Future<void> _pumpUntilFinder(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 12,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (finder.evaluate().isNotEmpty) return;
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

  testWidgets('reference search completes through the Strong worker',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: StrongsSearchScreen(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Gen 2:15 garden');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('Phrase Summary'));

    expect(find.textContaining('Maximum search time exceeded'), findsNothing);
  });

  testWidgets('manual search shows inline busy state before direct search',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: StrongsSearchScreen(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'G2411');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    expect(find.text('Searching...'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await _waitForFinder(tester, find.text('Phrase Summary'));
  });

  testWidgets('saved search shows restoring state before replaying results',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'lastStrongsSearchTerm': 'G2411',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: StrongsSearchScreen(),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Restoring search results...'), findsNothing);
    expect(find.text('Phrase Summary'), findsNothing);

    await _pumpUntilFinder(tester, find.text('Restoring search results...'));

    expect(find.text('Restoring search results...'), findsOneWidget);
    expect(find.text('Phrase Summary'), findsNothing);

    await _waitForFinder(tester, find.text('Phrase Summary'));
  });

  testWidgets('saved search waits for route transition before restoring',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'lastStrongsSearchTerm': 'G2411',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const StrongsSearchScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                ),
              );
            },
            child: const Text('Open Strong Search'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Strong Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Restoring search results...'), findsNothing);
    expect(find.text('Phrase Summary'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await _pumpUntilFinder(tester, find.text('Restoring search results...'));

    expect(find.text('Phrase Summary'), findsNothing);

    await _waitForFinder(tester, find.text('Phrase Summary'));
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
