import 'package:material_ui/material_ui.dart';
import '../widgets/highlight_dialog.dart';
import '../screens/multiple_verses_dialog.dart';

/// Shows a multiple verses selection dialog
void showMultipleVersesDialog({
  required BuildContext context,
  required String book,
  required int chapter,
  required int initialVerse,
  required List<Map<String, dynamic>> verses,
}) {
  showDialog(
    context: context,
    builder: (context) => MultipleVersesDialog(
      book: book,
      chapter: chapter,
      initialVerse: initialVerse,
      verses: verses.map((verseMap) {
        // Clean verse text by removing pilcrow marks
        String parsedVerse = (verseMap['text'] as String?) ?? '';
        String cleanedText = parsedVerse.replaceAll('¶ ', '');
        return {
          ...verseMap,
          'text': cleanedText,
        };
      }).toList(),
    ),
  );
}

/// Shows a highlight dialog and returns the result
Future<void> showHighlightDialog({
  required BuildContext context,
  required String rawVerseText,
  required int verseNumber,
  required String book,
  required int chapter,
  required VoidCallback onFinished,
}) async {
  await showDialog(
    context: context,
    useSafeArea: true,
    builder: (context) => HighlightDialog(
      rawVerseText: rawVerseText,
      verseNumber: verseNumber,
      book: book,
      chapter: chapter,
      onFinished: onFinished,
    ),
  );
}
