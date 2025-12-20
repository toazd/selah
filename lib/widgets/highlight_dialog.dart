// Reusable highlight dialog widget extracted from bible_screen.dart
import 'package:flutter/material.dart';
import 'package:selah/utils/snackbar_notification.dart';
import '../main.dart';
import '../utils/verse_display_utils.dart';
import '../utils/highlight_text_color_adjustments.dart';
import '../database/highlights_database.dart';
import '../utils/preferences_constants.dart';
import '../services/local_data_change_notifier.dart';
import '../utils/error_handler.dart';
import '../utils/font_size_adjustments.dart';

/// Highlight dialog widget for selecting and applying text highlights
class HighlightDialog extends StatefulWidget {
  final String rawVerseText;
  final int verseNumber;
  final String book;
  final int chapter;
  final Function()? onFinished;

  const HighlightDialog({
    super.key,
    required this.rawVerseText,
    required this.verseNumber,
    required this.book,
    required this.chapter,
    this.onFinished,
  });

  @override
  State<HighlightDialog> createState() => _HighlightDialogState();
}

class _HighlightDialogState extends State<HighlightDialog> {
  final Map<int, List<Map<String, dynamic>>> _currentHighlights = {};
  ValueNotifier<TextSelection?> textSelectionNotifier = ValueNotifier(null);
  ValueNotifier<int?> selectedColorIndexNotifier = ValueNotifier(null);
  ValueNotifier<int?> pressedColorIndexNotifier = ValueNotifier(null);

  String get _fullyCleanedVerseText => widget.rawVerseText.replaceAll(RegExp(r'</?r>'), ''); //.replaceAll('¶ ', '');

  @override
  void initState() {
    super.initState();
    // Load highlights after a small delay to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentHighlights();
    });
  }

  @override
  void dispose() {
    textSelectionNotifier.dispose();
    selectedColorIndexNotifier.dispose();
    pressedColorIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentHighlights() async {
    try {
      final highlightsList = await HighlightsDatabase.getHighlightsForVerse(
        widget.book,
        widget.chapter,
        widget.verseNumber,
      );

      if (mounted) {
        setState(() {
          _currentHighlights.clear();
          if (highlightsList.isNotEmpty) {
            // Store raw positions directly - applyHighlightsToText will handle conversion
            _currentHighlights[widget.verseNumber] = highlightsList;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'HighlightDialog _loadCurrentHighlights exception: $e');
      }
      ErrorHandler.logError(
        e,
        customMessage: 'HighlightDialog _loadCurrentHighlights exception',
        context: {'widget': 'HighlightDialog', 'method': '_loadCurrentHighlights'},
      );
    }
  }

  /// Build text widget with visual highlights for the highlight dialog
  Widget _buildHighlightTextWithVisualHighlights(
      String rawText, List<Map<String, dynamic>> highlights, int verseNumber) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verseTextColor = isDark ? darkTextColor.value : lightTextColor.value;
    //final darkTextColorValue = isDark ? darkTextColor.value : lightTextColor.value;
    //final lightTextColorValue = isDark ? darkTextColor.value : lightTextColor.value;

    // Get current selection for applying highlights
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: verseTextColor,
            ) ??
        TextStyle(color: verseTextColor);

    // Use applyHighlightsToText for consistent text rendering with main display
    return ValueListenableBuilder<TextSelection?>(
      valueListenable: textSelectionNotifier,
      builder: (context, textSelection, _) {
        return SelectableText.rich(
          TextSpan(
            style: baseStyle,
            children: applyHighlightsToText(
              widget.rawVerseText,
              rawText,
              baseStyle.copyWith(
                fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value),
              ),
              verseNumber,
              Theme.of(context).scaffoldBackgroundColor,
              highlights,
              //lightTextColorValue,
              lightTextColor.value,
              //darkTextColorValue,
              darkTextColor.value,
            ),
          ),
          contextMenuBuilder: (BuildContext context, EditableTextState editableTextState) {
            return Container(); // Disable default context menu to prevent interference with highlighting
          },
          onSelectionChanged: (selection, cause) {
            textSelectionNotifier.value = selection;
          },
        );
      },
    );
  }

  void _applyHighlight(int verseNumber, TextSelection selection, int colorIndex) async {
    // Get the selected text from the CLEAN verse (what user sees in dialog)
    final start = selection.start;
    final end = selection.end;

    if (start >= 0 && end > start && end <= _fullyCleanedVerseText.length) {
      // Get the selected color from the notifier
      final colors = highlightColorsNotifier.value;
      if (colorIndex >= 0 && colorIndex < colors.length) {
        final selectedColor = colors[colorIndex];

        // Convert clean text positions to raw text positions
        final actualStart = convertCleanPositionToRaw(widget.rawVerseText, start);
        final actualEnd = convertCleanPositionToRaw(widget.rawVerseText, end);

        if (actualStart >= 0 && actualEnd > actualStart && actualEnd <= widget.rawVerseText.length) {
          // Check for overlap with existing highlights
          final existingHighlights = await HighlightsDatabase.getHighlightsForVerse(
            widget.book,
            widget.chapter,
            verseNumber,
          );

          bool hasOverlap = false;
          for (final highlight in existingHighlights) {
            final existingStart = highlight['start'] as int;
            final existingEnd = highlight['end'] as int;
            if (actualStart < existingEnd && existingStart < actualEnd) {
              hasOverlap = true;
              break;
            }
          }

          if (!hasOverlap) {
            final timenowMs = DateTime.now().millisecondsSinceEpoch;

            // Save highlight to database using raw text positions
            await HighlightsDatabase.addHighlight(
              book: widget.book,
              chapter: widget.chapter,
              verse: verseNumber,
              start: actualStart,
              end: actualEnd,
              color: selectedColor.toARGB32(),
              createdAt: timenowMs,
              updatedAt: timenowMs,
              skipSync: false,
            );

            // Reload the dialog's highlights to show the new highlight immediately
            await _loadCurrentHighlights();

            // Update the UI about the changes
            LocalDataChangeNotifier.notifyHighlightsChanged();
          }
        }
      }
    }
  }

  void _editExistingHighlight(BuildContext context, Map<String, dynamic> highlight) async {
    // For now, just delete the highlight
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        //title: Text('Edit Highlight'),
        content: Text('Delete this highlight?',
            style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            child: Text('No',
                style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Yes', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
            onPressed: () async {
              final highlightId = highlight['id'] as int;

              await HighlightsDatabase.deleteHighlight(highlightId);

              // Refresh the dialog's own highlights
              await _loadCurrentHighlights();

              // Notify UIs about the changes
              LocalDataChangeNotifier.notifyHighlightsChanged();

              // Close the confirmation dialog
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingHighlights = _currentHighlights[widget.verseNumber] ?? [];
    final double screenWidth = MediaQuery.of(context).size.width;
    final double dialogWidth = screenWidth > 650 ? screenWidth * 0.6 : screenWidth * 0.9;

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Select text:',
                    style: TextStyle(
                        fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: getAdaptiveTextColor(context)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildHighlightTextWithVisualHighlights(
                    _fullyCleanedVerseText,
                    existingHighlights,
                    widget.verseNumber,
                  ),
                ),
                const SizedBox(height: 32),
                Text('Choose highlight color:',
                    style: TextStyle(
                        fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                const SizedBox(height: 8),
                ValueListenableBuilder<List<Color>>(
                  valueListenable: highlightColorsNotifier,
                  builder: (context, colors, _) {
                    return ValueListenableBuilder<TextSelection?>(
                      valueListenable: textSelectionNotifier,
                      builder: (context, textSelection, _) {
                        return ValueListenableBuilder<int?>(
                          valueListenable: selectedColorIndexNotifier,
                          builder: (context, selectedIndex, _) {
                            return ValueListenableBuilder<int?>(
                              valueListenable: pressedColorIndexNotifier,
                              builder: (context, pressedIndex, _) {
                                // Create color widgets
                                final colorWidgets = colors.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final color = entry.value;
                                  return GestureDetector(
                                    onTapDown: (_) => pressedColorIndexNotifier.value = index,
                                    onTapUp: (_) => pressedColorIndexNotifier.value = null,
                                    onTapCancel: () => pressedColorIndexNotifier.value = null,
                                    onTap: () {
                                      if (textSelection != null && textSelection.start != textSelection.end) {
                                        // Apply the highlight immediately and show it in the dialog
                                        _applyHighlight(widget.verseNumber, textSelection, index);

                                        // Clear the text selection to prevent duplication in preview
                                        textSelectionNotifier.value = null;

                                        // Update the selected color for preview
                                        selectedColorIndexNotifier.value = index;
                                      } else {
                                        // Update the selected color for preview
                                        selectedColorIndexNotifier.value = index;
                                      }
                                    },
                                    child: Container(
                                      width: 45,
                                      height: 45,
                                      decoration: BoxDecoration(
                                        color: color,
                                        // border: Border.all(
                                        //   color: selectedIndex == index ? Colors.black : Colors.grey,
                                        //   width: selectedIndex == index ? 3 : 1,
                                        // ),
                                        border: Border.all(
                                          color:
                                              pressedIndex == index ? getAdaptiveTextColor(context) : Colors.blueGrey,
                                          width: pressedIndex == index ? 3 : 2,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  );
                                }).toList();

                                // Use LayoutBuilder to switch between 2×8 grid and responsive Wrap
                                return LayoutBuilder(
                                  builder: (context, constraints) {
                                    const double breakpoint = 460.0; // Minimum width for 2×8 layout

                                    if (constraints.maxWidth >= breakpoint) {
                                      // Wide layout: keep the intended 2×8 grid
                                      final firstRow = colorWidgets.sublist(0, 8);
                                      final secondRow = colorWidgets.sublist(8, 16);

                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.start,
                                            children: firstRow
                                                .map((widget) => Padding(
                                                      padding: const EdgeInsets.only(right: 8.0),
                                                      child: widget,
                                                    ))
                                                .toList(),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.start,
                                            children: secondRow
                                                .map((widget) => Padding(
                                                      padding: const EdgeInsets.only(right: 8.0),
                                                      child: widget,
                                                    ))
                                                .toList(),
                                          ),
                                        ],
                                      );
                                    } else {
                                      // Narrow layout: use responsive Wrap
                                      return Wrap(
                                        spacing: 8.0,
                                        runSpacing: 8.0,
                                        alignment: WrapAlignment.start,
                                        children: colorWidgets,
                                      );
                                    }
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                if (existingHighlights.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Text('Remove existing highlights:',
                      style: TextStyle(
                          fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: existingHighlights.map((highlight) {
                      final color = Color(highlight['color'] as int);
                      final start = highlight['start'] as int;
                      final end = highlight['end'] as int;

                      // Get the actual highlighted text instead of character ranges
                      String highlightedText;
                      try {
                        // Convert raw positions to clean positions for substring
                        final cleanStart = convertRawPositionToClean(widget.rawVerseText, start);
                        final cleanEnd = convertRawPositionToClean(widget.rawVerseText, end);
                        if (cleanStart >= 0 && cleanEnd > cleanStart && cleanEnd <= _fullyCleanedVerseText.length) {
                          highlightedText = _fullyCleanedVerseText.substring(cleanStart, cleanEnd);
                          // Truncate very long highlights for display
                          if (highlightedText.length > 20) {
                            highlightedText = '${highlightedText.substring(0, 17)}...';
                          }
                        } else {
                          highlightedText = 'Invalid range';
                        }
                      } catch (e) {
                        highlightedText = 'Error';
                      }

                      // Calculate adjusted text color for the highlight background
                      //final isDark = Theme.of(context).brightness == Brightness.dark;
                      //final effectiveHighlightBackground = color.withValues(alpha: defaultHighlightAlpha);
                      final adjustedTextColor = adjustTextColorForHighlight(
                        getAdaptiveTextColor(context),
                        color,
                        //isDark ? darkTextColor.value : lightTextColor.value,
                        darkTextColor.value,
                        //isDark ? lightTextColor.value : darkTextColor.value,
                        lightTextColor.value,
                      );

                      return GestureDetector(
                        onTap: () {
                          // Allow editing existing highlight (delete for now)
                          _editExistingHighlight(context, highlight);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: defaultHighlightAlpha),
                            //border: Border.all(color: color, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            highlightedText,
                            style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: adjustedTextColor),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ], // else ...[
                const SizedBox(height: 32),
                //Text('No existing highlights for this verse', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
                //],
                //const SizedBox(height: 8),
                Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton(
                    onPressed: () {
                      if (widget.onFinished != null) {
                        widget.onFinished!();
                      }
                      Navigator.pop(context);
                    },
                    child: Text('Finished',
                        style: TextStyle(
                            fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
