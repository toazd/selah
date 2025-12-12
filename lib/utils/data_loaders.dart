import '../database/notes_database.dart';
import '../database/highlights_database.dart';

/// Loads notes for a chapter and returns them as a map keyed by verse number
Future<Map<int, Map<String, dynamic>>> loadNotesForChapter(String book, int chapter) async {
  final notesList = await NotesDatabase.getNotesForChapter(book, chapter);
  return {for (final note in notesList) note['verse'] as int: note};
}

/// Loads highlights for a chapter and groups them by verse number
Future<Map<int, List<Map<String, dynamic>>>> loadHighlightsForChapter(String book, int chapter) async {
  final highlightsList = await HighlightsDatabase.getHighlightsForChapter(book, chapter);

  final highlights = <int, List<Map<String, dynamic>>>{};
  for (final highlight in highlightsList) {
    final verse = highlight['verse'] as int;
    if (highlights[verse] == null) {
      highlights[verse] = [];
    }
    highlights[verse]!.add(highlight);
  }

  return highlights;
}
