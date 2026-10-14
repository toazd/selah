// Custom header component to replace AppBar in BibleScreen
import 'package:material_ui/material_ui.dart';
import '../main.dart'; // For color notifiers
import '../utils/book_name_converter.dart'; // For book name conversion

import '../utils/preferences_constants.dart'; // For uiFontSize / uiFontFamily

class BibleScreenHeader extends StatelessWidget {
  //final bool showViewMenu;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onShowHistory;
  final Future<void> Function()? onShowSearch;
  final VoidCallback? onTitlePressed;
  final String? selectedBook;
  final int? selectedChapter;
  final VoidCallback? onShowNotesSearch;
  final VoidCallback? onShowWebstersDefinitions;
  //final VoidCallback? onShowBookmarksManager;

  const BibleScreenHeader({
    super.key,
    //required this.showViewMenu,
    this.onOpenDrawer,
    this.onShowHistory,
    this.onShowSearch,
    this.onTitlePressed,
    this.selectedBook,
    this.selectedChapter,
    this.onShowNotesSearch,
    this.onShowWebstersDefinitions,
    //this.onShowBookmarksManager,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = _adjustBarColor(
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value,
        context);
    final primaryColor =
        isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
    final overflowActions = _buildOverflowActions();

    // Fixed layout: drawer menu on the left, title in the center,
    // and a single 3-dot overflow menu on the right. No width-based
    // dynamic icon logic.
    return Container(
      height: 55, // Fixed height for consistent sizing
      color: barColor,
      child: Row(
        children: [
          _buildHeaderIconButton(
            icon: Icons.menu,
            semanticLabel: 'Main Options Menu',
            tooltip: 'Options',
            onPressed: onOpenDrawer,
            color: primaryColor,
          ),

          // Title area (centered)
          Flexible(
            fit: FlexFit.tight,
            child: _buildTitleButton(context),
          ),

          _buildOverflowMenu(context, overflowActions, primaryColor),
        ],
      ),
    );
  }

  List<_HeaderAction> _buildOverflowActions() {
    void showSearch() {
      final callback = onShowSearch;
      if (callback != null) {
        callback();
      }
    }

    return [
      _HeaderAction(
        id: _HeaderActionId.search,
        icon: Icons.search,
        semanticLabel: 'Goto Search Screen',
        tooltip: 'Open Search Screen',
        onPressed: onShowSearch == null ? null : showSearch,
      ),
      _HeaderAction(
        id: _HeaderActionId.webstersDefinitions,
        icon: Icons.auto_stories,
        semanticLabel: 'Show Webster\'s 1828 Dictionary',
        tooltip: 'Webster\'s 1828 Dictionary',
        onPressed: onShowWebstersDefinitions,
      ),
      _HeaderAction(
        id: _HeaderActionId.history,
        icon: Icons.history,
        semanticLabel: 'Show Verse Reference History Dialog',
        tooltip: 'View Verse History',
        onPressed: onShowHistory,
      ),
      _HeaderAction(
        id: _HeaderActionId.notesSearch,
        icon: Icons.manage_search_rounded,
        semanticLabel: 'Open Search Notes Screen',
        tooltip: 'Open Notes Search Screen',
        onPressed: onShowNotesSearch,
      ),
      // Uncomment if bookmark functionality is added
      // _HeaderAction(
      //   id: _HeaderActionId.bookmarks,
      //   icon: Icons.bookmark_border_rounded,
      //   semanticLabel: 'Manage Bookmarks',
      //   tooltip: 'Bookmarks',
      //   onPressed: onShowBookmarksManager,
      // ),
    ];
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String semanticLabel,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        semanticLabel: semanticLabel,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 32,
      padding: EdgeInsets.all(8),
      color: color,
    );
  }

  Widget _buildOverflowMenu(
    BuildContext context,
    List<_HeaderAction> actions,
    Color primaryColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBackgroundColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    final menuTextColor = isDark ? darkTextColor.value : lightTextColor.value;
    final menuTextStyle = TextStyle(
      fontSize: uiFontSize,
      fontFamily: uiFontFamily,
      color: menuTextColor,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: menuBackgroundColor,
          textStyle: menuTextStyle,
          iconColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(
              color: primaryColor,
              width: 1.0,
            ),
          ),
        ),
      ),
      child: PopupMenuButton<_HeaderActionId>(
        icon: Icon(
          Icons.more_vert,
          semanticLabel: 'More Bible Header Actions',
          color: primaryColor,
        ),
        tooltip: 'More Actions',
        iconSize: 32,
        padding: EdgeInsets.all(8),
        color: menuBackgroundColor,
        onSelected: (id) {
          final action = actions.firstWhere((action) => action.id == id);
          action.onPressed?.call();
        },
        itemBuilder: (context) {
          return [
            for (final action in actions)
              PopupMenuItem<_HeaderActionId>(
                value: action.id,
                enabled: action.onPressed != null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      action.icon,
                      size: 22,
                      color:
                          action.onPressed != null ? primaryColor : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        action.tooltip,
                        style: menuTextStyle.copyWith(
                          color: action.onPressed != null
                              ? menuTextColor
                              : Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ];
        },
      ),
    );
  }

  Widget _buildTitleButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = _adjustBarColor(
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value,
        context);

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // final style = Theme.of(context).textTheme.bodyMedium ??
          //     TextStyle(
          //       fontSize: fontSizeNotifier.value,
          //       fontFamily: fontFamilyNotifier.value,
          //       color: isDark ? darkTextColor.value : lightTextColor.value,
          //     );
          final style = TextStyle(
            fontSize: fontSizeNotifier.value,
            fontFamily: fontFamilyNotifier.value,
            color: isDark ? darkTextColor.value : lightTextColor.value,
          );

          String makeTitle({required bool fullBookName}) {
            if (selectedBook == null || selectedChapter == null) {
              return 'Choose Verse';
            }

            // If fullBookName is true display the longBookName (Genesis), otherwise use the short name (Gen)
            final name = fullBookName
                ? BookNameConverter.shortNameToLongName(selectedBook!)
                : selectedBook;

            // Show just the book name and chapter number
            return '$name ${selectedChapter!}';
          }

          double textWidth(String text, TextStyle style) {
            final tp = TextPainter(
              text: TextSpan(text: text, style: style),
              maxLines: 1,
              textScaler: MediaQuery.textScalerOf(context),
              textDirection: TextDirection.ltr,
            )..layout(minWidth: 0, maxWidth: double.infinity);
            return tp.size.width;
          }

          // Precise available width inside this center slot
          final maxButtonWidth = constraints.maxWidth;

          // Button padding we will apply below
          const double horizontalPad = 16.0;
          final availableForText =
              (maxButtonWidth - (horizontalPad * 2)).clamp(0.0, maxButtonWidth);

          final fullTitle = makeTitle(fullBookName: true);
          final shortTitle = makeTitle(fullBookName: false);
          final label = textWidth(fullTitle, style) <= availableForText
              ? fullTitle
              : shortTitle;

          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _adjustBarColor(barColor, context),
              padding: const EdgeInsets.symmetric(horizontal: horizontalPad),
              minimumSize: Size(availableForText / 4.0, 42), // 54 available
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: onTitlePressed,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSizeNotifier.value - 4,
                fontFamily: fontFamilyNotifier.value,
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          );
        },
      ),
    );
  }

  // Helper function to adjust bar color (keeping existing logic from original code)
  Color _adjustBarColor(Color backgroundColor, BuildContext context) {
    final hsl = HSLColor.fromColor(backgroundColor);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // If dark mode / dark colors, adjust slightly more than light mode / light colors
    if (isDark) {
      final adjustedLightness = hsl.lightness > 0.5
          ? (hsl.lightness - 0.05)
              .clamp(0.0, 1.0) // Darker for light backgrounds
          : (hsl.lightness + 0.05)
              .clamp(0.0, 1.0); // Lighter for dark backgrounds
      return hsl.withLightness(adjustedLightness).toColor();
    } else {
      final adjustedLightness = hsl.lightness > 0.5
          ? (hsl.lightness - 0.02)
              .clamp(0.0, 1.0) // Darker for light backgrounds
          : (hsl.lightness + 0.02)
              .clamp(0.0, 1.0); // Lighter for dark backgrounds
      return hsl.withLightness(adjustedLightness).toColor();
    }
  }
}

enum _HeaderActionId {
  notesSearch,
  webstersDefinitions,
  history,
  search,
}

class _HeaderAction {
  const _HeaderAction({
    required this.id,
    required this.icon,
    required this.semanticLabel,
    required this.tooltip,
    required this.onPressed,
  });

  final _HeaderActionId id;
  final IconData icon;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback? onPressed;
}
