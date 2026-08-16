import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../database/search_database.dart';
import '../utils/snackbar_notification.dart'; // For showStyledSnackBar
import '../services/local_data_change_notifier.dart'; // For notifications
import '../services/supabase_sync_service.dart'; // For sync service streams
import '../utils/preferences_constants.dart'; // For uiFontSize and uiFontFamily
import '../main.dart'; // For getAdaptiveTextColor

class SearchHistoryDialog extends StatefulWidget {
  final void Function(Map<String, dynamic>) onUpdateSearchQuery;

  const SearchHistoryDialog({
    super.key,
    required this.onUpdateSearchQuery,
  });

  @override
  State<SearchHistoryDialog> createState() => _SearchHistoryDialogState();
}

class _SearchHistoryDialogState extends State<SearchHistoryDialog> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _searchHistoryItems = [];
  bool _isLoading = false;
  bool _hasMoreData = true;
  int _currentOffset = 0;
  static const int _pageSize = 50;

  // Stream subscriptions for real-time updates
  late StreamSubscription _localSearchHistorySubscription;
  late StreamSubscription _syncSearchHistorySubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialSearchHistory();
    _scrollController.addListener(_onScroll);

    // Listen to local data change notifier for immediate local search history updates
    _localSearchHistorySubscription =
        LocalDataChangeNotifier.searchHistoryChangedStream.listen((_) async {
      await _loadInitialSearchHistory();
      if (mounted) {
        setState(() {});
      }
    });

    // Listen to sync service streams for remote search history updates from other devices
    _syncSearchHistorySubscription =
        SupabaseSyncService.searchHistoryChangedStream.listen((_) async {
      await _loadInitialSearchHistory();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _localSearchHistorySubscription.cancel();
    _syncSearchHistorySubscription.cancel();
    super.dispose();
  }

  Future<void> _loadInitialSearchHistory() async {
    setState(() => _isLoading = true);
    try {
      final searchHistory =
          await SearchDatabase.getSearchHistoryPaginated(0, _pageSize);
      setState(() {
        _searchHistoryItems = searchHistory;
        _currentOffset = searchHistory.length;
        _hasMoreData = searchHistory.length == _pageSize;
      });
      setState(() => _isLoading = false);
    } catch (e) {
      _isLoading = false;
      _hasMoreData = false;
    }
  }

  Future<void> _loadMoreSearchHistory() async {
    if (_isLoading || !_hasMoreData) return;

    setState(() => _isLoading = true);
    try {
      final moreSearchHistory = await SearchDatabase.getSearchHistoryPaginated(
          _currentOffset, _pageSize);

      if (mounted) {
        setState(() {
          _searchHistoryItems =
              List<Map<String, dynamic>>.from(_searchHistoryItems)
                ..addAll(moreSearchHistory);
          _currentOffset = _searchHistoryItems.length;
          _hasMoreData = moreSearchHistory.length == _pageSize;
        });
      }
    } catch (e) {
      _isLoading = false;
      _hasMoreData = false;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreSearchHistory();
    }
  }

  void _updateSearchQuery(String query, Map<String, dynamic> h) {
    Navigator.pop(context);
    // Create search options map from current history item
    // Convert INTEGER database values (0/1) to boolean values
    final searchOptions = <String, dynamic>{
      'query': query,
      'useRegex': (h['useRegex'] as bool),
      'useNearby': (h['useNearby'] as bool),
      'useWholeWord': (h['useWholeWord'] as bool),
      'useRedLetter': (h['useRedLetter'] as bool),
      'caseSensitive': (h['caseSensitive'] as bool),
      'bookFilterType': h['bookFilterType'],
      'customBookFilter': h['customBookFilter'],
    };
    widget.onUpdateSearchQuery(searchOptions);
  }

  Future<void> _clearSearchHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text(
            'Are you sure you want to clear all search history? This action cannot be undone.',
            style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Clear',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SearchDatabase.clearSearchHistory();

      setState(() {
        _searchHistoryItems.clear();
        _hasMoreData = false;
      });
    }
  }

  Future<void> _deleteSearchHistoryItem(int itemId, int indexInList) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text('Delete this search history item?',
            style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Delete',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SearchDatabase.deleteSearchHistoryItem(itemId);
        setState(() {
          _searchHistoryItems =
              List<Map<String, dynamic>>.from(_searchHistoryItems)
                ..removeAt(indexInList);
          _currentOffset = _searchHistoryItems.length;
        });
        LocalDataChangeNotifier.notifySearchHistoryChanged();
      } catch (e) {
        if (mounted) {
          showStyledSnackBar(
              context, 'Failed to delete search history item: $e',
              isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: 300,
        height: MediaQuery.of(context).size.height * 0.9,
        child: _searchHistoryItems.isEmpty && !_isLoading
            ? Center(
                child: Text('Saved searches will appear here.',
                    style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(context))))
            : ListView.builder(
                controller: _scrollController,
                itemCount: _searchHistoryItems.length + (_hasMoreData ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _searchHistoryItems.length) {
                    // Loading indicator at the bottom
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final widgets = <Widget>[];

                  // Add date header for first entry or when date changes
                  if (i == 0) {
                    // Always show date header for the first entry
                    final currentDate = DateTime.fromMillisecondsSinceEpoch(
                        _searchHistoryItems[i]['timestamp']);
                    widgets.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          DateFormat('EEEE MMM d, y').format(currentDate),
                          style: TextStyle(
                            fontSize: uiFontSize + 2,
                            fontFamily: uiFontFamily,
                            fontWeight: FontWeight.bold,
                            color: getAdaptiveTextColor(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  } else {
                    // For subsequent entries, check if date changed from previous entry
                    final currentDate = DateTime.fromMillisecondsSinceEpoch(
                        _searchHistoryItems[i]['timestamp']);
                    final previousDate = DateTime.fromMillisecondsSinceEpoch(
                        _searchHistoryItems[i - 1]['timestamp']);

                    if (currentDate.year != previousDate.year ||
                        currentDate.month != previousDate.month ||
                        currentDate.day != previousDate.day) {
                      widgets.add(Divider());
                      widgets.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            DateFormat('EEEE MMM d, y').format(currentDate),
                            style: TextStyle(
                              fontSize: uiFontSize + 2,
                              fontFamily: uiFontFamily,
                              fontWeight: FontWeight.bold,
                              color: getAdaptiveTextColor(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                  }

                  final h = _searchHistoryItems[i];
                  final dt =
                      DateTime.fromMillisecondsSinceEpoch(h['timestamp']);
                  final dateStr =
                      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                  final query = h['query'] as String;

                  // Build comma-separated list of enabled search options
                  List<String> enabledOptions = [];

                  if ((h['useRegex'] as bool)) enabledOptions.add('Regex');
                  if ((h['useNearby'] as bool)) enabledOptions.add('Nearby');
                  if ((h['useWholeWord'] as bool)) {
                    enabledOptions.add('Whole word');
                  }
                  if ((h['useRedLetter'] as bool)) {
                    enabledOptions.add('Red letter');
                  }
                  if ((h['caseSensitive'] as bool)) {
                    enabledOptions.add('Case-sensitive');
                  }

                  //debugPrint('customBookFilter: $h');

                  // Handle book filter options
                  String? bookFilterType = h['bookFilterType'] as String?;

                  String? customBookFilter = h['customBookFilter'] as String?;
                  if (customBookFilter != null && customBookFilter.isNotEmpty) {
                    customBookFilter = customBookFilter
                        .replaceAll(' ', '\u00A0')
                        .replaceAll('-', '\u2011');
                  }

                  // Check raw bookFilterType before processing
                  if (bookFilterType == 'Custom Range' &&
                      customBookFilter != null &&
                      customBookFilter.isNotEmpty) {
                    enabledOptions.add('Book\u00A0filter: $customBookFilter');
                  } else if (bookFilterType != null &&
                      bookFilterType.isNotEmpty &&
                      bookFilterType != 'All Books') {
                    // Process for display
                    String displayValue = bookFilterType
                        .replaceAll(' ', '\u00A0')
                        .replaceAll('/', '\uFeFF/\uFeFF');
                    enabledOptions.add('Book\u00A0filter:\u00A0$displayValue');
                  }

                  // Create the formatted display text
                  final optionsText = enabledOptions.isNotEmpty
                      ? enabledOptions.join(', ')
                      : '';
                  //debugPrint('optionsText: "$optionsText"');

                  // Search history dialog
                  final listTile = ListTile(
                      subtitle: Text.rich(
                        TextSpan(
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context)),
                          children: <TextSpan>[
                            TextSpan(
                              text: query,
                              style: TextStyle(
                                  fontSize: uiFontSize + 2,
                                  fontFamily: uiFontFamily,
                                  fontWeight: FontWeight.normal,
                                  color: getAdaptiveTextColor(context)),
                            ),
                            const TextSpan(text: '\n'),
                            if (optionsText.isNotEmpty)
                              TextSpan(
                                text: optionsText,
                                style: TextStyle(
                                    fontSize: uiFontSize - 2,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context)),
                              ),
                            if (optionsText.isNotEmpty)
                              const TextSpan(text: '\n'),
                            TextSpan(
                                text: dateStr,
                                style: TextStyle(
                                    fontSize: uiFontSize - 2,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context))),
                          ],
                        ),
                      ),
                      onTap: () => {
                            _updateSearchQuery(query, h),
                          },
                      onLongPress: () =>
                          _deleteSearchHistoryItem(h['id'] as int, i));

                  widgets.add(listTile);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widgets,
                  );
                },
              ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _clearSearchHistory,
              child: Text('Clear',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: Colors.red)),
            ),
            TextButton(
              child: Text('Close',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ],
    );
  }
}
