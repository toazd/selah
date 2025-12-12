import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillController, Document;
import 'package:flutter_quill/quill_delta.dart' show Delta;

/// Utilities for handling note storage formats
/// The quill editor delta format is used throughout the app in both local db
/// storage and sync operations for consistency.
class NoteStorageFormat {
  /// Normalizes newlines in both plain text and Delta format
  /// Removes ONLY trailing blank lines (after any regular note text)
  /// Preserves intentional blank lines within the note content
//   static Delta normalizeNewlines(Delta delta) {
//     final operations = delta.toJson();
//     if (operations.isEmpty) return delta;

//     // Find the last non-blank operation index
//     int lastNonBlankIndex = -1;
//     for (int i = operations.length - 1; i >= 0; i--) {
//       final op = operations[i];
//       if (op['insert'] is String) {
//         final text = op['insert'] as String;
//         // Check if this operation contains only newlines (any number)
//         if (text.trim().isEmpty && text.contains('\n')) {
//           // This operation contains only newlines - skip it
//           continue;
//         } else {
//           // Found non-blank content
//           lastNonBlankIndex = i;
//           break;
//         }
//       } else {
//         // Non-text operation (like embeds) - consider non-blank
//         lastNonBlankIndex = i;
//         break;
//       }
//     }

//     // If all operations are blank, return single newline
//     if (lastNonBlankIndex == -1) {
//       return Delta.fromJson([
//         {'insert': '\n'}
//       ]);
//     }

//     // Remove all blank lines AFTER the last non-blank content
//     final processedOperations = operations.sublist(0, lastNonBlankIndex + 1);

// // Ensure the last operation ends with exactly one newline
//     if (processedOperations.isNotEmpty) {
//       final lastOp = processedOperations.last;
//       if (lastOp['insert'] is String) {
//         final lastText = lastOp['insert'] as String;

//         // Ensure the last operation ends with exactly one newline
//         if (!lastText.endsWith('\n')) {
//           // Add a newline if it doesn't end with one
//           // Check if the last operation has list attributes that should be preserved
//           final lastAttributes = lastOp['attributes'] as Map<String, dynamic>?;
//           if (lastAttributes != null && lastAttributes.containsKey('list')) {
//             // Preserve list attributes when adding the final newline
//             processedOperations.add({'insert': '\n', 'attributes': lastAttributes});
//           } else {
//             // No list attributes, add plain newline
//             processedOperations.add({'insert': '\n'});
//           }
//         } else {
//           // If it ends with multiple newlines, trim to one
//           final trimmedText = lastText.replaceAll(RegExp(r'\n+$'), '\n');
//           if (trimmedText != lastText) {
//             processedOperations[processedOperations.length - 1] = {'insert': trimmedText, if (lastOp['attributes'] != null) 'attributes': lastOp['attributes']};
//           }
//         }
//       } else {
//         // Non-text operation - add a newline after it
//         processedOperations.add({'insert': '\n'});
//       }
//     } else {
//       // No operations - add a single newline
//       processedOperations.add({'insert': '\n'});
//     }

//     return Delta.fromJson(processedOperations);
//   }

  /// Detects if a note text is in Delta JSON format
  static bool isDeltaFormat(String noteText) {
    if (noteText.trim().isEmpty) return false;

    try {
      final decoded = jsonDecode(noteText);
      // Check if it's a valid Delta structure (list of operations)
      if (decoded is List) {
        return decoded.every((op) => op is Map && op.containsKey('insert'));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Creates a QuillController from note text
  static QuillController createControllerFromNote(String? noteText) {
    if (noteText == null || noteText.trim().isEmpty) {
      // Create empty document
      final document = Document();
      return QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    if (isDeltaFormat(noteText)) {
      // Load Delta format directly
      final delta = Delta.fromJson(jsonDecode(noteText));
      return QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    // Unexpected format - treat as plain text for backwards compatibility
    final operations = [
      {'insert': noteText}
    ];
    return QuillController(
      document: Document.fromDelta(Delta.fromJson(operations)),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// Converts a Delta document to JSON string for storage
  static String deltaToJsonString(Document document) {
    return jsonEncode(document.toDelta().toJson());
  }

  /// Ensures text is in Delta JSON format
  static String ensureDeltaFormat(String text) {
    if (text.trim().isEmpty) {
      // Return empty Delta document
      return jsonEncode([
        {'insert': '\n'}
      ]);
    }

    if (isDeltaFormat(text)) {
      // Already in Delta format
      return text;
    }

    // Convert plain text to Delta for backwards compatibility
    final operations = [
      {'insert': text}
    ];
    return jsonEncode(operations);
  }
}
