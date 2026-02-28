// Utility functions shared across Bible-related screens and components

import 'package:flutter/material.dart';
import 'package:selah/main.dart';
import 'package:selah/utils/preferences_constants.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/book_name_converter.dart';
import '../screens/chapter_dialog.dart';

/// Safely converts dynamic value to integer with fallback
int toInt(dynamic v, {int orElse = 1 << 30}) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? orElse;
  return orElse;
}

/// Shared handler for v:// scheme links that opens ChapterDialog with target verses
/// This eliminates code duplication between BibleScreen and SearchScreen
Future<void> handleVerseLink(
  BuildContext context,
  String link,
  String? referenceText, {
  required Function(String, int, int?)? navigateToVerse,
  Function(String, String?)? onVerseLinkRecursion,
  Function(String, int, int, String?)? onNoteIconTap,
  Function(String, int, int, String?)? onNoteEditTap,
}) async {
  // Remove "unsafe:" prefix if present
  if (link.startsWith('unsafe:')) {
    link = link.replaceFirst('unsafe:', '');
  }

  // Parse v://book/chapter/verse or v://book/chapter/verse/endVerse
  final uri = Uri.parse(link);
  if (uri.scheme == 'v' && uri.host.isNotEmpty) {
    final parts = uri.pathSegments;
    if (parts.length >= 2) {
      final book = uri.host;
      final chapter = int.tryParse(parts[0]);
      final verseSpec = parts[1]; // This could be "5", "5-7", or "5,6,7"

      if (chapter != null) {
        // Parse verse spec in a generalized way:
        // single ("5"), range ("5-7"), list ("5,6,7"), or mixed ("5-7,9,11-12")
        final targetVerses = <int>[];
        final partsSpec = verseSpec.split(',');
        for (final partRaw in partsSpec) {
          final part = partRaw.trim();
          if (part.isEmpty) continue;

          if (part.contains('-')) {
            final rangeParts = part.split('-');
            if (rangeParts.length == 2) {
              final start = int.tryParse(rangeParts[0].trim());
              final end = int.tryParse(rangeParts[1].trim());
              if (start != null && end != null && end >= start) {
                for (int i = start; i <= end; i++) {
                  if (!targetVerses.contains(i)) {
                    targetVerses.add(i);
                  }
                }
              }
            }
          } else {
            final verse = int.tryParse(part);
            if (verse != null && !targetVerses.contains(verse)) {
              targetVerses.add(verse);
            }
          }
        }

        if (targetVerses.isNotEmpty) {
          // Convert book name to proper database format
          final normalizedBook = book.isNotEmpty
              ? BookNameConverter.normalizeShortName(book)
              : book;

          // Create recursive wrapper if needed (for infinite recursion)
          Function(String, String?)? finalOnVerseLink;
          if (onVerseLinkRecursion != null) {
            finalOnVerseLink = onVerseLinkRecursion;
          } else {
            // Create infinite recursion by calling handleVerseLink again with same parameters
            finalOnVerseLink = (recursiveLink, recursiveRefText) =>
                handleVerseLink(
                  context,
                  recursiveLink,
                  recursiveRefText,
                  navigateToVerse: navigateToVerse,
                  onVerseLinkRecursion: null, // This enables infinite recursion
                  onNoteIconTap: onNoteIconTap,
                  onNoteEditTap: onNoteEditTap,
                );
          }

          showDialog(
            context: context,
            builder: (context) => ChapterDialog(
              book: normalizedBook,
              chapter: chapter,
              targetVerses: targetVerses, // New parameter for individual verses
              referenceText: referenceText,
              onVerseLink: finalOnVerseLink, // Pass link handler for navigation
              onNavigateToVerse: navigateToVerse != null
                  ? (verse) => navigateToVerse(normalizedBook, chapter, verse)
                  : null, // Navigate to verse callback
              onNoteIconTap: onNoteIconTap != null
                  ? (verse, noteText) =>
                      onNoteIconTap(normalizedBook, chapter, verse, noteText)
                  : null,
              onNoteEditTap: onNoteEditTap != null
                  ? (verse, noteText) =>
                      onNoteEditTap(normalizedBook, chapter, verse, noteText)
                  : null,
            ),
          );
        }
      }
    }
  } else {
    // Handle external links (not v://) - show confirmation dialog
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          // title: Text(
          //   'Open External Link',
          //   style: TextStyle(
          //     color: isDark ? Colors.white : Colors.black,
          //   ),
          // ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will open the following link in your default browser:',
                style: TextStyle(
                  fontFamily: uiFontFamily,
                  fontSize: uiFontSize,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  link,
                  style: TextStyle(
                    color: getAdaptiveTextColor(
                        context), //isDark ? Colors.white : Colors.black,
                    fontFamily: 'Roboto Mono',
                    fontSize: uiFontSize,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: uiFontFamily,
                  fontSize: uiFontSize,
                  color: getAdaptiveTextColor(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Open Link',
                style: TextStyle(
                  fontFamily: uiFontFamily,
                  fontSize: uiFontSize,
                  color: isDark ? Colors.blue.shade300 : Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldOpen == true) {
      // Launch external URL
      try {
        await launchUrl(Uri.parse(link));
      } catch (e) {
        // Silently handle errors for external URL launching
      }
    }
  }
}
