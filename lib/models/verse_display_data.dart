import 'package:material_ui/material_ui.dart';

/// Data model for a verse to be rendered with all necessary information.
/// This allows ListView.builder to lazily build widgets without holding
/// all verse widgets in memory simultaneously.
class VerseDisplayData {
  final int verseNumber;
  final String rawVerseText;
  final Map<String, dynamic> noteForVerse;
  final List<Map<String, dynamic>> highlightsForVerse;
  final String fontFamily;
  final TextStyle textStyle;
  //final TextStyle numStyle;
  final double verseNumberWidth;
  final Color backgroundColor;
  final bool showNotesInline;
  final bool showTskReferences;
  final String tskText;
  final String noteText;
  final bool addParagraphBreak;
  //final bool customBgColor;
  final Color? customBackgroundColor;
  final GlobalKey? verseKey;
  final bool showStrongsNumbers;

  VerseDisplayData({
    required this.verseNumber,
    required this.rawVerseText,
    required this.noteForVerse,
    required this.highlightsForVerse,
    required this.fontFamily,
    required this.textStyle,
    //required this.numStyle,
    required this.verseNumberWidth,
    required this.backgroundColor,
    required this.showNotesInline,
    required this.showTskReferences,
    required this.tskText,
    required this.noteText,
    required this.addParagraphBreak,
    //required this.customBgColor,
    this.customBackgroundColor,
    this.verseKey,
    this.showStrongsNumbers = false,
  });
}
