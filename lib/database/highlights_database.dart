import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/supabase_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/data_validation.dart';

class HighlightsDatabase {
  static Database? _db;

  static Future<Database> getDatabase() async {
    if (_db != null) return _db!;

    String dbPath;
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // FFI is already initialized in main.dart - just open the database
        // Try both locations (same as bible database)
        String path1 = join(Directory.current.path, 'assets/user_highlights.sqlite');
        String path2 = join(Directory.current.path, 'data/flutter_assets/assets/user_highlights.sqlite');

        if (await File(path1).exists()) {
          dbPath = path1;
        } else if (await File(path2).exists()) {
          dbPath = path2;
        } else {
          // Use the flutter_assets location as default for new databases
          dbPath = path2;
          // Ensure directory exists
          await Directory(join(Directory.current.path, 'data/flutter_assets/assets')).create(recursive: true);
        }

        _db = await databaseFactory.openDatabase(dbPath);
      } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // Mobile: copy from assets to database path if needed
        final databasesPath = await getDatabasesPath();
        dbPath = join(databasesPath, 'user_highlights.sqlite');

        if (!await File(dbPath).exists()) {
          try {
            // Copy from assets
            ByteData data = await rootBundle.load('assets/user_highlights.sqlite');
            List<int> bytes = data.buffer.asUint8List();
            await File(dbPath).writeAsBytes(bytes, flush: true);
          } catch (e) {
            // If not exists in assets, proceed to create new db
          }
        }
        _db = await openDatabase(dbPath);
      } else if (kIsWeb) {
        // Simple names for Web
        dbPath = 'highlights.db';
        _db = await openDatabase(dbPath);
      } else {
        throw Exception('Unsupported platform');
      }

      if (_db == null) {
        throw Exception('Failed to open database at $dbPath');
      }

      // Create table if it doesn't exist
      await _db!.execute('''
        CREATE TABLE IF NOT EXISTS user_highlights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book TEXT NOT NULL,
          chapter INTEGER NOT NULL,
          verse INTEGER NOT NULL,
          start INTEGER NOT NULL,
          end INTEGER NOT NULL,
          color INTEGER NOT NULL,
          created_at INTEGER UNIQUE,
          updated_at INTEGER NOT NULL
        )
      ''');

      return _db!;
    } catch (e) {
      throw Exception('Database error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getHighlights() async {
    final db = await getDatabase();

    final result = await db.query('user_highlights', orderBy: 'updated_at DESC');

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in result) {
      final isValid = await DataValidation.validateDatabaseRecord(record, 'highlight', context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete('user_highlights', where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
    }

    return validResults;
  }

  static Future<List<Map<String, dynamic>>> getHighlightsForChapter(String book, int chapter) async {
    final db = await getDatabase();
    final highlights = await db.query('user_highlights', where: 'book = ? AND chapter = ?', whereArgs: [book, chapter], orderBy: 'verse ASC, start ASC');

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in highlights) {
      final isValid = await DataValidation.validateDatabaseRecord(record, 'highlight', context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete('user_highlights', where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
    }

    return validResults;
  }

  static Future<List<Map<String, dynamic>>> getHighlightsForVerse(String book, int chapter, int verse) async {
    final db = await getDatabase();
    final highlights = await db.query('user_highlights', where: 'book = ? AND chapter = ? AND verse = ?', whereArgs: [book, chapter, verse], orderBy: 'start ASC');

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in highlights) {
      final isValid = await DataValidation.validateDatabaseRecord(record, 'highlight', context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete('user_highlights', where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
    }

    return validResults;
  }

  static Future<int> addHighlight({
    required String book,
    required int chapter,
    required int verse,
    required int start,
    required int end,
    required int color,
    required int createdAt,
    required int updatedAt,
    required bool skipSync,
  }) async {
    // Validate data before saving to database
    final highlightData = {
      'book': book,
      'chapter': chapter,
      'verse': verse,
      'start': start,
      'end': end,
      'color': color,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };

    final isValid = await DataValidation.validateBeforeDatabaseWrite(highlightData, 'highlight');
    if (!isValid) {
      throw Exception('Invalid highlight data - failed validation. Operation rejected.');
    }

    final db = await getDatabase();
    final id = await db.insert('user_highlights', highlightData);

    // Add a 1ms delay to ensure no two records have the same created_at or timestamp
    await Future.delayed(Duration(milliseconds: 1));

    if (!skipSync) {
      // Queue create operation for sync service
      final syncData = {
        'id': id,
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'start': start,
        'end': end,
        'color': color,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      SupabaseSyncService().markOperation('highlight', createdAt.toInt(), 'create', syncData);
    }

    return id;
  }

  static Future<void> updateHighlight({
    required int id,
    required int start,
    required int end,
    required int color,
    int? updateAt,
  }) async {
    final timestamp = updateAt ?? DateTime.now().millisecondsSinceEpoch;

    // Get existing record first for validation
    final db = await getDatabase();
    final existing = await db.query('user_highlights', where: 'id = ?', whereArgs: [id]);
    if (existing.isEmpty) {
      throw Exception('Highlight with id $id not found');
    }

    // Validate data before updating (merge with existing data for complete validation)
    final existingData = existing.first;
    final updateData = {
      'book': existingData['book'],
      'chapter': existingData['chapter'],
      'verse': existingData['verse'],
      'start': start,
      'end': end,
      'color': color,
      'created_at': existingData['created_at'],
      'updated_at': timestamp,
    };

    final isValid = await DataValidation.validateBeforeDatabaseWrite(updateData, 'highlight');
    if (!isValid) {
      throw Exception('Invalid highlight data - failed validation. Update rejected.');
    }

    await db.update(
      'user_highlights',
      {
        'start': start,
        'end': end,
        'color': color,
        'updated_at': timestamp,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Add a 1ms delay to ensure no two records have the same created_at or timestamp
    await Future.delayed(Duration(milliseconds: 1));

    // Queue update operation for sync service
    final highlightData = {
      'id': id,
      'start': start,
      'end': end,
      'color': color,
      'updated_at': timestamp,
      'created_at': existingData['created_at'],
    };
    SupabaseSyncService().markOperation('highlight', existingData['created_at'] as int, 'update', highlightData);
  }

  static Future<void> deleteHighlight(int id) async {
    // Get the highlight data before deletion for sync
    final db = await getDatabase();
    final highlightToDelete = await db.query('user_highlights', where: 'id = ?', whereArgs: [id]);

    // Delete locally first
    await db.delete('user_highlights', where: 'id = ?', whereArgs: [id]);

    // Queue delete operation for sync service
    if (highlightToDelete.isNotEmpty) {
      SupabaseSyncService().markOperation('highlight', highlightToDelete.first['created_at'] as int, 'delete', highlightToDelete.first);
    }

    // Note: Remote deletion happens when queued operations are processed
  }
}
