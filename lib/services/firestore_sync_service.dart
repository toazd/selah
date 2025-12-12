import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../database/highlights_database.dart';
import '../database/notes_database.dart';
import '../database/history_database.dart';
import '../database/search_database.dart';
import 'local_data_change_notifier.dart';
import '../utils/note_storage_format.dart';
import '../utils/error_handler.dart';
import '../utils/preferences_constants.dart';
import '../utils/internet_access_checker.dart';
import '../utils/data_validation.dart';

// Add streams for notifying UI of data changes
StreamController<void>? _highlightsChangedController;
StreamController<void>? _notesChangedController;
StreamController<void>? _historyChangedController;
StreamController<void>? _searchHistoryChangedController;

/// Global notifier for UI to listen to sync status changes
final ValueNotifier<SyncStatus> syncStatusNotifier = ValueNotifier(SyncStatus.offline);

// Prevent rapid initialize() calls
bool _isInitialized = false;

enum SyncStatus { offline, connecting, online, syncing, error }

class SyncOperation {
  final String id;
  final String type; // 'highlight', 'note', 'history'
  final String operation; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount; // Track number of retry attempts

  SyncOperation({
    required this.id,
    required this.type,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
  });

  SyncOperation copyWith({int? retryCount}) {
    return SyncOperation(
      id: id,
      type: type,
      operation: operation,
      data: data,
      timestamp: timestamp,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'operation': operation,
      'data': data,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retryCount': retryCount,
    };
  }

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    return SyncOperation(
      id: map['id'],
      type: map['type'],
      operation: map['operation'],
      data: Map<String, dynamic>.from(map['data']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      retryCount: map['retryCount'] ?? 0,
    );
  }
}

class FirestoreSyncService {
  /// Simple, fault-tolerant sync service for multi-device Bible study app.
  /// Uploads local changes immediately, downloads remote changes incrementally.
  /// No automatic deletion of remote data to prevent data loss (unless it is found to be corrupt)
  static final FirestoreSyncService _instance = FirestoreSyncService._internal();
  factory FirestoreSyncService() => _instance;
  FirestoreSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();

  SyncStatus _syncStatus = SyncStatus.offline;
  bool _isListening = false;

  // Last sync timestamps to track changes
  DateTime? _lastHighlightsSync;
  DateTime? _lastNotesSync;
  DateTime? _lastHistorySync;
  DateTime? _lastSearchHistorySync;

  // Flags for pending changes
  bool _highlightsNeedSync = false;
  bool _notesNeedSync = false;
  bool _historyNeedSync = false;
  bool _searchHistoryNeedSync = false;

  // Last sync timestamps (now persisted)
  DateTime? _lastHighlightsSyncSaved;
  DateTime? _lastNotesSyncSaved;
  DateTime? _lastHistorySyncSaved;
  DateTime? _lastSearchHistorySyncSaved;

  // Listener subscriptions
  StreamSubscription<QuerySnapshot>? _highlightsSubscription;
  StreamSubscription<QuerySnapshot>? _notesSubscription;
  StreamSubscription<QuerySnapshot>? _historySubscription;
  StreamSubscription<QuerySnapshot>? _searchHistorySubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Persistent queues for offline changes (persist across app restarts)
  final List<SyncOperation> _highlightsPendingQueue = [];
  final List<SyncOperation> _notesPendingQueue = [];
  final List<SyncOperation> _historyPendingQueue = [];
  final List<SyncOperation> _searchHistoryPendingQueue = [];

  // Preferences keys for persistent queues
  static const String _highlightsQueueKey = 'pendingHighlightsQueue';
  static const String _notesQueueKey = 'pendingNotesQueue';
  static const String _historyQueueKey = 'pendingHistoryQueue';
  static const String _searchHistoryQueueKey = 'pendingSearchHistoryQueue';

  // Retry queue for failed sync operations
  final List<SyncOperation> _retryQueue = [];
  Timer? _retryTimer;

  // Flag to control whether failed retries should be preserved during sign out
  bool preserveRetriesOnSignOut = false;

  // Get current user ID
  String? get _currentUserId => _auth.currentUser?.uid;

  // Helper method to get sync enabled status from individual preferences
  Future<bool> _getSyncEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true;
  }

  // Load persisted last sync timestamps
  Future<void> _loadLastSyncTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final highlightsTs = prefs.getInt('lastHighlightsSync');
    final notesTs = prefs.getInt('lastNotesSync');
    final historyTs = prefs.getInt('lastHistorySync');
    final searchHistoryTs = prefs.getInt('lastSearchHistorySync');

    if (highlightsTs != null) {
      _lastHighlightsSyncSaved =
          await DataValidation.validateTimeStamp(DateTime.fromMillisecondsSinceEpoch(highlightsTs));
    }
    if (notesTs != null) {
      _lastNotesSyncSaved = await DataValidation.validateTimeStamp(DateTime.fromMillisecondsSinceEpoch(notesTs));
    }
    if (historyTs != null) {
      _lastHistorySyncSaved = await DataValidation.validateTimeStamp(DateTime.fromMillisecondsSinceEpoch(historyTs));
    }
    if (searchHistoryTs != null) {
      _lastSearchHistorySyncSaved =
          await DataValidation.validateTimeStamp(DateTime.fromMillisecondsSinceEpoch(searchHistoryTs));
    }

    // Initialize current session timestamps from persisted values
    _lastHighlightsSync = _lastHighlightsSyncSaved;
    _lastNotesSync = _lastNotesSyncSaved;
    _lastHistorySync = _lastHistorySyncSaved;
    _lastSearchHistorySync = _lastSearchHistorySyncSaved;
  }

  // Save last sync timestamps to preferences
  Future<void> _saveLastSyncTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    if (_lastHighlightsSync != null) {
      await prefs.setInt('lastHighlightsSync', _lastHighlightsSync!.millisecondsSinceEpoch);
      _lastHighlightsSyncSaved = _lastHighlightsSync;
    }
    if (_lastNotesSync != null) {
      await prefs.setInt('lastNotesSync', _lastNotesSync!.millisecondsSinceEpoch);
      _lastNotesSyncSaved = _lastNotesSync;
    }
    if (_lastHistorySync != null) {
      await prefs.setInt('lastHistorySync', _lastHistorySync!.millisecondsSinceEpoch);
      _lastHistorySyncSaved = _lastHistorySync;
    }
    if (_lastSearchHistorySync != null) {
      await prefs.setInt('lastSearchHistorySync', _lastSearchHistorySync!.millisecondsSinceEpoch);
      _lastSearchHistorySyncSaved = _lastSearchHistorySync;
    }
  }

  // Sync status getter
  bool get isOnline => _syncStatus == SyncStatus.online;

  // Public streams for UI to listen to - auto-recreate controllers if closed
  static Stream<void> get highlightsChangedStream {
    if (_highlightsChangedController == null || _highlightsChangedController!.isClosed) {
      _highlightsChangedController = StreamController<void>.broadcast();
    }
    return _highlightsChangedController!.stream;
  }

  static Stream<void> get notesChangedStream {
    if (_notesChangedController == null || _notesChangedController!.isClosed) {
      _notesChangedController = StreamController<void>.broadcast();
    }
    return _notesChangedController!.stream;
  }

  static Stream<void> get historyChangedStream {
    if (_historyChangedController == null || _historyChangedController!.isClosed) {
      _historyChangedController = StreamController<void>.broadcast();
    }
    return _historyChangedController!.stream;
  }

  static Stream<void> get searchHistoryChangedStream {
    if (_searchHistoryChangedController == null || _searchHistoryChangedController!.isClosed) {
      _searchHistoryChangedController = StreamController<void>.broadcast();
    }
    return _searchHistoryChangedController!.stream;
  }

  // Helper method to safely close a stream controller
  void _closeStreamController(StreamController<void>? controller) {
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  // Cleanup all stream controllers before recreating them
  void _cleanupStreamControllers() {
    _closeStreamController(_highlightsChangedController);
    _closeStreamController(_notesChangedController);
    _closeStreamController(_historyChangedController);
    _closeStreamController(_searchHistoryChangedController);
    _highlightsChangedController = null;
    _notesChangedController = null;
    _historyChangedController = null;
    _searchHistoryChangedController = null;
  }

  // Load persisted change queues from SharedPreferences
  Future<void> _loadPersistedQueues() async {
    final prefs = await SharedPreferences.getInstance();

    // Load and deserialize each queue
    final highlightsJson = prefs.getString(_highlightsQueueKey);
    if (highlightsJson != null) {
      try {
        final decoded = jsonDecode(highlightsJson) as List<dynamic>;
        _highlightsPendingQueue.addAll(decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        // Invalid data, clear it
        await prefs.remove(_highlightsQueueKey);
      }
    }

    final notesJson = prefs.getString(_notesQueueKey);
    if (notesJson != null) {
      try {
        final decoded = jsonDecode(notesJson) as List<dynamic>;
        _notesPendingQueue.addAll(decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        await prefs.remove(_notesQueueKey);
      }
    }

    final historyJson = prefs.getString(_historyQueueKey);
    if (historyJson != null) {
      try {
        final decoded = jsonDecode(historyJson) as List<dynamic>;
        _historyPendingQueue.addAll(decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        await prefs.remove(_historyQueueKey);
      }
    }

    final searchHistoryJson = prefs.getString(_searchHistoryQueueKey);
    if (searchHistoryJson != null) {
      try {
        final decoded = jsonDecode(searchHistoryJson) as List<dynamic>;
        _searchHistoryPendingQueue.addAll(decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        // Invalid data, clear it
        await prefs.remove(_searchHistoryQueueKey);
      }
    }
  }

  // Persist queues to SharedPreferences
  Future<void> _persistQueues() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_highlightsQueueKey, jsonEncode(_highlightsPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(_notesQueueKey, jsonEncode(_notesPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(_historyQueueKey, jsonEncode(_historyPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(
        _searchHistoryQueueKey, jsonEncode(_searchHistoryPendingQueue.map((op) => op.toMap()).toList()));
  }

  // Add operation to persistent queue by type (with deduplication)
  void _queueOperation(SyncOperation operation) {
    switch (operation.type) {
      case 'highlight':
        if (!_mergeOrQueueHighlightOperation(operation, _highlightsPendingQueue)) {
          _highlightsPendingQueue.add(operation);
        }
        break;
      case 'note':
        if (!_mergeOrQueueNoteOperation(operation, _notesPendingQueue)) {
          _notesPendingQueue.add(operation);
        }
        break;
      case 'history':
        if (!_isOperationAlreadyQueued(operation, _historyPendingQueue)) {
          _historyPendingQueue.add(operation);
        }
        break;
      case 'search_history':
        if (!_isSearchHistoryOperationQueued(operation, _searchHistoryPendingQueue)) {
          _searchHistoryPendingQueue.add(operation);
        }
        break;
    }
    _persistQueues();
  }

  // Check if operation is already queued to prevent duplicates
  bool _isOperationAlreadyQueued(SyncOperation operation, List<SyncOperation> queue) {
    return queue.any((queued) =>
        queued.id == operation.id && queued.type == operation.type && queued.operation == operation.operation);
  }

  // Check for existing highlight operations and merge if newer
  bool _mergeOrQueueHighlightOperation(SyncOperation operation, List<SyncOperation> queue) {
    if (operation.operation != 'create' && operation.operation != 'update') {
      return false; // Only merge create/update operations
    }

    final book = operation.data['book'] as String;
    final chapter = operation.data['chapter'] as int;
    final verse = operation.data['verse'] as int;
    final start = operation.data['start'] as int;
    final end = operation.data['end'] as int;
    final updatedAt = operation.data['updated_at'] as int? ?? operation.data['created_at'] as int;

    // Find existing operation to merge
    SyncOperation? existingOp;
    for (final op in queue) {
      if (op.type == 'highlight' &&
          op.data['book'] == book &&
          op.data['chapter'] == chapter &&
          op.data['verse'] == verse &&
          op.data['start'] == start &&
          op.data['end'] == end) {
        existingOp = op;
        break;
      }
    }

    if (existingOp != null) {
      // Found matching highlight - compare timestamps and keep newer
      final existingUpdatedAt = existingOp.data['updated_at'] as int? ?? existingOp.data['created_at'] as int;

      if (updatedAt > existingUpdatedAt) {
        // New operation is newer - remove old and will add new
        queue.remove(existingOp);
        return false; // Allow adding the new operation
      }
      // Existing is newer or same - keep existing
      return true; // Merged - don't add new operation
    }

    // No match found - allow adding new operation
    return false;
  }

  // Check for existing note operations and merge if newer
  bool _mergeOrQueueNoteOperation(SyncOperation operation, List<SyncOperation> queue) {
    if (operation.operation != 'create' && operation.operation != 'update') {
      return false; // Only merge create/update operations
    }

    final book = operation.data['book'] as String;
    final chapter = operation.data['chapter'] as int;
    final verse = operation.data['verse'] as int;
    final updatedAt = operation.data['updated_at'] as int? ?? operation.data['created_at'] as int;

    // Find existing operation to merge
    SyncOperation? existingOp;
    for (final op in queue) {
      if (op.type == 'note' && op.data['book'] == book && op.data['chapter'] == chapter && op.data['verse'] == verse) {
        existingOp = op;
        break;
      }
    }

    if (existingOp != null) {
      // Found matching note - compare timestamps and keep newer
      final existingUpdatedAt = existingOp.data['updated_at'] as int? ?? existingOp.data['created_at'] as int;

      if (updatedAt > existingUpdatedAt) {
        // New operation is newer - remove old and will add new
        queue.remove(existingOp);
        return false; // Allow adding the new operation
      }
      // Existing is newer or same - keep existing
      return true; // Merged - don't add new operation
    }

    // No match found - allow adding new operation
    return false;
  }

  // Check if search history operation is already queued (exact match required)
  bool _isSearchHistoryOperationQueued(SyncOperation operation, List<SyncOperation> queue) {
    return queue.any((queued) =>
        queued.type == operation.type &&
        queued.data['query'] == operation.data['query'] &&
        queued.data['useRegex'] == operation.data['useRegex'] &&
        queued.data['useNearby'] == operation.data['useNearby'] &&
        queued.data['useWholeWord'] == operation.data['useWholeWord'] &&
        queued.data['useRedLetter'] == operation.data['useRedLetter'] &&
        queued.data['caseSensitive'] == operation.data['caseSensitive'] &&
        queued.data['bookFilterType'] == operation.data['bookFilterType'] &&
        queued.data['customBookFilter'] == operation.data['customBookFilter'] &&
        queued.data['timestamp'] == operation.data['timestamp']);
  }

  // Get current local data for an operation type - returns null if item no longer exists locally
  Future<Map<String, dynamic>?> _getCurrentLocalData(String type, Map<String, dynamic> operationData) async {
    switch (type) {
      case 'highlight':
        // Highlights are identified by created_at timestamp
        final createdAt = operationData['created_at'] as int;
        final localHighlights = await HighlightsDatabase.getHighlights();
        return localHighlights.where((h) => h['created_at'] == createdAt).firstOrNull;

      case 'note':
        // Notes are identified by created_at timestamp
        final createdAt = operationData['created_at'] as int;
        final localNotes = await NotesDatabase.getNotes();
        return localNotes.where((n) => n['created_at'] == createdAt).firstOrNull;

      case 'history':
        // History items are identified by timestamp and book/chapter/verse
        final timestamp = operationData['timestamp'] as int;
        final book = operationData['book'] as String;
        final chapter = operationData['chapter'] as int;
        final verse = operationData['verse'] as int?;
        final localHistory = await HistoryDatabase.getHistory();
        return localHistory
            .where((h) =>
                h['timestamp'] == timestamp && h['book'] == book && h['chapter'] == chapter && h['verse'] == verse)
            .firstOrNull;

      case 'search_history':
        // Search history items are identified by exact match of all fields
        final timestamp = operationData['timestamp'] as int;
        final query = operationData['query'] as String;
        final useRegex = operationData['useRegex'] as bool?;
        final useNearby = operationData['useNearby'] as bool?;
        final useWholeWord = operationData['useWholeWord'] as bool?;
        final useRedLetter = operationData['useRedLetter'] as bool?;
        final caseSensitive = operationData['caseSensitive'] as bool?;
        final bookFilterType = operationData['bookFilterType'] as String?;
        final customBookFilter = operationData['customBookFilter'] as String?;

        final localSearchHistory = await SearchDatabase.getSearchHistory();
        return localSearchHistory
            .where((s) =>
                s['timestamp'] == timestamp &&
                s['query'] == query &&
                s['useRegex'] == useRegex &&
                s['useNearby'] == useNearby &&
                s['useWholeWord'] == useWholeWord &&
                s['useRedLetter'] == useRedLetter &&
                s['caseSensitive'] == caseSensitive &&
                s['bookFilterType'] == bookFilterType &&
                s['customBookFilter'] == customBookFilter)
            .firstOrNull;

      default:
        return null;
    }
  }

  // Queue a specific operation persistently (replaces old queuing methods)
  Future<void> _queuePersistentOperation(
      String operationKey, String type, String operation, Map<String, dynamic> data) async {
    // Only queue operations when user is logged in but offline (can't sync immediately)
    if (_currentUserId == null) {
      return;
    }

    // Check if operation already exists to avoid duplicates
    final List<SyncOperation> existingOps;
    final DateTime operationTimestamp;
    switch (type) {
      case 'highlight':
        existingOps = _highlightsPendingQueue;
        operationTimestamp = DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int);
        break;
      case 'note':
        existingOps = _notesPendingQueue;
        operationTimestamp = DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int);
        break;
      case 'history':
        existingOps = _historyPendingQueue;
        operationTimestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
        break;
      case 'search_history':
        existingOps = _searchHistoryPendingQueue;
        operationTimestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
        break;
      default:
        operationTimestamp = DateTime.now();
        throw ArgumentError('Unknown operation type: $type');
    }

    // Don't add duplicate operations
    final isDuplicate = existingOps.any((op) => op.id == operationKey && op.operation == operation);
    if (isDuplicate) {
      return;
    }

    // Create and queue the operation
    final syncOperation = SyncOperation(
      id: operationKey,
      type: type,
      operation: operation,
      data: data,
      timestamp: operationTimestamp,
    );

    _queueOperation(syncOperation);
  }

  // Process persistent queues when coming online
  Future<void> _processPendingQueues() async {
    if (!isOnline || _currentUserId == null || !await InternetAccessChecker.hasInternetAccess()) {
      return;
    }

    // Process each queue
    await _processPendingQueue(_highlightsPendingQueue);
    await _processPendingQueue(_notesPendingQueue);
    await _processPendingQueue(_historyPendingQueue);
    await _processPendingQueue(_searchHistoryPendingQueue);

    // Persist empty queues
    await _persistQueues();
  }

  // Process a specific pending queue
  Future<void> _processPendingQueue(List<SyncOperation> queue) async {
    if (queue.isEmpty) return;

    final operationsToProcess = List<SyncOperation>.from(queue);
    queue.clear();

    for (final operation in operationsToProcess) {
      // Determine what data to upload - use current local data for create/update if exists
      Map<String, dynamic>? uploadData = operation.data;

      if (operation.operation == 'create' || operation.operation == 'update') {
        final currentLocal = await _getCurrentLocalData(operation.type, operation.data);
        if (currentLocal == null) {
          // Item no longer exists locally - skip processing
          continue;
        }
        uploadData = currentLocal;
      }

      try {
        switch (operation.type) {
          case 'highlight':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadHighlight(uploadData);
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteHighlight(uploadData['created_at'] as int);
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            }
            break;
          case 'note':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadNote(uploadData);
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteNote(uploadData['created_at'] as int);
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            }
            break;
          case 'history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadHistoryItem(uploadData);
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteHistoryItem(uploadData['timestamp'].toString());
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            }
            break;
          case 'search_history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadSearchHistoryItem(uploadData);
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteSearchHistoryItem(uploadData['timestamp'].toString());
              } catch (e) {
                if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
              }
            }
            break;
        }
      } catch (e) {
        // Re-queue failed operations
        try {
          queue.add(operation);
        } catch (e) {
          if (kDebugMode) debugPrint('_processPendingQueue exception: $e');
        }
      }
    }
  }

  // Initialize the sync service
  Future<void> initialize({bool isLoginResync = false}) async {
    if (_isInitialized) return;
    if (_currentUserId == null) {
      return;
    }

    // Cancel existing first
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();
    _retryTimer?.cancel();

    // Check actual connectivity status and set appropriate initial state
    try {
      final hasConnection = await InternetAccessChecker.hasInternetAccess();
      if (hasConnection && _currentUserId != null) {
        _syncStatus = SyncStatus.online; // Connected and have user, assume online
      } else {
        _syncStatus = SyncStatus.offline; // No connection or no user
      }
    } catch (_) {
      _syncStatus = SyncStatus.offline; // On error, assume offline
    }

    syncStatusNotifier.value = _syncStatus;
    _isListening = false;
    _highlightsNeedSync = false;
    _notesNeedSync = false;
    _historyNeedSync = false;
    _searchHistoryNeedSync = false;

    // Initialize stream controllers to ensure they exist for immediate use
    _highlightsChangedController ??= StreamController<void>.broadcast();
    _notesChangedController ??= StreamController<void>.broadcast();
    _historyChangedController ??= StreamController<void>.broadcast();
    _searchHistoryChangedController ??= StreamController<void>.broadcast();

    // Load persisted last sync timestamps
    await _loadLastSyncTimestamps();

    // Load persisted change queues
    await _loadPersistedQueues();

    // Setup listeners and connection monitoring
    await _checkConnectionAndSetup();

    // Process any queued operations from offline changes
    if (isOnline) {
      await _processPendingQueues();
    }

    // Perform full sync on login (download all remote + upload local changes)
    // if we are not resuming (switching from paused to resumed state on mobile)
    if (isLoginResync && _currentUserId != null && isOnline) {
      try {
        // Try to sync all
        syncAll();
      } catch (e) {
        // If that fails sync what we can
        try {
          await syncHighlights();
        } catch (e) {
          if (kDebugMode) debugPrint('initialize syncHighlights exception: $e');
        }
        try {
          await syncNotes();
        } catch (e) {
          if (kDebugMode) debugPrint('initialize syncNotes exception: $e');
        }
        try {
          await syncHistory();
        } catch (e) {
          if (kDebugMode) debugPrint('initialize syncHistory exception: $e');
        }
        try {
          await syncSearchHistory();
        } catch (e) {
          if (kDebugMode) debugPrint('initialize syncSearchHistory exception: $e');
        }
      }
    } else if (!isLoginResync && _currentUserId != null && isOnline) {
      // App resume - do incremental sync to catch changes while backgrounded
      try {
        await _syncRecentChangesOnly();
      } catch (e) {
        // Continue with init even if sync fails
        if (kDebugMode) debugPrint('initialize _syncRecentChangesOnly exception: $e');
      }
    }

    // Start connection monitoring
    try {
      _startConnectionMonitoring();
    } catch (e) {
      if (kDebugMode) debugPrint('initialize _startConnectionMonitoring exception: $e');
    }

    // Cache the username after initialization
    if (_currentUserId != null) {
      await cacheUsername();
    }

    _isInitialized = true;
  }

  // Check connection and setup listeners
  Future<void> _checkConnectionAndSetup() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      //final hasConnection = connectivityResult != ConnectivityResult.none;
      final hasConnection = !connectivityResult.contains(ConnectivityResult.none);

      if (hasConnection) {
        await _testFirestoreConnection();
        await _setupRealtimeListeners();
        _syncStatus = SyncStatus.online;
        syncStatusNotifier.value = _syncStatus;
        await _processPendingQueues();
      } else {
        _syncStatus = SyncStatus.offline;
        syncStatusNotifier.value = _syncStatus;
      }
    } catch (e) {
      _syncStatus = SyncStatus.error;
    }
  }

  // Test Firestore connection
  Future<void> _testFirestoreConnection() async {
    try {
      if (_currentUserId == null) return;

      // Try to access user's document
      final testRef = _firestore.collection('users').doc(_currentUserId);
      await testRef.get();
    } catch (e) {
      rethrow;
    }
  }

  // Setup realtime listeners for user's data - only when all conditions are met
  Future<void> _setupRealtimeListeners() async {
    if (_currentUserId == null || _isListening) return;

    // Cancel existing listeners before setting up new ones
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

    _isListening = true;

    try {
      // Only setup listeners for enabled sync types
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');
      final notesEnabled = await _getSyncEnabled('syncNotes');
      final historyEnabled = await _getSyncEnabled('syncHistory');
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      // Listen for highlights changes if enabled
      if (highlightsEnabled) {
        _highlightsSubscription =
            _firestore.collection('users').doc(_currentUserId).collection('highlights').snapshots().listen((snapshot) {
          _onHighlightsChanged(snapshot);
        });
      }

      // Listen for notes changes if enabled
      if (notesEnabled) {
        _notesSubscription =
            _firestore.collection('users').doc(_currentUserId).collection('notes').snapshots().listen((snapshot) {
          _onNotesChanged(snapshot);
        });
      }

      // Listen for history changes if enabled
      if (historyEnabled) {
        _historySubscription =
            _firestore.collection('users').doc(_currentUserId).collection('history').snapshots().listen((snapshot) {
          _onHistoryChanged(snapshot);
        });
      }

      // Listen for search history changes if enabled
      if (searchHistoryEnabled) {
        _searchHistorySubscription = _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('search_history')
            .snapshots()
            .listen((snapshot) {
          _onSearchHistoryChanged(snapshot);
        });
      }
    } catch (e) {
      _isListening = false;
    }
  }

  /// Update listener for a specific sync category without affecting others
  Future<void> updateListenerForCategory(String category, bool shouldEnable) async {
    if (_currentUserId == null || !isOnline || _isListening == false) return;

    switch (category) {
      case 'highlights':
        if (shouldEnable && _highlightsSubscription == null) {
          // Setup highlights listener
          _highlightsSubscription = _firestore
              .collection('users')
              .doc(_currentUserId)
              .collection('highlights')
              .snapshots()
              .listen((snapshot) {
            _onHighlightsChanged(snapshot);
          });
        } else if (!shouldEnable && _highlightsSubscription != null) {
          // Cancel highlights listener
          _highlightsSubscription?.cancel();
          _highlightsSubscription = null;
        }
        break;

      case 'notes':
        if (shouldEnable && _notesSubscription == null) {
          // Setup notes listener
          _notesSubscription =
              _firestore.collection('users').doc(_currentUserId).collection('notes').snapshots().listen((snapshot) {
            _onNotesChanged(snapshot);
          });
        } else if (!shouldEnable && _notesSubscription != null) {
          // Cancel notes listener
          _notesSubscription?.cancel();
          _notesSubscription = null;
        }
        break;

      case 'history':
        if (shouldEnable && _historySubscription == null) {
          // Setup history listener
          _historySubscription =
              _firestore.collection('users').doc(_currentUserId).collection('history').snapshots().listen((snapshot) {
            _onHistoryChanged(snapshot);
          });
        } else if (!shouldEnable && _historySubscription != null) {
          // Cancel history listener
          _historySubscription?.cancel();
          _historySubscription = null;
        }
        break;

      case 'search_history':
        if (shouldEnable && _searchHistorySubscription == null) {
          // Setup search history listener
          _searchHistorySubscription = _firestore
              .collection('users')
              .doc(_currentUserId)
              .collection('search_history')
              .snapshots()
              .listen((snapshot) {
            _onSearchHistoryChanged(snapshot);
          });
        } else if (!shouldEnable && _searchHistorySubscription != null) {
          // Cancel search history listener
          _searchHistorySubscription?.cancel();
          _searchHistorySubscription = null;
        }
        break;
      default:
    }
  }

  // Handle highlights changes from Firestore
  void _onHighlightsChanged(QuerySnapshot snapshot) async {
    try {
      // Check if highlights sync is enabled
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');

      if (!highlightsEnabled) {
        return;
      }

      // Only process if there are actual changes
      if (snapshot.docChanges.isEmpty) {
        return;
      }

      final added = snapshot.docChanges.where((change) => change.type == DocumentChangeType.added).length;
      final modified = snapshot.docChanges.where((change) => change.type == DocumentChangeType.modified).length;
      final removed = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).length;

      // Process existing documents (adds/modifies)
      if (added > 0 || modified > 0) {
        final changedDocs =
            snapshot.docChanges.where((change) => change.doc.exists).map((change) => change.doc).toList();
        await _downloadHighlights(changedDocs);
      }

      // Process removed documents - delete local highlights
      if (removed > 0) {
        final removedDocs = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).toList();

        // Collect items to delete outside transaction to avoid deadlocks
        final db = await HighlightsDatabase.getDatabase();

        // Get all local highlights once outside transaction
        final localHighlights = await HighlightsDatabase.getHighlights();
        final highlightsToDelete = <Map<String, dynamic>>[];

        for (final change in removedDocs) {
          final data = change.doc.data() as Map<String, dynamic>;

          // Validate deleted data
          if (!await DataValidation.validateHighlightData(data,
              context: 'processing deleted highlight', documentId: change.doc.id)) {
            continue;
          }

          // Find local match by content
          final candidates = localHighlights.where((h) =>
              h['book'] == data['book'] &&
              h['chapter'] == data['chapter'] &&
              h['verse'] == data['verse'] &&
              h['start'] == data['start'] &&
              h['end'] == data['end'] &&
              h['color'] == data['color']);

          final localHighlight = candidates.firstOrNull;
          if (localHighlight != null) {
            highlightsToDelete.add(localHighlight);
          }
        }

        bool hasLocalChanges = false;
        int deletionsProcessed = 0;

        // Run deletes in transaction only
        await db.transaction((txn) async {
          for (final highlight in highlightsToDelete) {
            await txn.delete('user_highlights', where: 'id = ?', whereArgs: [highlight['id']]);
            deletionsProcessed++;
          }
        }); // Transaction commits here automatically

        if (deletionsProcessed > 0) {
          hasLocalChanges = true;
        }

        if (hasLocalChanges && deletionsProcessed > 0) {
          // Now safe to notify - deletes are guaranteed committed
          LocalDataChangeNotifier.notifyHighlightsChanged();
        }
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Handle notes changes from Firestore
  void _onNotesChanged(QuerySnapshot snapshot) async {
    try {
      // Check if notes sync is enabled
      final notesEnabled = await _getSyncEnabled('syncNotes');

      if (!notesEnabled) {
        return;
      }

      // Only process if there are actual changes
      if (snapshot.docChanges.isEmpty) {
        return;
      }

      final added = snapshot.docChanges.where((change) => change.type == DocumentChangeType.added).length;
      final modified = snapshot.docChanges.where((change) => change.type == DocumentChangeType.modified).length;
      final removed = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).length;

      // Process existing documents (adds/modifies)
      if (added > 0 || modified > 0) {
        final changedDocs =
            snapshot.docChanges.where((change) => change.doc.exists).map((change) => change.doc).toList();
        await _downloadNotes(changedDocs);
      }

      // Process removed documents - delete local notes
      if (removed > 0) {
        final removedDocs = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).toList();

        // Collect items to delete outside transaction to avoid deadlocks
        final db = await NotesDatabase.getDatabase();

        // Get notes to delete outside transaction - notes may have multiple items per verse
        final notesToDelete = <Map<String, dynamic>>[];

        for (final change in removedDocs) {
          final data = change.doc.data() as Map<String, dynamic>;

          // Validate deleted data
          final isValid = await DataValidation.validateNoteData(data,
              context: 'processing deleted note', documentId: change.doc.id);

          if (!isValid) {
            continue;
          }

          // Find local match by verse location (notes may have multiple per verse)
          final book = data['book'] as String;
          final chapter = data['chapter'] as int;
          final verse = data['verse'] as int;

          final localNote = await NotesDatabase.getNoteForVerse(book, chapter, verse);

          if (localNote != null) {
            notesToDelete.add(localNote);
          }
        }

        bool hasLocalChanges = false;
        int deletionsProcessed = 0;

        // Run deletes in transaction only
        await db.transaction((txn) async {
          for (final note in notesToDelete) {
            await txn.delete('user_notes', where: 'id = ?', whereArgs: [note['id']]);
            deletionsProcessed++;
          }
        }); // Transaction commits here automatically

        if (deletionsProcessed > 0) {
          hasLocalChanges = true;
        }

        if (hasLocalChanges && deletionsProcessed > 0) {
          // Now safe to notify - deletes are guaranteed committed

          LocalDataChangeNotifier.notifyNotesChanged();
        }
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Handle history changes from Firestore
  void _onHistoryChanged(QuerySnapshot snapshot) async {
    try {
      // Check if history sync is enabled
      final historyEnabled = await _getSyncEnabled('syncHistory');

      if (!historyEnabled) {
        return;
      }

      // Only process if there are actual changes
      if (snapshot.docChanges.isEmpty) {
        return;
      }

      final added = snapshot.docChanges.where((change) => change.type == DocumentChangeType.added).length;
      final modified = snapshot.docChanges.where((change) => change.type == DocumentChangeType.modified).length;
      final removed = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).length;

      // Process existing documents (adds/modifies)
      if (added > 0 || modified > 0) {
        final changedDocs =
            snapshot.docChanges.where((change) => change.doc.exists).map((change) => change.doc).toList();
        await _downloadHistory(changedDocs);
      }

      // Process removed documents - delete local history items
      if (removed > 0) {
        final removedDocs = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).toList();
        bool hasLocalChanges = false;
        int deletionsProcessed = 0;

        for (final change in removedDocs) {
          final docId = change.doc.id;
          final remoteTimestamp = int.tryParse(docId) ?? 0;

          if (remoteTimestamp == 0) {
            continue;
          }

          // Find local match by timestamp (since doc ID is timestamp)
          final localHistory = await HistoryDatabase.getHistory();
          final candidates = localHistory.where((h) => h['timestamp'] == remoteTimestamp);

          final localItem = candidates.firstOrNull;

          if (localItem != null) {
            // Delete local history item
            await HistoryDatabase.deleteHistoryItem(localItem['id'] as int);
            hasLocalChanges = true;
            deletionsProcessed++;
          } else {}
        }

        if (hasLocalChanges && deletionsProcessed > 0) {
          // Notify UI of deletions
          LocalDataChangeNotifier.notifyHistoryChanged();
        } else {}
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Handle search history changes from Firestore
  void _onSearchHistoryChanged(QuerySnapshot snapshot) async {
    try {
      // Check if search history sync is enabled
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      if (!searchHistoryEnabled) {
        return;
      }

      // Only process if there are actual changes
      if (snapshot.docChanges.isEmpty) {
        return;
      }

      final added = snapshot.docChanges.where((change) => change.type == DocumentChangeType.added).length;
      final modified = snapshot.docChanges.where((change) => change.type == DocumentChangeType.modified).length;
      final removed = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).length;

      // Process existing documents (adds/modifies)
      if (added > 0 || modified > 0) {
        final changedDocs =
            snapshot.docChanges.where((change) => change.doc.exists).map((change) => change.doc).toList();
        await _downloadSearchHistory(changedDocs);
      }

      // Process removed documents - delete local search history items
      if (removed > 0) {
        final removedDocs = snapshot.docChanges.where((change) => change.type == DocumentChangeType.removed).toList();
        bool hasLocalChanges = false;
        int deletionsProcessed = 0;

        for (final change in removedDocs) {
          final docId = change.doc.id;
          final remoteTimestamp = int.tryParse(docId) ?? 0;

          if (remoteTimestamp == 0) {
            continue;
          }

          // Find local match by timestamp (since doc ID is timestamp)
          final localSearchHistory = await SearchDatabase.getSearchHistory();
          final candidates = localSearchHistory.where((h) => h['timestamp'] == remoteTimestamp);

          final localItem = candidates.firstOrNull;

          if (localItem != null) {
            // Delete local search history item
            await SearchDatabase.deleteSearchHistoryItem(localItem['id'] as int, skipSync: true);
            hasLocalChanges = true;
            deletionsProcessed++;
          } else {}
        }

        if (hasLocalChanges && deletionsProcessed > 0) {
          // Notify UI of deletions
          LocalDataChangeNotifier.notifySearchHistoryChanged();
        } else {}
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Sync highlights to Firestore
  Future<void> syncHighlights() async {
    // Check if highlights sync is enabled
    final highlightsEnabled = await _getSyncEnabled('syncHighlights');

    if (!highlightsEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    // Get the baseline time for filtering (highlights added after this will be synced next time)
    final baselineTime = _lastHighlightsSync ?? DateTime.fromMillisecondsSinceEpoch(0);

    // Get local highlights - all for sync logic
    final localHighlights = await HighlightsDatabase.getHighlights();

    // Filter for recent changes if not forced
    final highlightsToSync = localHighlights
        .where((h) => (h['updated_at'] ?? h['created_at'] ?? 0) > baselineTime.millisecondsSinceEpoch)
        .toList();

    // Only skip sync if there are no changes to sync
    if (highlightsToSync.isEmpty && !_highlightsNeedSync) {
      // No changes, skip sync

      return;
    }

    if (highlightsToSync.isNotEmpty) {
      // Get remote highlights for comparison
      final remoteHighlightsSnapshot =
          await _firestore.collection('users').doc(_currentUserId).collection('highlights').get();

      final remoteHighlights = remoteHighlightsSnapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();

      // Sync logic: collect highlights that need uploading, then use adaptive upload (single vs batch)
      final highlightsToUpload = <Map<String, dynamic>>[];

      for (final highlight in highlightsToSync) {
        final highlightId = highlight['id'].toString();
        final remoteDoc = remoteHighlights.where((h) => h['id'] == highlightId).firstOrNull;

        if (remoteDoc == null) {
          // New highlight - needs upload
          highlightsToUpload.add(highlight);
        } else {
          // Check if local is newer
          final localTime = highlight['updated_at'] ?? highlight['created_at'] ?? 0;
          final remoteTime = remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

          if (localTime > remoteTime) {
            highlightsToUpload.add(highlight);
          }
        }
      }

      // Adaptive upload: single vs batch based on workload
      if (highlightsToSync.isNotEmpty) {
        try {
          if (highlightsToSync.length == 1) {
            // Single highlight - use fast individual upload
            await _uploadHighlight(highlightsToSync.first);
          } else {
            // Multiple highlights - use batch upload
            await _batchUploadHighlights(highlightsToSync);
          }

          _lastHighlightsSync = DateTime.now();
          _highlightsNeedSync = false;
        } catch (e) {
          // If batch upload fails, queue each operation individually for retry
          for (final highlight in highlightsToSync) {
            _enqueueFailedOperation(SyncOperation(
              id: highlight['created_at'].toString(),
              type: 'highlight',
              operation: 'create',
              data: highlight,
              timestamp: DateTime.fromMillisecondsSinceEpoch(highlight['created_at'] as int),
            ));
          }
        }
      }
    }

    // Download remote changes newer than last sync for bidirectional sync
    final lastSyncMs = _lastHighlightsSyncSaved?.millisecondsSinceEpoch ?? 0;
    final query = _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('highlights')
        .where('updated_at', isGreaterThan: lastSyncMs);
    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) {
      await _downloadHighlights(snapshot.docs);
    }

    // Always update the sync timestamp after sync operations (both upload and download)
    _lastHighlightsSync = DateTime.now();

    // Save timestamps to preferences
    await _saveLastSyncTimestamps();
  }

  // Download highlights from Firestore to local database
  Future<void> _downloadHighlights(List<DocumentSnapshot> docs) async {
    await _downloadHighlightsFromData({for (final doc in docs) doc.id: doc.data() as Map<String, dynamic>});
  }

  // Download highlights from raw data (used for missed downloads retry)
  Future<void> _downloadHighlightsFromData(Map<String, Map<String, dynamic>> docsData) async {
    try {
      bool hasChanges = false;
      int processedCount = 0;

      // Get local highlights - match by created_at timestamp only
      final localHighlights = await HighlightsDatabase.getHighlights();

      for (final MapEntry<String, Map<String, dynamic>> entry in docsData.entries) {
        final Map<String, dynamic> data = entry.value;

        // Validate data before processing
        if (!await DataValidation.validateHighlightData(data, context: 'download highlight', documentId: entry.key)) {
          // Delete corrupt remote document

          final docId = int.tryParse(data['created_at']?.toString() ?? '') ?? 0;
          if (docId != 0) {
            await deleteRemoteHighlight(docId);
          }

          continue; // Skip processing this document
        }

        final remoteTime = data['updated_at'] as int;
        final remoteCreatedAt = data['created_at'] as int;

        // Match highlights by created_at timestamp
        final localHighlight = localHighlights.where((h) => h['created_at'] == remoteCreatedAt).firstOrNull;
        final localTime = (localHighlight?['updated_at'] ?? localHighlight?['created_at'] ?? 0) as int;

        // Only update if remote is newer or new
        if (localHighlight == null || remoteTime > localTime) {
          final highlightData = Map<String, dynamic>.from({
            'book': data['book'] as String,
            'chapter': data['chapter'] as int,
            'verse': data['verse'] as int,
            'start': data['start'] as int,
            'end': data['end'] as int,
            'color': data['color'] as int,
            'created_at': remoteCreatedAt,
            'updated_at': remoteTime,
          });

          if (localHighlight == null) {
            // New highlight - add to local
            await HighlightsDatabase.addHighlight(
              book: highlightData['book'],
              chapter: highlightData['chapter'],
              verse: highlightData['verse'],
              start: highlightData['start'],
              end: highlightData['end'],
              color: highlightData['color'],
              createdAt: highlightData['created_at'] as int,
              updatedAt: highlightData['updated_at'] as int,
              skipSync: true,
            );
          } else {
            // Update existing - use the local ID
            await HighlightsDatabase.updateHighlight(
              id: localHighlight['id'] as int,
              start: highlightData['start'],
              end: highlightData['end'],
              color: highlightData['color'],
              updateAt: highlightData['updated_at'] as int,
            );
          }

          hasChanges = true;
          processedCount++;
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that highlights have been updated
        LocalDataChangeNotifier.notifyHighlightsChanged();
      } else {}
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Download notes from Firestore to local database
  Future<void> _downloadNotes(List<DocumentSnapshot> docs) async {
    await _downloadNotesFromData({for (final doc in docs) doc.id: doc.data() as Map<String, dynamic>});
  }

  // Download notes from raw data
  Future<void> _downloadNotesFromData(Map<String, Map<String, dynamic>> docsData) async {
    try {
      bool hasChanges = false;
      int processedCount = 0;

      for (final MapEntry<String, Map<String, dynamic>> entry in docsData.entries) {
        final Map<String, dynamic> data = entry.value;

        // Validate data before processing
        if (!await DataValidation.validateNoteData(data, context: 'download note', documentId: entry.key)) {
          // Delete corrupt remote document

          final docId = int.tryParse(data['created_at']?.toString() ?? '') ?? 0;
          if (docId != 0) {
            await deleteRemoteNote(docId);
          }

          continue; // Skip processing this document
        }

        final remoteTime = (data['updated_at'] ?? data['created_at'] ?? 0) as int;

        // For notes, check by verse location since database uses book/chapter/verse
        final book = data['book'] as String;
        final chapter = data['chapter'] as int;
        final verse = data['verse'] as int;
        final noteText = data['note_text'] as String;

        final localNote = await NotesDatabase.getNoteForVerse(book, chapter, verse);
        final localTime = (localNote?['updated_at'] ?? localNote?['created_at'] ?? 0) as int;

        if (localNote == null || remoteTime > localTime) {
          // Convert to Delta format before storing
          final deltaNoteText = NoteStorageFormat.ensureDeltaFormat(noteText);

          await NotesDatabase.addOrUpdateNote(
              book: book,
              chapter: chapter,
              verse: verse,
              noteText: deltaNoteText,
              createdAt: data['created_at'] as int,
              skipSync: true);
          hasChanges = true;
          processedCount++;
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that notes have been updated
        LocalDataChangeNotifier.notifyNotesChanged();
      } else {}
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Download history from Firestore to local database
  Future<void> _downloadHistory(List<DocumentSnapshot> docs) async {
    await _downloadHistoryFromData({for (final doc in docs) doc.id: doc.data() as Map<String, dynamic>});
  }

  // Download history from raw data
  Future<void> _downloadHistoryFromData(Map<String, Map<String, dynamic>> docsData) async {
    try {
      // Get all local history once for efficiency
      final localHistory = await HistoryDatabase.getHistory();
      final localTimestamps = Set<int>.from(localHistory.map((h) => h['timestamp'] as int));

      bool hasChanges = false;
      int processedCount = 0;

      for (final MapEntry<String, Map<String, dynamic>> entry in docsData.entries) {
        final Map<String, dynamic> data = entry.value;

        // Validate data before processing
        if (!await DataValidation.validateHistoryData(data, context: 'download history', documentId: entry.key)) {
          // Delete corrupt remote document

          final docId = data['timestamp']?.toString() ?? 'unknown';
          await deleteRemoteHistoryItem(docId);

          continue; // Skip processing this document
        }

        final remoteTime = (data['timestamp'] ?? 0) as int;

        // Only add remote history if no local item exists with exact same timestamp
        // If timestamps match, local takes precedence (no duplicate entries)
        if (!localTimestamps.contains(remoteTime)) {
          // Add remote history item with exact remote timestamp
          await HistoryDatabase.addHistory(
            data['book'] as String,
            data['chapter'] as int,
            data['verse'] as int?,
            remoteTime,
            true,
          );
          hasChanges = true;
          processedCount++;
        } else {}
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that history has been updated (though not used in BibleScreen)
        LocalDataChangeNotifier.notifyHistoryChanged();
      } else {}
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Download search history from Firestore to local database
  Future<void> _downloadSearchHistory(List<DocumentSnapshot> docs) async {
    await _downloadSearchHistoryFromData({for (final doc in docs) doc.id: doc.data() as Map<String, dynamic>});
  }

  // Download search history from raw data
  Future<void> _downloadSearchHistoryFromData(Map<String, Map<String, dynamic>> docsData) async {
    try {
      // Get all local search history once for efficiency
      final localSearchHistory = await SearchDatabase.getSearchHistory();
      final localTimestamps = Set<int>.from(localSearchHistory.map((h) => h['timestamp'] as int));

      bool hasChanges = false;
      int processedCount = 0;

      for (final MapEntry<String, Map<String, dynamic>> entry in docsData.entries) {
        final Map<String, dynamic> data = entry.value;

        // Validate data before processing
        if (!await DataValidation.validateSearchHistoryData(data, context: 'download search_history')) {
          // Delete corrupt remote document

          final docId = data['timestamp']?.toString() ?? '0';
          await deleteRemoteSearchHistoryItem(docId);

          continue; // Skip processing this document
        }

        final remoteTime = (data['timestamp'] ?? 0) as int;

        // Only add remote search history if no local item exists with exact same timestamp
        // If timestamps match, local takes precedence (no duplicate entries)
        if (!localTimestamps.contains(remoteTime)) {
          // Add remote search history item with exact remote timestamp and query
          // Use actual search options from remote data
          try {
            await SearchDatabase.addSearchHistory(
              data['query'] as String,
              data['useRegex'] as bool,
              data['useNearby'] as bool,
              data['useWholeWord'] as bool,
              data['useRedLetter'] as bool,
              data['caseSensitive'] as bool,
              data['bookFilterType'] as String,
              data['customBookFilter'] as String,
              remoteTime,
            );
            hasChanges = true;
            processedCount++;
          } catch (e) {
            if (kDebugMode) debugPrint('_downloadSearchHistoryFromData addSearchHistory exception: $e');
          }
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that search history has been updated
        LocalDataChangeNotifier.notifySearchHistoryChanged();
      } else {}
    } catch (e) {
      await ErrorHandler.handleSyncError(e);
    }
  }

  // Upload single highlight to Firestore
  Future<void> _uploadHighlight(Map<String, dynamic> highlight) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Firebase
    final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
    if (!isValid) {
      return;
    }

    await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('highlights')
        .doc(highlight['created_at'].toString())
        .set({
      'book': highlight['book'],
      'chapter': highlight['chapter'],
      'verse': highlight['verse'],
      'start': highlight['start'],
      'end': highlight['end'],
      'color': highlight['color'],
      'created_at': highlight['created_at'],
      'updated_at': highlight['updated_at'],
      'synced_at': FieldValue.serverTimestamp(),
    });
  }

  // Batch upload multiple highlights to Firestore (max 500 per batch)
  Future<void> _batchUploadHighlights(List<Map<String, dynamic>> highlights) async {
    if (_currentUserId == null || highlights.isEmpty) return;

    // Validate all highlights first
    final validHighlights = <Map<String, dynamic>>[];
    for (final highlight in highlights) {
      final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
      if (isValid) {
        validHighlights.add(highlight);
      }
    }

    if (validHighlights.isEmpty) return;

    // Process in batches of max 500 operations
    for (int i = 0; i < validHighlights.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < validHighlights.length) ? i + 500 : validHighlights.length;

      for (int j = i; j < end; j++) {
        final highlight = validHighlights[j];
        final docRef = _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('highlights')
            .doc(highlight['created_at'].toString());
        batch.set(docRef, {
          'book': highlight['book'],
          'chapter': highlight['chapter'],
          'verse': highlight['verse'],
          'start': highlight['start'],
          'end': highlight['end'],
          'color': highlight['color'],
          'created_at': highlight['created_at'],
          'updated_at': highlight['updated_at'],
          'synced_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
  }

  // Delete highlight from Firestore - PUBLIC
  Future<void> deleteRemoteHighlight(int createdAt) async {
    if (_currentUserId == null) return;

    await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('highlights')
        .doc(createdAt.toString())
        .delete();
  }

  // Sync notes to Firestore
  Future<void> syncNotes() async {
    // Check if notes sync is enabled
    final notesEnabled = await _getSyncEnabled('syncNotes');

    if (!notesEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    try {
      // Get local notes - all for deletion checks
      final localNotes = await NotesDatabase.getNotes();

      // Filter for recent changes if not forced
      final baselineTime = _lastNotesSync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final notesToSync = localNotes
          .where((n) => (n['updated_at'] ?? n['created_at'] ?? 0) > baselineTime.millisecondsSinceEpoch)
          .toList();

      // Only skip sync if there are no changes to sync
      if (notesToSync.isEmpty && !_notesNeedSync) {
        // No changes, skip sync

        return;
      }

      if (notesToSync.isNotEmpty) {
        // Get remote notes for comparison
        final remoteNotesSnapshot = await _firestore.collection('users').doc(_currentUserId).collection('notes').get();

        final remoteNotes = remoteNotesSnapshot.docs.map((doc) {
          return {'id': doc.id, ...doc.data()};
        }).toList();

        // Sync logic: collect notes that need uploading, then use adaptive upload (single vs batch)
        final notesToUpload = <Map<String, dynamic>>[];

        for (final note in notesToSync) {
          final localTimestamp = note['created_at'] as int;
          final remoteDoc = remoteNotes.where((n) => n['created_at'] == localTimestamp).firstOrNull;

          if (remoteDoc == null) {
            // New note - needs upload
            notesToUpload.add(note);
          } else {
            // Check if local is newer
            final localTime = note['updated_at'] ?? note['created_at'] ?? 0;
            final remoteTime = remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

            if (localTime > remoteTime) {
              notesToUpload.add(note);
            }
          }
        }

        // Adaptive upload: single vs batch based on workload
        if (notesToUpload.isNotEmpty) {
          try {
            if (notesToUpload.length == 1) {
              // Single note - use fast individual upload
              await _uploadNote(notesToUpload.first);
            } else {
              // Multiple notes - use batch upload
              await _batchUploadNotes(notesToUpload);
            }
            _lastNotesSync = DateTime.now();
            _notesNeedSync = false;
          } catch (e) {
            // If batch upload fails, queue each operation individually for retry
            for (final note in notesToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: note['created_at'].toString(),
                type: 'note',
                operation: 'create',
                data: note,
                timestamp: DateTime.fromMillisecondsSinceEpoch(note['created_at'] as int),
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastNotesSyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('notes')
          .where('updated_at', isGreaterThan: lastSyncMs);
      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        await _downloadNotes(snapshot.docs);
      }

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastNotesSync = DateTime.now();

      // Save timestamps to preferences
      await _saveLastSyncTimestamps();
    } catch (e) {
      // For critical failures, don't retry - just log
    }
  }

  // Upload single note to Firestore
  Future<void> _uploadNote(Map<String, dynamic> note) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Firebase
    final isValid = await DataValidation.validateBeforeUpload(note, 'note');
    if (!isValid) {
      return;
    }

    await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('notes')
        .doc(note['created_at'].toString())
        .set({
      'book': note['book'],
      'chapter': note['chapter'],
      'verse': note['verse'],
      'note_text': note['note_text'],
      'created_at': note['created_at'],
      'updated_at': note['updated_at'],
      'synced_at': FieldValue.serverTimestamp(),
    });
  }

  // Delete note from Firestore - PUBLIC
  Future<void> deleteRemoteNote(int createdAt) async {
    if (_currentUserId == null) return;

    final docId = createdAt.toString();

    try {
      await _firestore.collection('users').doc(_currentUserId).collection('notes').doc(docId).delete();
    } catch (e) {
      //
    }
  }

  // Batch upload multiple notes to Firestore (max 500 per batch)
  Future<void> _batchUploadNotes(List<Map<String, dynamic>> notes) async {
    if (_currentUserId == null || notes.isEmpty) return;

    // Validate all notes first
    final validNotes = <Map<String, dynamic>>[];
    for (final note in notes) {
      final isValid = await DataValidation.validateBeforeUpload(note, 'note');
      if (isValid) {
        validNotes.add(note);
      }
    }

    if (validNotes.isEmpty) return;

    // Process in batches of max 500 operations
    for (int i = 0; i < validNotes.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < validNotes.length) ? i + 500 : validNotes.length;

      for (int j = i; j < end; j++) {
        final note = validNotes[j];
        final docRef =
            _firestore.collection('users').doc(_currentUserId).collection('notes').doc(note['created_at'].toString());
        batch.set(docRef, {
          'book': note['book'],
          'chapter': note['chapter'],
          'verse': note['verse'],
          'note_text': note['note_text'],
          'created_at': note['created_at'],
          'updated_at': note['updated_at'],
          'synced_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
  }

  // Sync search history to Firestore
  Future<void> syncSearchHistory() async {
    // Check if search history sync is enabled
    final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

    if (!searchHistoryEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    // Get local search history - all for deletion checks
    final localSearchHistory = await SearchDatabase.getSearchHistory();

    // Filter for recent changes if not forced
    final baselineTime = _lastSearchHistorySync ?? DateTime.fromMillisecondsSinceEpoch(0);
    final searchHistoryToSync =
        localSearchHistory.where((h) => (h['timestamp'] ?? 0) > baselineTime.millisecondsSinceEpoch).toList();

    // Only skip sync if there are no changes to sync
    if (searchHistoryToSync.isEmpty && !_searchHistoryNeedSync) {
      // No changes, skip upload
      return;
    }

    if (searchHistoryToSync.isNotEmpty) {
      // Get remote search history
      final remoteSearchHistorySnapshot =
          await _firestore.collection('users').doc(_currentUserId).collection('search_history').get();

      final remoteSearchHistory = remoteSearchHistorySnapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();

      // Sync logic: collect search history items that need uploading, then use adaptive upload (single vs batch)
      final searchHistoryItemsToUpload = <Map<String, dynamic>>[];

      for (final searchHistoryItem in searchHistoryToSync) {
        final localTime = searchHistoryItem['timestamp'] ?? 0;
        final remoteDoc = remoteSearchHistory.where((s) => s['timestamp'] == localTime).firstOrNull;

        if (remoteDoc == null) {
          // New search history item - needs upload
          searchHistoryItemsToUpload.add(searchHistoryItem);
        } else {
          // Check if local is newer
          final remoteTime = remoteDoc['timestamp'] ?? 0;

          if (localTime > remoteTime) {
            searchHistoryItemsToUpload.add(searchHistoryItem);
          }
        }
      }

      // Adaptive upload: single vs batch based on workload
      if (searchHistoryToSync.isNotEmpty) {
        try {
          if (searchHistoryToSync.length == 1) {
            // Single search history item - use fast individual upload
            await _uploadSearchHistoryItem(searchHistoryToSync.first);
          } else {
            // Multiple search history items - use batch upload
            await _batchUploadSearchHistory(searchHistoryToSync);
          }
          _lastSearchHistorySync = DateTime.now();
          _searchHistoryNeedSync = false;
        } catch (e) {
          // If batch upload fails, queue each operation individually for retry
          for (final searchHistoryItem in searchHistoryToSync) {
            _enqueueFailedOperation(SyncOperation(
              id: searchHistoryItem['timestamp'].toString(),
              type: 'search_history',
              operation: 'create',
              data: searchHistoryItem,
              timestamp: DateTime.fromMillisecondsSinceEpoch(searchHistoryItem['timestamp'] as int),
            ));
          }
        }
      }
    }

    // Download remote changes newer than last sync for bidirectional sync
    final lastSyncMs = _lastSearchHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
    final query = _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('search_history')
        .where('timestamp', isGreaterThan: lastSyncMs);
    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) {
      await _downloadSearchHistory(snapshot.docs);
    }

    // Always update the sync timestamp after sync operations (both upload and download)
    _lastSearchHistorySync = DateTime.now();

    // Save timestamps to preferences
    await _saveLastSyncTimestamps();
  }

  // Batch upload multiple search history items to Firestore (max 500 per batch)
  Future<void> _batchUploadSearchHistory(List<Map<String, dynamic>> searchHistoryItems) async {
    if (_currentUserId == null || searchHistoryItems.isEmpty) return;

    // Validate all search history items first
    final validSearchHistoryItems = <Map<String, dynamic>>[];
    for (final searchHistoryItem in searchHistoryItems) {
      final isValid = await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
      if (isValid) {
        validSearchHistoryItems.add(searchHistoryItem);
      }
    }

    if (validSearchHistoryItems.isEmpty) return;

    // Process in batches of max 500 operations
    for (int i = 0; i < validSearchHistoryItems.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < validSearchHistoryItems.length) ? i + 500 : validSearchHistoryItems.length;

      for (int j = i; j < end; j++) {
        final searchHistoryItem = validSearchHistoryItems[j];
        final docRef = _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('search_history')
            .doc(searchHistoryItem['timestamp'].toString());
        batch.set(docRef, {
          'query': searchHistoryItem['query'],
          'useRegex': searchHistoryItem['useRegex'], // Use bool values directly
          'useNearby': searchHistoryItem['useNearby'],
          'useWholeWord': searchHistoryItem['useWholeWord'],
          'useRedLetter': searchHistoryItem['useRedLetter'],
          'caseSensitive': searchHistoryItem['caseSensitive'],
          'bookFilterType': searchHistoryItem['bookFilterType'],
          'customBookFilter': searchHistoryItem['customBookFilter'],
          'timestamp': searchHistoryItem['timestamp'],
          'synced_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
  }

  // Sync history to Firestore
  Future<void> syncHistory() async {
    // Check if history sync is enabled
    final historyEnabled = await _getSyncEnabled('syncHistory');

    if (!historyEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    // Get local history - all for deletion checks
    final localHistory = await HistoryDatabase.getHistory();

    // Filter for recent changes if not forced
    final baselineTime = _lastHistorySync ?? DateTime.fromMillisecondsSinceEpoch(0);
    final historyToSync =
        localHistory.where((h) => (h['timestamp'] ?? 0) > baselineTime.millisecondsSinceEpoch).toList();

    // Only skip sync if there are no changes to sync
    if (historyToSync.isEmpty && !_historyNeedSync) {
      // No changes, skip upload

      return;
    }

    if (historyToSync.isNotEmpty) {
      // Get remote history
      final remoteHistorySnapshot =
          await _firestore.collection('users').doc(_currentUserId).collection('history').get();

      final remoteHistory = remoteHistorySnapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();

      // Sync logic: collect history items that need uploading, then use adaptive upload (single vs batch)
      final historyItemsToUpload = <Map<String, dynamic>>[];

      for (final historyItem in historyToSync) {
        final localTime = historyItem['timestamp'] ?? 0;
        final remoteDoc = remoteHistory.where((h) => h['timestamp'] == localTime).firstOrNull;

        if (remoteDoc == null) {
          // New history item - needs upload
          historyItemsToUpload.add(historyItem);
        } else {
          // Check if local is newer
          final remoteTime = remoteDoc['timestamp'] ?? 0;

          if (localTime > remoteTime) {
            historyItemsToUpload.add(historyItem);
          }
        }
      }

      // Adaptive upload: single vs batch based on workload
      if (historyItemsToUpload.isNotEmpty) {
        try {
          if (historyItemsToUpload.length == 1) {
            // Single history item - use fast individual upload
            await _uploadHistoryItem(historyItemsToUpload.first);
          } else {
            // Multiple history items - use batch upload
            await _batchUploadHistory(historyItemsToUpload);
          }
          _lastHistorySync = DateTime.now();
          _historyNeedSync = false;
        } catch (e) {
          // If batch upload fails, queue each operation individually for retry
          for (final historyItem in historyItemsToUpload) {
            _enqueueFailedOperation(SyncOperation(
              id: historyItem['timestamp'].toString(),
              type: 'history',
              operation: 'create',
              data: historyItem,
              timestamp: DateTime.fromMillisecondsSinceEpoch(historyItem['timestamp'] as int),
            ));
          }
        }
      }
    }

    // Download remote changes newer than last sync for bidirectional sync
    final lastSyncMs = _lastHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
    final query = _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('history')
        .where('timestamp', isGreaterThan: lastSyncMs);
    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) {
      await _downloadHistory(snapshot.docs);
    }

    // Always update the sync timestamp after sync operations (both upload and download)
    _lastHistorySync = DateTime.now();

    // Save timestamps to preferences
    await _saveLastSyncTimestamps();
  }

  // Upload single history item to Firestore
  Future<void> _uploadHistoryItem(Map<String, dynamic> historyItem) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Firebase
    final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
    if (!isValid) {
      return;
    }

    await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('history')
        .doc(historyItem['timestamp'].toString())
        .set({
      'book': historyItem['book'],
      'chapter': historyItem['chapter'],
      'verse': historyItem['verse'],
      'timestamp': historyItem['timestamp'],
      'synced_at': FieldValue.serverTimestamp(),
    });
  }

  // Delete history item from Firestore - PUBLIC
  Future<void> deleteRemoteHistoryItem(String historyId) async {
    if (_currentUserId == null) return;
    await _firestore.collection('users').doc(_currentUserId).collection('history').doc(historyId).delete();
  }

  // Batch upload multiple history items to Firestore (max 500 per batch)
  Future<void> _batchUploadHistory(List<Map<String, dynamic>> historyItems) async {
    if (_currentUserId == null || historyItems.isEmpty) return;

    // Validate all history items first
    final validHistoryItems = <Map<String, dynamic>>[];
    for (final historyItem in historyItems) {
      final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
      if (isValid) {
        validHistoryItems.add(historyItem);
      }
    }

    if (validHistoryItems.isEmpty) return;

    // Process in batches of max 500 operations
    for (int i = 0; i < validHistoryItems.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < validHistoryItems.length) ? i + 500 : validHistoryItems.length;

      for (int j = i; j < end; j++) {
        final historyItem = validHistoryItems[j];
        final docRef = _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('history')
            .doc(historyItem['timestamp'].toString());
        batch.set(docRef, {
          'book': historyItem['book'],
          'chapter': historyItem['chapter'],
          'verse': historyItem['verse'],
          'timestamp': historyItem['timestamp'],
          'synced_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
  }

  // Sync only recent remote changes since last local sync (app resume scenario)
  Future<void> _syncRecentChangesOnly() async {
    if (_currentUserId == null || !isOnline) return;

    // Check sync settings and download recent changes only
    final highlightsEnabled = await _getSyncEnabled('syncHighlights');
    final notesEnabled = await _getSyncEnabled('syncNotes');
    final historyEnabled = await _getSyncEnabled('syncHistory');
    final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

    // Query and download highlights updated since last sync
    if (highlightsEnabled) {
      final baselineTime = _lastHighlightsSyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('highlights')
          .where('updated_at', isGreaterThan: baselineTime);
      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        await _downloadHighlights(snapshot.docs);
      }
    }

    // Query and download notes updated since last sync
    if (notesEnabled) {
      final lastSyncMs = _lastNotesSyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('notes')
          .where('updated_at', isGreaterThan: lastSyncMs);
      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        await _downloadNotes(snapshot.docs);
      }
    }

    // Query and download history items since last sync
    if (historyEnabled) {
      final lastSyncMs = _lastHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('history')
          .where('timestamp', isGreaterThan: lastSyncMs);
      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        await _downloadHistory(snapshot.docs);
      }
    }

    // Query and download search history items since last sync
    if (searchHistoryEnabled) {
      final lastSyncMs = _lastSearchHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('search_history')
          .where('timestamp', isGreaterThan: lastSyncMs);
      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        await _downloadSearchHistory(snapshot.docs);
      }
    }

    // Always update the sync timestamps after downloading changes to prevent re-downloading the same data
    _lastHighlightsSync = DateTime.now();
    _lastNotesSync = DateTime.now();
    _lastHistorySync = DateTime.now();
    _lastSearchHistorySync = DateTime.now();
    await _saveLastSyncTimestamps();
  }

  // Sync all data types
  Future<void> syncAll() async {
    if (_currentUserId == null) {
      if (kDebugMode) debugPrint('SyncAll called with null _currentUserID: $_currentUserId');
      return;
    }

    // Set syncing status to show progress dialog
    final previousStatus = _syncStatus;
    if (isOnline) {
      _syncStatus = SyncStatus.syncing;
      syncStatusNotifier.value = _syncStatus;
    }

    try {
      await syncHighlights();
      await syncNotes();
      await syncHistory();
      await syncSearchHistory();
    } finally {
      // Restore previous status
      _syncStatus = previousStatus;
      // Update notifier to reflect completion
      if (isOnline) {
        // If was syncing, restore to online status
        syncStatusNotifier.value = SyncStatus.online;
      } else {
        // If was offline, keep offline
        syncStatusNotifier.value = _syncStatus;
      }
    }
  }

  // Start connection monitoring using event-driven connectivity changes
  void _startConnectionMonitoring() {
    // Avoid duplicate listeners
    if (_connectivitySubscription != null) return;

    // Listen to connectivity changes instead of polling
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) async {
      try {
        // Debounce rapid connectivity changes (network fluctuations)
        await Future.delayed(const Duration(seconds: 2));

        final hasConnection = await InternetAccessChecker.hasInternetAccess();

        if (hasConnection && _syncStatus != SyncStatus.online) {
          // Connection restored - test and setup
          try {
            await _checkConnectionAndSetup();
          } catch (e) {
            if (kDebugMode) debugPrint('_startConnectionMonitoring _checkConnectionAndSetup exception: $e');
          }
        } else if (!hasConnection && _syncStatus != SyncStatus.offline) {
          // Connection lost
          _syncStatus = SyncStatus.offline;
          await ErrorHandler.handle('No network connection', type: ErrorType.network, severity: ErrorSeverity.medium);
        }
      } catch (e) {
        await ErrorHandler.handleNetworkError(e);
        _syncStatus = SyncStatus.error;
      }
    });

    // Also perform initial connectivity check
    _connectivity.checkConnectivity().then((result) async {
      final hasConnection = await InternetAccessChecker.hasInternetAccess();
      if (hasConnection) {
        await _checkConnectionAndSetup();
      } else {
        _syncStatus = SyncStatus.offline;
        await ErrorHandler.handle('No network connection', type: ErrorType.network, severity: ErrorSeverity.medium);
      }
    }).catchError((e) async {
      await ErrorHandler.handleNetworkError(e);
      _syncStatus = SyncStatus.error;
    });
  }

  // Stop connection monitoring (for Android background optimization)
  void stopConnectionMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  // Sync single highlight efficiently with bidirectional conflict resolution
  Future<void> syncSingleHighlight(Map<String, dynamic> highlight) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = highlight['created_at'].toString();

    try {
      // Query only the specific remote document
      final remoteDocRef = _firestore.collection('users').doc(_currentUserId).collection('highlights').doc(docId);
      final remoteDoc = await remoteDocRef.get();

      if (!remoteDoc.exists) {
        // Remote document doesn't exist - upload local version
        final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
        if (isValid) {
          await _uploadHighlight(highlight);
        }
      } else {
        // Remote document exists - compare timestamps
        final remoteData = remoteDoc.data() as Map<String, dynamic>;
        final isValidRemote = await DataValidation.validateHighlightData(remoteData,
            context: 'single highlight sync', documentId: remoteDoc.id);

        if (isValidRemote) {
          final localTime = highlight['updated_at'] ?? highlight['created_at'] ?? 0;
          final remoteTime = remoteData['updated_at'] ?? remoteData['created_at'] ?? 0;

          if (localTime > remoteTime) {
            // Local is newer - upload local version
            final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
            if (isValid) {
              await _uploadHighlight(highlight);
            }
          } else if (remoteTime > localTime) {
            // Remote is newer - download to update local
            await _downloadHighlightsFromData({remoteDoc.id: remoteData});
          }
          // If timestamps equal, no action needed (already in sync)
        } else {
          // Invalid remote data - this should have been deleted by validation, but upload local to overwrite
          final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
          if (isValid) {
            await _uploadHighlight(highlight);
          }
        }
      }
    } catch (e) {
      // On sync failure, the operation will be retried through existing retry logic
      rethrow; // Re-throw to allow retry queuing
    }
  }

  // Sync single note efficiently with bidirectional conflict resolution
  Future<void> syncSingleNote(Map<String, dynamic> note) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = note['created_at'].toString();

    try {
      // Query only the specific remote document
      final remoteDocRef = _firestore.collection('users').doc(_currentUserId).collection('notes').doc(docId);
      final remoteDoc = await remoteDocRef.get();

      if (!remoteDoc.exists) {
        // Remote document doesn't exist - upload local version
        final isValid = await DataValidation.validateBeforeUpload(note, 'note');
        if (isValid) {
          await _uploadNote(note);
        }
      } else {
        // Remote document exists - compare timestamps
        final remoteData = remoteDoc.data() as Map<String, dynamic>;
        final isValidRemote =
            await DataValidation.validateNoteData(remoteData, context: 'single note sync', documentId: remoteDoc.id);

        if (isValidRemote) {
          final localTime = note['updated_at'] ?? note['created_at'] ?? 0;
          final remoteTime = remoteData['updated_at'] ?? remoteData['created_at'] ?? 0;

          if (localTime > remoteTime) {
            // Local is newer - upload local version
            final isValid = await DataValidation.validateBeforeUpload(note, 'note');
            if (isValid) {
              await _uploadNote(note);
            }
          } else if (remoteTime > localTime) {
            // Remote is newer - download to update local
            await _downloadNotesFromData({remoteDoc.id: remoteData});
          }
          // If timestamps equal, no action needed (already in sync)
        } else {
          // Invalid remote data - this should have been deleted by validation, but upload local to overwrite
          final isValid = await DataValidation.validateBeforeUpload(note, 'note');
          if (isValid) {
            await _uploadNote(note);
          }
        }
      }
    } catch (e) {
      // On sync failure, the operation will be retried through existing retry logic
      rethrow; // Re-throw to allow retry queuing
    }
  }

  // Sync single history item efficiently with bidirectional conflict resolution
  Future<void> syncSingleHistoryItem(Map<String, dynamic> historyItem) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = historyItem['timestamp'].toString();

    try {
      // Query only the specific remote document
      final remoteDocRef = _firestore.collection('users').doc(_currentUserId).collection('history').doc(docId);
      final remoteDoc = await remoteDocRef.get();

      if (!remoteDoc.exists) {
        // Remote document doesn't exist - upload local version
        final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
        if (isValid) {
          await _uploadHistoryItem(historyItem);
        }
      } else {
        // Remote document exists - compare timestamps
        final remoteData = remoteDoc.data() as Map<String, dynamic>;
        final isValidRemote = await DataValidation.validateHistoryData(remoteData,
            context: 'single history sync', documentId: remoteDoc.id);

        if (isValidRemote) {
          final localTime = historyItem['timestamp'] ?? 0;
          final remoteTime = remoteData['timestamp'] ?? 0;

          if (localTime > remoteTime) {
            // Local is newer - upload local version
            final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
            if (isValid) {
              await _uploadHistoryItem(historyItem);
            }
          } else if (remoteTime > localTime) {
            // Remote is newer - download to update local
            await _downloadHistoryFromData({remoteDoc.id: remoteData});
          }
          // If timestamps equal, no action needed (already in sync)
        } else {
          // Invalid remote data - this should have been deleted by validation, but upload local to overwrite
          final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
          if (isValid) {
            await _uploadHistoryItem(historyItem);
          }
        }
      }
    } catch (e) {
      // On sync failure, the operation will be retried through existing retry logic
      rethrow; // Re-throw to allow retry queuing
    }
  }

  // Sync single search history item efficiently with bidirectional conflict resolution
  Future<void> syncSingleSearchHistoryItem(Map<String, dynamic> searchHistoryItem) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = searchHistoryItem['timestamp'].toString();

    try {
      // Query only the specific remote document
      final remoteDocRef = _firestore.collection('users').doc(_currentUserId).collection('search_history').doc(docId);
      final remoteDoc = await remoteDocRef.get();

      if (!remoteDoc.exists) {
        // Remote document doesn't exist - upload local version
        final isValid = await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
        if (isValid) {
          await _uploadSearchHistoryItem(searchHistoryItem);
        }
      } else {
        // Remote document exists - compare timestamps
        final remoteData = remoteDoc.data() as Map<String, dynamic>;
        final isValidRemote =
            await DataValidation.validateSearchHistoryData(remoteData, context: 'single search_history sync');

        if (isValidRemote) {
          final localTime = searchHistoryItem['timestamp'] ?? 0;
          final remoteTime = remoteData['timestamp'] ?? 0;

          if (localTime > remoteTime) {
            // Local is newer - upload local version
            final isValid = await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
            if (isValid) {
              await _uploadSearchHistoryItem(searchHistoryItem);
            }
          } else if (remoteTime > localTime) {
            // Remote is newer - download to update local
            await _downloadSearchHistoryFromData({remoteDoc.id: remoteData});
          }
          // If timestamps equal, no action needed (already in sync)
        } else {
          // Invalid remote data - this should have been deleted by validation, but upload local to overwrite
          final isValid = await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
          if (isValid) {
            await _uploadSearchHistoryItem(searchHistoryItem);
          }
        }
      }
    } catch (e) {
      // On sync failure, the operation will be retried through existing retry logic
      rethrow; // Re-throw to allow retry queuing
    }
  }

  // Unified operation marking method (handles all sync categories: highlight, note, history, search_history)
  Future<void> markOperation(String type, int itemId, String operation, Map<String, dynamic> data) async {
    // Set appropriate sync flag based on type
    switch (type) {
      case 'highlight':
        _highlightsNeedSync = true;
        LocalDataChangeNotifier.notifyHighlightsChanged();
        break;
      case 'note':
        _notesNeedSync = true;
        LocalDataChangeNotifier.notifyNotesChanged();
        break;
      case 'history':
        _historyNeedSync = true;
        LocalDataChangeNotifier.notifyHistoryChanged();
        break;
      case 'search_history':
        _searchHistoryNeedSync = true;
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        break;
    }

    // Handle offline queuing
    if (!isOnline || _currentUserId == null) {
      _queuePersistentOperation('${type}_$itemId', type, operation, data);
      _persistQueues();
      return;
    }

    // Handle online sync attempts
    try {
      if (operation == 'delete') {
        // Type-specific delete methods
        switch (type) {
          case 'highlight':
            await deleteRemoteHighlight(data['created_at'] as int);
            break;
          case 'note':
            try {
              await deleteRemoteNote(data['created_at'] as int);

              break;
            } catch (e) {
              //
            }
          case 'history':
            await deleteRemoteHistoryItem(itemId.toString());
            break;
          case 'search_history':
            await deleteRemoteSearchHistoryItem(itemId.toString());
            break;
        }
      } else {
        // Type-specific single-item sync methods for create/update
        switch (type) {
          case 'highlight':
            await syncSingleHighlight(data);
            break;
          case 'note':
            await syncSingleNote(data);
            break;
          case 'history':
            await syncSingleHistoryItem(data);
            break;
          case 'search_history':
            await syncSingleSearchHistoryItem(data);
            break;
        }
      }
    } catch (e) {
      // Prepare failed operation data with type-specific ID and timestamp extraction
      String id;
      DateTime timestamp;
      switch (type) {
        case 'highlight':
        case 'note':
          id = data['created_at'].toString();
          timestamp = DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int);
          break;
        case 'history':
        case 'search_history':
          id = data['timestamp'].toString();
          timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
          break;
        default:
          id = '0';
          timestamp = DateTime.now();
      }

      _enqueueFailedOperation(SyncOperation(
        id: id,
        type: type,
        operation: operation,
        data: data,
        timestamp: timestamp,
      ));
    }

    // Notify appropriate change notifier based on type
    switch (type) {
      case 'highlight':
        LocalDataChangeNotifier.notifyHighlightsChanged();
        break;
      case 'note':
        LocalDataChangeNotifier.notifyNotesChanged();
        break;
      case 'history':
        LocalDataChangeNotifier.notifyHistoryChanged();
        break;
      case 'search_history':
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        break;
    }
  }

  // Manual sync trigger
  Future<void> triggerManualSync() async {
    await syncAll();
    LocalDataChangeNotifier.notifyHighlightsChanged();
    LocalDataChangeNotifier.notifyNotesChanged();
    LocalDataChangeNotifier.notifyHistoryChanged();
    LocalDataChangeNotifier.notifySearchHistoryChanged();
  }

  // Public method to check Firebase connection for exit dialogs
  Future<bool> checkFirebaseConnection() async {
    if (_currentUserId == null) return false;

    try {
      // Test basic Firebase connectivity by attempting a small read
      await _firestore.collection('users').doc(_currentUserId).get();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Delete all remote data for a category when sync is disabled
  Future<void> deleteAllRemoteHighlights() async {
    if (_currentUserId == null) return;

    final highlightsRef = _firestore.collection('users').doc(_currentUserId).collection('highlights');
    final snapshot = await highlightsRef.get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  Future<void> deleteAllRemoteNotes() async {
    if (_currentUserId == null) return;

    final notesRef = _firestore.collection('users').doc(_currentUserId).collection('notes');
    final snapshot = await notesRef.get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  Future<void> deleteAllRemoteHistory() async {
    if (_currentUserId == null) return;

    final historyRef = _firestore.collection('users').doc(_currentUserId).collection('history');
    final snapshot = await historyRef.get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  Future<void> deleteAllRemoteSearchHistory() async {
    if (_currentUserId == null) return;

    final searchHistoryRef = _firestore.collection('users').doc(_currentUserId).collection('search_history');
    final snapshot = await searchHistoryRef.get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  // Cache the username locally for offline display
  Future<void> cacheUsername() async {
    if (_currentUserId == null) return;

    final doc = await _firestore.collection('users').doc(_currentUserId).get();
    final username = doc.data()?['username'] as String?;
    await HistoryDatabase.setCachedUsername(username ?? 'Unknown');
  }

  // Set cached username (for manual updates)
  Future<void> setCachedUsername(String username) async {
    await HistoryDatabase.setCachedUsername(username);
  }

  // Clear cached username (called on sign out)
  Future<void> clearCachedUsername() async {
    await HistoryDatabase.setCachedUsername('Unknown');
  }

  // Get cached username (for main.dart display)
  static Future<String?> getCachedUsername() async {
    return await HistoryDatabase.getCachedUsername();
  }

  // Upload single search history item to Firestore
  Future<void> _uploadSearchHistoryItem(Map<String, dynamic> searchHistoryItem) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Firebase
    final isValid = await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
    if (!isValid) {
      return;
    }

    // Store ALL search options to preserve user's search configuration
    await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('search_history')
        .doc(searchHistoryItem['timestamp'].toString())
        .set({
      'query': searchHistoryItem['query'],
      'useRegex': searchHistoryItem['useRegex'], // Use bool values directly
      'useNearby': searchHistoryItem['useNearby'],
      'useWholeWord': searchHistoryItem['useWholeWord'],
      'useRedLetter': searchHistoryItem['useRedLetter'],
      'caseSensitive': searchHistoryItem['caseSensitive'],
      'bookFilterType': searchHistoryItem['bookFilterType'],
      'customBookFilter': searchHistoryItem['customBookFilter'],
      'timestamp': searchHistoryItem['timestamp'],
      'synced_at': FieldValue.serverTimestamp(),
    });
  }

  // Delete search history item from Firestore - PUBLIC
  Future<void> deleteRemoteSearchHistoryItem(String searchHistoryId) async {
    if (_currentUserId == null) return;
    await _firestore.collection('users').doc(_currentUserId).collection('search_history').doc(searchHistoryId).delete();
  }

  // Add failed operation to retry queue for later retry
  void _enqueueFailedOperation(SyncOperation operation) {
    final operationWithRetryCount = operation.copyWith(retryCount: operation.retryCount + 1);
    _retryQueue.add(operationWithRetryCount);

    _startRetryTimer();
  }

  // Start or restart retry timer with fixed intervals based on retry attempt
  void _startRetryTimer() {
    _retryTimer?.cancel();

    if (_retryQueue.isEmpty) return;

    // Use shared retry delay constants: syncRetryDelay1Seconds, syncRetryDelay2Seconds, syncRetryDelay3Seconds
    final nextRetry = _retryQueue.first;
    final Duration delay;
    switch (nextRetry.retryCount) {
      case 1:
        delay = Duration(seconds: syncRetryDelay1Seconds); // First retry: 1 second
        break;
      case 2:
        delay = Duration(seconds: syncRetryDelay2Seconds); // Second retry: 15 seconds
        break;
      case 3:
        delay = Duration(seconds: syncRetryDelay3Seconds); // Third retry: 30 seconds
        break;
      default:
        delay = Duration.zero; // After 3 retries, process immediately to move to persistent queue
    }

    _retryTimer = Timer(delay, _processRetryQueue);
  }

  // Process operations in retry queue
  Future<void> _processRetryQueue() async {
    if (_retryQueue.isEmpty || _currentUserId == null || !isOnline) {
      return;
    }

    final operationsToRetry = List<SyncOperation>.from(_retryQueue);
    _retryQueue.clear();

    for (final operation in operationsToRetry) {
      // Check if this operation has exceeded max retries
      if (operation.retryCount >= 3) {
        // Move to persistent queue instead of retrying

        _queuePersistentOperation(operation.id, operation.type, operation.operation, operation.data);
        continue;
      }

      try {
        switch (operation.type) {
          case 'highlight':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadHighlight(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteHighlight(operation.data['created_at'] as int);
            }
            break;
          case 'note':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadNote(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteNote(operation.data['created_at'] as int);
            }
            break;
          case 'history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadHistoryItem(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteHistoryItem(operation.data['timestamp'].toString());
            }
            break;
          case 'search_history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadSearchHistoryItem(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteSearchHistoryItem(operation.data['timestamp'].toString());
            }
            break;
        }

        // Success - operation complete, no need to re-queue
      } catch (e) {
        // Re-queue for another attempt
        _enqueueFailedOperation(operation);
      }
    }
  }

  // Cleanup - called when user signs out or app is terminated
  void dispose() {
    // Move any remaining retry operations to persistent queues before cleanup
    if (_currentUserId != null) {
      for (final operation in _retryQueue) {
        _queueOperation(operation);
      }
    }

    _retryTimer?.cancel();

    // Cancel Firestore listeners
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

    // Stop connectivity monitoring
    stopConnectionMonitoring();

    _isListening = false;

    // Properly cleanup stream controllers
    _cleanupStreamControllers();

    _isInitialized = false;
  }

  // Prepare for sign-out - clean up listeners and reset state
  Future<void> prepareForSignOut() async {
    // If user chose to keep data, preserve failed retries by moving them to persistent queues
    if (preserveRetriesOnSignOut) {
      for (final operation in _retryQueue) {
        _queueOperation(operation);
      }
    }

    // Cancel all active listeners
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

    _retryTimer?.cancel();

    // Reset flags
    _isListening = false;
    _syncStatus = SyncStatus.offline;
    syncStatusNotifier.value = _syncStatus;
    _highlightsNeedSync = false;
    _notesNeedSync = false;
    _historyNeedSync = false;
    _searchHistoryNeedSync = false;

    // Clear sync timestamps and preferences
    _lastHighlightsSync = null;
    _lastNotesSync = null;
    _lastHistorySync = null;
    _lastSearchHistorySync = null;
    _lastHighlightsSyncSaved = null;
    _lastNotesSyncSaved = null;
    _lastHistorySyncSaved = null;
    _lastSearchHistorySyncSaved = null;

    // Clear persistent queues (they were already persisted above if we preserved retries)
    _highlightsPendingQueue.clear();
    _notesPendingQueue.clear();
    _historyPendingQueue.clear();
    _searchHistoryPendingQueue.clear();

    // Persist empty queues
    await _persistQueues();

    // Clear retry queue
    _retryQueue.clear();

    // Clear cached username on sign out
    await clearCachedUsername();

    // Reset the preservation flag
    preserveRetriesOnSignOut = false;

    _isInitialized = false;
  }

  void restartConnectionMonitoring() {
    _startConnectionMonitoring();
  }
}
