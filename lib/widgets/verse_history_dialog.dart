import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../database/history_database.dart';
import '../utils/snackbar_notification.dart'; // For showStyledSnackBar
import '../services/local_data_change_notifier.dart'; // For notifications
import '../services/firestore_sync_service.dart'; // For FirestoreSyncService
import '../utils/preferences_constants.dart'; // For uiFontSize and uiFontFamily
import '../utils/book_name_converter.dart'; // For book name conversion
import '../main.dart'; // For getAdaptiveTextColor

class VerseHistoryDialog extends StatefulWidget {
  final void Function(String?, int?, int?) onUpdateLocation;

  const VerseHistoryDialog({
    super.key,
    required this.onUpdateLocation,
  });

  @override
  State<VerseHistoryDialog> createState() => _VerseHistoryDialogState();
}

class _VerseHistoryDialogState extends State<VerseHistoryDialog> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _historyItems = [];
  bool _isLoading = false;
  bool _hasMoreData = true;
  int _currentOffset = 0;
  static const int _pageSize = 50;

  // Selection mode state
  bool _isSelectMode = false;
  final Set<int> _selectedItemIds = {};

  // Stream subscriptions for real-time updates
  late StreamSubscription _firestoreHistorySubscription;
  late StreamSubscription _localHistorySubscription;

  @override
  bool get wantKeepAlive => true;

  // History dialog
  @override
  void initState() {
    super.initState();
    _loadInitialHistory();
    _scrollController.addListener(_onScroll);

    // Listen to Firestore sync service changes for remote history updates
    _firestoreHistorySubscription = FirestoreSyncService.historyChangedStream.listen((_) async {
      await _loadInitialHistory();
      if (mounted) {
        setState(() {});
      }
    });

    // Listen to local data change notifier for immediate local history updates
    _localHistorySubscription = LocalDataChangeNotifier.historyChangedStream.listen((_) async {
      await _loadInitialHistory();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _firestoreHistorySubscription.cancel();
    _localHistorySubscription.cancel();
    super.dispose();
  }

  Future<void> _loadInitialHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await HistoryDatabase.getHistoryPaginated(0, _pageSize);
      setState(() {
        _historyItems = history
            .map((item) => {
                  ...item,
                  'bookLongName': BookNameConverter.shortNameToLongName(item['book'] as String),
                })
            .toList();
        _currentOffset = history.length;
        _hasMoreData = history.length == _pageSize;
      });

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _historyItems = [];
        _currentOffset = 0;
        _hasMoreData = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_isLoading || !_hasMoreData) return;

    setState(() => _isLoading = true);
    try {
      final moreHistory = await HistoryDatabase.getHistoryPaginated(_currentOffset, _pageSize);

      if (mounted) {
        setState(() {
          // Create a new modifiable list to avoid read-only issues and pre-compute book names
          _historyItems = List<Map<String, dynamic>>.from(_historyItems)
            ..addAll(moreHistory.map((item) => {
                  ...item,
                  'bookLongName': BookNameConverter.shortNameToLongName(item['book'] as String),
                }));
          _currentOffset = _historyItems.length;
          _hasMoreData = moreHistory.length == _pageSize;
        });
      }
    } catch (e) {
      setState(() {
        _historyItems = [];
        _currentOffset = 0;
        _hasMoreData = false;
        _isLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreHistory();
    }
  }

  void _updateLocation(String? book, int? chapter, int? verse) {
    Navigator.pop(context);
    widget.onUpdateLocation(book, chapter, verse);
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text('Are you sure you want to clear all history? This action cannot be undone.',
            style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            child: Text('Cancel',
                style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Clear', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final db = await HistoryDatabase.getDatabase();
        await db.delete('history');
      } finally {
        setState(() {
          _historyItems.clear();
          _hasMoreData = false;
        });
      }
    }
  }

  Future<void> _deleteHistoryItem(int itemId, int indexInList) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text('Delete this history item?',
            style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            child: Text('Cancel',
                style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Delete', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await HistoryDatabase.deleteHistoryItem(itemId);
        setState(() {
          // Create a new modifiable list to avoid read-only issues
          _historyItems = List<Map<String, dynamic>>.from(_historyItems)..removeAt(indexInList);
          _currentOffset = _historyItems.length;
        });
        LocalDataChangeNotifier.notifyHistoryChanged();
      } catch (e) {
        if (mounted) {
          showStyledSnackBar(context, 'Failed to delete history item: $e', isError: true);
        }
      }
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedItemIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text('Delete ${_selectedItemIds.length} selected history items?',
            style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            child: Text('Cancel',
                style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Delete', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Delete each selected item
        for (final itemId in _selectedItemIds) {
          HistoryDatabase.deleteHistoryItem(itemId);
        }

        setState(() {
          // Remove deleted items from the list
          _historyItems = List<Map<String, dynamic>>.from(_historyItems)
              .where((item) => !_selectedItemIds.contains(item['id']))
              .toList();
          _currentOffset = _historyItems.length;
          _selectedItemIds.clear();
          _isSelectMode = false; // Exit select mode after deletion
        });
      } catch (e) {
        if (mounted) {
          showStyledSnackBar(context, 'Failed to delete selected history items: $e', isError: true);
        }
      }
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      _selectedItemIds.clear(); // Clear any previous selection
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AlertDialog(
      content: SizedBox(
        width: 300,
        height: MediaQuery.of(context).size.height * 0.9,
        child: _historyItems.isEmpty && !_isLoading
            ? Center(
                child: Text('No history yet.',
                    style: TextStyle(
                        fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))))
            : ListView.builder(
                controller: _scrollController,
                itemCount: _historyItems.length + (_hasMoreData ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _historyItems.length) {
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
                    final currentDate = DateTime.fromMillisecondsSinceEpoch(_historyItems[i]['timestamp']);
                    widgets.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          DateFormat('EEEE MMM d, y').format(currentDate),
                          style: TextStyle(
                            fontSize: uiFontSize + 2,
                            fontFamily: uiFontFamily,
                            fontWeight: FontWeight.normal,
                            color: getAdaptiveTextColor(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  } else {
                    // For subsequent entries, check if date changed from previous entry
                    final currentDate = DateTime.fromMillisecondsSinceEpoch(_historyItems[i]['timestamp']);
                    final previousDate = DateTime.fromMillisecondsSinceEpoch(_historyItems[i - 1]['timestamp']);

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
                              fontWeight: FontWeight.normal,
                              color: getAdaptiveTextColor(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                  }

                  final h = _historyItems[i];
                  final dt = DateTime.fromMillisecondsSinceEpoch(h['timestamp']);
                  final dateStr =
                      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                  // Convert short book name to full book name for display
                  final fullBookName = h['bookLongName'] as String;
                  final locStr = h['verse'] != null && h['verse'] != 0
                      ? '$fullBookName ${h['chapter']}:${h['verse']}'
                      : '$fullBookName ${h['chapter']}:1';

                  final listTile = ListTile(
                      leading: _isSelectMode
                          ? Checkbox(
                              value: _selectedItemIds.contains(h['id']),
                              onChanged: (bool? selected) {
                                setState(() {
                                  if (selected!) {
                                    _selectedItemIds.add(h['id'] as int);
                                  } else {
                                    _selectedItemIds.remove(h['id'] as int);
                                  }
                                });
                              },
                            )
                          : null,
                      subtitle: Text.rich(
                        TextSpan(
                          style: TextStyle(
                              fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
                          children: <TextSpan>[
                            TextSpan(
                              text: locStr,
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  fontWeight: FontWeight.bold,
                                  color: getAdaptiveTextColor(context)),
                            ),
                            const TextSpan(text: '\n'),
                            TextSpan(
                                text: dateStr,
                                style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context))),
                          ],
                        ),
                      ),
                      onTap: _isSelectMode
                          ? () {
                              setState(() {
                                if (_selectedItemIds.contains(h['id'])) {
                                  _selectedItemIds.remove(h['id']);
                                } else {
                                  _selectedItemIds.add(h['id'] as int);
                                }
                              });
                            }
                          : () => _updateLocation(h['book'], h['chapter'], h['verse'] ?? 1),
                      onLongPress: _isSelectMode
                          ? () {
                              setState(() {
                                if (_selectedItemIds.contains(h['id'])) {
                                  _selectedItemIds.remove(h['id']);
                                } else {
                                  _selectedItemIds.add(h['id'] as int);
                                }
                              });
                            }
                          : () => _deleteHistoryItem(h['id'] as int, i));

                  widgets.add(listTile);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widgets,
                  );
                },
              ),
      ),
      actions: _isSelectMode
          ? [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _selectedItemIds.isEmpty ? null : _deleteSelectedItems,
                    child: Text(
                      'Delete Selected (${_selectedItemIds.length})',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: _selectedItemIds.isEmpty ? Colors.grey : Colors.red,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleSelectMode,
                    child: Text('Done',
                        style: TextStyle(
                            fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                  ),
                ],
              ),
            ]
          : [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _clearHistory,
                    child: Text('Clear',
                        style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _toggleSelectMode,
                        child: Text('Select',
                            style: TextStyle(
                                fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        child: Text('Close',
                            style: TextStyle(
                                fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ],
    );
  }
}
