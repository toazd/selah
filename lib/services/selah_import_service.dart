import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:selah/database/search_database.dart';
import '../database/history_database.dart';
import '../database/highlights_database.dart';
import '../database/notes_database.dart';
import '../services/supabase_sync_service.dart';
import '../services/local_data_change_notifier.dart';
import '../utils/note_storage_format.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';
import '../utils/error_handler.dart';

/// Get adaptive text color based on background color and theme
Color getAdaptiveTextColor(BuildContext context,
    {Color? backgroundColor, bool usePrimaryColor = false}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  Color bgColor;
  if (backgroundColor != null) {
    // Custom background color provided
    bgColor = backgroundColor;
  } else if (usePrimaryColor) {
    // Use primary color (for buttons)
    bgColor = isDark
        ? const Color(0xFF64B5F6)
        : const Color(0xFF1976D2); // Default blue colors
  } else {
    // Use background color (default behavior)
    bgColor = isDark
        ? const Color(0xFF000010)
        : const Color.fromARGB(255, 255, 247, 203);
  }

  return bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

/// Service for importing Selah app data from zip backup files
class SelahImportService {
  /// Main entry point for Selah data import
  static Future<void> importSelahData(BuildContext context) async {
    try {
      // Request storage permission
      bool hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        if (context.mounted) {
          showStyledSnackBar(
              context, 'Storage permission is required for import.',
              isError: true);
        }
        return;
      }

      // Let user choose zip file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: 'Select Selah Backup File',
      );

      if (result == null || result.files.single.path == null) return;

      final zipFilePath = result.files.single.path!;

      // Show loading dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Reading Backup File',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Validating backup file...',
                    style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(context))),
              ],
            ),
          ),
        );
      }

      // Extract and validate JSON
      final importData = await _extractAndValidateImportData(zipFilePath);

      // Close loading dialog
      if (context.mounted) Navigator.pop(context);

      // Show selection dialog
      if (context.mounted) {
        final selectionResult =
            await _showImportSelectionDialog(context, importData);

        if ((selectionResult['selectedTypes'] as Set<String>).isEmpty) return;

        final selectedTypes = selectionResult['selectedTypes'] as Set<String>;
        final isMergeMode = selectionResult['isMergeMode'] as bool;

        // Show import progress dialog
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Center(
                  child: Text('Importing Data',
                      style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context)))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  //const SizedBox(height: 16),
                  //Text('Importing selected data...', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                ],
              ),
            ),
          );
        }

        final syncService = SupabaseSyncService();

        Map<String, bool> results;

        // Import selected data types
        results = await _importSelectedData(
            importData, selectedTypes, isMergeMode, syncService);

        // Close progress dialog
        if (context.mounted) Navigator.pop(context);

        // Show results
        if (context.mounted) {
          _showImportResults(context, results);
        }
      }
    } catch (e) {
      // Close any open dialogs
      if (context.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }

      // Show error dialog
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            constraints: const BoxConstraints(maxWidth: 400),
            title: const Text('Import Failed',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: Colors.red)),
            content: Text('Failed to import data: $e',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Ok',
                    style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(context))),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Extract and validate JSON from zip file
  static Future<Map<String, dynamic>> _extractAndValidateImportData(
      String zipFilePath) async {
    // Extract zip file to temporary directory
    final tempDir = await Directory.systemTemp.createTemp('selah_import_');
    final encoder = ZipDecoder();
    final inputStream = InputFileStream(zipFilePath);

    try {
      final archive = encoder.decodeStream(inputStream);

      // Find JSON file in archive
      ArchiveFile? jsonFile;
      for (final file in archive.files) {
        if (file.name.endsWith('.json')) {
          jsonFile = file;
          break;
        }
      }

      if (jsonFile == null) {
        throw Exception('No JSON file found in backup archive!');
      }

      // Write JSON to temp file and parse
      final jsonPath = path.join(tempDir.path, 'selah_data.json');
      await File(jsonPath).writeAsBytes(jsonFile.content as List<int>);
      final jsonContent = await File(jsonPath).readAsString();
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;

      // Validate structure
      if (!data.containsKey('highlights') ||
          !data.containsKey('notes') ||
          !data.containsKey('history') ||
          !data.containsKey('searchHistory') ||
          !data.containsKey('exportInfo')) {
        throw Exception('Invalid backup file format');
      }

      return data;
    } finally {
      // Ensure file handle is properly closed
      inputStream.close();
      // Clean up temp files
      await tempDir.delete(recursive: true);
    }
  }

  /// Show import selection dialog with RadioGroup for merge/replace mode
  static Future<Map<String, dynamic>> _showImportSelectionDialog(
      BuildContext context, Map<String, dynamic> importData) async {
    final exportInfo = importData['exportInfo'] as Map<String, dynamic>;
    final availableTypes = Set<String>.from(exportInfo['dataTypes'] as List);

    return await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) {
            final selectedTypes = Set<String>.from(availableTypes);
            bool isMergeMode = true; // Default to merge mode
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  constraints: const BoxConstraints(maxWidth: 400),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMergeMode
                            ? '📝 Merge Mode\n\nImported data will be merged with existing data. Conflicts will be resolved with imported data taking precedence.'
                            : '⚠️ Replace Mode\n\nExisting data for the selected categories will be erased before importing.',
                        style: TextStyle(
                            color: isMergeMode ? Colors.blue : Colors.red,
                            fontFamily: uiFontFamily,
                            fontSize: uiFontSize),
                      ),
                      const SizedBox(height: 16),
                      Text('Import Mode:',
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context))),
                      RadioGroup<bool>(
                        groupValue: isMergeMode,
                        onChanged: (bool? value) {
                          if (value != null) {
                            setState(() {
                              isMergeMode = value;
                            });
                          }
                        },
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              title: Text('Replace existing data',
                                  style: TextStyle(
                                      fontSize: uiFontSize,
                                      fontFamily: uiFontFamily,
                                      color: getAdaptiveTextColor(context))),
                              value:
                                  false, // REQUIRED: The value this tile represents
                              controlAffinity: ListTileControlAffinity.leading,
                              // groupValue and onChanged are handled by the parent RadioGroup.
                            ),
                            RadioListTile<bool>(
                              title: Text('Merge with existing data',
                                  style: TextStyle(
                                      fontSize: uiFontSize,
                                      fontFamily: uiFontFamily,
                                      color: getAdaptiveTextColor(context))),
                              value:
                                  true, // REQUIRED: The value this tile represents
                              controlAffinity: ListTileControlAffinity.leading,
                              // groupValue and onChanged are handled by the parent RadioGroup.
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Available data in backup:',
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context))),
                      const SizedBox(height: 8),
                      ...availableTypes.map((type) {
                        final count = _getDataTypeCount(importData, type);
                        return CheckboxListTile(
                          title: Text(_getDataTypeDisplayName(type),
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          subtitle: Text('$count items',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          value: selectedTypes.contains(type),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                selectedTypes.add(type);
                              } else {
                                selectedTypes.remove(type);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: Text('Cancel',
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context))),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, {
                        'selectedTypes': selectedTypes,
                        'isMergeMode': isMergeMode,
                      }),
                      child: Text('Import Selected',
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context))),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        {'selectedTypes': <String>{}, 'isMergeMode': false};
  }

  /// Import selected data types
  static Future<Map<String, bool>> _importSelectedData(
      Map<String, dynamic> data,
      Set<String> selectedTypes,
      bool isMergeMode,
      SupabaseSyncService syncService) async {
    final results = <String, bool>{};

    // Reset sync timestamps for imported data types BEFORE syncing.
    // Imported records have their original updated_at timestamps which may be
    // older than the last sync time, causing them to be filtered out during sync.
    // Resetting the sync timestamps ensures a full sync will pick up all records.
    await syncService.resetSyncTimestampsForImport(selectedTypes);

    // Import highlights if selected
    if (selectedTypes.contains('highlights')) {
      try {
        await _importHighlights(
            data['highlights'] as List<dynamic>, isMergeMode);
        LocalDataChangeNotifier.notifyHighlightsChanged();

        // Trigger sync after results merged and UI updated
        final highlightCount = (data['highlights'] as List<dynamic>).length;
        if (highlightCount > 0) {
          try {
            await syncService.syncHighlights();
          } catch (e) {
            // Sync failed, will retry automatically
          }
        }
        results['highlights'] = true;
      } catch (e) {
        results['highlights'] = false;
      }
    }

    // Import notes if selected
    if (selectedTypes.contains('notes')) {
      try {
        await _importNotes(data['notes'] as List<dynamic>, isMergeMode);
        LocalDataChangeNotifier.notifyNotesChanged();

        // Trigger sync after results merged and UI updated
        final noteCount = (data['notes'] as List<dynamic>).length;
        if (noteCount > 0) {
          try {
            await syncService.syncNotes();
          } catch (e) {
            // Sync failed, will retry automatically
          }
        }
        results['notes'] = true;
      } catch (e) {
        results['notes'] = false;
      }
    }

    // Import history if selected
    if (selectedTypes.contains('history')) {
      try {
        await _importHistory(data['history'] as List<dynamic>, isMergeMode);
        LocalDataChangeNotifier.notifyHistoryChanged();

        // Trigger sync after results merged and UI updated
        final historyCount = (data['history'] as List<dynamic>).length;
        if (historyCount > 0) {
          try {
            await syncService.syncHistory();
          } catch (e) {
            // Sync failed, will retry automatically
          }
        }
        results['history'] = true;
      } catch (e) {
        results['history'] = false;
      }
    }

    // Import search history if selected
    if (selectedTypes.contains('searchHistory')) {
      try {
        await _importSearchHistory(
            data['searchHistory'] as List<dynamic>, isMergeMode);
        LocalDataChangeNotifier.notifySearchHistoryChanged();

        // Trigger sync after search history is imported to maintain continuity
        final searchHistoryCount =
            (data['searchHistory'] as List<dynamic>).length;
        if (searchHistoryCount > 0) {
          try {
            await syncService.syncSearchHistory();
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_ImportSelectedData syncSearchHistory exception',
              context: {
                'class': 'SelahImportService',
                'method': '_importSelectedData'
              },
            );
          }
        }

        results['searchHistory'] = true;
      } catch (e) {
        results['searchHistory'] = false;
      }
    }

    return results;
  }

  /// Import highlights from Selah backup
  static Future<void> _importHighlights(
      List<dynamic> highlights, bool isMergeMode) async {
    if (!isMergeMode) {
      // Clear existing highlights in replace mode
      final dbHighlights = await HighlightsDatabase.getDatabase();
      await dbHighlights.delete('user_highlights');
    }

    // Import highlights
    // Note: We intentionally don't preserve UUIDs from the backup file.
    // UUIDs are specific to each user's Supabase account. If we preserved them,
    // the sync would see UUIDs that don't exist in the current user's remote data
    // and incorrectly delete the imported records as "remotely deleted".
    for (final highlight in highlights) {
      await HighlightsDatabase.addHighlight(
        book: highlight['book'] as String,
        chapter: highlight['chapter'] as int,
        verse: highlight['verse'] as int,
        start: highlight['start'] as int,
        end: highlight['end'] as int,
        color: highlight['color'] as int,
        createdAt: highlight['created_at'] as int,
        updatedAt: highlight['updated_at'] as int,
        skipSync: true,
        uuid: null, // Don't preserve UUID - let sync assign new ones
      );
    }
  }

  /// Import notes from Selah backup
  static Future<void> _importNotes(
      List<dynamic> notes, bool isMergeMode) async {
    if (!isMergeMode) {
      // Clear existing notes in replace mode
      final db = await NotesDatabase.getDatabase();
      await db.delete('user_notes');
    }

    // Import notes
    // Note: We intentionally don't preserve UUIDs from the backup file.
    // UUIDs are specific to each user's Supabase account. If we preserved them,
    // the sync would see UUIDs that don't exist in the current user's remote data
    // and incorrectly delete the imported records as "remotely deleted".
    for (final note in notes) {
      // Convert to Delta format before storing
      final deltaNoteText =
          NoteStorageFormat.ensureDeltaFormat(note['note_text'] as String);

      await NotesDatabase.addOrUpdateNote(
        book: note['book'] as String,
        chapter: note['chapter'] as int,
        verse: note['verse'] as int,
        noteText: deltaNoteText,
        skipSync: true,
        uuid: null, // Don't preserve UUID - let sync assign new ones
      );
    }
  }

  /// Import history from Selah backup
  static Future<void> _importHistory(
      List<dynamic> history, bool isMergeMode) async {
    if (!isMergeMode) {
      // Clear existing history in replace mode
      final db = await HistoryDatabase.getDatabase();
      await db.delete('history');
    }

    // Import history
    // Note: We intentionally don't preserve UUIDs from the backup file.
    // UUIDs are specific to each user's Supabase account. If we preserved them,
    // the sync would see UUIDs that don't exist in the current user's remote data
    // and incorrectly delete the imported records as "remotely deleted".
    for (final entry in history) {
      await HistoryDatabase.addHistory(
        entry['book'] as String,
        entry['chapter'] as int,
        entry['verse'] as int?,
        entry['timestamp'] as int,
        false,
        uuid: null, // Don't preserve UUID - let sync assign new ones
      );
    }
  }

  /// Import search history from Selah backup
  static Future<void> _importSearchHistory(
      List<dynamic> searchHistory, bool isMergeMode) async {
    if (!isMergeMode) {
      // Clear existing search history in replace mode
      await SearchDatabase.clearSearchHistory();
    }

    // Import search history
    for (final entry in searchHistory) {
      // Handle both boolean values (from newer exports) and integer values (for backwards compatibility)
      bool parseBool(dynamic value) {
        if (value is bool) return value;
        if (value is int) return value == 1;
        return false; // Default to false for any other type
      }

      // Note: We intentionally don't preserve UUIDs from the backup file.
      // UUIDs are specific to each user's Supabase account. If we preserved them,
      // the sync would see UUIDs that don't exist in the current user's remote data
      // and incorrectly delete the imported records as "remotely deleted".
      await SearchDatabase.addSearchHistory(
        entry['query'] as String,
        parseBool(entry['useRegex']),
        parseBool(entry['useNearby']),
        parseBool(entry['useWholeWord']),
        parseBool(entry['useRedLetter']),
        parseBool(entry['caseSensitive']),
        entry['bookFilterType'] as String,
        entry['customBookFilter'] as String,
        entry['timestamp'] as int,
        uuid: null, // Don't preserve UUID - let sync assign new ones
      );
    }
  }

  /// Get count of items for a data type
  static int _getDataTypeCount(Map<String, dynamic> data, String type) {
    switch (type) {
      case 'highlights':
        return (data['highlights'] as List).length;
      case 'notes':
        return (data['notes'] as List).length;
      case 'history':
        return (data['history'] as List).length;
      case 'searchHistory':
        return (data['searchHistory'] as List).length;
      default:
        return 0;
    }
  }

  /// Get display name for a data type
  static String _getDataTypeDisplayName(String type) {
    switch (type) {
      case 'preferences':
        return 'Preferences';
      case 'highlights':
        return 'Highlights';
      case 'notes':
        return 'Notes';
      case 'history':
        return 'History';
      case 'searchHistory':
        return 'Search History';
      default:
        return type;
    }
  }

  /// Show import results dialog
  static void _showImportResults(
      BuildContext context, Map<String, bool> results) {
    final successful =
        results.entries.where((e) => e.value).map((e) => e.key).toList();
    final failed =
        results.entries.where((e) => !e.value).map((e) => e.key).toList();

    //Show success snackbars for each successful import
    //for (final type in successful) {
    //  showStyledSnackBar(context, '✅ ${_getDataTypeDisplayName(type)} imported successfully');
    //}

    // Show error dialog for any failures
    if (failed.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          title: const Text('Import Completed with Errors',
              style: TextStyle(
                  color: Colors.red,
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The following items failed to import:',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              ...failed
                  .map((type) => Text('❌ ${_getDataTypeDisplayName(type)}')),
              const SizedBox(height: 16),
              Text('Your existing data for failed items has been preserved.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Ok',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
            ),
          ],
        ),
      );
    } else if (successful.isNotEmpty) {
      // Show final success message if everything worked
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 300),
          content: Text(
              '✅ All of the selected data types have been imported successfully.',
              style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Ok',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
            ),
          ],
        ),
      );
    }
  }

  /// Request storage permission
  static Future<bool> _requestStoragePermission() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      PermissionStatus status = await Permission.storage.request();
      return status.isGranted;
    }
    return true; // For desktop, no need
  }
}

/// Custom RadioGroup widget for grouping radio buttons
/*
class RadioGroup<T> extends InheritedWidget {
  final T? groupValue;
  final ValueChanged<T?>? onChanged;

  const RadioGroup({
    super.key,
    required super.child,
    required this.groupValue,
    required this.onChanged,
  });

  static RadioGroup<T> of<T>(BuildContext context) {
    final RadioGroup<T>? result = context.dependOnInheritedWidgetOfExactType<RadioGroup<T>>();
    assert(result != null, 'No RadioGroup found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(RadioGroup oldWidget) {
    return oldWidget.groupValue != groupValue;
  }
}
*/
