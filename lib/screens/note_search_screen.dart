import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:flutter_quill/flutter_quill.dart' show Document;
import '../database/notes_database.dart';
import '../database/bible_database.dart';
import '../main.dart';
import '../utils/book_name_converter.dart'; // Import for book name conversion
import '../utils/book_filter.dart'; // Import for book filtering
import '../database/history_database.dart'; // Import for history tracking
import 'package:flutter/services.dart'; // <-- added to request on-screen keyboard
import '../utils/preferences_constants.dart'; // For uiFontSize and uiFontFamily
import '../../utils/snackbar_notification.dart';
import '../widgets/responsive_text.dart';
import '../widgets/quill_note_display.dart';
import 'dart:async';
import '../utils/font_size_adjustments.dart';
import '../utils/note_storage_format.dart';
import '../utils/bible_utils.dart';
import '../screens/note_screen.dart';
import '../screens/chapter_dialog.dart'; // Import for ChapterDialog
import '../utils/error_handler.dart';
import '../utils/verse_text_parser.dart';

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor) {
  final hsl = HSLColor.fromColor(backgroundColor);
  // If lightness > 0.5 (light color), make slightly darker; otherwise make slightly lighter
  final adjustedLightness = hsl.lightness > 0.5
      ? (hsl.lightness - 0.03).clamp(0.0, 1.0) // Darker for light backgrounds
      : (hsl.lightness + 0.03).clamp(0.0, 1.0); // Lighter for dark backgrounds
  return hsl.withLightness(adjustedLightness).toColor();
}

class NoteSearchScreen extends StatefulWidget {
  final int? sourceScreenIndex;

  const NoteSearchScreen({
    super.key,
    this.sourceScreenIndex,
  });

  @override
  State<NoteSearchScreen> createState() => _NoteSearchScreenState();
}

class _NoteSearchScreenState extends State<NoteSearchScreen>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  final FocusNode _searchButtonFocusNode = FocusNode();

  static const String _regexKey = 'noteSearchRegex';
  static const String _wholeWordKey = 'noteSearchWholeWord';
  static const String _caseSensitiveKey = 'noteSearchCaseSensitive';
  static const String _bookFilterTypeKey = 'noteSearchBookFilterType';
  static const String _bookFilterCustomKey = 'noteSearchBookFilterCustom';

  bool _useRegex = false;
  bool _useWholeWord = false;
  bool _caseSensitive = false;
  bool _isResetting = false; // Flag to prevent spamming the reset button
  bool _isOptionsDrawerOpen = false;

  // Book filter state
  String _bookFilterType = 'All Books'; // Current selected filter type
  String _customBookFilter = ''; // Custom range specification
  List<String> _allowedBooks = []; // Parsed allowed books (short names)
  Map<String, Set<int>> _allowedChapters =
      {}; // Parsed allowed chapters per book
  late TextEditingController
      _customRangeController; // Controller for custom range input
  String? _customRangeError; // Error message for invalid custom range

  // Search results
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  int? _totalMatches;
  int? _totalVerses;
  RegExp? _currentRegex;

  // Tracking when the user last input any character
  DateTime _lastInputTime = DateTime.now();

  @override
  bool get wantKeepAlive => true;

  // Get highlight color based on theme (same as search_screen.dart)
  Color _getHighlightColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkHighlightColor.value
        : lightHighlightColor.value;
  }

  // Get the display span for verse text in note search results.
  // Note search highlighting only belongs in the note body, not the verse text.
  TextSpan _getVerseSpan(String verseText, TextStyle baseStyle) {
    return VerseTextParser.parseVerseText(verseText, baseStyle);
  }

  // Create RegExp with conditional unicode flag based on pattern content
  RegExp _createRegExp(String pattern, bool caseSensitive) {
    // Enable unicode mode if the pattern contains Unicode-aware regex features
    final hasUnicodePatterns = pattern.contains('\\p{P}') ||
        pattern.contains('\\p{L}') ||
        pattern.contains('\\p{N}') ||
        pattern.contains('\\p{S}') ||
        pattern.contains('\\p{Z}') ||
        pattern.contains('\\p{M}');
    return RegExp(pattern,
        caseSensitive: caseSensitive, unicode: hasUnicodePatterns);
  }

  // Convert Delta to plain text for searching
  String _convertDeltaToSearchableText(String deltaJson) {
    // Check if the note is already in Delta format
    if (NoteStorageFormat.isDeltaFormat(deltaJson)) {
      final delta = Delta.fromJson(jsonDecode(deltaJson));
      final document = Document.fromDelta(delta);
      // Get plain text directly from the document
      final plainText = document.getPlainText(0, document.length);
      return plainText.replaceAll('¶ ', '').replaceAll('\uFFFC', '');
    } else {
      // Plain text - return directly (backwards compatibility)
      return deltaJson.replaceAll('¶ ', '').replaceAll('\uFFFC', '');
    }
  }

  // Get the searchable text from a note (Delta converted to HTML, then HTML tags removed)
  String _getSearchText(String noteText) {
    return _convertDeltaToSearchableText(noteText);
  }

  Future<List<Map<String, dynamic>>> _searchNotes(String input) async {
    // Get all notes from database
    final allNotes = await NotesDatabase.getNotes();

    await _buildBookOrderIndex();

    List<Map<String, dynamic>> filteredResults = allNotes
        .where((note) {
          String searchText = _getSearchText(note['note_text'] as String);
          return _currentRegex!.hasMatch(searchText);
        })
        .where((note) {
          // Apply book filtering
          return BookFilter.verseMatchesFilter(
              note, _allowedBooks, _allowedChapters);
        })
        .map((note) => {
              ...note,
              'bookLongName':
                  BookNameConverter.shortNameToLongName(note['book'] as String),
            })
        .toList();

    _sortResultsInNoteOrder(filteredResults);
    return filteredResults;
  }

  // --- BEGIN: Ensure results are in DB/Biblical order ---
  Map<String, int>? _bookOrderIndex;

  String _normBook(dynamic b) => b.toString().trim().toUpperCase();

  Future<void> _buildBookOrderIndex() async {
    if (_bookOrderIndex != null) return;
    // Import book list from bible database to maintain order
    final books = await NotesDatabase.getDatabase().then((db) async {
      // We need to get book order from bible database since notes use same book abbreviations
      // For simplicity, we'll create a standard biblical order
      return [
        'Gen',
        'Exo',
        'Lev',
        'Num',
        'Deu',
        'Jos',
        'Jdg',
        'Rut',
        '1Sa',
        '2Sa',
        '1Ki',
        '2Ki',
        '1Ch',
        '2Ch',
        'Ezr',
        'Neh',
        'Est',
        'Job',
        'Psa',
        'Pro',
        'Ecc',
        'Sng',
        'Isa',
        'Jer',
        'Lam',
        'Ezk',
        'Dan',
        'Hos',
        'Jol',
        'Amo',
        'Oba',
        'Jon',
        'Mic',
        'Nam',
        'Hab',
        'Zep',
        'Hag',
        'Zec',
        'Mal',
        'Mat',
        'Mar',
        'Luk',
        'Jhn',
        'Act',
        'Rom',
        '1Co',
        '2Co',
        'Gal',
        'Eph',
        'Php',
        'Col',
        '1Th',
        '2Th',
        '1Ti',
        '2Ti',
        'Tit',
        'Phm',
        'Heb',
        'Jas',
        '1Pe',
        '2Pe',
        '1Jn',
        '2Jn',
        '3Jn',
        'Jde',
        'Rev'
      ];
    });

    final map = <String, int>{};
    for (int i = 0; i < books.length; i++) {
      final raw = books[i];
      map[raw] = i; // exact key
      map[_normBook(raw)] = i; // normalized key
    }
    _bookOrderIndex = map;
  }

  int _bookIdx(dynamic b) {
    final m = _bookOrderIndex;
    if (m == null) return 1 << 30;
    final norm = _normBook(b);
    return m[norm] ?? m[b] ?? (1 << 30);
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  void _sortResultsInNoteOrder(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final ia = _bookIdx(a['book']);
      final ib = _bookIdx(b['book']);
      if (ia != ib) return ia.compareTo(ib);
      final ca = _asInt(a['chapter']);
      final cb = _asInt(b['chapter']);
      if (ca != cb) return ca.compareTo(cb);
      final va = _asInt(a['verse']);
      final vb = _asInt(b['verse']);
      return va.compareTo(vb);
    });
  }

  // --- END: Ensure results are in DB/Biblical order ---

  Map<String, dynamic> _buildSearchPattern(
      bool useRegex, String input, bool useWholeWord) {
    if (useRegex) {
      RegExp searchRegex = _createRegExp(input, _caseSensitive);

      return {'Regular Expressions': searchRegex};
    } else {
      // parse phrases and words
      RegExp phraseRegExp = RegExp(r'"([^"]+)"');
      final phrases = phraseRegExp
          .allMatches(input)
          .map((m) => m.group(1)!)
          .where((p) => p.isNotEmpty)
          .toList();
      String queryWithoutPhrases = input.replaceAll(phraseRegExp, '').trim();
      final originalWords = queryWithoutPhrases
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final allTerms = [...phrases, ...originalWords];
      if (allTerms.isEmpty) {
        return {'Regular Expressions': _createRegExp('.*', _caseSensitive)};
      }

      // Treat * as [A-Za-z]*
      List<String> escapedTerms = allTerms.map((term) {
        String escaped = RegExp.escape(term);
        escaped = escaped.replaceAll('\\*', '[A-Za-z]*');
        return escaped;
      }).toList();

      // Only use word boundaries when whole word search is enabled
      String pattern;
      if (useWholeWord) {
        pattern = '\\b(${escapedTerms.join('|')})\\b';
      } else {
        pattern = '(${escapedTerms.join('|')})';
      }
      return {'Regular Expressions': _createRegExp(pattern, _caseSensitive)};
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    _customRangeController = TextEditingController(text: _customBookFilter);

    // Add a listener to the focus node to show/hide the on-screen keyboard.
    //_searchFocusNode.addListener(_onFocusChange);

    _loadSearchOptions();
    _loadLastSearch();
    _resultsScrollController.addListener(_saveScrollOffset);
  }

  @override
  void dispose() {
    _searchButtonFocusNode.dispose();
    _controller.dispose();
    _customRangeController.dispose();
    _resultsScrollController.removeListener(_saveScrollOffset);
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _useRegex = prefs.getBool(_regexKey) ?? false;
        _useWholeWord = prefs.getBool(_wholeWordKey) ?? false;
        _caseSensitive = prefs.getBool(_caseSensitiveKey) ?? false;
        _bookFilterType =
            BookFilter.normalizeFilterType(prefs.getString(_bookFilterTypeKey));
        _customBookFilter = prefs.getString(_bookFilterCustomKey) ?? '';
        // Update the text controller to reflect loaded custom range
        _customRangeController.text = _customBookFilter;
      });
      // Update parsed filter state
      await _updateBookFilter();
    } catch (e) {
      // If error, keep defaults
      await _updateBookFilter();
    }
  }

  Future<void> _saveSearchOptions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_regexKey, _useRegex);
    await prefs.setBool(_wholeWordKey, _useWholeWord);
    await prefs.setBool(_caseSensitiveKey, _caseSensitive);
    await prefs.setString(_bookFilterTypeKey, _bookFilterType);
    await prefs.setString(_bookFilterCustomKey, _customBookFilter);
  }

  // Update the parsed book filter state based on current filter type and custom input
  Future<void> _updateBookFilter() async {
    final result = await BookFilter.parseCustomRange(_customBookFilter);
    setState(() {
      if (_bookFilterType == 'Custom Range') {
        if (result.isSuccess) {
          _allowedBooks = result.books;
          _allowedChapters = result.chapters;
          _customRangeError = null; // Clear any previous error
        } else {
          _customRangeError = result.error;
          _allowedBooks = [];
          _allowedChapters = {};
        }
      } else {
        // Use predefined category
        _allowedBooks = BookFilter.predefinedCategories[_bookFilterType] ?? [];
        _allowedChapters = {};
        _customRangeError =
            null; // Clear error when switching away from Custom Range
      }
    });
  }

  Future<void> _loadLastSearch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSearch = prefs.getString('lastNoteSearchTerm');
      if (lastSearch == null || lastSearch.trim().isEmpty) {
        await prefs.setDouble('noteSearchScrollOffset', 0.0);
        setState(() {
          _controller.text = '';
          _searchResults = [];
        });
        return;
      }

      // Load last search options
      final lastSearchUseRegex =
          prefs.getBool('lastNoteSearchUseRegex') ?? false;
      final lastSearchUseWholeWord =
          prefs.getBool('lastNoteSearchUseWholeWord') ?? false;
      final lastSearchCaseSensitive =
          prefs.getBool('lastNoteSearchCaseSensitive') ?? false;

      setState(() {
        _useRegex = lastSearchUseRegex;
        _useWholeWord = lastSearchUseWholeWord;
        _caseSensitive = lastSearchCaseSensitive;
        _controller.text = lastSearch;
        _isSearching = true;
      });

      final patternData =
          _buildSearchPattern(_useRegex, lastSearch, _useWholeWord);
      _currentRegex = patternData['Regular Expressions'] as RegExp;

      // Perform the search
      final results = await _searchNotes(lastSearch);

      // Calculate match and verse counts
      int verseCount = results.length;
      int matchCount = 0;
      for (var note in results) {
        String text = _getSearchText(note['note_text'] as String);
        matchCount += _currentRegex!.allMatches(text).length;
      }

      setState(() {
        _searchResults = results;
        _setTotals(matchCount, verseCount);
        _isSearching = false;
      });
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('noteSearchScrollOffset', 0.0);
      setState(() {
        _controller.text = '';
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  Future<void> _saveLastSearch(String term, bool useRegex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastNoteSearchTerm', term);
    await prefs.setBool('lastNoteSearchUseRegex', useRegex);
    await prefs.setBool('lastNoteSearchUseWholeWord', _useWholeWord);
    await prefs.setBool('lastNoteSearchCaseSensitive', _caseSensitive);
  }

  Future<void> _saveScrollOffset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
        'noteSearchScrollOffset', _resultsScrollController.offset);
  }

  // Reset results scroll position and stored offset to top for new searches.
  Future<void> _resetResultsScrollToTop() async {
    try {
      if (_resultsScrollController.hasClients) {
        _resultsScrollController.jumpTo(0.0);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_resultsScrollController.hasClients) {
            _resultsScrollController.jumpTo(0.0);
          }
        });
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('noteSearchScrollOffset', 0.0);
    } catch (_) {}
  }

  Future<void> _onSearch() async {
    // Validate input - prevent empty searches that would cause freezing
    final searchText = _useRegex ? _controller.text : _controller.text.trim();
    if (searchText.isEmpty) {
      setState(() {
        _searchResults = [];
        _setTotals(0, 0);
      });
      return;
    }

    // Show loading indicator
    setState(() {
      _isSearching = true;
      _searchResults = [];
      _setTotals(0, 0);
    });

    // Ensure results start at the top for each new search
    await _resetResultsScrollToTop();

    try {
      final patternData =
          _buildSearchPattern(_useRegex, searchText, _useWholeWord);
      _currentRegex = patternData['Regular Expressions'] as RegExp;

      // Perform the search
      final results = await _searchNotes(searchText);

      // Calculate match and verse counts
      int verseCount = results.length;
      int matchCount = 0;
      for (var note in results) {
        String text = _getSearchText(note['note_text'] as String);
        matchCount += _currentRegex!.allMatches(text).length;
      }

      setState(() {
        _searchResults = results;
        _setTotals(matchCount, verseCount);
        _isSearching = false;
      });

      await _saveLastSearch(searchText, _useRegex);

      // Don't bother to use this bug-workaround if we aren't on windows
      // and we aren't in tablet mode because it can be frustrating having
      // the focus removed when we aren't done typing. when in tablet mode
      // we have to deal with it because the OSK bug is far more frustrating once
      // it is triggered (it opens the OSK on ANY UI interaction)
      if (!kIsWeb && (Platform.isWindows && TabletModeService().isTablet)) {
        // After a delay of 1s, check if any input was recieved in the last 1s, if not
        // then force the focus away to prevent the windows OSK bug
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!_isSearching &&
              DateTime.now().difference(_lastInputTime).inMilliseconds >=
                  1000) {
            if (_searchResults.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _searchButtonFocusNode.canRequestFocus) {
                  _searchButtonFocusNode.requestFocus();
                }
              });
            }
          }
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _setTotals(0, 0);
        _isSearching = false;
      });
    }
  }

  // Show focused help for a single search option (triggered by the
  // circled-i icon next to each toggle in the options drawer).
  void _showSearchOptionHelp(String title, List<String> bullets) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: EdgeInsets.all(0.0),
        contentPadding: EdgeInsets.all(16.0),
        actionsPadding: EdgeInsets.all(0.0),
        titlePadding: EdgeInsets.all(0.0),
        backgroundColor: bgColor,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              ...bullets.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      '\u2022 $b',
                      style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context)),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
              child: Text(
                'Close',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  // Glanceable indicator shown only when any mode toggle is non-default (on).
  // Appears as a small line after the Reset/Search buttons and before results.
  // On the same line it also reports whether a book filter is in use.
  Widget _buildActiveModesIndicator() {
    final activeModes = <String>[];
    if (_caseSensitive) activeModes.add('Case-sensitive');
    if (_useWholeWord) activeModes.add('Whole Word');
    if (_useRegex) activeModes.add('Regular Expressions');
    if (activeModes.isEmpty) return const SizedBox.shrink();

    final bool hasBookFilter = _bookFilterType != 'All Books';
    String indicatorText = activeModes.join(', ');
    if (hasBookFilter) {
      final String filterLabel;
      if (_bookFilterType == 'Custom Range') {
        final custom = _customBookFilter.trim();
        filterLabel = custom.isEmpty ? 'Custom Range' : 'Custom ($custom)';
      } else {
        filterLabel = _bookFilterType;
      }
      indicatorText += ' • Filter: $filterLabel';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 4.0),
      child: Text(
        indicatorText,
        textAlign: TextAlign.center,
        softWrap: true,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: uiFontSize - 4,
          fontFamily: uiFontFamily,
          fontStyle: FontStyle.italic,
          color: getAdaptiveTextColor(context).withValues(alpha: 0.75),
        ),
      ),
    );
  }

  // Builds a drawer toggle row with a large help button to the left of the
  // label (matching the app's size-32 icon convention). The info button
  // sits outside the SwitchListTile so tapping it never flips the toggle.
  Widget _buildSearchOptionTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String helpTitle,
    required List<String> helpBullets,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: Icon(
              Icons.info_outline,
              size: 32,
              color: getAdaptiveTextColor(context),
              semanticLabel: '$title help',
            ),
            tooltip: '$title help',
            onPressed: () => _showSearchOptionHelp(helpTitle, helpBullets),
          ),
        ),
        Expanded(
          child: SwitchListTile(
            title: Text(title,
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
            contentPadding: const EdgeInsets.only(left: 0.0, right: 16.0),
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // Show action menu for search results (simplified for notes)
  void _showNoteSearchResultActionMenu(
      BuildContext context, Map<String, dynamic> result) async {
    final book = result['book'] as String;
    final chapter = result['chapter'] as int;
    final verse = result['verse'] as int;
    final bookName = result['bookLongName'] as String;

    // Get the verse text from database
    String verseText = '';
    try {
      final verses = await BibleDatabase.getVerses(book, chapter);
      final verseData = verses.firstWhere(
        (v) => v['verse'] == verse,
        orElse: () => <String, dynamic>{} as Map<String, Object>,
      );
      verseText = verseData['text'] as String? ?? '';
    } catch (e) {
      verseText = 'Verse not found';
      ErrorHandler.logError(
        '$book $chapter:$verse',
        context: {
          'class': 'NoteSearchScreen',
          'method': '_showNoteSearchResultActionMenu',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
    }

    final cleanVerseText = VerseTextParser.toPlainVerseText(verseText);
    final copyText = '$bookName $chapter:$verse\n$cleanVerseText';

    if (context.mounted) {
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
                    fontSize: uiFontSize + 8,
                    color: getAdaptiveTextColor(context)),
              )),
              onTap: () {
                Navigator.of(context).pop();
                _gotoVerse(book, chapter, verse);
              },
            ),
            ListTile(
              title: Center(
                  child: Text(
                'Show Context',
                style: TextStyle(
                    fontFamily: fontFamilyNotifier.value,
                    fontSize: uiFontSize + 8,
                    color: getAdaptiveTextColor(context)),
              )),
              onTap: () {
                Navigator.of(context).pop();
                _showContextDialog(book, chapter, verse);
              },
            ),
            ListTile(
              title: Center(
                  child: Text(
                'Edit Note',
                style: TextStyle(
                    fontFamily: fontFamilyNotifier.value,
                    fontSize: uiFontSize + 8,
                    color: getAdaptiveTextColor(context)),
              )),
              onTap: () {
                Navigator.of(context).pop();
                _editNoteFromSearch(result);
              },
            ),
            ListTile(
              title: Center(
                  child: Text(
                'Delete Note',
                style: TextStyle(
                    fontFamily: fontFamilyNotifier.value,
                    fontSize: uiFontSize + 8,
                    color: Colors.red),
              )),
              onTap: () {
                Navigator.of(context).pop();
                _deleteNoteFromSearch(result);
              },
            ),
            ListTile(
              title: Center(
                  child: Text(
                'Copy Verse $verse',
                style: TextStyle(
                    fontFamily: fontFamilyNotifier.value,
                    fontSize: uiFontSize + 8,
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
  }

  // Show context dialog with chapter dialog (mirrors search_screen.dart)
  Future<void> _showContextDialog(
      String? book, int? chapter, int? verseNum) async {
    if (book == null || chapter == null || verseNum == null) return;

    // Convert database book name to display key for ChapterDialog
    final normalizedShortBookName = BookNameConverter.normalizeShortName(book);
    // Create reference text to highlight the target verse
    final fullBookName =
        BookNameConverter.shortNameToLongName(normalizedShortBookName);
    final referenceText = '$fullBookName $chapter:$verseNum';

    // Show ChapterDialog with target verse highlighted
    showDialog(
      context: context,
      builder: (context) => ChapterDialog(
        book: normalizedShortBookName,
        chapter: chapter,
        verse: verseNum, // Focus on the target verse
        referenceText: referenceText, // Highlight the target verse
        onNavigateToVerse: (verse) => _gotoVerse(
            normalizedShortBookName, chapter, verse), // Navigate to the verse
        onNoteEditTap: (int verse, String? noteText) => _openNoteFromSearch(
            normalizedShortBookName, chapter, verse, noteText),
        onVerseLink: (link, referenceText) => handleVerseLink(
          context,
          link,
          referenceText,
          navigateToVerse: _gotoVerse,
          onVerseLinkRecursion: null, // Infinite recursion enabled by default
          onNoteEditTap: _openNoteFromSearch,
        ),
      ),
    );
  }

  // Open the note editor for a search result (same behavior as bible screen's
  // Edit Note) and refresh the result row once the editor closes
  Future<void> _editNoteFromSearch(Map<String, dynamic> result) async {
    final book = result['book'] as String;
    final chapter = result['chapter'] as int;
    final verse = result['verse'] as int;
    await _openNoteFromSearch(
        book, chapter, verse, result['note_text'] as String?);
    await _refreshResultAfterEdit(result);
  }

  // Refresh a result row after the note editor closes. If the note was
  // deleted while editing, remove the result since it is no longer valid.
  Future<void> _refreshResultAfterEdit(Map<String, dynamic> result) async {
    final book = result['book'] as String;
    final chapter = result['chapter'] as int;
    final verse = result['verse'] as int;
    try {
      final updated = await NotesDatabase.getNoteForVerse(book, chapter, verse);
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _searchResults.removeWhere((r) => r['id'] == result['id']);
          _recalculateTotals();
        });
      } else if (updated['note_text'] != result['note_text']) {
        setState(() {
          result['note_text'] = updated['note_text'];
        });
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_refreshResultAfterEdit exception',
        context: {
          'class': 'NoteSearchScreen',
          'method': '_refreshResultAfterEdit',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
    }
  }

  // Delete a note from a search result (same confirmation flow as bible
  // screen's Delete Note). On success the result is immediately removed from
  // the search results because it is no longer a valid result.
  Future<void> _deleteNoteFromSearch(Map<String, dynamic> result) async {
    final noteId = result['id'] as int?;
    if (noteId == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text(
            'Are you sure you want to delete this note? This action cannot be undone.',
            style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await NotesDatabase.deleteNote(noteId);
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_deleteNoteFromSearch exception',
        context: {
          'class': 'NoteSearchScreen',
          'method': '_deleteNoteFromSearch',
          'noteId': noteId
        },
      );
      if (mounted) {
        showStyledSnackBar(context, 'Failed to delete note', isError: true);
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _searchResults.removeWhere((r) => r['id'] == noteId);
      _recalculateTotals();
    });
    showStyledSnackBar(context, 'Note deleted');
  }

  // Recalculate the match and note totals after results have changed
  void _recalculateTotals() {
    int noteCount = _searchResults.length;
    int matchCount = 0;
    final regex = _currentRegex;
    if (regex != null) {
      for (final note in _searchResults) {
        String text = _getSearchText(note['note_text'] as String);
        matchCount += regex.allMatches(text).length;
      }
    }
    _setTotals(matchCount, noteCount);
  }

  // Navigate to verse in the source bible screen
  void _gotoVerse(String? book, int? chapter, int? verse) async {
    if (book == null || chapter == null || verse == null) {
      ErrorHandler.logError(
        '_gotoVerse null return: book:"$book" chapter:"$chapter" verse:"$verse"',
        context: {
          'class': 'NoteSearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
      return;
    }

    // Return data to the source bible screen using short book name
    final result = {
      'verseLocation': {
        'book': book, // Use short name for database operations
        'chapter': chapter,
        'verse': verse,
      },
      'targetScreenIndex': widget.sourceScreenIndex ?? 0,
    };

    if (mounted) {
      Navigator.of(context).pop(result);
    }

    // Add verse to history with short book name (database format)
    try {
      HistoryDatabase.addHistory(
          book, chapter, verse, DateTime.now().millisecondsSinceEpoch, false);
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_gotoVerse addHistory exception',
        context: {
          'class': 'NoteSearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
    }
  }

  // Open NoteScreen for editing notes in search screen context
  Future<void> _openNoteFromSearch(
      String book, int chapter, int verse, String? existingNote) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NoteScreen(
                book: book,
                chapter: chapter,
                verse: verse,
                existingNote: existingNote))); // Use provided existing note
  }

  void _toggleSearchOptionsDrawer() {
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) return;

    if (_isOptionsDrawerOpen) {
      scaffoldState.closeEndDrawer();
    } else {
      scaffoldState.openEndDrawer();
    }
  }

  String _formatNumber(int? number) {
    return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+($|\D))'),
        (match) => '${match.group(1)},');
  }

  // Update totals
  void _setTotals(int? matches, int? verses) {
    _totalMatches = matches;
    _totalVerses = verses;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = _adjustBarColor(
        Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      key: _scaffoldKey,
      onEndDrawerChanged: (isOpened) {
        if (_isOptionsDrawerOpen == isOpened) return;
        setState(() {
          _isOptionsDrawerOpen = isOpened;
        });
      },
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(
          size: 32,
          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
        ),
        elevation: 0,
        title: (_totalMatches != null && _totalVerses != null)
            ? Center(
                child: ResponsiveText(
                text:
                    '${_formatNumber(_totalMatches)} ${_totalMatches == 1 ? 'match' : 'matches'} in ${_formatNumber(_totalVerses)} ${_totalVerses == 1 ? 'note' : 'notes'}',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
                minFontSize: uiFontSize - 8,
              ))
            : Text(
                '',
                style: TextStyle(color: Colors.transparent),
              ),
        // Text(
        //     'Notes Search',
        //     style: TextStyle(fontFamily: uiFontFamily, fontSize: uiFontSize + 2, color: getAdaptiveTextColor(context)),
        //   ),
        toolbarHeight: 60,
        backgroundColor: barColor,
        actions: [
          IconButton(
            icon: Icon(
              _isOptionsDrawerOpen ? Icons.menu_open : Icons.menu,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: _isOptionsDrawerOpen
                  ? 'Close Notes Search Options Menu'
                  : 'Show Notes Search Options Menu',
            ),
            tooltip: _isOptionsDrawerOpen ? 'Close' : 'Search Options',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: _toggleSearchOptionsDrawer,
          ),
        ],
      ),
      endDrawer: Drawer(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            width: 1.0,
          ),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value,
        child: SingleChildScrollView(
            child: Column(
          children: [
            AppBar(
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(
                size: 32,
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
              automaticallyImplyLeading: false,
              toolbarHeight: 60,
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? darkBackgroundColor.value
                  : lightBackgroundColor.value,
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.menu_open,
                    size: 32,
                    color: isDark
                        ? darkPrimaryColor.value
                        : lightPrimaryColor.value,
                    semanticLabel: 'Close Notes Search Options Menu',
                  ),
                  tooltip: 'Close',
                  color:
                      isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                  onPressed: () => _scaffoldKey.currentState?.closeEndDrawer(),
                ),
              ],
            ),
            Center(
              child: Text('Notes Search Options',
                  style: TextStyle(
                      fontSize: uiFontSize + 2,
                      fontFamily: uiFontFamily,
                      fontWeight: FontWeight.bold,
                      color: getAdaptiveTextColor(context))),
            ),
            const SizedBox(height: 8),
            Divider(
              indent: 16,
              endIndent: 16,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Mode Toggles',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
            ),
            const SizedBox(height: 8),
            _buildSearchOptionTile(
              title: _caseSensitive
                  ? 'Disable Case-sensitivity'
                  : 'Enable Case-sensitivity',
              value: _caseSensitive,
              onChanged: (val) async {
                setState(() {
                  _caseSensitive = val;
                });
                await _saveSearchOptions();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
              },
              helpTitle: 'Case-sensitivity',
              helpBullets: const [
                'Off: case is ignored, so "love" matches love, Love, and LOVE.',
                'On: only exact case matches, so "Love" will not match "love".',
                'Applies to regular, whole-word, and regex searches.',
              ],
            ),
            _buildSearchOptionTile(
              title: _useWholeWord ? 'Disable Whole Word' : 'Enable Whole Word',
              value: _useWholeWord,
              onChanged: (val) async {
                setState(() {
                  _useWholeWord = val;
                  if (_useWholeWord) _useRegex = false;
                });
                await _saveSearchOptions();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
              },
              helpTitle: 'Whole Word',
              helpBullets: const [
                'Matches complete words only: "love" finds love but NOT loved or lovely.',
                'With several words, a note must contain every word as a whole word.',
                'The * wildcard still works (eg. love* matches love, loved, and loveth).',
                'Enabling this turns off Regular Expressions.',
              ],
            ),
            _buildSearchOptionTile(
              title: _useRegex
                  ? 'Disable Regular Expressions'
                  : 'Enable Regular Expressions',
              value: _useRegex,
              onChanged: (val) async {
                setState(() {
                  _useRegex = val;
                  if (_useRegex) {
                    _useWholeWord = false;
                  }
                });
                await _saveSearchOptions();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
              },
              helpTitle: 'Regular Expressions',
              helpBullets: const [
                'Enables ECMAScript 2018 regular expressions with Unicode property support (eg. \\p{L} matches any letter).',
                'Enabling this turns off Whole Word (they are mutually exclusive).',
                'The caret symbol ^ matches the start of any line (eg. "^My" matches any note that begins with My).',
                'The dollar symbol \$ matches the end of a line (eg. "!\$" matches any note that ends with an exclamation mark).',
                'The period character . matches any single character (eg. "S.chem"). Add a quantifier to match more than one character (eg. "S.+chem").',
                '\\s matches any white-space character (eg. " ").',
                '\\w is shorthand for the word character class [a-zA-Z0-9_] which is the same as any lower or uppercase character, any digit, and the underscore symbol.',
                'Parenthesis group text and combine with the alternation operator | to match close variations (eg. "S(y|i|he)chem" matches "Sichem", "Shechem", and "Sychem").',
                'Character classes match any one of the characters in the set (eg. "[abc]" matches any ONE of a, b, or c; "[a-z]+thite" matches Hamathite, Kohathite, and more).',
                'The negation operator inside character classes excludes characters (eg. "\\b[^gG]od\\b" matches any three-letter word ending in "od" that does not begin with "g" or "G").',
                'Positive/negative lookahead (?=)/(?!) and lookbehinds (?<=)/(?<!) are supported (eg. "(?<!dark)ness" matches words ending with "ness" but not "darkness").',
                'Quantifiers after a character, class, or group set how many match: * = zero or more, + = one or more, ? = zero or one, {n} = exactly n, {n,} = n or more, {n,m} = between n and m.',
              ],
            ),
            const SizedBox(height: 8),
            Divider(
              indent: 16,
              endIndent: 16,
            ),
            const SizedBox(height: 8),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Book Filter',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    fontWeight: FontWeight.normal,
                    color: getAdaptiveTextColor(context)),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: DropdownButton<String>(
                value: _bookFilterType,
                isExpanded: true,
                items: [
                  ...BookFilter.categoryDisplayNames.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(
                        category,
                        style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context)),
                      ),
                    );
                  }),
                  DropdownMenuItem<String>(
                    value: 'Custom Range',
                    child: Text(
                      'Custom Range',
                      style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context)),
                    ),
                  ),
                ],
                onChanged: (String? newValue) async {
                  if (newValue != null) {
                    setState(() {
                      _bookFilterType = newValue;
                      // When switching TO Custom Range, ensure controller shows preserved text
                      if (newValue == 'Custom Range') {
                        _customRangeController.text = _customBookFilter;
                      }
                    });
                    _updateBookFilter();
                    await _saveSearchOptions();
                    if (_controller.text.trim().isNotEmpty) {
                      _onSearch();
                    }
                  }
                },
              ),
            ),
            if (_bookFilterType == 'Custom Range')
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: TextField(
                      autofocus: true,
                      maxLength: 100,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      controller: _customRangeController,
                      decoration: InputDecoration(
                        counter:
                            SizedBox.shrink(), // Hide the counter eg. 0/100
                        hintText: '',
                        hintStyle: TextStyle(
                            fontSize: uiFontSize - 4, fontFamily: uiFontFamily),
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDark
                                ? darkPrimaryColor.value
                                : lightPrimaryColor.value,
                            semanticLabel: 'Clear Custom Range',
                          ),
                          onPressed: () async {
                            setState(() {
                              _customRangeController.clear();
                              _customBookFilter = ''; // Reset underlying state
                              _customRangeError =
                                  null; // Clear any lingering error
                            });
                            await _saveSearchOptions();
                          },
                          iconSize: 32,
                        ),
                        errorText: _customRangeError,
                        errorMaxLines: 3,
                        errorStyle: TextStyle(
                          fontSize: uiFontSize - 4,
                          fontFamily: uiFontFamily,
                          color: Colors.red,
                        ),
                      ),
                      style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context)),
                      onChanged: (value) {
                        _customBookFilter = value;
                        _updateBookFilter();
                      },
                      onSubmitted: (_) async {
                        await _saveSearchOptions();
                        if (_controller.text.trim().isNotEmpty) {
                          _onSearch();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _saveSearchOptions();
                        if (_controller.text.trim().isNotEmpty) {
                          _onSearch();
                        }
                      },
                      child: Text('Apply',
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context,
                                  usePrimaryColor: true))),
                    ),
                  ),
                  if (_bookFilterType == 'Custom Range') ...[
                    const SizedBox(height: 16),
                    ListTile(
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          Text('Custom Range Rules:',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  fontWeight: FontWeight.bold,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 16),
                          Text(
                              '• Both short and long book names are supported.',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 8),
                          Text(
                              '• Book and chapter ranges must be separated by a dash and can optionally include chapter numbers\n(eg. Mat 22 - John).',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 8),
                          Text(
                              '• Multiple ranges must be separated by a comma (,)',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 8),
                          Text(
                              '• For example:\nGenesis, Num 10-20, Jud-Rev, Mat 22 - Joh 15',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                        ]))
                  ],
                ],
              ),
          ],
        )),
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
                      hintText: 'Search your notes',
                      hintStyle: TextStyle(
                          fontFamily: uiFontFamily, fontSize: uiFontSize + 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.blueGrey,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.blueGrey,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.blueGrey,
                          width: 2.0,
                        ),
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
                    onChanged: (_) {
                      _lastInputTime = DateTime.now();
                    },
                    onSubmitted: (_) => _onSearch(),
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
                          onPressed: () async {
                            if (_isResetting) return;
                            setState(() => _isResetting = true);

                            setState(() {
                              _controller.clear();
                              _useRegex = false;
                              _useWholeWord = false;
                              _caseSensitive = false;
                              // Reset book filter
                              _bookFilterType = 'All Books';
                              _customBookFilter = '';
                              _customRangeController.text = '';
                              _searchResults = [];
                              _totalMatches = null;
                              _totalVerses = null;
                            });
                            await _saveSearchOptions();

                            // Clear saved search preferences so they don't restore on screen return
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.remove('lastNoteSearchTerm');
                            await prefs.remove('lastNoteSearchUseRegex');
                            await prefs.remove('lastNoteSearchUseWholeWord');
                            await prefs.remove('lastNoteSearchCaseSensitive');
                            await prefs.remove(_bookFilterTypeKey);
                            await prefs.remove(_bookFilterCustomKey);
                            await prefs.setDouble(
                                'noteSearchScrollOffset', 0.0);

                            if (context.mounted) {
                              showStyledSnackBar(context, 'Search Reset');
                            }

                            Future.delayed(const Duration(seconds: 3), () {
                              if (mounted) {
                                setState(() => _isResetting = false);
                              }
                            });
                          },
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
                  _buildActiveModesIndicator(),
                  Expanded(
                    child: _controller.text.trim().isEmpty
                        ? Center(
                            child: Text(
                              'Enter search terms above to find your notes',
                              style: TextStyle(
                                fontSize: uiFontSize + 6,
                                fontFamily: uiFontFamily,
                                color: getAdaptiveTextColor(context),
                              ),
                            ),
                          )
                        : _isSearching
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text('Searching notes...🔎',
                                        style: TextStyle(
                                            fontSize: uiFontSize + 8,
                                            fontFamily: uiFontFamily,
                                            color:
                                                getAdaptiveTextColor(context))),
                                  ],
                                ),
                              )
                            : (_searchResults.isEmpty &&
                                    (_controller.text.split('"').length - 1) %
                                            2 ==
                                        0)
                                ? Center(
                                    child: Text(
                                        'No matches found in your notes 🧐',
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
                                              child: ListView.builder(
                                                padding: EdgeInsets.only(
                                                    bottom: 100.0),
                                                controller:
                                                    _resultsScrollController,
                                                itemCount:
                                                    _searchResults.length,
                                                itemBuilder: (context, index) {
                                                  final result =
                                                      _searchResults[index];
                                                  // final baseStyle = TextStyle(
                                                  //   fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSize),
                                                  //   color: Theme.of(context).brightness == Brightness.dark ? darkTextColor.value : lightTextColor.value,
                                                  // );

                                                  return GestureDetector(
                                                    onTap: () =>
                                                        _showNoteSearchResultActionMenu(
                                                            context, result),
                                                    child: Container(
                                                      color: barColor,
                                                      width: double.infinity,
                                                      padding: EdgeInsets.only(
                                                          left: 0.0,
                                                          top: 0.0,
                                                          bottom: 0.0,
                                                          right: 18.0),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                '${result['bookLongName'] as String} ${result['chapter']}:${result['verse']}',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: FontSizeAdjustments.getAdjustedSize(
                                                                      fontFamilyNotifier
                                                                          .value,
                                                                      fontSize),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Theme.of(context)
                                                                              .brightness ==
                                                                          Brightness
                                                                              .dark
                                                                      ? darkPrimaryColor
                                                                          .value
                                                                      : lightPrimaryColor
                                                                          .value,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 4),
                                                              // Display the verse text with bible screen styling
                                                              FutureBuilder<
                                                                  List<
                                                                      Map<String,
                                                                          dynamic>>>(
                                                                future: BibleDatabase.getVerses(
                                                                    result['book']
                                                                        as String,
                                                                    result['chapter']
                                                                        as int),
                                                                builder: (context,
                                                                    snapshot) {
                                                                  if (snapshot
                                                                          .connectionState ==
                                                                      ConnectionState
                                                                          .waiting) {
                                                                    return SizedBox
                                                                        .shrink();
                                                                  }
                                                                  if (snapshot
                                                                          .hasError ||
                                                                      !snapshot
                                                                          .hasData) {
                                                                    return SizedBox
                                                                        .shrink();
                                                                  }

                                                                  final verses =
                                                                      snapshot
                                                                          .data!;
                                                                  final verseData =
                                                                      verses
                                                                          .firstWhere(
                                                                    (v) =>
                                                                        v['verse'] ==
                                                                        result[
                                                                            'verse'],
                                                                    orElse: () => <String,
                                                                            dynamic>{}
                                                                        as Map<
                                                                            String,
                                                                            Object>,
                                                                  );

                                                                  if (verseData
                                                                      .isEmpty) {
                                                                    return SizedBox
                                                                        .shrink();
                                                                  }

                                                                  // Display verse text without note-search highlighting
                                                                  final verseTextStyle =
                                                                      TextStyle(
                                                                    fontSize: FontSizeAdjustments.getAdjustedSize(
                                                                        fontFamilyNotifier
                                                                            .value,
                                                                        fontSize),
                                                                    fontFamily:
                                                                        fontFamilyNotifier
                                                                            .value,
                                                                    color: Theme.of(context).brightness ==
                                                                            Brightness
                                                                                .dark
                                                                        ? darkTextColor
                                                                            .value
                                                                        : lightTextColor
                                                                            .value,
                                                                  );

                                                                  // Parse verse text for normal verse styling only
                                                                  final rawVerseText =
                                                                      verseData[
                                                                              'text']
                                                                          as String;
                                                                  final verseSpan =
                                                                      _getVerseSpan(
                                                                          rawVerseText,
                                                                          verseTextStyle);

                                                                  return Text.rich(
                                                                      verseSpan);
                                                                },
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              // Use QuillNoteDisplay to properly render the note
                                                              QuillNoteDisplay(
                                                                noteText: result[
                                                                        'note_text']
                                                                    as String,
                                                                onTap: () =>
                                                                    _editNoteFromSearch(
                                                                        result),
                                                                highlightRegex:
                                                                    _currentRegex,
                                                                highlightColor:
                                                                    _getHighlightColor(
                                                                        context),
                                                                onLinkTap: (url,
                                                                        element) =>
                                                                    handleVerseLink(
                                                                  context,
                                                                  url,
                                                                  element,
                                                                  navigateToVerse:
                                                                      _gotoVerse,
                                                                  onVerseLinkRecursion:
                                                                      null, // Infinite recursion enabled by default in handleVerseLink
                                                                  onNoteEditTap:
                                                                      _openNoteFromSearch,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          if (index <
                                                              _searchResults
                                                                      .length -
                                                                  1)
                                                            Divider(
                                                              thickness: 1,
                                                              height: 16,
                                                              indent: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.01,
                                                              endIndent:
                                                                  MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.01,
                                                              color: const Color
                                                                  .fromARGB(
                                                                  47,
                                                                  158,
                                                                  158,
                                                                  158),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
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
}
