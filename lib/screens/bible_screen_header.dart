// Custom header component to replace AppBar in BibleScreen
import 'package:flutter/material.dart';
import '../main.dart'; // For color notifiers
import '../utils/book_name_converter.dart'; // For book name conversion

class BibleScreenHeader extends StatelessWidget {
  //final bool showViewMenu;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onShowHistory;
  final Future<void> Function()? onShowSearch;
  final VoidCallback? onTitlePressed;
  final String? selectedBook;
  final int? selectedChapter;
  final VoidCallback? onShowNotesSearch;
  final VoidCallback? onShowStrongsDefinitions;
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
    this.onShowStrongsDefinitions,
    this.onShowWebstersDefinitions,
    //this.onShowBookmarksManager,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = _adjustBarColor(
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value,
        context);

    return Container(
      height: 55, // Fixed height for consistent sizing
      color: barColor,
      child: Row(
        children: [
          // Leading area
          SizedBox(
              child: IconButton(
            icon: Icon(
              Icons.menu,
              semanticLabel: 'Main Options Menu',
            ),
            tooltip: 'Options',
            onPressed: onOpenDrawer,
            iconSize: 32,
            padding: EdgeInsets.all(8),
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
          )),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.manage_search_rounded,
                  semanticLabel: 'Search Notes',
                ),
                tooltip: 'Notes Search',
                onPressed: onShowNotesSearch,
                iconSize: 32,
                padding: EdgeInsets.all(8),
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
              IconButton(
                icon: Icon(
                  Icons.menu_book,
                  semanticLabel: 'Show Strong\'s Definitions Lookup',
                ),
                tooltip: 'Strong\'s Definitions',
                onPressed: onShowStrongsDefinitions,
                iconSize: 32,
                padding: EdgeInsets.all(8),
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
            ],
          ),
          // Title area (centered)
          //Expanded(
          Flexible(
            fit: FlexFit.tight,
            child: _buildTitleButton(context),
          ),

          // Actions area
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.library_books,
                  semanticLabel: 'Show Webster\'s 1828 Dictionary',
                ),
                tooltip: 'Webster\'s 1828 Dictionary',
                onPressed: onShowWebstersDefinitions,
                iconSize: 32,
                padding: EdgeInsets.all(8),
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
              // Uncomment if bookmark functionality is added
              // IconButton(
              //   icon: Icon(
              //     Icons.bookmark_border_rounded,
              //     semanticLabel: 'Manage Bookmarks',
              //   ),
              //   tooltip: 'Bookmarks',
              //   onPressed: onShowBookmarksManager,
              //   iconSize: 32,
              //   padding: EdgeInsets.all(8),
              //   color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              // ),
              IconButton(
                icon: Icon(
                  Icons.history,
                  semanticLabel: 'Show Verse Reference History Dialog',
                ),
                tooltip: 'History',
                onPressed: onShowHistory,
                iconSize: 32,
                padding: EdgeInsets.all(8),
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
              IconButton(
                icon: Icon(
                  Icons.search,
                  semanticLabel: 'Goto Search Screen',
                ),
                tooltip: 'Search',
                onPressed: onShowSearch != null
                    ? () async {
                        await onShowSearch!();
                      }
                    : null,
                iconSize: 32,
                padding: EdgeInsets.all(8),
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
            ],
          ),
        ],
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
