import 'package:path/path.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/firestore_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/data_validation.dart';
import 'package:flutter/foundation.dart';

class NotesDatabase {
  static Database? _db;

  static Future<Database> getDatabase() async {
    if (_db != null) return _db!;

    String dbPath;
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // FFI is already initialized in main.dart - just open the database
        // Try both locations (same as bible database)
        String path1 = join(Directory.current.path, 'assets/user_notes.sqlite');
        String path2 = join(Directory.current.path, 'data/flutter_assets/assets/user_notes.sqlite');

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
        dbPath = join(databasesPath, 'user_notes.sqlite');

        if (!await File(dbPath).exists()) {
          try {
            // Copy from assets
            ByteData data = await rootBundle.load('assets/user_notes.sqlite');
            List<int> bytes = data.buffer.asUint8List();
            await File(dbPath).writeAsBytes(bytes, flush: true);
          } catch (e) {
            // If not exists in assets, proceed to create new db
          }
        }
        _db = await openDatabase(dbPath);
      } else if (kIsWeb) {
        // Simple names for Web
        dbPath = 'notes.db';
        _db = await openDatabase(dbPath);
      } else {
        throw Exception('Unsupported platform');
      }

      if (_db == null) {
        throw Exception('Failed to open database at $dbPath');
      }

      // Create table if it doesn't exist
      await _db!.execute('''
        CREATE TABLE IF NOT EXISTS user_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book TEXT NOT NULL,
          chapter INTEGER NOT NULL,
          verse INTEGER NOT NULL,
          note_text TEXT NOT NULL,
          created_at INTEGER UNIQUE,
          updated_at INTEGER NOT NULL
        )
      ''');

      return _db!;
    } catch (e) {
      throw Exception('Database error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getNotes() async {
    final db = await getDatabase();

    final result = await db.query('user_notes', orderBy: 'updated_at DESC');

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in result) {
      final isValid = await DataValidation.validateDatabaseRecord(record, 'note', context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete('user_notes',
          where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
    }

    return validResults;
  }

  static Future<Map<String, dynamic>?> getNoteForVerse(String book, int chapter, int verse) async {
    final db = await getDatabase();
    final result = await db.query('user_notes',
        where: 'book = ? AND chapter = ? AND verse = ?', whereArgs: [book, chapter, verse], limit: 1);

    if (result.isNotEmpty) {
      final record = result.first;
      final isValid = await DataValidation.validateDatabaseRecord(record, 'note', context: 'database query');

      if (!isValid) {
        // Delete corrupt record

        await db.delete('user_notes', where: 'id = ?', whereArgs: [record['id']]);
        return null;
      }

      return record;
    }
    return null;
  }

  static Future<int> addOrUpdateNote({
    required String book,
    required int chapter,
    required int verse,
    required String noteText,
    int? createdAt,
    required bool skipSync,
  }) async {
    final db = await getDatabase();

    // Check if note exists
    final existing = await getNoteForVerse(book, chapter, verse);
    final updatedAt = DateTime.now().millisecondsSinceEpoch;

    // If createdAt wasn't provided it is a new note
    if (createdAt == null || createdAt == 0) {
      createdAt = updatedAt;
    }

    // Validate data before saving to database
    final noteData = existing != null
        ? {
            'id': existing['id'],
            'book': book,
            'chapter': chapter,
            'verse': verse,
            'note_text': noteText,
            'created_at': existing['created_at'],
            'updated_at': updatedAt,
          }
        : {
            'book': book,
            'chapter': chapter,
            'verse': verse,
            'note_text': noteText,
            'created_at': createdAt,
            'updated_at': updatedAt,
          };

    final isValid = await DataValidation.validateBeforeDatabaseWrite(noteData, 'note');
    if (!isValid) {
      throw Exception('Invalid note data - failed validation. Operation rejected.');
    }

    if (existing != null) {
      // Update
      await db.update(
        'user_notes',
        {
          'note_text': noteText,
          'updated_at': updatedAt,
        },
        where: 'id = ?',
        whereArgs: [existing['id']],
      );

      // Add a 1ms delay to ensure no two records have the same created_at or timestamp
      await Future.delayed(Duration(milliseconds: 1));

      if (!skipSync) {
        // Queue update operation for sync service
        final syncData = {
          'id': existing['id'],
          'book': book,
          'chapter': chapter,
          'verse': verse,
          'note_text': noteText,
          'created_at': existing['created_at'],
          'updated_at': updatedAt,
        };
        FirestoreSyncService().markOperation('note', existing['created_at'] as int, 'update', syncData);
      }

      return existing['id'] as int;
    } else {
      // Insert the data into the database
      final id = await db.insert('user_notes', noteData);

      // Add a 1ms delay to ensure no two records have the same created_at or timestamp
      await Future.delayed(Duration(milliseconds: 1));

      if (!skipSync) {
        // Queue create operation for sync service
        final syncData = {
          'id': id,
          'book': book,
          'chapter': chapter,
          'verse': verse,
          'note_text': noteText,
          'created_at': createdAt,
          'updated_at': updatedAt,
        };
        await FirestoreSyncService().markOperation('note', createdAt.toInt(), 'create', syncData);
      }

      return id;
    }
  }

  static Future<void> deleteNote(int id, {skipSync = false}) async {
    // Get the note data before deletion for sync
    final db = await getDatabase();
    final noteToDelete = await db.query('user_notes', where: 'id = ?', whereArgs: [id]);

    // Delete locally first
    await db.delete('user_notes', where: 'id = ?', whereArgs: [id]);

    // Queue delete operation for sync service
    if (!skipSync) {
      if (noteToDelete.isNotEmpty) {
        FirestoreSyncService()
            .markOperation('note', noteToDelete.first['created_at'] as int, 'delete', noteToDelete.first);
      }
    }

    // Note: Remote deletion happens when queued operations are processed
  }

  static Future<List<Map<String, dynamic>>> getNotesForChapter(String book, int chapter) async {
    final db = await getDatabase();
    final result =
        await db.query('user_notes', where: 'book = ? AND chapter = ?', whereArgs: [book, chapter]);

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in result) {
      final isValid = await DataValidation.validateDatabaseRecord(record, 'note', context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete('user_notes',
          where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
    }

    return validResults;
  }
}
