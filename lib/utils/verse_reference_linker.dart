// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter_quill/flutter_quill.dart' show Document, LinkAttribute;
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'verse_reference_detector.dart';

/// Utility class for adding verse reference links to Quill documents
class VerseReferenceLinker {
  /// Checks if a specific range in a Quill document already has link attributes
  static bool hasLinkAtRange(Document document, int startIndex, int length) {
    try {
      final delta = document.toDelta();
      final operations = delta.toList();

      int currentPosition = 0;
      final endIndex = startIndex + length;
      int coveredByLink = 0;

      for (final operation in operations) {
        final data = operation.data;
        final opLength = data is String ? data.length : 0;
        final opStart = currentPosition;
        final opEnd = currentPosition + opLength;

        // Check if this operation overlaps with our target range
        if (opStart < endIndex && opEnd > startIndex) {
          // Determine overlap portion
          final overlapStart = opStart < startIndex ? startIndex : opStart;
          final overlapEnd = opEnd > endIndex ? endIndex : opEnd;
          final overlapLength = overlapEnd - overlapStart;

          if (overlapLength > 0) {
            // If this overlapping operation has a link attribute, count how many characters
            // of the target range are already covered by a link.
            if (operation.attributes != null &&
                operation.attributes!.containsKey('link')) {
              coveredByLink += overlapLength;
            }
          }
        }

        currentPosition += opLength;

        // If we've passed the end of our target range, we can stop
        if (currentPosition >= endIndex) {
          break;
        }
      }

      // Only treat the range as already linked if every character is covered
      final fullyLinked = coveredByLink >= length;
      return fullyLinked;
    } catch (e) {
      // If we can't check, assume no link to be safe
      return false;
    }
  }

  /// Adds verse reference links to a Quill document for any plain text references
  /// that haven't been converted to links yet. Existing links are preserved.
  static Document addVerseReferenceLinks(Document document) {
    final plainText = document.getPlainText(0, document.length);
    final references = VerseReferenceDetector.detectReferences(plainText);

    if (references.isEmpty) {
      return document; // No references found, return original
    }

    // Create a new document with links using the current document
    final newDocument = Document.fromDelta(document.toDelta());

    // Sort references in descending order by startIndex to avoid position shifting
    final sortedReferences = references.toList()
      ..sort((a, b) => b.startIndex.compareTo(a.startIndex));

    for (final reference in sortedReferences) {
      try {
        // Check if this specific range already has link formatting
        if (hasLinkAtRange(
            newDocument, reference.startIndex, reference.originalText.length)) {
          // Skip this reference - it's already a link
          continue;
        }

        // Preserve the exact verse spec from the matched text whenever possible.
        // This supports single, dash ranges, comma lists, and mixed forms.
        String verseSpec = '';
        final colonIndex = reference.originalText.indexOf(':');
        if (colonIndex != -1 &&
            colonIndex + 1 < reference.originalText.length) {
          verseSpec = reference.originalText
              .substring(colonIndex + 1)
              .replaceAll(RegExp(r'\s+'), '');
        }

        if (verseSpec.isEmpty && reference.endVerse != null) {
          // This is a range like "Gen 1:4-6"
          verseSpec = '${reference.verse}-${reference.endVerse}';
        } else if (verseSpec.isEmpty) {
          // Single verse
          verseSpec = reference.verse.toString();
        }

        final linkData =
            'v://${reference.book}/${reference.chapter}/$verseSpec';

        // Format the text at the reference position as a link
        newDocument.format(
          reference.startIndex,
          reference.originalText.length,
          LinkAttribute(linkData),
        );
      } catch (e) {
        // Silently skip if formatting fails
        continue;
      }
    }

    return newDocument;
  }

  /// Removes all v:// links from a Quill document (for editing existing notes)
  /// This prevents stale links when users edit previously saved notes
  static Document removeVerseLinksForEditing(Document document) {
    try {
      final delta = document.toDelta();
      final operations = delta.toList();
      final cleanedOperations = <dynamic>[];

      for (final operation in operations) {
        if (operation.attributes != null &&
            operation.attributes!.containsKey('link')) {
          final linkValue = operation.attributes!['link'] as String?;

          // Handle conversion from the old verse: to the new v:
          if (linkValue != null &&
              (linkValue.startsWith('v://') ||
                  linkValue.startsWith('v:') ||
                  linkValue.startsWith('verse://') ||
                  linkValue.startsWith('verse:'))) {
            // This IS a verse link - remove the link attribute
            final cleanedAttributes =
                Map<String, dynamic>.from(operation.attributes!);
            cleanedAttributes.remove('link');

            cleanedOperations.add({
              'insert': operation.data,
              'attributes':
                  cleanedAttributes.isNotEmpty ? cleanedAttributes : null,
            });
          } else {
            // This has link but is NOT a verse link (keep it)
            cleanedOperations.add(operation.toJson());
          }
        } else {
          // No link attribute at all (plain text, formatting, etc.)
          cleanedOperations.add(operation.toJson());
        }
      }

      return Document.fromDelta(Delta.fromJson(cleanedOperations));
    } catch (e) {
      return document;
    }
  }
}
