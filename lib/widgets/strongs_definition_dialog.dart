import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';

import '../database/strongs_definitions_database.dart';
import '../main.dart';
import '../utils/bible_utils.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';
import '../utils/verse_reference_detector.dart';

class StrongsDefinitionDialog {
  static final RegExp _htmlTagPattern = RegExp(r'<[^>]+>');
  static final RegExp _strongsReferencePattern =
      RegExp(r'(^|[^A-Za-z0-9])([GH]\d{1,4})(?![A-Za-z0-9])');
  static const String _strongsLinkPrefix = 'strongs://';

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
          style: primaryTextStyle(dialogContext, uiFontSize),
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
    final html = _linkDefinitionReferencesInHtml(definition);

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Html(
            data: html,
            onLinkTap: (String? url, Map<String, String> attributes, _) {
              if (url == null) return;
              final normalizedUrl = _normalizeInternalLink(url);
              if (normalizedUrl.startsWith(_strongsLinkPrefix)) {
                final strongsNumber =
                    normalizedUrl.substring(_strongsLinkPrefix.length);
                if (onStrongsTap != null) {
                  onStrongsTap(strongsNumber);
                } else {
                  show(context, strongsNumber);
                }
                return;
              }

              if (_isVerseLink(normalizedUrl)) {
                handleVerseLink(
                  context,
                  normalizedUrl,
                  attributes['data-reference-text'],
                  navigateToVerse: null,
                  onVerseLinkRecursion: null,
                  onNoteIconTap: null,
                  onNoteEditTap: null,
                );
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

  // @visibleForTesting
  // static String linkDefinitionReferencesForTesting(String html) {
  //   return _linkDefinitionReferencesInHtml(html);
  // }

  static String _linkDefinitionReferencesInHtml(String html) {
    final buffer = StringBuffer();
    var currentIndex = 0;
    var anchorDepth = 0;

    for (final match in _htmlTagPattern.allMatches(html)) {
      if (match.start > currentIndex) {
        final text = html.substring(currentIndex, match.start);
        buffer.write(anchorDepth > 0 ? text : _linkReferencesInText(text));
      }

      final tag = match.group(0)!;
      final lowerTag = tag.toLowerCase();
      if (RegExp(r'^<\s*a\b').hasMatch(lowerTag)) {
        anchorDepth++;
      } else if (RegExp(r'^<\s*/\s*a\b').hasMatch(lowerTag) &&
          anchorDepth > 0) {
        anchorDepth--;
      }

      buffer.write(tag);
      currentIndex = match.end;
    }

    if (currentIndex < html.length) {
      final text = html.substring(currentIndex);
      buffer.write(anchorDepth > 0 ? text : _linkReferencesInText(text));
    }

    return buffer.toString();
  }

  static String _linkReferencesInText(String text) {
    final linkCandidates = <_DefinitionLinkCandidate>[];

    for (final reference in VerseReferenceDetector.detectReferences(text)) {
      linkCandidates.add(
        _DefinitionLinkCandidate(
          startIndex: reference.startIndex,
          endIndex: reference.startIndex + reference.originalText.length,
          href: _verseLinkForReference(reference),
          referenceText: reference.originalText,
        ),
      );
    }

    for (final match in _strongsReferencePattern.allMatches(text)) {
      final prefixText = match.group(1) ?? '';
      final strongsNumber = match.group(2);
      if (strongsNumber == null) continue;

      final startIndex = match.start + prefixText.length;
      linkCandidates.add(
        _DefinitionLinkCandidate(
          startIndex: startIndex,
          endIndex: startIndex + strongsNumber.length,
          href: '$_strongsLinkPrefix$strongsNumber',
        ),
      );
    }

    if (linkCandidates.isEmpty) {
      return text;
    }

    linkCandidates.sort((a, b) {
      final startCompare = a.startIndex.compareTo(b.startIndex);
      if (startCompare != 0) return startCompare;
      return b.length.compareTo(a.length);
    });

    final acceptedLinks = <_DefinitionLinkCandidate>[];
    var lastEnd = -1;
    for (final candidate in linkCandidates) {
      if (candidate.startIndex < lastEnd) continue;
      acceptedLinks.add(candidate);
      lastEnd = candidate.endIndex;
    }

    if (acceptedLinks.isEmpty) {
      return text;
    }

    final buffer = StringBuffer();
    var currentIndex = 0;
    for (final link in acceptedLinks) {
      buffer.write(text.substring(currentIndex, link.startIndex));
      final linkedText = text.substring(link.startIndex, link.endIndex);
      buffer.write('<a href="${_escapeHtmlAttribute(link.href)}"');
      if (link.referenceText != null) {
        buffer.write(
          ' data-reference-text="'
          '${_escapeHtmlAttribute(link.referenceText!)}"',
        );
      }
      buffer.write('>$linkedText</a>');
      currentIndex = link.endIndex;
    }
    buffer.write(text.substring(currentIndex));
    return buffer.toString();
  }

  static String _verseLinkForReference(VerseReference reference) {
    var verseSpec = '';
    final colonIndex = reference.originalText.indexOf(':');
    if (colonIndex != -1 && colonIndex + 1 < reference.originalText.length) {
      verseSpec = reference.originalText
          .substring(colonIndex + 1)
          .replaceAll(RegExp(r'\s+'), '');
    }

    if (verseSpec.isEmpty && reference.endVerse != null) {
      verseSpec = '${reference.verse}-${reference.endVerse}';
    } else if (verseSpec.isEmpty) {
      verseSpec = reference.verse.toString();
    }

    return 'v://${reference.book}/${reference.chapter}/$verseSpec';
  }

  static String _escapeHtmlAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String _normalizeInternalLink(String link) {
    return link.startsWith('unsafe:') ? link.substring('unsafe:'.length) : link;
  }

  static bool _isVerseLink(String link) {
    return link.startsWith('v://') ||
        link.startsWith('v:') ||
        link.startsWith('verse://') ||
        link.startsWith('verse:');
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

class _DefinitionLinkCandidate {
  final int startIndex;
  final int endIndex;
  final String href;
  final String? referenceText;

  const _DefinitionLinkCandidate({
    required this.startIndex,
    required this.endIndex,
    required this.href,
    this.referenceText,
  });

  int get length => endIndex - startIndex;
}
