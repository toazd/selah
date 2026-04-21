import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/csv_parser.dart';
import '../models/olive_tree_data.dart';
import '../utils/color_mapper.dart';
import '../database/highlights_database.dart';
import '../database/notes_database.dart';
import '../data/bible_data.dart';
import '../widgets/olive_tree_import_dialogs.dart';
import '../utils/note_storage_format.dart';
import '../services/local_data_change_notifier.dart';
import '../services/supabase_sync_service.dart';

/// Service for importing Olive Tree Bible data
class OliveTreeImportService {
  /// Main entry point for Olive Tree import
  static Future<void> importOliveTreeData(BuildContext context) async {
    try {
      // Step 1: Let user select CSV file
      final csvContent = await _selectAndReadCsvFile();
      if (csvContent == null) return;

      // Step 2: Parse CSV data
      final csvRows = CsvParser.parse(csvContent);
      if (csvRows.isEmpty) {
        if (context.mounted) {
          _showErrorDialog(context, 'No data found in the selected file.');
        }
        return;
      }

      final oliveTreeData = OliveTreeData.fromCsvRows(csvRows);

      // Step 3: Show category selection dialog
      if (!context.mounted) return;
      final selectedTypes =
          await _showCategorySelectionDialog(context, oliveTreeData);
      if (selectedTypes == null || selectedTypes.isEmpty) return;

      // Step 4: Handle color mapping if highlights are selected
      Map<String, int>? colorMappings;
      if (selectedTypes.contains('highlights') &&
          oliveTreeData.highlightCount > 0) {
        if (!context.mounted) return;
        final oliveTreeColors = ColorMapper.extractUniqueColors(
            oliveTreeData.highlights.map((h) => h.highlighterName).toList());
        final currentHighlightColors =
            await ColorMapper.getCurrentHighlightColors();
        final initialMappings =
            await ColorMapper.generateColorMappings(oliveTreeColors);

        if (context.mounted) {
          colorMappings = await _showColorMappingDialog(context,
              oliveTreeColors, initialMappings, currentHighlightColors);
        }
        if (colorMappings == null) return;
      }

      // Step 5: Perform the import
      if (!context.mounted) return;
      final currentHighlightColors =
          await ColorMapper.getCurrentHighlightColors();
      if (context.mounted) {
        await _performImport(context, oliveTreeData, selectedTypes,
            colorMappings ?? {}, currentHighlightColors);
      }
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showErrorDialog(
            context, 'Import failed: $e\n\nStack trace: $stackTrace');
      }
    }
  }

  /// Let user select and read CSV file
  static Future<String?> _selectAndReadCsvFile() async {
    final result = await FilePicker.pickFiles(
      //FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: 'Select Olive Tree CSV Export File',
    );

    if (result == null || result.files.single.path == null) {
      return null;
    }

    final file = File(result.files.single.path!);
    return await file.readAsString();
  }

  /// Show category selection dialog
  static Future<List<String>?> _showCategorySelectionDialog(
      BuildContext context, OliveTreeData data) async {
    return await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OliveTreeCategorySelectionDialog(data: data),
    );
  }

  /// Show color mapping dialog
  static Future<Map<String, int>?> _showColorMappingDialog(
    BuildContext context,
    List<String> oliveTreeColors,
    Map<String, int> initialMappings,
    List<Color> currentHighlightColors,
  ) async {
    return await showDialog<Map<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OliveTreeColorMappingDialog(
        oliveTreeColors: oliveTreeColors,
        initialMappings: initialMappings,
        currentHighlightColors: currentHighlightColors,
      ),
    );
  }

  /// Perform the actual import
  static Future<void> _performImport(
    BuildContext context,
    OliveTreeData data,
    List<String> selectedTypes,
    Map<String, int> colorMappings,
    List<Color> currentHighlightColors,
  ) async {
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const OliveTreeImportProgressDialog(message: 'Importing data...'),
    );

    try {
      final results = <String, dynamic>{};
      final allFailedRows = <FailedRow>[];

      // Include parsing failures
      allFailedRows.addAll(data.failedRows);

      // Import highlights if selected
      if (selectedTypes.contains('highlights')) {
        final highlightResults = await _importHighlights(
            data.highlights, colorMappings, currentHighlightColors);

        // Manually merge results to avoid overwriting
        results['highlights'] = highlightResults['highlights'];
        if (highlightResults.containsKey('failedRows')) {
          allFailedRows
              .addAll(highlightResults['failedRows'] as List<FailedRow>);
        }

        // Notify UI to refresh highlights
        LocalDataChangeNotifier.notifyHighlightsChanged();

        // Trigger sync after results merged and UI updated
        final highlightCount = highlightResults['highlights'] as int;
        if (highlightCount > 1) {
          try {
            await SupabaseSyncService().syncHighlights();
          } catch (e) {
            //
          }
        }
      }

      // Import notes if selected
      if (selectedTypes.contains('notes')) {
        final noteResults = await _importNotes(data.notes);

        // Manually merge results to avoid overwriting
        results['notes'] = noteResults['notes'];
        if (noteResults.containsKey('failedRows')) {
          allFailedRows.addAll(noteResults['failedRows'] as List<FailedRow>);
        }

        // Notify UI to refresh notes
        LocalDataChangeNotifier.notifyNotesChanged();

        // Trigger sync after results merged and UI updated
        final noteCount = noteResults['notes'] as int;
        if (noteCount > 1) {
          try {
            await SupabaseSyncService().syncNotes();
          } catch (e) {
            //
          }
        }
      }

      // Set the combined failed rows
      if (allFailedRows.isNotEmpty) {
        results['failedRows'] = allFailedRows;
      }

      // Close progress dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      // Show results
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => OliveTreeImportResultsDialog(results: results),
        );
      }
    } catch (e) {
      // Close progress dialog
      if (context.mounted) {
        Navigator.pop(context);
      }
      rethrow;
    }
  }

  /// Import highlights
  static Future<Map<String, dynamic>> _importHighlights(
    List<OliveTreeHighlight> highlights,
    Map<String, int> colorMappings,
    List<Color> currentHighlightColors,
  ) async {
    int successCount = 0;
    final failedRows = <FailedRow>[];

    // MERGE MODE: Keep existing highlights, replace only conflicts

    for (final highlight in highlights) {
      // Validate required fields
      final validationError = _validateHighlightFields(highlight);
      if (validationError != null) {
        failedRows.add(FailedRow(
            rowData: _highlightToRowData(highlight), reason: validationError));
        continue;
      }

      // Check for range highlights
      if (highlight.referenceStart.trim() != highlight.referenceEnd.trim()) {
        failedRows.add(FailedRow(
            rowData: _highlightToRowData(highlight),
            reason: 'Range highlights not supported'));
        continue;
      }

      try {
        // Check for invalid verse reference
        if (highlight.verseReference == null) {
          final reason = highlight.content.trim().isEmpty
              ? 'Empty content field'
              : 'Invalid verse reference';
          failedRows.add(FailedRow(
              rowData: _highlightToRowData(highlight), reason: reason));
          continue;
        }

        // Check for null verse number
        if (highlight.verseReference!.verse == null) {
          failedRows.add(FailedRow(
              rowData: _highlightToRowData(highlight),
              reason:
                  'Chapter-level references not supported (missing verse number)'));
          continue;
        }

        // Get the mapped color index
        final colorIndex = colorMappings[highlight.highlighterName] ?? 0;

        // Find character positions in the verse text
        final positions = _findHighlightPositions(highlight);
        if (positions == null) {
          failedRows.add(FailedRow(
              rowData: _highlightToRowData(highlight),
              reason: 'Could not find highlight text in verse'));
          continue;
        }

        // MERGE MODE: Remove overlapping existing highlights
        await _removeOverlappingHighlights(
          highlight.verseReference!.book,
          highlight.verseReference!.chapter,
          highlight.verseReference!.verse!,
          positions.start,
          positions.end,
        );

        final timenowMs = DateTime.now().millisecondsSinceEpoch;
        // Add a 1ms delay to ensure no two records have the same created_at or timestamp
        await Future.delayed(Duration(milliseconds: 1));

        // Add the highlight
        await HighlightsDatabase.addHighlight(
          book: highlight.verseReference!.book,
          chapter: highlight.verseReference!.chapter,
          verse: highlight.verseReference!.verse!,
          start: positions.start,
          end: positions.end,
          color: currentHighlightColors[colorIndex].toARGB32(),
          createdAt: timenowMs,
          updatedAt: timenowMs,
          skipSync: true,
        );

        successCount++;
      } catch (e) {
        failedRows.add(FailedRow(
            rowData: _highlightToRowData(highlight),
            reason: 'Import error: $e'));
      }
    }

    return {'highlights': successCount, 'failedRows': failedRows};
  }

  /// Validate required fields for highlights
  static String? _validateHighlightFields(OliveTreeHighlight highlight) {
    if (highlight.highlighterName.trim().isEmpty) {
      return 'Missing required field: highlighter_name';
    }
    // Allow empty content only for whole verse highlights (when reference_start == reference_end)
    if (highlight.content.trim().isEmpty &&
        highlight.referenceStart.trim() != highlight.referenceEnd.trim()) {
      return 'Missing required field: content';
    }
    return null;
  }

  /// Convert highlight back to row data for error reporting
  static Map<String, String> _highlightToRowData(OliveTreeHighlight highlight) {
    return {
      'category_name': highlight.categoryName,
      'type': highlight.type,
      'highlighter_name': highlight.highlighterName,
      'title': highlight.title,
      'content': highlight.content,
      'reference_start': highlight.referenceStart,
      'reference_end': highlight.referenceEnd,
      'associated_product': highlight.associatedProduct,
      'date_created': highlight.dateCreated.toIso8601String(),
      'last_modified': highlight.lastModified.toIso8601String(),
      'tags': highlight.tags,
    };
  }

  /// Import notes
  static Future<Map<String, dynamic>> _importNotes(
      List<OliveTreeNote> notes) async {
    int successCount = 0;
    final failedRows = <FailedRow>[];

    // MERGE MODE: Keep existing notes, replace only conflicts (handled by addOrUpdateNote)

    // Group notes by verse (book + chapter + verse)
    final notesByVerse = <String, List<OliveTreeNote>>{};

    for (final note in notes) {
      // Validate required fields
      final validationError = _validateNoteFields(note);
      if (validationError != null) {
        failedRows.add(
            FailedRow(rowData: _noteToRowData(note), reason: validationError));
        continue;
      }

      // Check for invalid verse reference
      if (note.verseReference == null) {
        failedRows.add(FailedRow(
            rowData: _noteToRowData(note), reason: 'Invalid verse reference'));
        continue;
      }

      // Check for null verse number
      if (note.verseReference!.verse == null) {
        failedRows.add(FailedRow(
            rowData: _noteToRowData(note),
            reason:
                'Chapter-level references not supported (missing verse number)'));
        continue;
      }

      final verseKey =
          '${note.verseReference!.book}_${note.verseReference!.chapter}_${note.verseReference!.verse}';
      notesByVerse.putIfAbsent(verseKey, () => []).add(note);
    }

    // Process each verse group
    for (final entry in notesByVerse.entries) {
      final verseNotes = entry.value;
      final firstNote = verseNotes.first;

      // Check if the verse exists in the Bible data
      if (!_verseExists(
          firstNote.verseReference!.book,
          firstNote.verseReference!.chapter,
          firstNote.verseReference!.verse!)) {
        for (final note in verseNotes) {
          failedRows.add(FailedRow(
              rowData: _noteToRowData(note),
              reason: 'Verse not found in Bible data'));
        }
        continue;
      }

      try {
        // Concatenate notes for this verse
        final concatenatedNote = _concatenateNotesForVerse(verseNotes);

        // Convert to Delta format before storing
        final deltaNoteText =
            NoteStorageFormat.ensureDeltaFormat(concatenatedNote);

        // Use the first note's reference for the database entry
        await NotesDatabase.addOrUpdateNote(
          book: firstNote.verseReference!.book,
          chapter: firstNote.verseReference!.chapter,
          verse: firstNote.verseReference!.verse!,
          noteText: deltaNoteText,
          skipSync: true,
        );

        successCount += verseNotes.length; // Count individual notes
      } catch (e) {
        // Record ALL notes in the failed verse group
        for (final note in verseNotes) {
          failedRows.add(FailedRow(
              rowData: _noteToRowData(note), reason: 'Import error: $e'));
        }
      }
    }

    return {'notes': successCount, 'failedRows': failedRows};
  }

  /// Validate required fields for notes
  static String? _validateNoteFields(OliveTreeNote note) {
    if (note.content.trim().isEmpty) {
      return 'Missing required field: content';
    }
    if (note.noteText.trim().isEmpty) {
      return 'Empty note content after cleaning';
    }
    return null;
  }

  /// Convert note back to row data for error reporting
  static Map<String, String> _noteToRowData(OliveTreeNote note) {
    return {
      'category_name': note.categoryName,
      'type': note.type,
      'highlighter_name': note.highlighterName,
      'title': note.title,
      'content': note.content,
      'reference_start': note.referenceStart,
      'reference_end': note.referenceEnd,
      'associated_product': note.associatedProduct,
      'date_created': note.dateCreated.toIso8601String(),
      'last_modified': note.lastModified.toIso8601String(),
      'tags': note.tags,
    };
  }

  /// Concatenate multiple notes for the same verse
  static String _concatenateNotesForVerse(List<OliveTreeNote> notes) {
    final buffer = StringBuffer();

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];

      // Add content
      buffer.write(note.noteText);

      // Add separator between notes (except for the last one)
      if (i < notes.length - 1) {
        buffer.write('\n\n');
      }
    }

    return buffer.toString();
  }

  /// Find start and end positions of highlighted text in verse
  static _HighlightPosition? _findHighlightPositions(
      OliveTreeHighlight highlight) {
    if (highlight.verseReference == null) return null;

    // Get the full verse text
    final bookData = bibleData[highlight.verseReference!.book];
    if (bookData == null) return null;

    final chapterData = bookData[highlight.verseReference!.chapter];
    if (chapterData == null) return null;

    final verseText = chapterData[highlight.verseReference!.verse];
    if (verseText == null) return null;

    // Handle whole verse highlights (empty highlightedText)
    if (highlight.highlightedText.isEmpty) {
      return _HighlightPosition(start: 0, end: verseText.length);
    }

    // First try whole-word matching using regex word boundaries
    final wordRegex =
        RegExp(r'\b' + RegExp.escape(highlight.highlightedText) + r'\b');
    final wordMatch = wordRegex.firstMatch(verseText);
    if (wordMatch != null) {
      return _HighlightPosition(start: wordMatch.start, end: wordMatch.end);
    }

    // Fallback to substring matching if whole-word match fails
    int highlightIndex = verseText.indexOf(highlight.highlightedText);
    int highlightLength = highlight.highlightedText.length;
    if (highlightIndex == -1) {
      // Try stripping leading verse number (e.g., "11 ") from highlightedText for single verse highlights
      final strippedHighlightedText = highlight.highlightedText
          .replaceFirst(RegExp(r'^\d+ '), '')
          .replaceAll('\n', ' ');
      highlightIndex = verseText.indexOf(strippedHighlightedText);
      if (highlightIndex != -1) {
        highlightLength = strippedHighlightedText.length;
      } else {
        return null;
      }
    }

    return _HighlightPosition(
        start: highlightIndex, end: highlightIndex + highlightLength);
  }

  /// Check if a verse exists in the Bible data
  static bool _verseExists(String book, int chapter, int verse) {
    final bookData = bibleData[book];
    if (bookData == null) return false;

    final chapterData = bookData[chapter];
    if (chapterData == null) return false;

    final verseText = chapterData[verse];
    return verseText != null;
  }

  /// Remove existing highlights that overlap with the new highlight range
  static Future<void> _removeOverlappingHighlights(
      String book, int chapter, int verse, int newStart, int newEnd) async {
    // Get existing highlights for this verse
    final existingHighlights =
        await HighlightsDatabase.getHighlightsForVerse(book, chapter, verse);

    // Find overlapping highlights
    final overlappingIds = <int>[];
    for (final highlight in existingHighlights) {
      final existingStart = highlight['start'] as int;
      final existingEnd = highlight['end'] as int;

      // Check for overlap: two ranges overlap if max(start1, start2) < min(end1, end2)
      if (newStart < existingEnd && existingStart < newEnd) {
        overlappingIds.add(highlight['id'] as int);
      }
    }

    // Delete overlapping highlights
    for (final id in overlappingIds) {
      await HighlightsDatabase.deleteHighlight(id);
    }
    LocalDataChangeNotifier.notifyHighlightsChanged();
  }

  /// Show error dialog
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        title: const Text('Import Error', style: TextStyle(color: Colors.red)),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }
}

/// Helper class for highlight positions
class _HighlightPosition {
  final int start;
  final int end;

  _HighlightPosition({required this.start, required this.end});
}
