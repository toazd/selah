import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';

import '../database/strongs_definitions_database.dart';
import '../main.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';

class StrongsDefinitionDialog {
  static Future<void> show(
    BuildContext context,
    String strongsNumber,
  ) async {
    final definition = StrongsDefinitionsDatabase.getDefinition(strongsNumber);
    if (!context.mounted || definition == null) {
      if (context.mounted) {
        showStyledSnackBar(
          context,
          'Definition not found for $strongsNumber',
          isError: true,
        );
      }
      return;
    }

    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final maxWidth = MediaQuery.of(context).size.width * 0.9;
    final constrainedMaxWidth = isMobile
        ? MediaQuery.of(context).size.width
        : (maxWidth > 720.0 ? 720.0 : maxWidth);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0)
            : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        title: Text(
          strongsNumber,
          style: primaryTextStyle(dialogContext, uiFontSize + 4),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constrainedMaxWidth,
            maxHeight: maxHeight,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: buildDefinitionWidgets(dialogContext, definition),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final plain =
                  '$strongsNumber\n${StrongsDefinitionsDatabase.stripHtml(definition)}';
              Clipboard.setData(ClipboardData(text: plain));
              showStyledSnackBar(
                dialogContext,
                'Definition copied to clipboard',
              );
            },
            child: Text('Copy', style: textStyle(dialogContext, uiFontSize)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close', style: textStyle(dialogContext, uiFontSize)),
          ),
        ],
      ),
    );
  }

  static List<Widget> buildDefinitionWidgets(
    BuildContext context,
    String definition, {
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    final baseStyle = textStyle(context, uiFontSize);
    final strongsRegExp = RegExp(r'[GH]\d{1,4}');
    final html = definition.replaceAllMapped(strongsRegExp, (match) {
      final strongsNumber = match.group(0)!;
      return '<a href="strongs://$strongsNumber">$strongsNumber</a>';
    });

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Html(
            data: html,
            onLinkTap: (String? url, Map<String, String> attributes, _) {
              if (url == null || !url.startsWith('strongs://')) return;
              final strongsNumber = url.substring('strongs://'.length);
              if (onStrongsTap != null) {
                onStrongsTap(strongsNumber);
              } else {
                show(context, strongsNumber);
              }
            },
            style: {
              'body': Style(
                fontSize: FontSize(uiFontSize),
                fontFamily: fontFamilyNotifier.value,
                color: baseStyle.color,
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                lineHeight: const LineHeight(1.5),
              ),
              'a': Style(
                color: Theme.of(context).brightness == Brightness.dark
                    ? darkPrimaryColor.value
                    : lightPrimaryColor.value,
                textDecoration: TextDecoration.none,
                fontWeight: FontWeight.bold,
              ),
            },
          ),
        ),
      ),
    ];
  }

  static TextStyle primaryTextStyle(BuildContext context, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
        fontFamilyNotifier.value,
        fontSize,
      ),
      color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
    );
  }

  static TextStyle textStyle(
    BuildContext context,
    double fontSize, {
    bool bold = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
        fontFamilyNotifier.value,
        fontSize + 2,
      ),
      fontWeight: bold ? FontWeight.bold : null,
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
  }
}
