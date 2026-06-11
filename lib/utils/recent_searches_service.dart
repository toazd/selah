import 'package:shared_preferences/shared_preferences.dart';

/// Manages a list of recent search strings saved in SharedPreferences.
/// Supports separate namespaces so different screens can maintain their own lists.
class RecentSearchesService {
  static const int _maxItems = 5;
  static const String _keyPrefix = 'recent_searches_';

  /// Retrieve the recent searches list for the given [namespace].
  /// Returns most recent first. Never null.
  static Future<List<String>> getRecent(String namespace) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('$_keyPrefix$namespace');
    return list ?? [];
  }

  /// Add a [query] to the recent searches list for [namespace].
  /// Duplicates are moved to the front. List is capped at [_maxItems].
  static Future<void> addSearch(String namespace, String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$namespace';
    final list = prefs.getStringList(key) ?? [];

    list.remove(query); // Remove any existing duplicate
    list.insert(0, query); // Insert at front (most recent)

    // Trim to max items
    if (list.length > _maxItems) {
      list.removeRange(_maxItems, list.length);
    }

    await prefs.setStringList(key, list);
  }

  /// Manually filter the cached suggestions. If [query] is empty, returns the
  /// full list; otherwise returns items that contain [query] (case-insensitive).
  static List<String> filter(List<String> recent, String query) {
    if (query.trim().isEmpty) {
      return recent;
    }
    final lower = query.trim().toLowerCase();
    return recent.where((s) => s.toLowerCase().contains(lower)).toList();
  }
}
