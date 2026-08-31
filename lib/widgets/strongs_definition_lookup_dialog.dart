import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/strongs_definitions.dart';
import '../database/strongs_definitions_database.dart';
import '../main.dart';
import '../screens/strongs_search_screen.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';
import 'strongs_definition_dialog.dart';

class StrongsDefinitionLookupDialog extends StatefulWidget {
  const StrongsDefinitionLookupDialog({super.key});

  @override
  State<StrongsDefinitionLookupDialog> createState() =>
      _StrongsDefinitionLookupDialogState();
}

class _StrongsDefinitionLookupDialogState
    extends State<StrongsDefinitionLookupDialog> {
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
          duration: const Duration(milliseconds: 250),
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
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 122.0,
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
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          minThumbLength: 80.0,
                          thumbColor: WidgetStateProperty.all(
                            isDark
                                ? darkPrimaryColor.value.withValues(alpha: 0.8)
                                : lightPrimaryColor.value
                                    .withValues(alpha: 0.8),
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
                                        fontSize: uiFontSize + 2,
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
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentStrongsNumber != null)
                          Text(
                            _currentStrongsNumber!,
                            style: StrongsDefinitionDialog.primaryTextStyle(
                                context, uiFontSize + 2),
                          ),
                        if (_currentStrongsNumber != null)
                          const SizedBox(height: 8),
                        if (_errorText != null)
                          Text(
                            _errorText!,
                            style: StrongsDefinitionDialog.textStyle(
                                context, uiFontSize),
                          ),
                        if (_currentDefinition != null &&
                            _currentStrongsNumber != null)
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: StrongsDefinitionDialog
                                    .buildDefinitionWidgets(
                                  context,
                                  _currentDefinition!,
                                  onStrongsTap: (strongsNumber) =>
                                      StrongsDefinitionDialog.show(
                                    context,
                                    strongsNumber,
                                  ),
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
                                'Strong\'s Concordance Definitions',
                                style: StrongsDefinitionDialog.textStyle(
                                        context, uiFontSize)
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
          onPressed: () {
            final plain =
                '${_currentStrongsNumber ?? ''}\n${_currentDefinition != null ? StrongsDefinitionsDatabase.stripHtml(_currentDefinition!) : ''}';
            Clipboard.setData(ClipboardData(text: plain));
            showStyledSnackBar(context, 'Definition copied to clipboard');
          },
          child: Text(
            'Copy',
            style: StrongsDefinitionDialog.textStyle(context, uiFontSize),
          ),
        ),
        TextButton(
          onPressed: _currentStrongsNumber == null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                      strongsSearchTermPreferenceKey, _currentStrongsNumber!);
                  if (!mounted) return;
                  navigator.pop();
                  await navigator.push<void>(
                    MaterialPageRoute(
                      builder: (_) => const StrongsSearchScreen(
                        searchImmediately: true,
                      ),
                    ),
                  );
                },
          child: Text(
            'Search',
            style: StrongsDefinitionDialog.textStyle(context, uiFontSize),
          ),
        ),
        TextButton(
          onPressed: () {
            _persistState();
            Navigator.of(context).pop();
          },
          child: Text(
            'Close',
            style: StrongsDefinitionDialog.textStyle(context, uiFontSize),
          ),
        ),
      ],
    );
  }
}
