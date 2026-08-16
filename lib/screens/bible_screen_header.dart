// Custom header component to replace AppBar in BibleScreen
import 'package:material_ui/material_ui.dart';
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
    final primaryColor =
        isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
    final actions = _buildHeaderActions();

    return Container(
      height: 55, // Fixed height for consistent sizing
      color: barColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final visibleActionIds =
              _visibleActionIdsForWidth(constraints.maxWidth);
          final visibleActions = actions
              .where((action) => visibleActionIds.contains(action.id))
              .toList();
          final hiddenActions = actions
              .where((action) => !visibleActionIds.contains(action.id))
              .toList();
          final canShowOverflow =
              constraints.maxWidth >= _minTitleWidth + _headerIconExtent;
          final leftActions = visibleActions
              .where((action) => action.side == _HeaderActionSide.left);
          final rightActions = visibleActions
              .where((action) => action.side == _HeaderActionSide.right);

          return Row(
            children: [
              for (final action in leftActions)
                _buildHeaderIconButton(action, primaryColor),

              // Title area (centered)
              //Expanded(
              Flexible(
                fit: FlexFit.tight,
                child: _buildTitleButton(context),
              ),

              for (final action in rightActions)
                _buildHeaderIconButton(action, primaryColor),
              if (hiddenActions.isNotEmpty && canShowOverflow)
                _buildOverflowMenu(hiddenActions, primaryColor),
            ],
          );
        },
      ),
    );
  }

  List<_HeaderAction> _buildHeaderActions() {
    void showSearch() {
      final callback = onShowSearch;
      if (callback != null) {
        callback();
      }
    }

    return [
      _HeaderAction(
        id: _HeaderActionId.menu,
        side: _HeaderActionSide.left,
        icon: Icons.menu,
        semanticLabel: 'Main Options Menu',
        tooltip: 'Options',
        onPressed: onOpenDrawer,
      ),
      _HeaderAction(
        id: _HeaderActionId.notesSearch,
        side: _HeaderActionSide.left,
        icon: Icons.manage_search_rounded,
        semanticLabel: 'Search Notes',
        tooltip: 'Notes Search',
        onPressed: onShowNotesSearch,
      ),
      _HeaderAction(
        id: _HeaderActionId.strongsDefinitions,
        side: _HeaderActionSide.left,
        icon: Icons.menu_book,
        semanticLabel: 'Show Strong\'s Definitions Lookup',
        tooltip: 'Strong\'s Definitions',
        onPressed: onShowStrongsDefinitions,
      ),
      _HeaderAction(
        id: _HeaderActionId.webstersDefinitions,
        side: _HeaderActionSide.right,
        icon: Icons.auto_stories,
        semanticLabel: 'Show Webster\'s 1828 Dictionary',
        tooltip: 'Webster\'s 1828 Dictionary',
        onPressed: onShowWebstersDefinitions,
      ),
      // Uncomment if bookmark functionality is added
      // _HeaderAction(
      //   id: _HeaderActionId.bookmarks,
      //   side: _HeaderActionSide.right,
      //   icon: Icons.bookmark_border_rounded,
      //   semanticLabel: 'Manage Bookmarks',
      //   tooltip: 'Bookmarks',
      //   onPressed: onShowBookmarksManager,
      // ),
      _HeaderAction(
        id: _HeaderActionId.history,
        side: _HeaderActionSide.right,
        icon: Icons.history,
        semanticLabel: 'Show Verse Reference History Dialog',
        tooltip: 'Verse History',
        onPressed: onShowHistory,
      ),
      _HeaderAction(
        id: _HeaderActionId.search,
        side: _HeaderActionSide.right,
        icon: Icons.search,
        semanticLabel: 'Goto Search Screen',
        tooltip: 'Search',
        onPressed: onShowSearch == null ? null : showSearch,
      ),
    ];
  }

  Set<_HeaderActionId> _visibleActionIdsForWidth(double maxWidth) {
    // Wide to narrow: keep the full bar until overflow is needed, then
    // preserve symmetry with only the outer menu and More Actions buttons.
    final visibleActionSets = [
      {
        _HeaderActionId.menu,
        _HeaderActionId.search,
        _HeaderActionId.notesSearch,
        _HeaderActionId.history,
        _HeaderActionId.strongsDefinitions,
        _HeaderActionId.webstersDefinitions,
      },
      {
        _HeaderActionId.menu,
      },
      <_HeaderActionId>{},
    ];

    for (final visibleActionIds in visibleActionSets) {
      final hiddenActionCount = _headerActionCount - visibleActionIds.length;
      final overflowWidth = hiddenActionCount > 0 ? _headerIconExtent : 0.0;
      final reservedWidth =
          (visibleActionIds.length * _headerIconExtent) + overflowWidth;

      if (maxWidth - reservedWidth >= _minTitleWidth) {
        return visibleActionIds;
      }
    }

    return const {};
  }

  Widget _buildHeaderIconButton(_HeaderAction action, Color color) {
    return IconButton(
      icon: Icon(
        action.icon,
        semanticLabel: action.semanticLabel,
      ),
      tooltip: action.tooltip,
      onPressed: action.onPressed,
      iconSize: 32,
      padding: EdgeInsets.all(8),
      color: color,
    );
  }

  Widget _buildOverflowMenu(List<_HeaderAction> actions, Color color) {
    return PopupMenuButton<_HeaderActionId>(
      icon: Icon(
        Icons.more_vert,
        semanticLabel: 'More Bible Header Actions',
        color: color,
      ),
      tooltip: 'More Actions',
      iconSize: 32,
      padding: EdgeInsets.all(8),
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
                  Icon(action.icon, size: 22),
                  const SizedBox(width: 12),
                  Text(action.tooltip),
                ],
              ),
            ),
        ];
      },
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

const double _headerIconExtent = 48.0;
const double _minTitleWidth = 80.0;
const int _headerActionCount = 6;

enum _HeaderActionId {
  menu,
  notesSearch,
  strongsDefinitions,
  webstersDefinitions,
  history,
  search,
}

enum _HeaderActionSide {
  left,
  right,
}

class _HeaderAction {
  const _HeaderAction({
    required this.id,
    required this.side,
    required this.icon,
    required this.semanticLabel,
    required this.tooltip,
    required this.onPressed,
  });

  final _HeaderActionId id;
  final _HeaderActionSide side;
  final IconData icon;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback? onPressed;
}
