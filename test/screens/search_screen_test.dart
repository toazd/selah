import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selah/data/bible_data_strongs.dart';
import 'package:selah/screens/search_screen.dart';
import 'package:selah/utils/verse_text_parser.dart';
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

Future<void> _waitForHighlightedText(
  WidgetTester tester,
  String needle, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_hasHighlightedText(tester, needle)) return;

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }

  fail('Timed out waiting for highlighted "$needle"');
}

Future<void> _pumpSearchScreenWithOptions(
  WidgetTester tester, {
  bool wholeWord = false,
  bool caseSensitive = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'searchWholeWord': wholeWord,
    'searchCaseSensitive': caseSensitive,
  });

  await tester.pumpWidget(
    MaterialApp(
      home: SearchScreen(key: UniqueKey()),
    ),
  );
  await tester.pump();
}

Finder _searchFieldFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Search the Holy Bible',
  );
}

bool _hasHighlightedText(WidgetTester tester, String needle) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .any((richText) => _spanHasHighlightedText(richText.text, needle));
}

bool _spanHasHighlightedText(InlineSpan span, String needle) {
  final plainText = StringBuffer();
  final highlighted = <bool>[];

  void visit(InlineSpan span, {bool parentHighlighted = false}) {
    if (span is! TextSpan) return;

    final isHighlighted =
        parentHighlighted || span.style?.backgroundColor != null;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      plainText.write(text);
      highlighted.addAll(List<bool>.filled(text.length, isHighlighted));
    }

    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, parentHighlighted: isHighlighted);
    }
  }

  visit(span);

  final haystack = plainText.toString();
  final lowerHaystack = haystack.toLowerCase();
  final lowerNeedle = needle.toLowerCase();
  var index = lowerHaystack.indexOf(lowerNeedle);

  while (index != -1) {
    final end = index + needle.length;
    var allHighlighted = true;
    for (var i = index; i < end; i++) {
      if (haystack[i].trim().isEmpty) continue;
      if (!highlighted[i]) {
        allHighlighted = false;
        break;
      }
    }
    if (allHighlighted) return true;
    index = lowerHaystack.indexOf(lowerNeedle, index + 1);
  }

  return false;
}

({int matches, int verses, List<String> refs}) _auditPhraseMatches(
  String phrase, {
  required bool wholeWord,
  required bool caseSensitive,
}) {
  final escapedPhrase = RegExp.escape(phrase);
  final pattern = wholeWord ? '\\b($escapedPhrase)\\b' : '($escapedPhrase)';
  final regex = RegExp(pattern, caseSensitive: caseSensitive);
  var matchCount = 0;
  var verseCount = 0;
  final refs = <String>[];

  for (final bookEntry in bibleDataStrongs.entries) {
    for (final chapterEntry in bookEntry.value.entries) {
      for (final verseEntry in chapterEntry.value.entries) {
        var searchText = VerseTextParser.toPlainVerseText(
          verseEntry.value,
          removePilcrow: false,
        );
        if (searchText.contains('¶ ')) {
          searchText = searchText.replaceAll('¶ ', '');
        }

        final matches = regex.allMatches(searchText).length;
        if (matches == 0) continue;

        matchCount += matches;
        verseCount++;
        refs.add('${bookEntry.key} ${chapterEntry.key}:${verseEntry.key}');
      }
    }
  }

  return (matches: matchCount, verses: verseCount, refs: refs);
}

void main() {
  test('word of the LORD phrase counts match cleaned text boundaries', () {
    final defaultResult = _auditPhraseMatches(
      'word of the LORD',
      wholeWord: false,
      caseSensitive: false,
    );
    final wholeWordResult = _auditPhraseMatches(
      'word of the LORD',
      wholeWord: true,
      caseSensitive: false,
    );
    final wholeWordCaseSensitiveResult = _auditPhraseMatches(
      'word of the LORD',
      wholeWord: true,
      caseSensitive: true,
    );

    expect(defaultResult.matches, 264);
    expect(defaultResult.verses, 261);
    expect(wholeWordResult.matches, 258);
    expect(wholeWordResult.verses, 255);
    expect(wholeWordCaseSensitiveResult.matches, 242);
    expect(wholeWordCaseSensitiveResult.verses, 239);

    expect(defaultResult.refs, contains('Jdg 7:18'));
    expect(wholeWordResult.refs, isNot(contains('Jdg 7:18')));
  });

  testWidgets('word of the LORD phrase counts match the search UI',
      (tester) async {
    await _pumpSearchScreenWithOptions(tester);

    await tester.enterText(_searchFieldFinder(), '"word of the LORD"');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('264 matches in 261 verses'));

    await _pumpSearchScreenWithOptions(tester, wholeWord: true);

    await tester.enterText(_searchFieldFinder(), '"word of the LORD"');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('258 matches in 255 verses'));

    await _pumpSearchScreenWithOptions(
      tester,
      wholeWord: true,
      caseSensitive: true,
    );

    await tester.enterText(_searchFieldFinder(), '"word of the LORD"');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('242 matches in 239 verses'));
  });

  testWidgets('quoted phrase search matches Strong-tagged visible text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    final searchField = _searchFieldFinder();

    await tester.enterText(searchField, '"second year of darius"');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('5 matches in 5 verses'));
    expect(_hasHighlightedText(tester, 'second year of Darius'), isTrue);
  });

  testWidgets(
      'regex phrase search highlights across Strong-tagged visible text',
      (tester) async {
    SharedPreferences.setMockInitialValues({'searchRegex': true});

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    final searchField = _searchFieldFinder();

    await tester.enterText(searchField, r'second\s+year\s+of\s+Darius');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('5 matches in 5 verses'));
    expect(_hasHighlightedText(tester, 'second year of Darius'), isTrue);
  });

  testWidgets('default search does not match Strong numbers', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    final searchField = _searchFieldFinder();

    await tester.enterText(searchField, 'H1867');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('0 matches in 0 verses'));
  });

  testWidgets('nearby search does not match Strong numbers', (tester) async {
    SharedPreferences.setMockInitialValues({'searchNearby': true});

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    final searchField = _searchFieldFinder();

    await tester.enterText(searchField, 'H1867 Darius');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForFinder(tester, find.text('0 matches in 0 verses'));
  });

  testWidgets('nearby search highlights keywords after Strong tags are ignored',
      (tester) async {
    SharedPreferences.setMockInitialValues({'searchNearby': true});

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    final searchField = _searchFieldFinder();

    await tester.enterText(searchField, 'God darkness');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pump();

    await _waitForHighlightedText(tester, 'God');
    expect(_hasHighlightedText(tester, 'darkness'), isTrue);
  });
}
