import 'dart:async';

/// Local data change notifier for immediate UI updates
/// Independent of Firestore sync service - works even when offline or signed out
class LocalDataChangeNotifier {
  static final LocalDataChangeNotifier _instance = LocalDataChangeNotifier._internal();
  factory LocalDataChangeNotifier() => _instance;
  LocalDataChangeNotifier._internal();

  // Private controllers for local notifications
  static StreamController<void>? _highlightsChangedController;
  static StreamController<void>? _notesChangedController;
  static StreamController<void>? _historyChangedController;
  static StreamController<void>? _searchHistoryChangedController;

  // Public streams for UI components to subscribe to
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

  // Public notification methods
  static void notifyHighlightsChanged() {
    if (_highlightsChangedController == null || _highlightsChangedController!.isClosed) {
      _highlightsChangedController = StreamController<void>.broadcast();
    }
    _highlightsChangedController!.add(null);
  }

  static void notifyNotesChanged() {
    if (_notesChangedController == null || _notesChangedController!.isClosed) {
      _notesChangedController = StreamController<void>.broadcast();
    }
    _notesChangedController!.add(null);
  }

  static void notifyHistoryChanged() {
    if (_historyChangedController == null || _historyChangedController!.isClosed) {
      _historyChangedController = StreamController<void>.broadcast();
    }
    _historyChangedController!.add(null);
  }

  static void notifySearchHistoryChanged() {
    if (_searchHistoryChangedController == null || _searchHistoryChangedController!.isClosed) {
      _searchHistoryChangedController = StreamController<void>.broadcast();
    }
    _searchHistoryChangedController!.add(null);
  }

  // static void notifyPreferencesChanged() {
  //   if (_preferencesChangedController == null || _preferencesChangedController!.isClosed) {
  //     _preferencesChangedController = StreamController<void>.broadcast();
  //   }
  //   _preferencesChangedController!.add(null);
  // }

  // Cleanup method (only for app shutdown)
  static void dispose() {
    _highlightsChangedController?.close();
    _notesChangedController?.close();
    _historyChangedController?.close();
    //_preferencesChangedController?.close();
  }
}
