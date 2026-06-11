import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import '../database/strongs_database.dart';
import '../database/strongs_definitions_database.dart';
import '../data/strongs_definitions.dart';
import '../database/history_database.dart';
import '../utils/error_handler.dart';
import '../main.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';
import '../utils/book_name_converter.dart';
import '../utils/bible_utils.dart';
import '../utils/verse_reference_detector.dart';
import '../screens/chapter_dialog.dart';
import '../screens/note_screen.dart';

// Top-level functions for compute() to enable off-main-thread execution
Future<List<Map<String, dynamic>>> _computeStrongsNumberSearch(
    String strongsNumber) async {
  return StrongsDatabase.searchByStrongsNumber(strongsNumber);
}

Future<List<Map<String, dynamic>>> _computeWordSearch(String word) async {
  return StrongsDatabase.searchByWord(word);
}

Future<Map<String, Map<String, dynamic>>> _computeFindStrongsNumbers(
    SearchTaskData data) async {
  return StrongsDatabase.findStrongsNumbersForWord(data.word, data.wordVerses);
}

Future<List<Map<String, dynamic>>> _computeSearchByStrongsNumbers(
    SearchTaskData data) async {
  return StrongsDatabase.searchByStrongsNumbers(data.strongsList);
}

Future<Map<String, int>> _computeExtractPhraseSummary(
    SummaryTaskData data) async {
  return StrongsDatabase.extractPhraseSummary(data.results, data.strongsList);
}

Future<ReferenceSearchResult> _computeReferenceSearch(
    ReferenceSearchTaskData data) async {
  // Validate book, chapter, verse
  final availableBooks = StrongsDatabase.getAvailableBooks();
  if (!availableBooks.contains(data.book)) {
    return ReferenceSearchResult(error: 'Invalid book: ${data.book}');
  }

  final availableChapters = StrongsDatabase.getAvailableChapters(data.book);
  if (!availableChapters.contains(data.chapter)) {
    return ReferenceSearchResult(
        error: 'Invalid chapter ${data.chapter} for ${data.book}');
  }

  final availableVerses =
      StrongsDatabase.getAvailableVerses(data.book, data.chapter);
  if (!availableVerses.contains(data.verse)) {
    return ReferenceSearchResult(
        error: 'Invalid verse ${data.verse} for ${data.book} ${data.chapter}');
  }

  // Check if word exists in verse
  if (!StrongsDatabase.wordExistsInVerse(
      data.book, data.chapter, data.verse, data.word)) {
    return ReferenceSearchResult(
        error:
            'Word "${data.word}" not found in ${data.book} ${data.chapter}:${data.verse}');
  }

  // Get Strong's numbers for the word in this verse
  final strongsNumbers = StrongsDatabase.findStrongsNumbersForWordInVerse(
      data.book, data.chapter, data.verse, data.word);

  if (strongsNumbers.isEmpty) {
    return ReferenceSearchResult(
        error:
            'No Strong\'s numbers found for "${data.word}" in ${data.book} ${data.chapter}:${data.verse}');
  }

  // Get the verse text
  final verseText =
      StrongsDatabase.getVerseText(data.book, data.chapter, data.verse);

  return ReferenceSearchResult(
    strongsNumbers: strongsNumbers,
    verseText: verseText,
    book: data.book,
    chapter: data.chapter,
    verse: data.verse,
    word: data.word,
  );
}

// Helper data classes for passing data to compute()
class SearchTaskData {
  final String word;
  final List<Map<String, dynamic>> wordVerses;
  final List<String> strongsList;

  SearchTaskData({
    required this.word,
    required this.wordVerses,
    required this.strongsList,
  });
}

class SummaryTaskData {
  final List<Map<String, dynamic>> results;
  final List<String> strongsList;

  SummaryTaskData({
    required this.results,
    required this.strongsList,
  });
}

class ReferenceSearchTaskData {
  final String book;
  final int chapter;
  final int verse;
  final String word;

  ReferenceSearchTaskData({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.word,
  });
}

class ReferenceSearchResult {
  final List<String>? strongsNumbers;
  final String? verseText;
  final String? book;
  final int? chapter;
  final int? verse;
  final String? word;
  final String? error;

  ReferenceSearchResult({
    this.strongsNumbers,
    this.verseText,
    this.book,
    this.chapter,
    this.verse,
    this.word,
    this.error,
  });
}

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor) {
  final hsl = HSLColor.fromColor(backgroundColor);
  final adjustedLightness = hsl.lightness > 0.5
      ? (hsl.lightness - 0.03).clamp(0.0, 1.0)
      : (hsl.lightness + 0.03).clamp(0.0, 1.0);
  return hsl.withLightness(adjustedLightness).toColor();
}

final RegExp _definitionStrongsNumberPattern = RegExp(r'[GH]\d{1,4}');

typedef _DefinitionWidgetsBuilder = List<Widget> Function(
  BuildContext context,
  String definition, {
  void Function(String strongsNumber)? onStrongsTap,
});

typedef _TextStyleBuilder = TextStyle Function(
    BuildContext context, double fontSize);

class StrongsSearchScreen extends StatefulWidget {
  final int? sourceScreenIndex;

  const StrongsSearchScreen({
    super.key,
    this.sourceScreenIndex,
  });

  @override
  State<StrongsSearchScreen> createState() => _StrongsSearchScreenState();
}

class _StrongsSearchScreenState extends State<StrongsSearchScreen>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchButtonFocusNode = FocusNode();
  final ScrollController _resultsScrollController = ScrollController();
  final List<TapGestureRecognizer> _verseReferenceRecognizers = [];

  bool _isResetting = false;
  bool _isRestoring = false;
  int _verseReferenceRecognizerIndex = 0;
  int? _verseReferenceRecognizerCleanupExpectedCount;

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, Map<String, dynamic>> _foundStrongsNumbers = {};
  Map<String, int> _phraseSummary = {};
  int? _totalMatches;
  int? _totalVerses;
  String? _searchType;
  String? _searchTerm;
  bool _isLoadingDialogVisible = false;

  static const String _lastSearchTermKey = 'lastStrongsSearchTerm';
  static const String _scrollOffsetKey = 'strongsSearchScrollOffset';

  @override
  bool get wantKeepAlive => true;

  void _showLoadingDialog() {
    _isLoadingDialogVisible = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    showDialog(
      animationStyle: AnimationStyle(duration: Duration(seconds: 0)),
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              padding: EdgeInsetsGeometry.all(0),
              constraints: BoxConstraints.tight(Size(72, 72)),
              strokeWidth: 7.0,
              semanticsLabel: "Searching",
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Searching...',
              style: TextStyle(
                fontSize: uiFontSize + 4,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideLoadingDialog() {
    if (_isLoadingDialogVisible && mounted && Navigator.canPop(context)) {
      _isLoadingDialogVisible = false;
      Navigator.pop(context);
    }
  }

  /// Attempts to parse a reference search (e.g., "Gen 2:15 garden")
  /// Returns a ReferenceSearchTaskData if valid, null otherwise
  ReferenceSearchTaskData? _parseReferenceSearch(String input) {
    // Pattern: Book Chapter:Verse Word
    // Examples: Gen 2:15 garden, Mat 5:7 merciful
    final pattern = RegExp(r'^([A-Za-z0-9]+)\s+(\d+):(\d+)\s+(\w+)$');
    final match = pattern.firstMatch(input.trim());
    if (match == null) return null;

    final bookInput = match.group(1)!;
    final chapterStr = match.group(2)!;
    final verseStr = match.group(3)!;
    final word = match.group(4)!;

    // Normalize the book name to support case-insensitive and both short/long names
    final normalizedBook = BookNameConverter.normalizeBookName(bookInput);

    final chapter = int.tryParse(chapterStr);
    final verse = int.tryParse(verseStr);

    if (chapter == null || verse == null) return null;

    return ReferenceSearchTaskData(
      book: normalizedBook,
      chapter: chapter,
      verse: verse,
      word: word,
    );
  }

  void _showHelpDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // insetPadding: EdgeInsets.all(0.0),
        // contentPadding: EdgeInsets.all(16.0),
        // actionsPadding: EdgeInsets.all(0.0),
        // titlePadding: EdgeInsets.all(0.0),
        backgroundColor: bgColor,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text(
              //   'Strong\'s Search',
              //   style: TextStyle(
              //       fontWeight: FontWeight.bold,
              //       fontSize: uiFontSize,
              //       fontFamily: uiFontFamily,
              //       color: getAdaptiveTextColor(context)),
              // ),
              // const SizedBox(height: 8),
              Text('You can search three ways:\n',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              Text(
                  '1. Word search - Enter a single word (e.g. "covenant") to find all Strong\'s numbers associated with that word and all verses containing them.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '    Note: Word search only supports single words. Additional words after the first will be ignored.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      fontStyle: FontStyle.italic,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '2. Strong\'s number search - Enter a Strong\'s number (e.g. H1285 or G1242) to find all verses containing that specific Strong\'s number.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '3. Reference search - Enter a verse reference with a word (e.g. "Gen 2:15 garden") to find the Strong\'s number(s) for that specific word and then show all the verses where that Strong\'s number appears.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '    When appropriate, a phrase summary will be generated from every verse where the Strong\'s number(s) appear. The second column represents the number of times that phrase appears in the verse results.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      fontStyle: FontStyle.italic,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '4. Definitions lookup - Tap the book icon in the toolbar to look up a Strong\'s number definition without running a search.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
            ],
          ),
        ),
        actions: [
          TextButton(
              child: Text('Close',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  void _onSearch({bool showLoading = true, bool resetScroll = true}) {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() {
        _searchResults = [];
        _foundStrongsNumbers = {};
        _phraseSummary = {};
        _totalMatches = 0;
        _totalVerses = 0;
        _searchType = null;
        _searchTerm = null;
      });
      _persistSearchState('');
      return;
    }

    setState(() {
      _searchResults = [];
      _foundStrongsNumbers = {};
      _phraseSummary = {};
      _totalMatches = null;
      _totalVerses = null;
      _searchTerm = input;
    });

    _persistSearchState(input);

    if (resetScroll && _resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0.0);
    }

    if (showLoading) {
      _showLoadingDialog();
    }

    // Try to parse as reference search first (e.g., "Gen 2:15 garden")
    final referenceSearch = _parseReferenceSearch(input);
    if (referenceSearch != null) {
      _performReferenceSearch(referenceSearch);
      return;
    }

    // Try to parse as Strong's number (e.g., "H1234")
    final words =
        input.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    String searchTerm = words[0];

    if (words.length > 1) {
      showStyledSnackBar(context,
          'Strong\'s search only supports single words. Extra words were ignored.');
    }

    final strongsNumber = StrongsDatabase.validateStrongsNumber(searchTerm);

    Future.microtask(() {
      if (strongsNumber != null) {
        _performStrongsNumberSearch(strongsNumber);
      } else {
        _performWordSearch(searchTerm);
      }
    });
  }

  void _performStrongsNumberSearch(String strongsNumber) async {
    _unfocusSearchField(); // Don't wait or it flashes for a split second
    try {
      final results = await compute(_computeStrongsNumberSearch, strongsNumber);
      if (!mounted) return;
      if (_isResetting) return;

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'strongs';
          _isRestoring = false;
        });
        _hideLoadingDialog();
        return;
      }

      final phraseSummary =
          StrongsDatabase.extractPhraseSummary(results, [strongsNumber]);
      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _foundStrongsNumbers = {};
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'strongs';
        _isRestoring = false;
      });
      _hideLoadingDialog();
    } catch (e) {
      if (mounted) {
        if (!_isResetting) {
          setState(() {
            _isRestoring = false;
          });
          _hideLoadingDialog();
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  void _performWordSearch(String word) async {
    _unfocusSearchField(); // Don't wait or it flashes for a split second
    try {
      final wordVerses = await compute(_computeWordSearch, word);
      if (!mounted) return;
      if (_isResetting) return;

      if (wordVerses.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'word';
          _isRestoring = false;
        });
        _hideLoadingDialog();
        return;
      }

      final findStrongsData = SearchTaskData(
        word: word,
        wordVerses: wordVerses,
        strongsList: [],
      );
      final foundStrongs =
          await compute(_computeFindStrongsNumbers, findStrongsData);
      if (!mounted) return;
      if (_isResetting) return;

      if (foundStrongs.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'word';
          _isRestoring = false;
        });
        _hideLoadingDialog();
        return;
      }

      final strongsList = foundStrongs.keys.toList();
      final searchData = SearchTaskData(
        word: word,
        wordVerses: wordVerses,
        strongsList: strongsList,
      );
      final results = await compute(_computeSearchByStrongsNumbers, searchData);
      if (!mounted) return;
      if (_isResetting) return;

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = foundStrongs;
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'word';
          _isRestoring = false;
        });
        _hideLoadingDialog();
        return;
      }

      final summaryData = SummaryTaskData(
        results: results,
        strongsList: strongsList,
      );
      final phraseSummary =
          await compute(_computeExtractPhraseSummary, summaryData);
      if (!mounted) return;
      if (_isResetting) return;

      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _foundStrongsNumbers = foundStrongs;
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'word';
        _isRestoring = false;
      });
      _hideLoadingDialog();
    } catch (e) {
      if (mounted) {
        if (!_isResetting) {
          setState(() {
            _isRestoring = false;
          });
          _hideLoadingDialog();
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _performReferenceSearch(
      ReferenceSearchTaskData refSearch) async {
    _unfocusSearchField();
    try {
      final result = await compute(_computeReferenceSearch, refSearch);
      if (!mounted) return;
      if (_isResetting) return;

      // Check for errors
      if (result.error != null) {
        _hideLoadingDialog();
        showStyledSnackBar(context, result.error!);
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'reference';
          _isRestoring = false;
        });
        return;
      }

      final strongsNumbers = result.strongsNumbers!;

      final foundStrongs = <String, Map<String, dynamic>>{};
      for (final sn in strongsNumbers) {
        foundStrongs[sn] = {
          'book': result.book!,
          'chapter': result.chapter!,
          'verse': result.verse!,
        };
      }

      setState(() {
        _foundStrongsNumbers = foundStrongs;
      });

      // Search the entire bible for all these Strong's numbers
      final searchData = SearchTaskData(
        word: result.word!,
        wordVerses: [],
        strongsList: strongsNumbers,
      );
      final results = await compute(_computeSearchByStrongsNumbers, searchData);
      if (!mounted) return;
      if (_isResetting) return;

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'reference';
          _isRestoring = false;
        });
        _hideLoadingDialog();
        return;
      }

      final summaryData = SummaryTaskData(
        results: results,
        strongsList: strongsNumbers,
      );
      final phraseSummary =
          await compute(_computeExtractPhraseSummary, summaryData);
      if (!mounted) return;
      if (_isResetting) return;

      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'reference';
        _isRestoring = false;
      });
      _hideLoadingDialog();
    } catch (e) {
      if (mounted) {
        if (!_isResetting) {
          setState(() {
            _isRestoring = false;
          });
          _hideLoadingDialog();
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  Color _getHighlightColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkHighlightColor.value
        : lightHighlightColor.value;
  }

  void _showStrongsDefinitionDialog(
      BuildContext context, String strongsNumber) {
    final definition = StrongsDefinitionsDatabase.getDefinition(strongsNumber);
    if (!mounted || definition == null) {
      if (mounted) {
        showStyledSnackBar(context,
            'Definition not found for $strongsNumber!\nThis is a bug that you should report at https://github.com/toazd/selah/issues.',
            isError: true);
      }
      return;
    }

    final definitionChildren = _buildDefinitionWidgets(context, definition);

    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final maxWidth = MediaQuery.of(context).size.width * 0.9;
    final constrainedMaxWidth = isMobile
        ? MediaQuery.of(context).size.width
        : (maxWidth > 720.0 ? 720.0 : maxWidth);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0)
              : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
          title: Text(
            strongsNumber,
            style: _getPrimaryTextStyle(dialogContext, uiFontSize + 4),
          ),
          content: SizedBox(
            width: constrainedMaxWidth,
            height: maxHeight,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: definitionChildren,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // prepend the Strong's number (available via the strongsNumber argument)
                final plain = '$strongsNumber\n$definition';
                Clipboard.setData(ClipboardData(text: plain));
                showStyledSnackBar(
                    dialogContext, 'Definition copied to clipboard');
              },
              child:
                  Text('Copy', style: _getTextStyle(dialogContext, uiFontSize)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Close',
                  style: _getTextStyle(dialogContext, uiFontSize)),
            ),
          ]),
    );
  }

  void _showStrongsDefinitionLookupDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _StrongsDefinitionLookupDialog(
        buildDefinitionWidgets: _buildDefinitionWidgets,
        buildPrimaryTextStyle: _getPrimaryTextStyle,
        buildTextStyle: _getTextStyle,
        listenToDefinitionSelected: (String strongsNumber) {
          _showStrongsDefinitionDialog(context, strongsNumber);
        },
      ),
    );
  }

  List<Widget> _buildDefinitionWidgets(
    BuildContext context,
    String definition, {
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    final baseStyle = _getTextStyle(context, uiFontSize);
    final definitionChildren = <Widget>[];
    for (final line in definition.split('\n')) {
      definitionChildren.add(RichText(
        text: TextSpan(
          style: baseStyle,
          children: _buildDefinitionPlainSpans(
            context,
            line,
            baseStyle,
            onStrongsTap: onStrongsTap,
          ),
        ),
      ));
    }
    return definitionChildren;
  }

  List<InlineSpan> _buildDefinitionPlainSpans(
    BuildContext context,
    String text,
    TextStyle style, {
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    final spans = <InlineSpan>[];
    int index = 0;

    for (final match in _definitionStrongsNumberPattern.allMatches(text)) {
      if (!_isExactDefinitionStrongsNumber(text, match)) continue;

      if (match.start > index) {
        spans.add(
            TextSpan(text: text.substring(index, match.start), style: style));
      }

      spans.add(_buildClickableDefinitionStrongsSpan(
        context,
        match.group(0)!,
        style,
        onStrongsTap: onStrongsTap,
      ));
      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: style));
    }

    return spans;
  }

  bool _isExactDefinitionStrongsNumber(String text, RegExpMatch match) {
    final start = match.start;
    final end = match.end;
    final previousIsAlphanumeric =
        start > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(text[start - 1]);
    final nextIsAlphanumeric =
        end < text.length && RegExp(r'[A-Za-z0-9]').hasMatch(text[end]);
    return !previousIsAlphanumeric && !nextIsAlphanumeric;
  }

  WidgetSpan _buildClickableDefinitionStrongsSpan(
    BuildContext context,
    String strongsNumber,
    TextStyle style, {
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    final primaryStyle = style.copyWith(
      color: Theme.of(context).brightness == Brightness.dark
          ? darkPrimaryColor.value
          : lightPrimaryColor.value,
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (onStrongsTap != null) {
              onStrongsTap(strongsNumber);
            } else {
              _showStrongsDefinitionDialog(context, strongsNumber);
            }
          },
          child: Text(strongsNumber, style: primaryStyle),
        ),
      ),
    );
  }

  WidgetSpan _buildClickableStrongsSpan(BuildContext context,
      String strongsNumber, double baseFontSize, double fontSize, Color color) {
    final adjustedFontSize =
        FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSize);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _showStrongsDefinitionDialog(context, strongsNumber),
          child: Transform.translate(
            offset: Offset(0, -baseFontSize * 0.5),
            child: Text(
              strongsNumber,
              style: TextStyle(
                fontSize: adjustedFontSize * 0.8,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build a TextSpan for a verse.
  /// Parses text left-to-right. For each word group followed by a Strong's tag:
  ///   - If the tag matches a searched Strong's number: words are HIGHLIGHTED,
  ///     the Strong's number is shown as superscript.
  ///   - If the tag doesn't match: words shown normally, tag stripped.
  /// For standalone Strong's tags (no preceding words):
  ///   - If the tag matches: looks BACK for the nearest preceding words
  ///     (skipping intermediate tags/spaces) and highlights them, shows superscript.
  ///   - If the tag doesn't match: stripped.
  TextSpan _buildVerseSpan(
      BuildContext context, Map<String, dynamic> verseData, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
          fontFamilyNotifier.value, fontSize),
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
    final highlightColor = _getHighlightColor(context);

    final text = verseData['text'] as String;
    final matchedStrongs =
        (verseData['matchedStrongs'] as List<dynamic>?)?.cast<String>() ?? [];

    if (matchedStrongs.isEmpty) {
      return TextSpan(
        text: StrongsDatabase.stripAllStrongsTags(text),
        style: baseStyle,
      );
    }

    final matchedSet = matchedStrongs.toSet();
    final spans = <InlineSpan>[];

    // Regex to extract all tokens sequentially from the text.
    // Three branches:
    // 1. (words) + one or more consecutive ({STRONG})   -> groups 1 & 2
    // 2. standalone {STRONG}                             -> matches but no groups 1/2
    // 3. any single character (.,;: etc)
    final tokenPattern = RegExp(
      r"([A-Za-z'\-]+(?:\s+[A-Za-z'\-]+)*)((?:\s*\{[A-Za-z]\d+\})+)"
      r"|"
      r"\{[A-Za-z]\d+\}"
      r"|"
      r".",
      caseSensitive: false,
    );

    // We also need to look backwards for words preceding a standalone {SN}
    // that is in the matched set. We'll scan all matches first, collecting
    // them into a list of "fragments".
    final allMatches = tokenPattern.allMatches(text).toList();

    int lastEnd = 0;
    for (int i = 0; i < allMatches.length; i++) {
      final match = allMatches[i];

      // Emit any text between matches
      if (match.start > lastEnd) {
        final between = text.substring(lastEnd, match.start);
        if (between.isNotEmpty) {
          spans.add(TextSpan(text: between, style: baseStyle));
        }
      }

      final wordsGroup = match.group(1);
      final tagGroup = match.group(2);

      if (wordsGroup != null && tagGroup != null) {
        // Pattern 1: word/phrase + one or more consecutive {STRONG} tags
        // Extract ALL Strong's numbers from the tag group
        final tagSnMatches = RegExp(r'\{([A-Za-z]\d+)\}').allMatches(tagGroup);
        final allSns =
            tagSnMatches.map((m) => m.group(1)!.toUpperCase()).toList();

        // Check if ANY of these SNs are in the matched set
        final anyMatched = allSns.any((sn) => matchedSet.contains(sn));

        if (anyMatched) {
          // MATCHED (at least one): highlight words, show ALL SNs as superscript
          spans.add(TextSpan(
            text: wordsGroup,
            style: baseStyle.copyWith(
              backgroundColor: highlightColor,
              //fontWeight: FontWeight.bold,
            ),
          ));
          for (int si = 0; si < allSns.length; si++) {
            final sn = allSns[si];
            // Add a space before this SN if it's not the first one
            if (si > 0) {
              spans.add(TextSpan(text: " ", style: baseStyle));
            }
            spans.add(_buildClickableStrongsSpan(
              context,
              sn,
              baseStyle.fontSize!,
              fontSize,
              isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            ));
          }
        } else {
          // NOT matched: show words normally, strip all tags
          spans.add(TextSpan(text: wordsGroup, style: baseStyle));
        }
      } else if (RegExp(r'\{[A-Za-z]\d+\}').hasMatch(match.group(0)!)) {
        // Pattern 2: standalone {STRONG} tag
        final sn = RegExp(r'\{([A-Za-z]\d+)\}')
            .firstMatch(match.group(0)!)
            ?.group(1)
            ?.toUpperCase();

        if (sn != null && matchedSet.contains(sn)) {
          // This is a matched Strong's number but appears without immediately
          // preceding words. Look backwards through the spans to find the
          // most recent word group and highlight it instead.
          // Find the last text span that contains actual word characters
          // (skip spans that are just whitespace/punctuation).
          // Allow already-highlighted spans too — they'll keep the same color
          // and we need them for standalone SNs that share the same word.
          int? highlightIndex;
          for (int j = spans.length - 1; j >= 0; j--) {
            if (spans[j] is TextSpan) {
              final ts = spans[j] as TextSpan;
              // Only target spans that contain at least one word character
              // (a-z, A-Z, 0-9), skipping pure whitespace/punctuation spans
              if (ts.text != null &&
                  RegExp(r'[A-Za-z0-9]').hasMatch(ts.text!)) {
                highlightIndex = j;
                break;
              }
            }
          }

          if (highlightIndex != null) {
            // Replace that span with a highlighted version
            final oldSpan = spans[highlightIndex] as TextSpan;
            spans[highlightIndex] = TextSpan(
              text: oldSpan.text,
              style: baseStyle.copyWith(
                backgroundColor: highlightColor,
                //fontWeight: FontWeight.bold,
              ),
            );

            // Remove any trailing whitespace span between the word and the
            // superscript, so the SN appears directly after the word
            // (consistent with pattern 1 behavior)
            if (highlightIndex + 1 < spans.length) {
              final nextSpan = spans[highlightIndex + 1];
              if (nextSpan is TextSpan &&
                  nextSpan.text != null &&
                  nextSpan.text!.trim().isEmpty) {
                spans.removeAt(highlightIndex + 1);
              }
            }
          }

          // Show the Strong's number as superscript
          spans.add(_buildClickableStrongsSpan(
            context,
            sn,
            baseStyle.fontSize!,
            fontSize,
            isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
          ));
        }
        // If NOT matched: strip it (add nothing)
      } else {
        // Pattern 3: any other character (punctuation, space, etc.)
        spans.add(TextSpan(text: match.group(0), style: baseStyle));
      }

      lastEnd = match.end;
    }

    // Any text after the last match
    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd);
      spans.add(TextSpan(text: remaining, style: baseStyle));
    }

    return TextSpan(children: spans);
  }

  String _formatNumber(int? number) {
    return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+($|\D))'),
        (match) => '${match.group(1)},');
  }

  InlineSpan _buildVerseReferenceSpan(
      BuildContext context, String refText, TextStyle refStyle) {
    final reference = VerseReferenceDetector.detectQuickJumpReference(refText);
    if (reference?.verse == null) {
      return TextSpan(text: refText, style: refStyle);
    }

    final recognizer = _getVerseReferenceRecognizer(context, reference!);
    return TextSpan(
      text: refText,
      style: refStyle.copyWith(
        color: Theme.of(context).brightness == Brightness.dark
            ? darkVerseReferenceColor.value
            : lightVerseReferenceColor.value,
        decoration: TextDecoration.none,
      ),
      mouseCursor: SystemMouseCursors.click,
      recognizer: recognizer,
    );
  }

  TapGestureRecognizer _getVerseReferenceRecognizer(
      BuildContext context, VerseReference reference) {
    TapGestureRecognizer recognizer;
    if (_verseReferenceRecognizerIndex < _verseReferenceRecognizers.length) {
      recognizer = _verseReferenceRecognizers[_verseReferenceRecognizerIndex];
    } else {
      recognizer = TapGestureRecognizer();
      _verseReferenceRecognizers.add(recognizer);
    }

    recognizer.onTap = () => _openValidatedStrongReference(
          context,
          reference.book,
          reference.chapter,
          reference.verse!,
        );
    _verseReferenceRecognizerIndex++;
    return recognizer;
  }

  void _openValidatedStrongReference(
      BuildContext context, String book, int chapter, int verse) {
    // Book name is already in short format so no need to convert
    final referenceText = '$book $chapter:$verse';
    handleVerseLink(
      context,
      'v://$book/$chapter/$verse',
      referenceText,
      navigateToVerse: null,
      onVerseLinkRecursion: null,
      onNoteIconTap: null,
      onNoteEditTap: null,
    );
  }

  void _showStrongsVerseActionMenu(
      BuildContext context, Map<String, dynamic> result) {
    final book = result['book'] as String?;
    final chapter = result['chapter'] as int?;
    final verseNum = result['verse'] as int?;
    final rawVerseText = result['text'] as String? ?? '';
    final cleanVerseText = StrongsDatabase.stripAllStrongsTags(rawVerseText);
    final bookName =
        book == null ? '' : BookNameConverter.shortNameToLongName(book);
    final copyText = '$bookName $chapter:$verseNum\n$cleanVerseText';

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Center(
                child: Text(
              'Goto Verse',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 10,
                  color: getAdaptiveTextColor(context)),
            )),
            onTap: () {
              Navigator.of(context).pop();
              _gotoVerse(book, chapter, verseNum);
            },
          ),
          ListTile(
            title: Center(
                child: Text(
              'Show Context',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 10,
                  color: getAdaptiveTextColor(context)),
            )),
            onTap: () {
              Navigator.of(context).pop();
              _showContextDialog(book, chapter, verseNum);
            },
          ),
          ListTile(
            title: Center(
                child: Text(
              'Copy Verse $verseNum',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 10,
                  color: getAdaptiveTextColor(context)),
            )),
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyText)).then((_) {
                if (!context.mounted) return;
                showStyledSnackBar(context, 'Verse copied to clipboard');
                Navigator.of(context).pop();
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _gotoVerse(String? book, int? chapter, int? verse) async {
    if (book == null || chapter == null || verse == null) {
      ErrorHandler.logError(
        '_gotoVerse null return: book:"$book" chapter:"$chapter" verse:"$verse"',
        context: {
          'class': 'StrongsSearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
      return;
    }

    final result = {
      'verseLocation': {
        'book': book,
        'chapter': chapter,
        'verse': verse,
      },
      'targetScreenIndex': widget.sourceScreenIndex ?? 0,
    };

    if (mounted) {
      Navigator.of(context).pop(result);
    }

    try {
      await HistoryDatabase.addHistory(
          book, chapter, verse, DateTime.now().millisecondsSinceEpoch, false);
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_gotoVerse addHistory exception',
        context: {
          'class': 'StrongsSearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
    }
  }

  Future<void> _showContextDialog(
      String? book, int? chapter, int? verseNum) async {
    if (book == null || chapter == null || verseNum == null) return;

    final normalizedShortBookName = BookNameConverter.normalizeShortName(book);
    final fullBookName =
        BookNameConverter.shortNameToLongName(normalizedShortBookName);
    final referenceText = '$fullBookName $chapter:$verseNum';

    showDialog(
      context: context,
      builder: (context) => ChapterDialog(
        book: normalizedShortBookName,
        chapter: chapter,
        verse: verseNum,
        referenceText: referenceText,
        onNavigateToVerse: (verse) =>
            _gotoVerse(normalizedShortBookName, chapter, verse),
        onNoteIconTap: (int verse, String? noteText) => _openNoteFromContext(
            normalizedShortBookName, chapter, verse, noteText),
        onNoteEditTap: (int verse, String? noteText) => _openNoteFromContext(
            normalizedShortBookName, chapter, verse, noteText),
        onVerseLink: (link, referenceText) => handleVerseLink(
          context,
          link,
          referenceText,
          navigateToVerse: _gotoVerse,
          onVerseLinkRecursion: null,
          onNoteIconTap: _openNoteFromContext,
          onNoteEditTap: _openNoteFromContext,
        ),
      ),
    );
  }

  Future<void> _openNoteFromContext(
      String book, int chapter, int verse, String? existingNote) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NoteScreen(
                book: book,
                chapter: chapter,
                verse: verse,
                existingNote: existingNote)));
  }

  void _unfocusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchButtonFocusNode.canRequestFocus) {
        _searchButtonFocusNode.requestFocus();
      }
    });
  }

  void _resetVerseReferenceRecognizers() {
    _verseReferenceRecognizerIndex = 0;
  }

  void _scheduleVerseReferenceRecognizerCleanup(int expectedCount) {
    _verseReferenceRecognizerCleanupExpectedCount = expectedCount;
    if (expectedCount >= _verseReferenceRecognizers.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_verseReferenceRecognizerCleanupExpectedCount != expectedCount) {
        return;
      }

      for (int i = expectedCount; i < _verseReferenceRecognizers.length; i++) {
        final recognizer = _verseReferenceRecognizers[i];
        recognizer.onTap = null;
        recognizer.dispose();
      }
      _verseReferenceRecognizers.removeRange(
          expectedCount, _verseReferenceRecognizers.length);
      _verseReferenceRecognizerCleanupExpectedCount = null;
    });
  }

  void _disposeVerseReferenceRecognizers() {
    for (final recognizer in _verseReferenceRecognizers) {
      recognizer.onTap = null;
      recognizer.dispose();
    }
    _verseReferenceRecognizers.clear();
    _verseReferenceRecognizerCleanupExpectedCount = null;
  }

  @override
  void initState() {
    super.initState();
    _restoreSearchState();
    _resultsScrollController.addListener(_saveScrollOffset);
  }

  @override
  void dispose() {
    _disposeVerseReferenceRecognizers();
    _searchButtonFocusNode.dispose();
    _persistSearchState(_controller.text.trim());
    _resultsScrollController.removeListener(_saveScrollOffset);
    _controller.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreSearchState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSearch = prefs.getString(_lastSearchTermKey);
    if (!mounted) return;

    if (lastSearch == null || lastSearch.trim().isEmpty) {
      await prefs.setDouble(_scrollOffsetKey, 0.0);
      setState(() {
        _controller.text = '';
        _searchResults = [];
        _foundStrongsNumbers = {};
        _phraseSummary = {};
        _totalMatches = null;
        _totalVerses = null;
        _searchType = null;
        _searchTerm = null;
      });
      return;
    }

    setState(() {
      _controller.text = lastSearch;
      _isRestoring = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _onSearch(showLoading: false, resetScroll: false);
      await _loadScrollOffset();
    });
  }

  Future<void> _persistSearchState(String searchTerm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSearchTermKey, searchTerm);
  }

  Future<void> _loadScrollOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final offset = prefs.getDouble(_scrollOffsetKey) ?? 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_resultsScrollController.hasClients && offset >= 0.0) {
        _resultsScrollController.jumpTo(offset);
      }
    });
  }

  Future<void> _saveScrollOffset() async {
    if (!_resultsScrollController.hasClients) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollOffsetKey, _resultsScrollController.offset);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showStrongNumbersTable =
        (_searchType == 'word' || _searchType == 'reference') &&
            _foundStrongsNumbers.isNotEmpty;
    if (!showStrongNumbersTable) {
      _resetVerseReferenceRecognizers();
      _scheduleVerseReferenceRecognizerCleanup(0);
    }
    final barColor = _adjustBarColor(
        Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      key: _scaffoldKey,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(
          size: 32,
          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
        ),
        elevation: 0,
        title: (_totalMatches != null && _totalVerses != null)
            ? Center(
                child: Text(
                '${_formatNumber(_totalMatches)} ${_totalMatches == 1 ? 'match' : 'matches'} in ${_formatNumber(_totalVerses)} ${_totalVerses == 1 ? 'verse' : 'verses'}',
                style: TextStyle(
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ))
            : Text('Strongs Search',
                style: TextStyle(
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
        toolbarHeight: 60,
        backgroundColor: barColor,
        actions: [
          IconButton(
            icon: Icon(
              Icons.menu_book,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Show Definitions Lookup',
            ),
            tooltip: 'Strong\'s Definitions',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: () => _showStrongsDefinitionLookupDialog(context),
          ),
          IconButton(
            icon: Icon(
              Icons.help_outline,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Show Help Dialog',
            ),
            tooltip: 'Help',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: _showHelpDialog,
          ),
          // No options for Strong's search yet
          //
          // IconButton(
          //   icon: Icon(
          //     Icons.menu,
          //     size: 32,
          //     color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
          //     semanticLabel: 'Show Options Menu',
          //   ),
          //   tooltip: 'Options',
          //   color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
          //   onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          // ),
        ],
      ),
      endDrawer: Drawer(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value,
        child: SingleChildScrollView(
            child: Column(children: [
          AppBar(
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            ),
            automaticallyImplyLeading: true,
            toolbarHeight: 60,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? darkBackgroundColor.value
                : lightBackgroundColor.value,
          ),
          const SizedBox(height: 16),
          // Padding(
          //   padding:
          //       const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
          //   child: Text('Options coming soon',
          //       style: TextStyle(
          //           fontSize: uiFontSize,
          //           fontFamily: uiFontFamily,
          //           color: getAdaptiveTextColor(context))),
          // ),
        ])),
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? darkBackgroundColor.value
          : lightBackgroundColor.value,
      body: SafeArea(
        child: Container(
            color: barColor,
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 16, top: 0, right: 16, bottom: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    maxLength: 100,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    controller: _controller,
                    decoration: InputDecoration(
                      counter: SizedBox.shrink(),
                      hintText: 'Search Strongs',
                      hintStyle: TextStyle(
                          fontFamily: uiFontFamily, fontSize: uiFontSize + 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: Colors.blueGrey, width: 2.0),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDark
                              ? darkPrimaryColor.value
                              : lightPrimaryColor.value,
                          semanticLabel: 'Clear Search Query',
                        ),
                        onPressed: () => _controller.clear(),
                        iconSize: 32,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      _onSearch();
                    },
                    style: TextStyle(
                        fontSize: uiFontSize + 4,
                        fontFamily: fontFamilyNotifier.value),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                      alignment: WrapAlignment.end,
                      runAlignment: WrapAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: _isResetting
                              ? null
                              : () async {
                                  if (_isResetting) return;
                                  setState(() => _isResetting = true);
                                  setState(() {
                                    _controller.clear();
                                    _searchResults = [];
                                    _foundStrongsNumbers = {};
                                    _phraseSummary = {};
                                    _totalMatches = null;
                                    _totalVerses = null;
                                    _searchType = null;
                                    _searchTerm = null;
                                    _isRestoring = false;
                                  });

                                  Future.delayed(const Duration(seconds: 3),
                                      () {
                                    if (mounted) {
                                      setState(() => _isResetting = false);
                                    }
                                  });
                                },
                          style: ButtonStyle(
                            backgroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                                    (states) {
                              if (states.contains(WidgetState.disabled)) {
                                return Colors.grey;
                              }
                              return Theme.of(context)
                                      .elevatedButtonTheme
                                      .style
                                      ?.backgroundColor
                                      ?.resolve(states) ??
                                  Colors.blue;
                            }),
                            foregroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                                    (states) {
                              if (states.contains(WidgetState.disabled)) {
                                return Colors.white60;
                              }
                              return Theme.of(context)
                                      .elevatedButtonTheme
                                      .style
                                      ?.foregroundColor
                                      ?.resolve(states) ??
                                  Colors.white;
                            }),
                          ),
                          child: Text('Reset',
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context,
                                      usePrimaryColor: true))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          focusNode: _searchButtonFocusNode,
                          onPressed: () => _onSearch(),
                          child: Text('Search',
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context,
                                      usePrimaryColor: true))),
                        ),
                      ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _controller.text.trim().isEmpty
                        ? Center(
                            child: Text('Enter search terms above',
                                style: TextStyle(
                                  fontSize: uiFontSize + 6,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                )))
                        : _isRestoring
                            ? Center(
                                child: Text('Restoring search results...',
                                    style: TextStyle(
                                        fontSize: uiFontSize + 8,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context))))
                            : (_searchResults.isEmpty && _totalMatches == 0)
                                ? Center(
                                    child: Text('No matches found 🧐',
                                        style: TextStyle(
                                            fontSize: uiFontSize + 8,
                                            fontFamily: uiFontFamily,
                                            color:
                                                getAdaptiveTextColor(context))))
                                : ValueListenableBuilder<double>(
                                    valueListenable: fontSizeNotifier,
                                    builder: (context, fontSize, child) {
                                      return RawScrollbar(
                                          thumbColor: isDark
                                              ? darkPrimaryColor.value
                                                  .withValues(alpha: 0.3)
                                              : lightPrimaryColor.value
                                                  .withValues(alpha: 0.5),
                                          thumbVisibility: false,
                                          trackVisibility: false,
                                          thickness: 16.0,
                                          controller: _resultsScrollController,
                                          radius: Radius.circular(8.0),
                                          child: ScrollConfiguration(
                                              behavior: ScrollConfiguration.of(
                                                      context)
                                                  .copyWith(scrollbars: false),
                                              child: CustomScrollView(
                                                controller:
                                                    _resultsScrollController,
                                                slivers: [
                                                  if (showStrongNumbersTable)
                                                    SliverToBoxAdapter(
                                                      child:
                                                          _buildStrongNumbersTableSection(
                                                              context,
                                                              fontSize),
                                                    ),
                                                  if (_phraseSummary.isNotEmpty)
                                                    SliverToBoxAdapter(
                                                      child:
                                                          _buildPhraseSummaryTableSection(
                                                              context,
                                                              fontSize),
                                                    ),
                                                  if (_searchResults.isNotEmpty)
                                                    SliverPadding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              bottom: 100.0),
                                                      sliver:
                                                          _buildVerseResultsSliver(
                                                              context,
                                                              fontSize,
                                                              barColor),
                                                    ),
                                                ],
                                              )));
                                    },
                                  ),
                  ),
                ],
              ),
            )),
      ),
    );
  }

  Widget _buildStrongNumbersTableSection(
      BuildContext context, double fontSize) {
    _resetVerseReferenceRecognizers();

    final strongsEntries = _foundStrongsNumbers.entries.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final refStyle = _getPrimaryTextStyle(context, fontSize);
    final snStyle = _getTextStyle(context, fontSize);
    final tableRows = <TableRow>[];

    for (final entry in strongsEntries) {
      final ref = entry.value;
      final refText = '${ref['book']} ${ref['chapter']}:${ref['verse']}';
      final phrase =
          StrongsDatabase.extractPhraseBeforeStrongs(refText, entry.key);

      tableRows.add(_buildTableRow(
        [
          Text.rich(_buildVerseReferenceSpan(context, refText, refStyle)),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showStrongsDefinitionDialog(context, entry.key),
              child: Text(
                entry.key,
                style: snStyle.copyWith(
                  color:
                      isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Text(
            phrase,
            style: snStyle,
            textAlign: TextAlign.left,
          ),
        ],
        const [TextAlign.left, TextAlign.center, TextAlign.left],
      ));
    }

    _scheduleVerseReferenceRecognizerCleanup(_verseReferenceRecognizerIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildSectionHeader(context,
            'Strong\'s numbers associated with "${_searchTerm ?? ''}"'),
        _buildCenteredTable(tableRows),
        _buildSectionDivider(),
      ],
    );
  }

  Widget _buildPhraseSummaryTableSection(
      BuildContext context, double fontSize) {
    final sortedPhrases = _phraseSummary.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final phraseStyle = _getTextStyle(context, fontSize);
    final countStyle = _getTextStyle(context, fontSize);
    final totalPhraseStyle = _getTextStyle(context, fontSize, bold: true);
    final totalCountStyle = _getTextStyle(context, fontSize, bold: true);
    final tableRows = <TableRow>[];

    for (final entry in sortedPhrases) {
      tableRows.add(_buildTableRow(
        [
          Text(
            entry.key,
            style: phraseStyle,
            textAlign: TextAlign.left,
          ),
          Text(
            '${entry.value}',
            style: countStyle,
            textAlign: TextAlign.left,
          ),
        ],
        const [TextAlign.left, TextAlign.left],
      ));
    }

    final total =
        _phraseSummary.values.fold<int>(0, (sum, count) => sum + count);
    tableRows.add(_buildTableRow(
      [
        Text(
          'Total',
          style: totalPhraseStyle,
          textAlign: TextAlign.left,
        ),
        Text(
          '$total',
          style: totalCountStyle,
          textAlign: TextAlign.left,
        ),
      ],
      const [TextAlign.left, TextAlign.left],
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildSectionHeader(context, 'Phrase Summary'),
        _buildCenteredTable(tableRows),
        _buildSectionDivider(),
      ],
    );
  }

  Widget _buildCenteredTable(List<TableRow> tableRows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Center(
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: tableRows,
        ),
      ),
    );
  }

  TableRow _buildTableRow(List<Widget> cells, List<TextAlign> alignments) {
    return TableRow(
      children: List.generate(cells.length, (index) {
        return _buildTableCell(cells[index], alignments[index]);
      }),
    );
  }

  Widget _buildTableCell(Widget child, TextAlign alignment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 1.0),
      child: child,
    );
  }

  TextStyle _getPrimaryTextStyle(BuildContext context, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
          fontFamilyNotifier.value, fontSize),
      color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
    );
  }

  TextStyle _getTextStyle(BuildContext context, double fontSize,
      {bool bold = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
          fontFamilyNotifier.value, fontSize + 2),
      fontWeight: bold ? FontWeight.bold : null,
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
  }

  Widget _buildSectionDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Divider(thickness: 1),
    );
  }

  SliverList _buildVerseResultsSliver(
      BuildContext context, double fontSize, Color barColor) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, resultIndex) {
          return _buildVerseResult(context, _searchResults[resultIndex],
              resultIndex, fontSize, barColor);
        },
        childCount: _searchResults.length,
      ),
    );
  }

  Widget _buildVerseResult(BuildContext context, Map<String, dynamic> result,
      int resultIndex, double fontSize, Color barColor) {
    final bookShort = result['book'] as String;
    final chapter = result['chapter'] as int;
    final verse = result['verse'] as int;
    final bookLongName = BookNameConverter.shortNameToLongName(bookShort);

    return GestureDetector(
      onTap: () => _showStrongsVerseActionMenu(context, result),
      child: Container(
        color: barColor,
        width: double.infinity,
        padding: const EdgeInsets.only(
            left: 0.0, top: 0.0, bottom: 0.0, right: 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(children: [
              TextSpan(
                text: '$bookLongName $chapter:$verse\n',
                style: TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                        fontFamilyNotifier.value, fontSize),
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? darkPrimaryColor.value
                        : lightPrimaryColor.value),
              ),
              _buildVerseSpan(context, result, fontSize),
            ])),
            if (resultIndex < _searchResults.length - 1)
              Divider(
                thickness: 1,
                height: 16,
                indent: MediaQuery.of(context).size.width * 0.01,
                endIndent: MediaQuery.of(context).size.width * 0.01,
                color: const Color.fromARGB(47, 158, 158, 158),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0, left: 4.0),
      child: Text(title,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: uiFontSize + 2,
              fontFamily: uiFontFamily,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? darkPrimaryColor.value
                  : lightPrimaryColor.value)),
    );
  }
}

class _StrongsDefinitionLookupDialog extends StatefulWidget {
  final _DefinitionWidgetsBuilder buildDefinitionWidgets;
  final _TextStyleBuilder buildPrimaryTextStyle;
  final _TextStyleBuilder buildTextStyle;
  final void Function(String strongsNumber)? listenToDefinitionSelected;

  const _StrongsDefinitionLookupDialog({
    required this.buildDefinitionWidgets,
    required this.buildPrimaryTextStyle,
    required this.buildTextStyle,
    this.listenToDefinitionSelected,
  });

  @override
  State<_StrongsDefinitionLookupDialog> createState() =>
      _StrongsDefinitionLookupDialogState();
}

class _StrongsDefinitionLookupDialogState
    extends State<_StrongsDefinitionLookupDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  Timer? _persistTimer;

  String? _currentStrongsNumber;
  String? _currentDefinition;
  String? _errorText;

  /// Index in _allStrongsNumbers currently highlighted by keyboard navigation.
  int _focusedIndex = 0;

  /// Flat sorted list of all available Strong's numbers like ["G1", "G10", ..., "H8674"].
  late final List<String> _allStrongsNumbers;

  static const String _lastInputKey = 'lastStrongsLookupInput';
  static const String _focusedIndexKey = 'lastStrongsLookupFocusedIndex';

  @override
  void initState() {
    super.initState();
    _allStrongsNumbers = _buildAllStrongsNumbersList();
    //_controller.addListener(_schedulePersist);
    _restoreState();
  }

  @override
  void deactivate() {
    _persistState();
    super.deactivate();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistState();
    _textFieldFocusNode.dispose();
    _listFocusNode.dispose();
    _controller.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  // void _schedulePersist() {
  //   _persistTimer?.cancel();
  //   _persistTimer = Timer(const Duration(milliseconds: 250), () {
  //     _persistTimer = null;
  //     _persistState();
  //   });
  // }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastInput = prefs.getString(_lastInputKey);
    final savedIndex = prefs.getInt(_focusedIndexKey);

    bool restored = false;
    if (lastInput != null && lastInput.isNotEmpty) {
      final normalized = _normalizeInput(lastInput);
      if (normalized != null) {
        final definition = StrongsDefinitionsDatabase.getDefinition(normalized);
        final validIndex = savedIndex != null &&
            savedIndex >= 0 &&
            savedIndex < _allStrongsNumbers.length &&
            _allStrongsNumbers[savedIndex] == normalized;

        if (definition != null && validIndex) {
          setState(() {
            _currentStrongsNumber = normalized;
            _currentDefinition = definition;
            _errorText = null;
            _focusedIndex = savedIndex;
            _controller.text = normalized;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: normalized.length),
            );
          });
          _scrollToStrongsNumber(normalized);
          restored = true;
        }
      }
    }

    if (!restored) {
      setState(() {
        _currentStrongsNumber = null;
        _currentDefinition = null;
        _errorText = null;
        _focusedIndex = 0;
      });
      _controller.clear();
    }
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastInputKey, _controller.text.trim());
    await prefs.setInt(_focusedIndexKey, _focusedIndex);
  }

  /// Builds a flat sorted list of all Strong's numbers from the definitions map.
  static List<String> _buildAllStrongsNumbersList() {
    final result = <String>[];
    for (final prefixEntry in strongsDefinitions.entries) {
      final prefix = prefixEntry.key; // "H" or "G"
      for (final numberEntry in prefixEntry.value.entries) {
        result.add('$prefix${numberEntry.key}');
      }
    }
    result.sort((a, b) {
      // Sort by prefix first (G before H), then numerically by number
      final aPrefix = a[0];
      final bPrefix = b[0];
      if (aPrefix != bPrefix) return aPrefix.compareTo(bPrefix);
      final aNum = int.parse(a.substring(1));
      final bNum = int.parse(b.substring(1));
      return aNum.compareTo(bNum);
    });
    return result;
  }

  /// Scrolls the list so the given strongsNumber is visible and highlighted.
  void _scrollToStrongsNumber(String strongsNumber) {
    final index = _allStrongsNumbers.indexOf(strongsNumber);
    if (index < 0) return;
    // Use a post-frame callback to ensure the list is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listScrollController.hasClients) {
        final itemExtent = 36.0;
        final visibleItems =
            _listScrollController.position.viewportDimension / itemExtent;
        final targetOffset =
            (index * itemExtent) - (visibleItems / 2) * itemExtent;
        _listScrollController.animateTo(
          targetOffset.clamp(
              0.0, _listScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  String? _normalizeInput(String input) {
    final match = RegExp(r'^([HhGg])0*(\d+)$').firstMatch(input.trim());
    if (match == null) return null;

    final prefix = match.group(1)!.toUpperCase();
    final numericPart = match.group(2)!;
    final number = int.tryParse(numericPart);
    if (number == null) return null;

    return '$prefix$number';
  }

  void _lookup(String input) {
    final normalized = _normalizeInput(input);
    if (normalized == null) {
      setState(() {
        _currentStrongsNumber = null;
        _currentDefinition = null;
        _errorText = 'Enter a Strong\'s number such as H1285 or G25.';
      });
      _persistState();
      return;
    }

    final definition = StrongsDefinitionsDatabase.getDefinition(normalized);
    setState(() {
      _currentStrongsNumber = normalized;
      _currentDefinition = definition;
      _errorText =
          definition == null ? 'Definition not found for $normalized.' : null;
      _controller.text = normalized;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _focusedIndex = _allStrongsNumbers.indexOf(normalized);
    _scrollToStrongsNumber(normalized);
    _persistState();
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _currentStrongsNumber = null;
      _currentDefinition = null;
      _errorText = null;
    });
    _textFieldFocusNode.requestFocus();
    _persistState();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxWidth = screenWidth * 1;
    final constrainedMaxWidth =
        isMobile ? screenWidth : (maxWidth > 1000.0 ? 1000.0 : maxWidth);
    final maxHeight = screenHeight * 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? darkPrimaryColor.value : lightPrimaryColor.value;

    return AlertDialog(
      // title: Text(
      //   'Strong\'s Definitions',
      //   style: widget.buildPrimaryTextStyle(context, uiFontSize + 4),
      // ),
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0)
          : const EdgeInsets.symmetric(horizontal: 32.0, vertical: 64.0),
      contentPadding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
      content: SizedBox(
        width: constrainedMaxWidth,
        height: maxHeight,
        child: Column(
          children: [
            TextField(
              focusNode: _textFieldFocusNode,
              controller: _controller,
              maxLength: 5,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: InputDecoration(
                counter: const SizedBox.shrink(),
                hintText: 'Enter a Strong\'s number or choose one below',
                hintStyle: TextStyle(
                  fontFamily: uiFontFamily,
                  fontSize: uiFontSize + 2,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Colors.blueGrey, width: 2.0),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.clear,
                    semanticLabel: 'Reset',
                    color: primaryColor,
                  ),
                  onPressed: _clear,
                ),
              ),
              onSubmitted: _lookup,
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: fontFamilyNotifier.value,
                color: getAdaptiveTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            // Text(
            //   '${_allStrongsNumbers.length} definitions',
            //   style: TextStyle(
            //     fontSize: uiFontSize - 2,
            //     fontFamily: uiFontFamily,
            //     color: isDark
            //         ? darkTextColor.value.withValues(alpha: 0.6)
            //         : lightTextColor.value.withValues(alpha: 0.6),
            //   ),
            // ),
            //const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100.0,
                    child: Focus(
                      focusNode: _listFocusNode,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent || event is KeyRepeatEvent) {
                          if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            final nextIndex = (_focusedIndex + 1)
                                .clamp(0, _allStrongsNumbers.length - 1);
                            if (nextIndex != _focusedIndex) {
                              setState(() => _focusedIndex = nextIndex);
                              _lookup(_allStrongsNumbers[_focusedIndex]);
                            }
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            final prevIndex = (_focusedIndex - 1)
                                .clamp(0, _allStrongsNumbers.length - 1);
                            if (prevIndex != _focusedIndex) {
                              setState(() => _focusedIndex = prevIndex);
                              _lookup(_allStrongsNumbers[_focusedIndex]);
                            }
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Scrollbar(
                        controller: _listScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _listScrollController,
                          itemCount: _allStrongsNumbers.length,
                          itemExtent: 36.0,
                          itemBuilder: (context, index) {
                            final sn = _allStrongsNumbers[index];
                            final isSelected = sn == _currentStrongsNumber;
                            return Material(
                              color: isSelected
                                  ? primaryColor.withValues(alpha: 0.25)
                                  : Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  _focusedIndex = index;
                                  _lookup(sn);
                                },
                                child: Text(
                                  sn,
                                  style: TextStyle(
                                    fontSize: uiFontSize + 4,
                                    fontFamily: fontFamilyNotifier.value,
                                    color: isSelected
                                        ? primaryColor
                                        : getAdaptiveTextColor(context),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 1.0,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentStrongsNumber != null)
                          Text(
                            _currentStrongsNumber!,
                            style: widget.buildPrimaryTextStyle(
                                context, uiFontSize + 2),
                          ),
                        if (_currentStrongsNumber != null)
                          const SizedBox(height: 8),
                        if (_errorText != null)
                          Text(
                            _errorText!,
                            style: widget.buildTextStyle(context, uiFontSize),
                          ),
                        if (_currentDefinition != null &&
                            _currentStrongsNumber != null)
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: widget.buildDefinitionWidgets(
                                  context,
                                  _currentDefinition!,
                                  onStrongsTap: _lookup,
                                ),
                              ),
                            ),
                          ),
                        if (_currentDefinition == null &&
                            _currentStrongsNumber == null &&
                            _errorText == null)
                          Expanded(
                            child: Center(
                              child: Text(
                                'Select or search a Strong\'s number',
                                style: widget
                                    .buildTextStyle(context, uiFontSize)
                                    .copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: isDark
                                          ? darkTextColor.value
                                              .withValues(alpha: 0.5)
                                          : lightTextColor.value
                                              .withValues(alpha: 0.5),
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _lookup(_controller.text),
          child: Text(
            'Lookup',
            style: widget.buildTextStyle(context, uiFontSize),
          ),
        ),
        TextButton(
          onPressed: () {
            // prepend the Strong's number (available via _currentStrongsNumber)
            final plain =
                '${_currentStrongsNumber ?? ''}\n${_currentDefinition ?? ''}';
            Clipboard.setData(ClipboardData(text: plain));
            showStyledSnackBar(context, 'Definition copied to clipboard');
          },
          child: Text(
            'Copy',
            style: widget.buildTextStyle(context, uiFontSize),
          ),
        ),
        TextButton(
          onPressed: () {
            _persistState();
            Navigator.of(context).pop();
          },
          child: Text(
            'Close',
            style: widget.buildTextStyle(context, uiFontSize),
          ),
        ),
      ],
    );
  }
}
