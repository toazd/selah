import 'error_handler.dart';

/// Centralized data validation utility for user data (highlights, notes, history)
/// Provides validation functions to prevent data corruption throughout the app
/// 1. Any data that is to be saved must pass validation first
/// 2. Any data that is to be synced must pass validation first
/// 3. Failures are and should be removed from whatever source they were detected from
/// 4. Because of sync, ignoring failures is not an option sometimes
/// This stops local and remote data corruption as soon as it is detected and
/// keeps it from spreading (potentially to multiple clients logged into the
/// same account)

class DataValidation {
  /// Validates highlight data for required fields and data integrity
  /// Returns true if valid, logs error and returns false if invalid
  static Future<bool> validateHighlightData(Map<String, dynamic> data,
      {String context = 'highlight', String? documentId}) async {
    // if (kDebugMode) {
    //   final start = data['start'] as int?;
    //   final end = data['end'] as int?;
    //   final createdAt = data['created_at'] as int?;
    //   final updatedAt = data['updated_at'] as int?;
    //   debugPrint(
    //       'DEBUG: Validating $context highlight data - book=${data['book']}, chapter=${data['chapter']}, verse=${data['verse']}, start=$start, end=$end, color=${data['color']}, created_at=$createdAt, updated_at=$updatedAt');
    // }
    try {
      // Check required fields
      final book = data['book'] as String?;
      final chapter = data['chapter'] as int?;
      final verse = data['verse'] as int?;
      final color = data['color'] as int?;

      // Reject if required fields are missing or invalid
      final isValidBook = book != null && book.trim().isNotEmpty;
      final isValidChapter = chapter != null && chapter > 0;
      final isValidVerse = verse != null && verse > 0;
      final isValidColor = color != null && color >= 0;

      // if (kDebugMode) {
      //   debugPrint(
      //       'DEBUG: $context highlight validation results - book=$isValidBook, chapter=$isValidChapter, verse=$isValidVerse, color=$isValidColor');
      // }

      if (!isValidBook || !isValidChapter || !isValidVerse || !isValidColor) {
        return false;
      }

      // Validate document ID matches created_at timestamp (required for sync)
      if (documentId != null) {
        final expectedDocId = (data['created_at'] as int?)?.toString();
        if (expectedDocId == null || documentId != expectedDocId) {
          // if (kDebugMode) {
          //   debugPrint('DEBUG: $context document ID mismatch - expected: $expectedDocId, got: $documentId');
          // }
          return false;
        }
      }

      //if (kDebugMode) debugPrint('DEBUG: $context highlight data validation PASSED');
      return true;
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Exception during $context highlight validation',
        context: {'class': 'DataValidation', 'context': context},
      );
      return false;
    }
  }

  /// Validates note data for required fields and data integrity
  /// Returns true if valid, logs error and returns false if invalid
  static Future<bool> validateNoteData(Map<String, dynamic> data,
      {String context = 'note', String? documentId}) async {
    try {
      // Check required fields with type safety
      final book = data['book'];
      final chapter = data['chapter'];
      final verse = data['verse'];
      final noteText = data['note_text'];

      // Reject if required fields are missing or invalid
      final isValidBook = book != null && book.trim().isNotEmpty;
      final isValidChapter = chapter != null && chapter > 0;
      final isValidVerse = verse != null && verse > 0;
      final isValidNoteText = noteText is String && noteText.trim().isNotEmpty;

      if (!isValidBook ||
          !isValidChapter ||
          !isValidVerse ||
          !isValidNoteText) {
        return false;
      }

      // Validate document ID matches created_at timestamp (required for sync)
      if (documentId != null) {
        final expectedDocId = (data['created_at'] as int?)?.toString();
        if (expectedDocId == null || documentId != expectedDocId) {
          ErrorHandler.logError(
            'DEBUG: $context document ID mismatch - expected: $expectedDocId, got: $documentId',
            context: {
              'class': 'DataValidation',
              'context': context,
              'expectedDocId': expectedDocId,
              'documentId': documentId
            },
          );
          return false;
        }
      }

      //if (kDebugMode) debugPrint('DEBUG: $context note data validation PASSED');
      return true;
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Exception during $context note validation',
        context: {'class': 'DataValidation', 'context': context},
      );
      return false;
    }
  }

  /// Validates history data for required fields and data integrity
  /// Returns true if valid, logs error and returns false if invalid
  static Future<bool> validateHistoryData(Map<String, dynamic> data,
      {String context = 'history', String? documentId}) async {
    // if (kDebugMode) {
    //   debugPrint(
    //       'DEBUG: Validating $context history data - book=${data['book']}, chapter=${data['chapter']}, verse=${data['verse']}, timestamp=${data['timestamp']}');
    // }
    try {
      // Check required fields
      final book = data['book'] as String?;
      final chapter = data['chapter'] as int?;
      final verse =
          data['verse'] as int?; // Verse can be null for chapter history
      final timestamp = data['timestamp'] as int?;

      // Reject if required fields are missing or invalid
      final isValidBook = book != null && book.trim().isNotEmpty;
      final isValidChapter = chapter != null && chapter > 0;
      // Verse can be null for chapter-level history entries.
      final isValidVerse = verse == null || verse > 0;
      final isValidTimestamp = timestamp != null && timestamp > 0;

      // if (kDebugMode) {
      //   debugPrint('DEBUG: $context history validation results - book=$isValidBook, chapter=$isValidChapter, timestamp=$isValidTimestamp');
      // }

      if (!isValidBook ||
          !isValidChapter ||
          !isValidVerse ||
          !isValidTimestamp) {
        return false;
      }

      // Validate document ID matches timestamp (required for sync)
      if (documentId != null) {
        final expectedDocId = (data['timestamp'] as int?)?.toString();
        if (expectedDocId == null || documentId != expectedDocId) {
          ErrorHandler.logError(
            'DEBUG: $context document ID mismatch - expected: $expectedDocId, got: $documentId',
            context: {
              'class': 'DataValidation',
              'context': context,
              'expectedDocId': expectedDocId,
              'documentId': documentId
            },
          );
          return false;
        }
      }

      //if (kDebugMode) debugPrint('DEBUG: $context history data validation PASSED');
      return true;
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Exception during $context history validation',
        context: {'class': 'DataValidation', 'context': context},
      );
      return false;
    }
  }

  /// Validates search history data for required fields and data integrity
  /// Returns true if valid, logs error and returns false if invalid
  static Future<bool> validateSearchHistoryData(Map<String, dynamic> data,
      {String context = 'search_history'}) async {
    try {
      // Check required fields
      final query = data['query'] as String?;
      final timestamp = data['timestamp'] as int?;

      // Validate query
      final isValidQuery = query != null && query.trim().isNotEmpty;

      // Validate timestamp
      final isValidTimestamp = timestamp != null && timestamp > 0;

      // Validate boolean options (ensure they're actually bools)
      final useRegex = data['useRegex'];
      final useNearby = data['useNearby'];
      final useWholeWord = data['useWholeWord'];
      final useRedLetter = data['useRedLetter'];
      final caseSensitive = data['caseSensitive'];
      final isValidOptions = [
        useRegex,
        useNearby,
        useWholeWord,
        useRedLetter,
        caseSensitive
      ].every((opt) => opt is bool);

      // Validate book filter fields
      final bookFilterType = data['bookFilterType'] as String?;
      final customBookFilter = data['customBookFilter'] as String?;
      final isValidFilterType =
          bookFilterType != null && bookFilterType.trim().isNotEmpty;
      final isValidCustomFilter =
          customBookFilter is String; // Can be empty but must be string

      if (!isValidQuery ||
          !isValidTimestamp ||
          !isValidOptions ||
          !isValidFilterType ||
          !isValidCustomFilter) {
        return false;
      }

      return true;
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Exception during $context validation',
        context: {'class': 'DataValidation', 'context': context},
      );
      return false;
    }
  }

  /// Validates timestamp for corruption and reasonableness
  /// Returns validated timestamp if valid, null if invalid
  static Future<DateTime?> validateTimeStamp(DateTime timeStamp) async {
    final timeStampMs = timeStamp.millisecondsSinceEpoch;
    final isValidTimeStamp = timeStampMs > 0;

    try {
      // Check if timestamp can be converted to valid DateTime

      if (!isValidTimeStamp) {
        return null;
      }

      return timeStamp;
    } catch (e) {
      // Invalid timestamp that can't be converted
      ErrorHandler.logError(
        e,
        customMessage: 'Invalid timestamp rejected: $timeStamp',
        context: {
          'class': 'DataValidation',
          'method': 'validateTimeStamp',
          'timestamp': timeStamp.toIso8601String()
        },
      );
      return null;
    }
  }

  /// Validates database record structure for records returned from queries
  /// This ensures database integrity when reading data
  static Future<bool> validateDatabaseRecord(
      Map<String, dynamic> record, String dataType,
      {String context = 'database'}) async {
    switch (dataType) {
      case 'highlight':
        return await validateHighlightData(record,
            context: '$context $dataType');
      case 'note':
        return await validateNoteData(record, context: '$context $dataType');
      case 'history':
        return await validateHistoryData(record, context: '$context $dataType');
      case 'search_history':
        return await validateSearchHistoryData(record,
            context: '$context $dataType');
      default:
        ErrorHandler.logError(
          'DEBUG: Unknown data type for validation: "$dataType"',
          context: {
            'class': 'DataValidation',
            'method': 'validateDatabaseRecord',
            'dataType': dataType
          },
        );
        return false;
    }
  }

  /// Validates data before database insertion/updates
  /// This ensures we never write corrupt data to local databases
  static Future<bool> validateBeforeDatabaseWrite(
      Map<String, dynamic> data, String dataType,
      {String context = 'write'}) async {
    switch (dataType) {
      case 'highlight':
        return await validateHighlightData(data, context: '$context $dataType');
      case 'note':
        return await validateNoteData(data, context: '$context $dataType');
      case 'history':
        return await validateHistoryData(data, context: '$context $dataType');
      case 'search_history':
        return await validateSearchHistoryData(data,
            context: '$context $dataType');
      default:
        ErrorHandler.logError(
          'DEBUG: Unknown data type for $context validation: $dataType',
          context: {
            'class': 'DataValidation',
            'method': 'validateBeforeDatabaseWrite',
            'context': context,
            'dataType': dataType
          },
        );
        return false;
    }
  }

  /// Validates data before upload to remote sync service
  /// This ensures we never send corrupt data to Firestore
  static Future<bool> validateBeforeUpload(
      Map<String, dynamic> data, String dataType,
      {String context = 'upload'}) async {
    switch (dataType) {
      case 'highlight':
        return await validateHighlightData(data, context: '$context $dataType');
      case 'note':
        return await validateNoteData(data, context: '$context $dataType');
      case 'history':
        return await validateHistoryData(data, context: '$context $dataType');
      case 'search_history':
        return await validateSearchHistoryData(data,
            context: '$context $dataType');
      default:
        ErrorHandler.logError(
          'DEBUG: Unknown data type for $context validation: $dataType',
          context: {
            'class': 'DataValidation',
            'method': 'validateBeforeUpload',
            'context': context,
            'dataType': dataType
          },
        );
        return false;
    }
  }
}
