import 'package:flutter/material.dart';
import 'package:selah/utils/snackbar_notification.dart';
import 'dart:math';
import '../database/bible_database.dart';
import '../main.dart';
import '../utils/book_name_converter.dart';
import '../utils/highlight_text_color_adjustments.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/preferences_constants.dart';
import '../utils/verse_reference_detector.dart';

enum TapMode { threeTap, twoTap }

enum NavigationMode { grid, list }

class VerseChooserDialog extends StatefulWidget {
  const VerseChooserDialog({
    super.key,
    this.currentBook,
    this.currentChapter,
    this.currentVerse,
  });

  final String? currentBook;
  final int? currentChapter;
  final int? currentVerse;

  @override
  State<VerseChooserDialog> createState() => _VerseChooserDialogState();
}

class _VerseChooserDialogState extends State<VerseChooserDialog> {
  List<String> _books = [];
  List<int> _chapters = [];
  List<int> _verses = [];
  String? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerse;
  bool _loading = true;
  final _scrollController = ScrollController();
  TapMode _tapMode = TapMode.threeTap;
  NavigationMode _navigationMode = NavigationMode.grid;
  bool _showQuickJump = false;
  final TextEditingController _quickJumpController = TextEditingController();

  // Color coding for book short names (display keys)
  final Map<String, Color> _bookColorsLight = {
    // Genesis - Deuteronomy
    'Gen': Colors.orange, 'Exo': Colors.orange, 'Lev': Colors.orange,
    'Num': Colors.orange, 'Deu': Colors.orange,
    // Joshua - Esther
    'Jos': const Color.fromARGB(255, 168, 152, 5),
    'Jdg': const Color.fromARGB(255, 168, 152, 5),
    'Rth': const Color.fromARGB(255, 168, 152, 5),
    '1Sa': const Color.fromARGB(255, 168, 152, 5),
    '2Sa': const Color.fromARGB(255, 168, 152, 5),
    '1Ki': const Color.fromARGB(255, 168, 152, 5),
    '2Ki': const Color.fromARGB(255, 168, 152, 5),
    '1Ch': const Color.fromARGB(255, 168, 152, 5),
    '2Ch': const Color.fromARGB(255, 168, 152, 5),
    'Ezr': const Color.fromARGB(255, 168, 152, 5),
    'Neh': const Color.fromARGB(255, 168, 152, 5),
    'Est': const Color.fromARGB(255, 168, 152, 5),
    // Job - Song of Solomon
    'Job': Colors.green, 'Psa': Colors.green, 'Pro': Colors.green,
    'Ecc': Colors.green, 'Son': Colors.green,
    // Isaiah - Malachi
    'Isa': Colors.teal, 'Jer': Colors.teal, 'Lam': Colors.teal,
    'Eze': Colors.teal, 'Dan': Colors.teal,
    'Hos': Colors.purple, 'Joe': Colors.purple, 'Amo': Colors.purple,
    'Oba': Colors.purple, 'Jon': Colors.purple,
    'Mic': Colors.purple, 'Nah': Colors.purple, 'Hab': Colors.purple,
    'Zep': Colors.purple, 'Hag': Colors.purple,
    'Zec': Colors.purple, 'Mal': Colors.purple,
    // New Testament
    'Mat': Colors.deepOrange, 'Mar': Colors.deepOrange,
    'Luk': Colors.deepOrange, 'Joh': Colors.deepOrange,
    'Act': Colors.teal, 'Rom': Colors.green, '1Co': Colors.green,
    '2Co': Colors.green, 'Gal': Colors.green,
    'Eph': Colors.green, 'Phi': Colors.green, 'Col': Colors.green,
    '1Th': Colors.green, '2Th': Colors.green,
    '1Ti': Colors.green, '2Ti': Colors.green, 'Tit': Colors.green,
    'Phm': Colors.green, 'Heb': Colors.green,
    'Jam': Colors.indigo, '1Pe': Colors.indigo, '2Pe': Colors.indigo,
    '1Jo': Colors.indigo, '2Jo': Colors.indigo,
    '3Jo': Colors.indigo, 'Jud': Colors.blue, 'Rev': Colors.purple,
  };
  final Map<String, Color> _bookColorsDark = {
    // Same keys, but use lighter/brighter colors for dark mode
    'Gen': Colors.deepOrangeAccent,
    'Exo': Colors.deepOrangeAccent,
    'Lev': Colors.deepOrangeAccent,
    'Num': Colors.deepOrangeAccent,
    'Deu': Colors.deepOrangeAccent,
    'Jos': Colors.amberAccent,
    'Jdg': Colors.amberAccent,
    'Rth': Colors.amberAccent,
    '1Sa': Colors.amberAccent,
    '2Sa': Colors.amberAccent,
    '1Ki': Colors.amberAccent,
    '2Ki': Colors.amberAccent,
    '1Ch': Colors.amberAccent,
    '2Ch': Colors.amberAccent,
    'Ezr': Colors.amberAccent,
    'Neh': Colors.amberAccent, 'Est': Colors.amberAccent,
    'Job': Colors.lightGreenAccent,
    'Psa': Colors.lightGreenAccent,
    'Pro': Colors.lightGreenAccent,
    'Ecc': Colors.lightGreenAccent,
    'Son': Colors.lightGreenAccent,
    'Isa': Colors.cyanAccent,
    'Jer': Colors.cyanAccent,
    'Lam': Colors.cyanAccent,
    'Eze': Colors.cyanAccent,
    'Dan': Colors.cyanAccent,
    'Hos': Colors.purpleAccent,
    'Joe': Colors.purpleAccent,
    'Amo': Colors.purpleAccent,
    'Oba': Colors.purpleAccent,
    'Jon': Colors.purpleAccent,
    'Mic': Colors.purpleAccent,
    'Nah': Colors.purpleAccent,
    'Hab': Colors.purpleAccent,
    'Zep': Colors.purpleAccent,
    'Hag': Colors.purpleAccent,
    'Zec': Colors.purpleAccent, 'Mal': Colors.purpleAccent,
    'Mat': Colors.deepOrange, 'Mar': Colors.deepOrange,
    'Luk': Colors.deepOrange, 'Joh': Colors.deepOrange,
    'Act': Colors.green,
    'Rom': Colors.greenAccent,
    '1Co': Colors.greenAccent,
    '2Co': Colors.greenAccent,
    'Gal': Colors.greenAccent,
    'Eph': Colors.greenAccent,
    'Phi': Colors.greenAccent,
    'Col': Colors.greenAccent,
    '1Th': Colors.greenAccent,
    '2Th': Colors.greenAccent,
    '1Ti': Colors.greenAccent,
    '2Ti': Colors.greenAccent,
    'Tit': Colors.greenAccent,
    'Phm': Colors.greenAccent,
    'Heb': Colors.greenAccent,
    'Jam': Colors.indigoAccent,
    '1Pe': Colors.indigoAccent,
    '2Pe': Colors.indigoAccent,
    '1Jo': Colors.indigoAccent,
    '2Jo': Colors.indigoAccent,
    '3Jo': Colors.indigoAccent, 'Jud': Colors.blueAccent,
    'Rev': Colors.purpleAccent,
  };

  @override
  void initState() {
    //debugPrint('initState running');
    super.initState();
    _loadSettings();
    _loadBooks();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _quickJumpController.dispose();
    super.dispose();
  }

  // Convert a DB code to the canonical display key.
  String _toDisplayKey(String dbName) => dbName.trim();

  bool _isCurrentScreenBook(String book) {
    final currentBook = widget.currentBook?.trim();
    return currentBook != null && _toDisplayKey(book) == currentBook;
  }

  Color _dialogSurfaceColor(BuildContext context) {
    return Theme.of(context).dialogTheme.backgroundColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value);
  }

  Color _adjustSurfaceLightness(Color color, double delta) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  Color _currentBookTileBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = _dialogSurfaceColor(context);
    final preferredCandidate =
        _adjustSurfaceLightness(baseColor, isDark ? 0.045 : -0.1);
    final fallbackCandidate =
        _adjustSurfaceLightness(baseColor, isDark ? 0.07 : -0.1);
    final preferredContrast =
        calculateContrastRatio(baseColor, preferredCandidate);

    if (preferredContrast >= 1.08) {
      return preferredCandidate;
    }

    return fallbackCandidate;
  }

  double _measureTextWidth(
    BuildContext context,
    String text,
    TextStyle style, {
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  double _measureTextHeight(
    BuildContext context,
    String text,
    TextStyle style, {
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.height;
  }

  Size _scaledTileSize(
    BuildContext context, {
    required Iterable<String> labels,
    required TextStyle style,
    double horizontalPadding = 14,
    double verticalPadding = 8,
    double minWidth = 48,
    double minHeight = 36,
    int maxLines = 1,
  }) {
    if (labels.isEmpty) {
      return Size(minWidth, minHeight);
    }

    double maxWidth = 0;
    double maxHeight = 0;
    for (final label in labels) {
      maxWidth = max(
        maxWidth,
        _measureTextWidth(context, label, style, maxLines: maxLines),
      );
      maxHeight = max(
        maxHeight,
        _measureTextHeight(context, label, style, maxLines: maxLines),
      );
    }

    return Size(
      max(minWidth, maxWidth + horizontalPadding),
      max(minHeight, maxHeight + verticalPadding),
    );
  }

  Future<void> _loadBooks() async {
    //debugPrint('_loadBooks starting');
    List<String> books = await BibleDatabase.getBooks();
    books = books.map((b) => b.trim()).toList();

    if (_navigationMode == NavigationMode.list && books.isNotEmpty) {
      // For list mode, pre-load everything before setting state

      final preferredBook = widget.currentBook?.trim();
      final initialBook = preferredBook != null && books.contains(preferredBook)
          ? preferredBook
          : books.first;
      List<int> chapters = await BibleDatabase.getChapters(initialBook);
      chapters.sort();

      if (chapters.isNotEmpty) {
        final initialChapter = widget.currentBook?.trim() == initialBook &&
                widget.currentChapter != null &&
                chapters.contains(widget.currentChapter)
            ? widget.currentChapter!
            : chapters.first;
        final verses =
            await BibleDatabase.getVerses(initialBook, initialChapter);
        final verseNums = verses.map((v) {
          final val = v['verse'];
          return val is int ? val : int.tryParse(val.toString()) ?? 0;
        }).toList()
          ..sort();

        final initialVerse = widget.currentBook?.trim() == initialBook &&
                widget.currentChapter == initialChapter &&
                widget.currentVerse != null &&
                verseNums.contains(widget.currentVerse)
            ? widget.currentVerse
            : (verseNums.isNotEmpty ? verseNums.first : null);

        setState(() {
          _books = books;
          _selectedBook = initialBook;
          _chapters = chapters;
          _selectedChapter = initialChapter;
          _verses = verseNums;
          _selectedVerse = initialVerse;
          _loading = false;
        });
      } else {
        setState(() {
          _books = books;
          _selectedBook = initialBook;
          _chapters = chapters;
          _selectedChapter = chapters.isNotEmpty ? chapters.first : null;
          _verses = [];
          _selectedVerse = null;
          _loading = false;
        });
      }
    } else {
      // For grid mode
      setState(() {
        _books = books;
        _selectedBook = null;
        _chapters = [];
        _selectedChapter = null;
        _verses = [];
        _selectedVerse = null;
        _loading = false;
      });
    }
  }

  Future<void> _loadChapters() async {
    if (_selectedBook != null) {
      List<int> chapters = await BibleDatabase.getChapters(_selectedBook!);
      // Ensure natural numeric order
      final sortedChapters = [...chapters]..sort();
      setState(() {
        _chapters = sortedChapters;
        _selectedChapter = null;
        _verses = [];
        _selectedVerse = null;
      });
    }
  }

  Future<void> _loadVerses() async {
    if (_selectedBook != null && _selectedChapter != null) {
      final verses =
          await BibleDatabase.getVerses(_selectedBook!, _selectedChapter!);
      // Map to ints robustly and sort numerically
      final verseNums = verses.map((v) {
        final val = v['verse'];
        return val is int ? val : int.tryParse(val.toString()) ?? 0;
      }).toList()
        ..sort();
      setState(() {
        _verses = verseNums;
        _selectedVerse = null;
      });
    }
  }

  void _onBookSelected(String book) async {
    setState(() {
      _selectedBook = book;
      // For list mode, don't auto-select chapter - let user choose
      if (_navigationMode != NavigationMode.list) {
        _selectedChapter = null;
        _selectedVerse = null;
        _chapters = [];
        _verses = [];
      }
    });
    await _loadChapters();
    _scrollController.jumpTo(0.0);
    if (_navigationMode == NavigationMode.list && _chapters.isNotEmpty) {
      // For list mode, pre-select first chapter but don't auto-navigate
      setState(() {
        _selectedChapter = _chapters.first;
      });
      await _loadVerses();
      if (_verses.isNotEmpty) {
        setState(() {
          _selectedVerse = _verses.first;
        });
      }
    }
  }

  void _onChapterSelected(int chapter) async {
    setState(() {
      _selectedChapter = chapter;
      // For list mode, don't auto-navigate - let user choose verse
      if (_navigationMode != NavigationMode.list) {
        if (_tapMode == TapMode.twoTap) {
          // For two tap in grid mode, immediately navigate with verse null
          // to scroll to top of chapter (showing any titles)
          _selectedVerse = null;
          Navigator.pop(context, {
            'book': _selectedBook,
            'chapter': _selectedChapter,
            'verse': null,
          });
          return;
        }
        _selectedVerse = null;
        _verses = [];
      }
    });
    await _loadVerses();
    _scrollController.jumpTo(0.0);
    if (_navigationMode == NavigationMode.list && _verses.isNotEmpty) {
      // For list mode, pre-select first verse but don't auto-navigate
      setState(() {
        _selectedVerse = _verses.first;
      });
    }
  }

  void _onVerseSelected(int verse) {
    setState(() {
      _selectedVerse = verse;
    });
    // For list mode, don't auto-navigate - only navigate when Go is pressed
    if (_navigationMode != NavigationMode.list &&
        _selectedBook != null &&
        _selectedChapter != null &&
        _selectedVerse != null) {
      Navigator.pop(context, {
        'book': _selectedBook,
        'chapter': _selectedChapter,
        'verse': _selectedVerse,
      });
    }
  }

  // Back: from chapters to books
  Future<void> _backToBookChoice() async {
    setState(() {
      _selectedBook = null;
      _selectedChapter = null;
      _selectedVerse = null;
      _chapters = [];
      _verses = [];
    });
  }

  // Back: from verses to chapters
  Future<void> _backToChapterChoice() async {
    setState(() {
      _selectedChapter = null; // keep _selectedBook
      _selectedVerse = null;
      _verses = [];
    });
    // Ensure chapters list is loaded (should already be, but safe)
    if (_chapters.isEmpty && _selectedBook != null) {
      await _loadChapters();
    }
  }

  // Preferences keys
  static const String _prefsKeyTapMode = 'verseChooserTapMode';
  static const String _prefsKeyNavigationMode = 'verseChooserNavigationMode';
  static const String _prefsKeyShowQuickJump = 'verseChooserShowQuickJump';

  // Load saved settings
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tapModeIdx = prefs.getInt(_prefsKeyTapMode);
      final navigationModeIdx = prefs.getInt(_prefsKeyNavigationMode);
      final showQuickJump = prefs.getBool(_prefsKeyShowQuickJump);
      if (mounted) {
        setState(() {
          _tapMode =
              tapModeIdx != null ? TapMode.values[tapModeIdx] : TapMode.twoTap;
          _navigationMode = navigationModeIdx != null
              ? NavigationMode.values[navigationModeIdx]
              : NavigationMode.grid;
          _showQuickJump = showQuickJump ?? true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tapMode = TapMode.twoTap;
          _navigationMode = NavigationMode.grid;
          _showQuickJump = true;
        });
      }
    }
  }

  // Save settings
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyTapMode, _tapMode.index);
    await prefs.setInt(_prefsKeyNavigationMode, _navigationMode.index);
    await prefs.setBool(_prefsKeyShowQuickJump, _showQuickJump);
  }

  void _onSettingsChanged({
    TapMode? tapMode,
    NavigationMode? navigationMode,
    bool? showQuickJump,
  }) {
    setState(() {
      if (tapMode != null) _tapMode = tapMode;
      if (navigationMode != null) _navigationMode = navigationMode;
      if (showQuickJump != null) _showQuickJump = showQuickJump;
    });
    _saveSettings();
  }

  void _onQuickJumpSubmit(String text) {
    final reference = VerseReferenceDetector.detectQuickJumpReference(text);
    //debugPrint('$reference');
    if (reference != null) {
      Navigator.pop(context, {
        'book': reference.book,
        'chapter': reference.chapter,
        'verse': reference.verse,
      });
    } else {
      showStyledSnackBar(context, 'Invalid Verse Reference');
    }
  }

  Widget _buildQuickJumpField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_showQuickJump) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 44, right: 44, bottom: 16),
      child: TextField(
        autofocus:
            false, // Don't autofocus, it's annoying on mobile/tablet mode
        textAlign: TextAlign.center,
        maxLength: 25,
        style: TextStyle(
            fontFamily: uiFontFamily,
            fontSize: uiFontSize + 6,
            color: getAdaptiveTextColor(context)),
        controller: _quickJumpController,
        decoration: InputDecoration(
          counterText: "",
          contentPadding: const EdgeInsets.only(top: 18),
          //labelText: 'Quick Jump',
          //labelStyle: TextStyle(fontFamily: uiFontFamily, fontSize: uiFontSize),
          //alignLabelWithHint: true,
          //floatingLabelBehavior: FloatingLabelBehavior.never,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                width:
                    2.0), // Example focused color (e.g., blue, slightly thicker)
          ),
          // Color when the TextField is not focused (but enabled)
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                width: 1.0), // Example unfocused color (e.g., grey, thinner)
          ),
          suffixIcon: IconButton(
            icon: Icon(
              size: 32,
              Icons.search_rounded,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            ),
            onPressed: () {
              // Don't bother if empty
              // Don't bother if less than 5 characters (shortest book name + 1 space + 1 digit)
              if (_quickJumpController.text.isNotEmpty &&
                  _quickJumpController.text.length >= 5) {
                _onQuickJumpSubmit(_quickJumpController.text);
              }
            },
          ),
        ),
        onSubmitted: _onQuickJumpSubmit,
      ),
    );
  }

  Widget _buildDropdownSelector() {
    if (_books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No books found! This is a critical error.\nUninstalling and reinstalling this app might fix this problem.',
              style: TextStyle(
                  color: Colors.red,
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily),
            ),
          ],
        ),
      );
    }

    //debugPrint('Books: $_books');
    //debugPrint('Chapters: $_chapters');
    //debugPrint('Verses: $_verses');

    // When switching from Grid mode (which uses _selectedBook == null to determine when
    // the settings icon should be shown and when it shouldn't) reset to default values
    _selectedBook ??= 'Gen';
    _selectedChapter ??= 1;
    _selectedVerse ??= 1;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentBookBackground = _currentBookTileBackground(context);

    final dropdownTextStyle =
        TextStyle(fontFamily: uiFontFamily, fontSize: uiFontSize);
    final bookLabels = _books.map(BookNameConverter.shortNameToLongName);
    final chapterLabels =
        _chapters.isEmpty ? <String>['119'] : _chapters.map((c) => '$c');
    final verseLabels =
        _verses.isEmpty ? <String>['176'] : _verses.map((v) => '$v');

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width - 64;

          final bookWidth = _scaledTileSize(
            context,
            labels: bookLabels,
            style: dropdownTextStyle,
            horizontalPadding: 92,
            verticalPadding: 0,
            minWidth: 180,
            minHeight: 0,
          ).width;
          final chapterWidth = _scaledTileSize(
            context,
            labels: chapterLabels,
            style: dropdownTextStyle,
            horizontalPadding: 92,
            verticalPadding: 0,
            minWidth: 180,
            minHeight: 0,
          ).width;
          final verseWidth = _scaledTileSize(
            context,
            labels: verseLabels,
            style: dropdownTextStyle,
            horizontalPadding: 92,
            verticalPadding: 0,
            minWidth: 180,
            minHeight: 0,
          ).width;

          final dropdownWidth =
              min(maxWidth, max(bookWidth, max(chapterWidth, verseWidth)));

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: dropdownWidth,
                  child: DropdownButton<String>(
                    value: _selectedBook,
                    isExpanded: true,
                    alignment: Alignment.center,
                    underline: Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark
                          ? darkPrimaryColor.value
                          : lightPrimaryColor.value,
                    ),
                    icon: Icon(
                      Icons.menu_book_rounded,
                      color: isDark
                          ? darkPrimaryColor.value
                          : lightPrimaryColor.value,
                    ),
                    selectedItemBuilder: (context) {
                      return _books.map((b) {
                        final isCurrentScreenBook = _isCurrentScreenBook(b);
                        return Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isCurrentScreenBook
                                  ? currentBookBackground
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Text(
                              BookNameConverter.shortNameToLongName(b),
                              style: dropdownTextStyle,
                              textAlign: TextAlign.center,
                              softWrap: true,
                            ),
                          ),
                        );
                      }).toList();
                    },
                    items: [
                      ..._books.map((b) => DropdownMenuItem(
                            value: b,
                            child: Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _isCurrentScreenBook(b)
                                      ? currentBookBackground
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(
                                  BookNameConverter.shortNameToLongName(b),
                                  style: dropdownTextStyle,
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                ),
                              ),
                            ),
                          )),
                    ],
                    onChanged: (book) => _onBookSelected(book!),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: dropdownWidth,
                  child: DropdownButton<int>(
                    value: _selectedChapter,
                    isExpanded: true,
                    alignment: Alignment.center,
                    underline: Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark
                          ? darkPrimaryColor.value
                          : lightPrimaryColor.value,
                    ),
                    icon: Icon(
                      Icons.library_books_rounded,
                      color: isDark
                          ? darkPrimaryColor.value
                          : lightPrimaryColor.value,
                    ),
                    selectedItemBuilder: (context) {
                      return _chapters.map((c) {
                        return Center(
                          child: Text(
                            '$c',
                            style: dropdownTextStyle,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }).toList();
                    },
                    items: _chapters.isEmpty
                        ? []
                        : _chapters
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Center(
                                    child: Text(
                                      '$c',
                                      style: dropdownTextStyle,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ))
                            .toList(),
                    onChanged: (chapter) => _onChapterSelected(chapter!),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: dropdownWidth,
                  child: DropdownButton<int>(
                    value: _selectedVerse,
                    isExpanded: true,
                    alignment: Alignment.center,
                    underline: Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark
                          ? darkPrimaryColor.value
                          : lightPrimaryColor.value,
                    ),
                    icon: Icon(
                      Icons.pageview_rounded,
                      color: isDark
                          ? darkPrimaryColor.value
                          : lightPrimaryColor.value,
                    ),
                    selectedItemBuilder: (context) {
                      return _verses.map((v) {
                        return Center(
                          child: Text(
                            '$v',
                            style: dropdownTextStyle,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }).toList();
                    },
                    items: _verses.isEmpty
                        ? []
                        : _verses
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Center(
                                    child: Text(
                                      '$v',
                                      style: dropdownTextStyle,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ))
                            .toList(),
                    onChanged: (verse) => _onVerseSelected(verse!),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _selectedBook != null &&
                          _selectedChapter != null &&
                          _selectedVerse != null
                      ? () {
                          Navigator.pop(context, {
                            'book': _selectedBook,
                            'chapter': _selectedChapter,
                            'verse': _selectedVerse,
                          });
                        }
                      : null,
                  child: Text(
                    'Go',
                    style: TextStyle(
                      fontFamily: uiFontFamily,
                      fontSize: uiFontSize,
                      color:
                          getAdaptiveTextColor(context, usePrimaryColor: true),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettingsDialog() {
    // Local copies for the dialog - moved outside StatefulBuilder to persist across rebuilds
    TapMode localTapMode = _tapMode;
    NavigationMode localNavigationMode = _navigationMode;
    bool localShowQuickJump = _showQuickJump;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              //title: Text('Verse Chooser Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        'Enables manual\n book, chapter, and optional\nverse entry (eg. John 3).',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: uiFontFamily,
                            fontSize: uiFontSize,
                            color: getAdaptiveTextColor(context))),
                    SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Quick Jump',
                          style: TextStyle(
                              fontFamily: uiFontFamily,
                              fontSize: uiFontSize,
                              color: getAdaptiveTextColor(context))),
                      value: localShowQuickJump,
                      onChanged: (bool value) {
                        setStateDialog(() => localShowQuickJump = value);
                      },
                    ),
                    SizedBox(height: 8),
                    Divider(
                      thickness: 1,
                      color: getAdaptiveTextColor(context),
                    ),
                    SizedBox(height: 8),
                    Text(
                        'When in grid mode\n3-Tap requires choosing\na verse number and\n2-Tap does not.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: uiFontFamily,
                            fontSize: uiFontSize,
                            color: getAdaptiveTextColor(context))),
                    SizedBox(height: 16),
                    SwitchListTile(
                      title: Text(
                          localTapMode == TapMode.threeTap
                              ? '3 Tap Mode'
                              : '2 Tap Mode',
                          style: TextStyle(
                              fontFamily: uiFontFamily,
                              fontSize: uiFontSize,
                              color: getAdaptiveTextColor(context))),
                      value: localTapMode == TapMode.threeTap,
                      onChanged: (bool value) {
                        setStateDialog(() {
                          localTapMode =
                              value ? TapMode.threeTap : TapMode.twoTap;
                        });
                      },
                    ),
                    SizedBox(height: 8),
                    Divider(
                      thickness: 1,
                      color: getAdaptiveTextColor(context),
                    ),
                    SizedBox(height: 8),
                    Text(
                        'Navigate books using\ndrop-down lists\nor a colored grid.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: uiFontFamily,
                            fontSize: uiFontSize,
                            color: getAdaptiveTextColor(context))),
                    SizedBox(height: 16),
                    SwitchListTile(
                      title: Text(
                          localNavigationMode == NavigationMode.grid
                              ? 'Grid'
                              : 'List',
                          style: TextStyle(
                              fontFamily: uiFontFamily,
                              fontSize: uiFontSize,
                              color: getAdaptiveTextColor(context))),
                      value: localNavigationMode == NavigationMode.grid,
                      onChanged: (bool value) {
                        setStateDialog(() {
                          // Reset values when switching modes
                          if (value) {
                            // Grid Mode
                            _selectedBook = null;
                            _selectedChapter = null;
                            _selectedVerse = null;
                          } else {
                            // List Mode
                            _selectedBook = widget.currentBook ?? 'Gen';
                            _selectedChapter = widget.currentChapter ?? 1;
                            _selectedVerse = widget.currentVerse ?? 1;
                          }
                          localNavigationMode =
                              value ? NavigationMode.grid : NavigationMode.list;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setStateDialog(() {
                      localTapMode = TapMode.threeTap;
                      localNavigationMode = NavigationMode.grid;
                      localShowQuickJump = false;
                      // Reset selections when switching to grid mode
                      _selectedBook = null;
                      _selectedChapter = null;
                      _selectedVerse = null;
                    });
                  },
                  child: Text('Reset',
                      style: TextStyle(
                          fontFamily: uiFontFamily,
                          fontSize: uiFontSize,
                          color: Colors.red)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(
                          fontFamily: uiFontFamily,
                          fontSize: uiFontSize,
                          color: getAdaptiveTextColor(context))),
                ),
                TextButton(
                  onPressed: () {
                    _onSettingsChanged(
                      tapMode: localTapMode,
                      navigationMode: localNavigationMode,
                      showQuickJump: localShowQuickJump,
                    );
                    // Close both dialogs when settings are saved to avoid weird
                    // UI issues when switching from grid to list mode (the list mode
                    // doesn't looks like it builds correctly until it is closed and then
                    // reopened)
                    int count = 0;
                    Navigator.popUntil(context, (route) {
                      return count++ == 2;
                    });
                  },
                  child: Text('Save',
                      style: TextStyle(
                          fontFamily: uiFontFamily,
                          fontSize: uiFontSize,
                          color: getAdaptiveTextColor(context))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Compact settings button that opens the options menu
  // Widget _buildCompactSettingsButton(Color txtColor) {
  //   return GestureDetector(
  //     behavior: HitTestBehavior.opaque,
  //     onTap: () => _showSettingsDialog(),
  //     child: SizedBox(
  //       height: 32,
  //       width: 32,
  //       child: Icon(
  //         Icons.settings,
  //         color: txtColor,
  //         size: 32,
  //         semanticLabel: 'Verse Chooser Settings',
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final txtColor = isDark ? darkTextColor.value : lightTextColor.value;
    final bookColors = isDark ? _bookColorsDark : _bookColorsLight;
    final currentBookBackground = _currentBookTileBackground(context);
    final bookTileStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: uiFontSize + 6,
      fontFamily: fontFamilyNotifier.value,
    );
    final numberTileStyle = TextStyle(
      fontWeight: FontWeight.normal,
      fontSize: uiFontSize + 7,
      fontFamily: fontFamilyNotifier.value,
    );
    final dropdownStyle =
        TextStyle(fontFamily: uiFontFamily, fontSize: uiFontSize);

    final bookChipSize = _scaledTileSize(
      context,
      labels: _books.map(_toDisplayKey),
      style: bookTileStyle,
      horizontalPadding: 20,
      verticalPadding: 10,
      minWidth: 67,
      minHeight: 36,
    );
    final chapterChipSize = _scaledTileSize(
      context,
      labels: _chapters.isEmpty ? ['119'] : _chapters.map((c) => '$c'),
      style: numberTileStyle,
      horizontalPadding: 18,
      verticalPadding: 10,
      minWidth: 48,
      minHeight: 36,
    );
    final verseChipSize = _scaledTileSize(
      context,
      labels: _verses.isEmpty ? ['176'] : _verses.map((v) => '$v'),
      style: numberTileStyle,
      horizontalPadding: 18,
      verticalPadding: 10,
      minWidth: 48,
      minHeight: 36,
    );

    const gridSpacing = 8.0;
    const gridColumns = 6;
    final gridContentWidth = (bookChipSize.width * gridColumns) +
        (gridSpacing * (gridColumns - 1)) +
        24;
    final listBookWidth = _measureTextWidth(
          context,
          _books
              .map(BookNameConverter.shortNameToLongName)
              .fold('', (a, b) => b.length > a.length ? b : a),
          dropdownStyle,
        ) +
        120;
    final longestChapterLabel =
        _chapters.isEmpty ? '119' : _chapters.fold<int>(0, max).toString();
    final longestVerseLabel =
        _verses.isEmpty ? '176' : _verses.fold<int>(0, max).toString();
    final listNumberWidth = max(
          _measureTextWidth(context, longestChapterLabel, dropdownStyle),
          _measureTextWidth(context, longestVerseLabel, dropdownStyle),
        ) +
        120;
    final listContentWidth = max(285.0, max(listBookWidth, listNumberWidth));
    final maxDialogWidth = max(280.0, MediaQuery.of(context).size.width - 32);
    final targetDialogWidth = _navigationMode == NavigationMode.grid
        ? max(480.0, gridContentWidth)
        : listContentWidth;
    final dialogWidth =
        targetDialogWidth.clamp(280.0, maxDialogWidth).toDouble();

    // Use display key for color of the selected book title
    Color? selectedBookColor;
    if (_selectedBook != null) {
      final disp = _toDisplayKey(_selectedBook!);
      selectedBookColor = bookColors[disp] ?? txtColor;
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.all(8),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height - 64,
                ),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildQuickJumpField(),
                          if (_navigationMode == NavigationMode.list)
                            _buildDropdownSelector()
                          else
                            Builder(
                              builder: (context) {
                                // Book selection (grid mode)
                                if (_selectedBook == null) {
                                  final otList = _books.take(39).toList();
                                  final ntList = _books.skip(39).toList();

                                  Widget buildBookWrap(List<String> list) {
                                    return Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: list.map((b) {
                                        final disp = _toDisplayKey(b);
                                        final isCurrentScreenBook =
                                            _isCurrentScreenBook(b);
                                        final textStyle = TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: bookColors[disp] ?? txtColor,
                                          fontSize: uiFontSize + 6,
                                          fontFamily: fontFamilyNotifier.value,
                                        );
                                        return GestureDetector(
                                          onTap: () => _onBookSelected(b),
                                          child: Container(
                                            width: bookChipSize.width,
                                            height: bookChipSize.height,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: isCurrentScreenBook
                                                  ? currentBookBackground
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.transparent,
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Text(
                                              disp,
                                              textAlign: TextAlign.center,
                                              style: textStyle,
                                              overflow: TextOverflow.clip,
                                              softWrap: false,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Center(child: buildBookWrap(otList)),
                                      Divider(
                                        thickness: 1,
                                        height: 16,
                                        indent:
                                            MediaQuery.of(context).size.width *
                                                0.01,
                                        endIndent:
                                            MediaQuery.of(context).size.width *
                                                0.01,
                                        color: const Color.fromARGB(
                                            47, 158, 158, 158),
                                      ),
                                      Center(child: buildBookWrap(ntList)),
                                    ],
                                  );
                                }

                                // Chapter selection (grid mode)
                                if (_selectedBook != null &&
                                    _selectedChapter == null) {
                                  final disp = _toDisplayKey(_selectedBook!);
                                  final wide =
                                      MediaQuery.of(context).size.width >= 360;
                                  final title = wide
                                      ? BookNameConverter.shortNameToLongName(
                                          _selectedBook!)
                                      : disp;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.arrow_back,
                                              color:
                                                  selectedBookColor ?? txtColor,
                                              size: 32,
                                              semanticLabel: 'Back',
                                            ),
                                            tooltip: 'Back to books',
                                            onPressed: _backToBookChoice,
                                          ),
                                          Expanded(
                                            child: Text(
                                              title,
                                              textAlign: TextAlign.center,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: uiFontSize + 7,
                                                color: selectedBookColor ??
                                                    txtColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Center(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _chapters
                                              .map((c) => GestureDetector(
                                                    child: Container(
                                                      width:
                                                          chapterChipSize.width,
                                                      height: chapterChipSize
                                                          .height,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: Colors
                                                              .transparent,
                                                          width: 0.5,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        '$c',
                                                        textAlign:
                                                            TextAlign.center,
                                                        softWrap: false,
                                                        style: TextStyle(
                                                          color: txtColor,
                                                          fontWeight:
                                                              FontWeight.normal,
                                                          fontSize:
                                                              uiFontSize + 7,
                                                          fontFamily:
                                                              fontFamilyNotifier
                                                                  .value,
                                                        ),
                                                      ),
                                                    ),
                                                    onTap: () =>
                                                        _onChapterSelected(c),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                }

                                // Verse selection (grid mode)
                                if (_selectedBook != null &&
                                    _selectedChapter != null) {
                                  final disp = _toDisplayKey(_selectedBook!);
                                  final wide =
                                      MediaQuery.of(context).size.width >= 360;
                                  final bookLabel = wide
                                      ? BookNameConverter.shortNameToLongName(
                                          _selectedBook!)
                                      : disp;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.arrow_back,
                                              color:
                                                  selectedBookColor ?? txtColor,
                                              size: 32,
                                              semanticLabel: 'Back',
                                            ),
                                            tooltip: 'Back to chapters',
                                            onPressed: _backToChapterChoice,
                                          ),
                                          Expanded(
                                            child: Text(
                                              '$bookLabel ${_selectedChapter!}',
                                              textAlign: TextAlign.center,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: uiFontSize + 7,
                                                color: selectedBookColor ??
                                                    txtColor,
                                                fontFamily:
                                                    fontFamilyNotifier.value,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Center(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _verses
                                              .map((v) => GestureDetector(
                                                    child: Container(
                                                      width:
                                                          verseChipSize.width,
                                                      height:
                                                          verseChipSize.height,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: Colors
                                                              .transparent,
                                                          width: 0.5,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        '$v',
                                                        softWrap: false,
                                                        style: TextStyle(
                                                          color: txtColor,
                                                          fontSize:
                                                              uiFontSize + 7,
                                                          fontWeight:
                                                              FontWeight.normal,
                                                          fontFamily:
                                                              fontFamilyNotifier
                                                                  .value,
                                                        ),
                                                      ),
                                                    ),
                                                    onTap: () =>
                                                        _onVerseSelected(v),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                }

                                return SizedBox.shrink();
                              },
                            ),
                        ],
                      ),
                    ),
                    if (_selectedBook == null ||
                        _navigationMode == NavigationMode.list)
                      Positioned(
                        bottom: 0.0, // Keep it always at the bottom right
                        right: 0.0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showSettingsDialog(),
                          child: SizedBox(
                            height: 32,
                            width: 32,
                            child: Icon(
                              Icons.settings,
                              color: isDark
                                  ? darkPrimaryColor.value
                                  : lightPrimaryColor.value,
                              size: 32,
                              semanticLabel: 'Verse Chooser Settings',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
