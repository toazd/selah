import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../services/supabase_sync_service.dart';
import '../utils/data_validation.dart';
import 'package:flutter/foundation.dart';
import '../utils/platform_paths.dart';
import '../utils/error_handler.dart';
import '../utils/preferences_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        // Use platform-specific user data directory
        dbPath = await PlatformPaths.getDatabasePath('user_history');

        // Check if database exists in assets (for initial setup)
        if (!await File(dbPath).exists()) {
          final assetPath =
              await PlatformPaths.getAssetPath('user_history.sqlite');
          if (await File(assetPath).exists()) {
            // Copy from assets to user data directory
            await File(assetPath).copy(dbPath);
          }
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
        ErrorHandler.logError(
          null,
          customMessage: 'Unsupported platform',
          type: ErrorType.system,
          context: {'class': 'HistoryDatabase', 'method': '_initDatabase'},
        );
        throw Exception('Unsupported platform');
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Database init error',
        type: ErrorType.system,
        context: {'class': 'HistoryDatabase', 'method': '_initDatabase'},
      );
      throw Exception('Database error: ${e.toString()}');
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

  static Future<void> upsertHistoryFromSync(
      String book, int chapter, int? verse, int timestamp,
      {String? uuid}) async {
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
      if (kDebugMode) {
        debugPrint(
            'upsertHistoryFromSync rejected invalid history item: $historyData');
      }
      throw Exception(
          'Invalid history data - failed validation. Sync upsert rejected.');
    }

    final db = await getDatabase();
    final existing = await db.query(historyTable,
        where: '$colTimestamp = ?', whereArgs: [timestamp], limit: 1);

    if (existing.isNotEmpty) {
      await db.update(
        historyTable,
        {
          colBook: book,
          colChapter: chapter,
          colVerse: verse,
          colTimestamp: timestamp,
          'uuid': uuid ?? existing.first['uuid'],
        },
        where: '$colId = ?',
        whereArgs: [existing.first[colId]],
      );
      return;
    }

    await db.insert(historyTable, {
      colBook: book,
      colChapter: chapter,
      colVerse: verse,
      colTimestamp: timestamp,
      'uuid': uuid,
    });
  }

  // Delete history item
  static Future<void> deleteHistoryItem(int id,
      {bool skipSync = false, String? uuid}) async {
    try {
      // Get the history item data before deletion for sync
      final db = await getDatabase();
      final historyItem =
          await db.query(historyTable, where: '$colId = ?', whereArgs: [id]);

      if (historyItem.isNotEmpty) {
        // Delete locally first
        await db.delete(historyTable, where: '$colId = ?', whereArgs: [id]);

        // Queue delete operation for sync service
        if (!skipSync) {
          final historyData = Map<String, dynamic>.from(historyItem.first);
          if (uuid != null) {
            historyData['uuid'] = uuid;
          }
          SupabaseSyncService().markOperation('history',
              historyData['timestamp'] as int, 'delete', historyData);
        }
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'deleteHistoryItem exception',
        context: {
          'class': 'HistoryDatabase',
          'method': 'deleteHistoryItem',
          'id': id
        },
      );
    }
  }

  static Future<List<DateTime>> getHistoryDates() async {
    final db = await getDatabase();
    final rows = await db.query(
      historyTable,
      columns: [colTimestamp],
      orderBy: '$colTimestamp DESC',
    );

    final seenDates = <String>{};
    final dates = <DateTime>[];

    for (final row in rows) {
      final timestamp = row[colTimestamp] as int?;
      if (timestamp == null) continue;

      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final dateKey = '${date.year}-${date.month}-${date.day}';
      if (seenDates.add(dateKey)) {
        dates.add(DateTime(date.year, date.month, date.day));
      }
    }

    return dates;
  }

  static Future<int> countHistoryBeforeTimestamp(int timestamp) async {
    final db = await getDatabase();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $historyTable WHERE $colTimestamp < ?',
      [timestamp],
    );

    final count = result.first['count'];
    return count is num ? count.toInt() : 0;
  }

  static Future<int> deleteHistoryBeforeTimestamp(int timestamp,
      {bool skipSync = false}) async {
    final db = await getDatabase();
    final historyItems = await db.query(
      historyTable,
      where: '$colTimestamp < ?',
      whereArgs: [timestamp],
    );

    if (historyItems.isEmpty) return 0;

    final deletedCount = await db.delete(
      historyTable,
      where: '$colTimestamp < ?',
      whereArgs: [timestamp],
    );

    if (!skipSync) {
      for (final item in historyItems) {
        final historyData = Map<String, dynamic>.from(item);
        SupabaseSyncService().markOperation(
          'history',
          historyData[colTimestamp] as int,
          'delete',
          historyData,
        );
      }
    }

    return deletedCount;
  }

  /// Migrate the username cache from older releases into SharedPreferences.
  ///
  /// The old table is intentionally retained so opening an old database is
  /// harmless, but all new reads and writes use SharedPreferences.
  static Future<void> migrateCachedUsernameToPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.containsKey(cachedUsernamePreferenceKey)) return;

      final db = await getDatabase();
      final table = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [userCacheTable],
      );
      if (table.isEmpty) return;

      final result = await db.query(
        userCacheTable,
        where: '$colKey = ?',
        whereArgs: ['username'],
        limit: 1,
      );
      if (result.isEmpty) return;

      final username = result.first[colValue] as String?;
      if (username != null && username.isNotEmpty) {
        await preferences.setString(cachedUsernamePreferenceKey, username);
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'migrateCachedUsernameToPreferences exception',
        context: {
          'class': 'HistoryDatabase',
          'method': 'migrateCachedUsernameToPreferences',
        },
      );
    }
  }
}
