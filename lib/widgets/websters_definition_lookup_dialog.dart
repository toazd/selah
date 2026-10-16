import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/websters_1828_definitions_database.dart';
import '../main.dart';
import '../utils/bible_utils.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';
import 'websters_definition_renderer.dart';

class WebstersDefinitionDialog {
  static Future<void> show(
    BuildContext context,
    String input,
  ) async {
    final headword = Websters1828DefinitionsDatabase.findHeadword(input);
    final definition = headword == null
        ? null
        : Websters1828DefinitionsDatabase.getDefinition(headword);

    if (!context.mounted || headword == null || definition == null) {
      if (context.mounted) {
        showStyledSnackBar(
          context,
          'Definition not found for $input',
          isError: true,
        );
      }
      return;
    }

    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final maxWidth = MediaQuery.of(context).size.width * 0.9;
    final constrainedMaxWidth = isMobile
        ? MediaQuery.of(context).size.width
        : (maxWidth > 720.0 ? 720.0 : maxWidth);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0)
            : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        titlePadding: const EdgeInsets.fromLTRB(24.0, 8.0, 8.0, 0.0),
        title: Row(
          children: [
            Expanded(
              child: Text(
                headword,
                style: textStyle(dialogContext, uiFontSize, bold: true),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constrainedMaxWidth,
            maxHeight: maxHeight,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: buildDefinitionWidgets(
                dialogContext,
                definition,
                onDictionaryTap: (linkedHeadword) =>
                    show(dialogContext, linkedHeadword),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final plain =
                  '$headword\n${Websters1828DefinitionsDatabase.stripHtml(definition)}';
              Clipboard.setData(ClipboardData(text: plain));
              showStyledSnackBar(
                dialogContext,
                'Definition copied to clipboard',
              );
            },
            child: Text('Copy Definition',
                style: textStyle(dialogContext, uiFontSize)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close', style: textStyle(dialogContext, uiFontSize)),
          ),
        ],
      ),
    );
  }

  static List<Widget> buildDefinitionWidgets(
    BuildContext context,
    String definition, {
    void Function(String headword)? onDictionaryTap,
  }) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: WebstersDefinitionRenderer(
          data: definition,
          onLinkTap: (url, referenceText) {
            if (url.startsWith('dict://')) {
              if (onDictionaryTap != null) {
                onDictionaryTap(url);
              } else {
                show(context, url);
              }
              return;
            }
            if (url.startsWith('v://') || url.startsWith('v:')) {
              handleVerseLink(
                context,
                url,
                referenceText,
                navigateToVerse: null,
                onVerseLinkRecursion: null,
                onNoteEditTap: null,
              );
            }
          },
        ),
      ),
    ];
  }

  // static TextStyle primaryTextStyle(BuildContext context, double fontSize) {
  //   final isDark = Theme.of(context).brightness == Brightness.dark;
  //   return TextStyle(
  //     fontSize: FontSizeAdjustments.getAdjustedSize(
  //       fontFamilyNotifier.value,
  //       fontSize,
  //     ),
  //     color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
  //   );
  // }

  static TextStyle textStyle(
    BuildContext context,
    double fontSize, {
    bool bold = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
        fontFamilyNotifier.value,
        fontSize + 2,
      ),
      fontWeight: bold ? FontWeight.bold : null,
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
  }
}

class WebstersDefinitionLookupDialog extends StatefulWidget {
  const WebstersDefinitionLookupDialog({super.key});

  @override
  State<WebstersDefinitionLookupDialog> createState() =>
      _WebstersDefinitionLookupDialogState();
}

class _WebstersDefinitionLookupDialogState
    extends State<WebstersDefinitionLookupDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  Timer? _persistTimer;

  late final List<String> _allHeadwords;
  late List<String> _visibleHeadwords;

  String? _currentHeadword;
  String? _currentDefinition;
  String? _errorText;
  int _focusedIndex = 0;

  static const String _lastInputKey = 'lastWebsters1828LookupInput';
  static const String _selectedHeadwordKey = 'lastWebsters1828SelectedHeadword';

  @override
  void initState() {
    super.initState();
    _allHeadwords = Websters1828DefinitionsDatabase.getHeadwords();
    _visibleHeadwords = _allHeadwords;
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

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final lastInput = prefs.getString(_lastInputKey) ?? '';
    final selectedHeadword = prefs.getString(_selectedHeadwordKey);
    final visibleHeadwords = lastInput.trim().isEmpty
        ? _allHeadwords
        : Websters1828DefinitionsDatabase.searchHeadwords(
            lastInput,
            limit: 600,
          );
    final restoredHeadword = selectedHeadword == null
        ? null
        : Websters1828DefinitionsDatabase.findHeadword(selectedHeadword);
    final definition = restoredHeadword == null
        ? null
        : Websters1828DefinitionsDatabase.getDefinition(restoredHeadword);
    final focusedIndex = restoredHeadword == null
        ? -1
        : visibleHeadwords.indexOf(restoredHeadword);

    setState(() {
      _currentHeadword = definition == null ? null : restoredHeadword;
      _currentDefinition = definition;
      _errorText = null;
      _visibleHeadwords =
          visibleHeadwords.isEmpty ? _allHeadwords : visibleHeadwords;
      _focusedIndex = focusedIndex >= 0 ? focusedIndex : 0;
      _controller.text = lastInput;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: lastInput.length),
      );
    });
    if (restoredHeadword != null) {
      _scrollToHeadword(restoredHeadword);
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 300), _persistState);
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastInputKey, _controller.text.trim());
    final currentHeadword = _currentHeadword;
    if (currentHeadword == null) {
      await prefs.remove(_selectedHeadwordKey);
    } else {
      await prefs.setString(_selectedHeadwordKey, currentHeadword);
    }
  }

  void _filterHeadwords(String input) {
    final matches = input.trim().isEmpty
        ? _allHeadwords
        : Websters1828DefinitionsDatabase.searchHeadwords(input, limit: 600);
    final currentIndex =
        _currentHeadword == null ? -1 : matches.indexOf(_currentHeadword!);

    setState(() {
      _visibleHeadwords = matches;
      _focusedIndex = currentIndex >= 0 ? currentIndex : 0;
      if (_errorText != null) {
        _errorText = null;
      }
    });
    _schedulePersist();
  }

  void _lookup(String input) {
    final headword = Websters1828DefinitionsDatabase.findHeadword(input);
    if (headword == null) {
      setState(() {
        _currentHeadword = null;
        _currentDefinition = null;
        _errorText = 'Enter a word such as Abandon or choose one below.';
      });
      _schedulePersist();
      return;
    }

    final definition = Websters1828DefinitionsDatabase.getDefinition(headword);
    final visibleHeadwords =
        Websters1828DefinitionsDatabase.searchHeadwords(headword, limit: 600);
    final focusedIndex = visibleHeadwords.indexOf(headword);

    setState(() {
      _currentHeadword = headword;
      _currentDefinition = definition;
      _errorText =
          definition == null ? 'Definition not found for $headword.' : null;
      _visibleHeadwords =
          visibleHeadwords.isEmpty ? _allHeadwords : visibleHeadwords;
      _focusedIndex = focusedIndex >= 0 ? focusedIndex : 0;
      _controller.text = headword;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _scrollToHeadword(headword);
    _persistState();
  }

  void _selectHeadword(String headword, {bool scrollToSelection = false}) {
    final definition = Websters1828DefinitionsDatabase.getDefinition(headword);
    setState(() {
      _currentHeadword = headword;
      _currentDefinition = definition;
      _errorText =
          definition == null ? 'Definition not found for $headword.' : null;
      _focusedIndex = _visibleHeadwords.indexOf(headword);
      if (_focusedIndex < 0) {
        _focusedIndex = 0;
      }
    });
    if (scrollToSelection) {
      _scrollToHeadword(headword);
    }
    _persistState();
  }

  void _showLinkedDefinitionDialog(String input) {
    WebstersDefinitionDialog.show(context, input);
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _visibleHeadwords = _allHeadwords;
      _currentHeadword = null;
      _currentDefinition = null;
      _errorText = null;
      _focusedIndex = 0;
    });
    _textFieldFocusNode.requestFocus();
    _persistState();
  }

  void _scrollToHeadword(String headword) {
    final index = _visibleHeadwords.indexOf(headword);
    if (index < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listScrollController.hasClients) {
        const itemExtent = 36.0;
        final visibleItems =
            _listScrollController.position.viewportDimension / itemExtent;
        final targetOffset =
            (index * itemExtent) - (visibleItems / 2) * itemExtent;
        _listScrollController.animateTo(
          targetOffset.clamp(
              0.0, _listScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  KeyEventResult _handleListKey(KeyEvent event) {
    if (_visibleHeadwords.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final nextIndex =
            (_focusedIndex + 1).clamp(0, _visibleHeadwords.length - 1);
        if (nextIndex != _focusedIndex) {
          _focusedIndex = nextIndex;
          _selectHeadword(
            _visibleHeadwords[_focusedIndex],
            scrollToSelection: true,
          );
        }
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        final previousIndex =
            (_focusedIndex - 1).clamp(0, _visibleHeadwords.length - 1);
        if (previousIndex != _focusedIndex) {
          _focusedIndex = previousIndex;
          _selectHeadword(
            _visibleHeadwords[_focusedIndex],
            scrollToSelection: true,
          );
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _copyDefinition() {
    if (_currentHeadword == null || _currentDefinition == null) return;
    final plain =
        '${_currentHeadword!}\n${Websters1828DefinitionsDatabase.stripHtml(_currentDefinition!)}';
    Clipboard.setData(ClipboardData(text: plain));
    showStyledSnackBar(context, 'Definition copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
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
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0)
          : const EdgeInsets.symmetric(horizontal: 32.0, vertical: 64.0),
      titlePadding: const EdgeInsets.fromLTRB(16.0, 8.0, 8.0, 0.0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              "Noah Webster's 1828 Dictionary Unabridged",
              style: _textStyle(context, uiFontSize, bold: true),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () {
              _persistState();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
      content: SizedBox(
        width: constrainedMaxWidth,
        height: maxHeight,
        child: Column(
          children: [
            TextField(
              focusNode: _textFieldFocusNode,
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Enter a word or choose one below',
                hintStyle: TextStyle(
                  fontFamily: uiFontFamily,
                  fontSize: uiFontSize,
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
                    semanticLabel: 'Clear Search Text',
                    color: primaryColor,
                  ),
                  tooltip: 'Clear Search Text',
                  onPressed: _clear,
                ),
              ),
              onChanged: _filterHeadwords,
              onSubmitted: _lookup,
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: fontFamilyNotifier.value,
                color: getAdaptiveTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final listWidth = constraints.maxWidth < 520 ? 136.0 : 180.0;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: listWidth,
                        child: Focus(
                          focusNode: _listFocusNode,
                          onKeyEvent: (node, event) => _handleListKey(event),
                          child: ScrollbarTheme(
                            data: ScrollbarThemeData(
                              minThumbLength: 80.0,
                              thumbColor: WidgetStateProperty.all(
                                primaryColor.withValues(alpha: 0.8),
                              ),
                            ),
                            child: Scrollbar(
                              interactive: true,
                              thickness: 22.0,
                              controller: _listScrollController,
                              thumbVisibility: true,
                              trackVisibility: false,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: _visibleHeadwords.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No entries',
                                          style:
                                              _textStyle(context, uiFontSize),
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _listScrollController,
                                        itemCount: _visibleHeadwords.length,
                                        itemExtent: 36.0,
                                        itemBuilder: (context, index) {
                                          final headword =
                                              _visibleHeadwords[index];
                                          final isSelected =
                                              headword == _currentHeadword;
                                          return Material(
                                            color: isSelected
                                                ? primaryColor.withValues(
                                                    alpha: 0.25)
                                                : Colors.transparent,
                                            child: InkWell(
                                              onTap: () {
                                                _focusedIndex = index;
                                                _selectHeadword(headword);
                                              },
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  headword,
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.fade,
                                                  style: TextStyle(
                                                    fontSize: uiFontSize + 2,
                                                    fontFamily:
                                                        fontFamilyNotifier
                                                            .value,
                                                    color: isSelected
                                                        ? primaryColor
                                                        : getAdaptiveTextColor(
                                                            context),
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errorText != null)
                              Text(
                                _errorText!,
                                style: _textStyle(context, uiFontSize),
                              ),
                            if (_currentDefinition != null &&
                                _currentHeadword != null)
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: WebstersDefinitionDialog
                                        .buildDefinitionWidgets(
                                      context,
                                      _currentDefinition!,
                                      onDictionaryTap:
                                          _showLinkedDefinitionDialog,
                                    ),
                                  ),
                                ),
                              ),
                            if (_currentDefinition == null &&
                                _currentHeadword == null &&
                                _errorText == null)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    'Noah Webster\'s 1828 Dictionary Unabridged',
                                    style: _textStyle(context, uiFontSize)
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
                  );
                },
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
            style: _textStyle(context, uiFontSize),
          ),
        ),
        if (_currentHeadword != null && _currentDefinition != null)
          TextButton(
            onPressed: _copyDefinition,
            child: Text(
              'Copy Definition',
              style: _textStyle(context, uiFontSize),
            ),
          ),
        TextButton(
          onPressed: () {
            _persistState();
            Navigator.of(context).pop();
          },
          child: Text(
            'Close',
            style: _textStyle(context, uiFontSize),
          ),
        ),
      ],
    );
  }

  static TextStyle _textStyle(
    BuildContext context,
    double fontSize, {
    bool bold = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
        fontFamilyNotifier.value,
        fontSize + 2,
      ),
      fontWeight: bold ? FontWeight.bold : null,
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
  }
}
