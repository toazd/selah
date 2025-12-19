import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../services/supabase_sync_service.dart';
import '../utils/data_validation.dart';
import 'package:flutter/foundation.dart';

class HistoryDatabase {
  static Database? _database;

  // Database table name
  static const String historyTable = 'history';
  //static const String searchHistoryTable = 'search_history';
  static const String userCacheTable = 'user_cache';

  // History table columns
  static const String colId = 'id';
  static const String colBook = 'book';
  static const String colChapter = 'chapter';
  static const String colVerse = 'verse';
  static const String colTimestamp = 'timestamp';

  // User cache table columns
  static const String colKey = 'key';
  static const String colValue = 'value';

  // Initialize database
  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    String dbPath;
    try {
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // FFI is already initialized in main.dart - just open the database
        // Try both locations (same as bible database)
        String path1 =
            join(Directory.current.path, 'assets/user_history.sqlite');
        String path2 = join(Directory.current.path,
            'data/flutter_assets/assets/user_history.sqlite');

        if (await File(path1).exists()) {
          dbPath = path1;
        } else if (await File(path2).exists()) {
          dbPath = path2;
        } else {
          // Use the flutter_assets location as default for new databases
          dbPath = path2;
          // Ensure directory exists
          await Directory(
                  join(Directory.current.path, 'data/flutter_assets/assets'))
              .create(recursive: true);
        }

        _database = await databaseFactory.openDatabase(dbPath);

        // Create table if it doesn't exist
        await _database!.execute('''
          CREATE TABLE IF NOT EXISTS $historyTable (
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colBook TEXT NOT NULL,
            $colChapter INTEGER NOT NULL,
            $colVerse INTEGER NOT NULL,
            $colTimestamp INTEGER UNIQUE,
            uuid TEXT UNIQUE NULL
          )
        ''');

        // Create user cache table if it doesn't exist
        await _database!.execute('''
          CREATE TABLE IF NOT EXISTS $userCacheTable (
            $colKey TEXT PRIMARY KEY,
            $colValue TEXT
          )
        ''');

        return _database!;
      } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // Mobile: use database path
        final databasesPath = await getDatabasesPath();
        dbPath = join(databasesPath, 'user_history.sqlite');
        return await openDatabase(
          dbPath,
          version: 1, // Incremented version to add user_cache table
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      } else if (kIsWeb) {
        // Simple names for Web
        dbPath = 'history.db';
        _database = await openDatabase(
          dbPath,
          version: 1,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        return _database!;
      } else {
        throw Exception('Unsupported platform');
      }
    } catch (e) {
      throw Exception('Database error: $e');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create history table
    await db.execute('''
      CREATE TABLE $historyTable (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colBook TEXT,
        $colChapter INTEGER,
        $colVerse INTEGER,
        $colTimestamp INTEGER UNIQUE,
        uuid TEXT UNIQUE NULL
      )
    ''');

    // Create user cache table
    await db.execute('''
      CREATE TABLE $userCacheTable (
        $colKey TEXT PRIMARY KEY,
        $colValue TEXT
      )
    ''');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add user cache table in version 2
      await db.execute('''
        CREATE TABLE $userCacheTable (
          $colKey TEXT PRIMARY KEY,
          $colValue TEXT
        )
      ''');
    }
  }

  // Get all history
  static Future<List<Map<String, dynamic>>> getHistory() async {
    Database db = await getDatabase();

    final result = await db.query(historyTable, orderBy: '$colTimestamp DESC');

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in result) {
      final isValid = await DataValidation.validateDatabaseRecord(
          record, 'history',
          context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete(historyTable,
          where: 'id IN (${corruptIds.map((_) => '?').join(',')})',
          whereArgs: corruptIds);
    }

    return validResults;
  }

  // Get history with pagination (for performance with large datasets)
  static Future<List<Map<String, dynamic>>> getHistoryPaginated(
      int offset, int limit) async {
    Database db = await getDatabase();

    try {
      // First verify database integrity
      final tableExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$historyTable'");

      if (tableExists.isEmpty) {
        await _onCreate(db, 1);
      }

      final result = await db.query(
        historyTable,
        orderBy: '$colTimestamp DESC',
        limit: limit,
        offset: offset,
      );

      // Validate and filter out corrupt records
      final validResults = <Map<String, dynamic>>[];
      final corruptIds = <int>[];

      for (final record in result) {
        final isValid = await DataValidation.validateDatabaseRecord(
            record, 'history',
            context: 'database query');
        if (isValid) {
          validResults.add(record);
        } else {
          corruptIds.add(record['id'] as int);
        }
      }

      // Delete corrupt records
      if (corruptIds.isNotEmpty) {
        await db.delete(historyTable,
            where: 'id IN (${corruptIds.map((_) => '?').join(',')})',
            whereArgs: corruptIds);
      }

      return validResults;
    } catch (e) {
      rethrow;
    }
  }

  // Add history
  static Future<void> addHistory(
      String book, int chapter, int? verse, int timestamp, bool skipSync,
      {String? uuid}) async {
    // Validate data before saving to database
    final historyData = {
      'book': book,
      'chapter': chapter,
      'verse': verse,
      'timestamp': timestamp,
      'uuid': uuid,
    };

    final isValid = await DataValidation.validateBeforeDatabaseWrite(
        historyData, 'history');
    if (!isValid) {
      throw Exception(
          'Invalid history data - failed validation. Operation rejected.');
    }

    Database db = await getDatabase();

    // Check for existing entry with same book, chapter, verse, and hour:minute timestamp
    // to prevent duplicates in display (which only shows hour:minute precision)
    final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

    // Create a timestamp representing the start of this minute (hour:minute:00)
    final DateTime minuteStart = DateTime(dateTime.year, dateTime.month,
        dateTime.day, dateTime.hour, dateTime.minute);
    final int minuteStartTimestamp = minuteStart.millisecondsSinceEpoch;

    // Create a timestamp representing the start of the next minute
    final DateTime nextMinuteStart = minuteStart.add(Duration(minutes: 1));
    final int nextMinuteTimestamp = nextMinuteStart.millisecondsSinceEpoch;

    final existingEntries = await db.query(
      historyTable,
      where:
          '$colBook = ? AND $colChapter = ? AND $colVerse = ? AND $colTimestamp >= ? AND $colTimestamp < ?',
      whereArgs: [
        book,
        chapter,
        verse,
        minuteStartTimestamp,
        nextMinuteTimestamp
      ],
    );

    // If no existing entry found for this minute, add the new history item
    if (existingEntries.isEmpty) {
      await db.insert(historyTable, {
        colBook: book,
        colChapter: chapter,
        colVerse: verse,
        colTimestamp: timestamp,
        'uuid': uuid,
      });

      // Add a 1ms delay to ensure no two records have the same created_at or timestamp
      await Future.delayed(Duration(milliseconds: 1));

      if (!skipSync) {
        // Queue history operation for sync
        final syncData = {
          'id': timestamp, // Keep as int for history items
          'book': book,
          'chapter': chapter,
          'verse': verse,
          'timestamp': timestamp,
          'uuid': uuid,
        };
        SupabaseSyncService()
            .markOperation('history', timestamp, 'create', syncData);
      }
    }
    // If an existing entry was found, skip adding this duplicate
  }

  // Delete history item
  static Future<void> deleteHistoryItem(int id, {String? uuid}) async {
    try {
      // Get the history item data before deletion for sync
      final db = await getDatabase();
      final historyItem =
          await db.query(historyTable, where: '$colId = ?', whereArgs: [id]);

      if (historyItem.isNotEmpty) {
        // Delete locally first
        await db.delete(historyTable, where: '$colId = ?', whereArgs: [id]);

        // Queue delete operation for sync service
        final historyData = Map<String, dynamic>.from(historyItem.first);
        if (uuid != null) {
          historyData['uuid'] = uuid;
        }
        SupabaseSyncService().markOperation(
            'history', historyData['timestamp'] as int, 'delete', historyData);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('deleteHistoryItem exception: $e');
    }
  }

  // Cache username in database
  static Future<void> setCachedUsername(String username) async {
    try {
      Database db = await getDatabase();
      await db.insert(
        userCacheTable,
        {colKey: 'username', colValue: username},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('setCachedUsername exception: $e');
    }
  }

  // Get cached username from database
  static Future<String?> getCachedUsername() async {
    Database db = await getDatabase();
    List<Map<String, dynamic>> result = await db.query(
      userCacheTable,
      where: '$colKey = ?',
      whereArgs: ['username'],
    );
    if (result.isNotEmpty) {
      return result.first[colValue] as String?;
    }
    return null;
  }

  // // Clear user cache
  // static Future<void> clearUserCache() async {
  //   Database db = await getDatabase();
  //   await db.delete(userCacheTable);
  // }
}
