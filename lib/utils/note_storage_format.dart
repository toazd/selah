// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show QuillController, Document, QuillControllerConfig, QuillClipboardConfig;
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:flutter_quill/internal.dart';

/// Utilities for handling note storage formats
/// The quill editor delta format is used throughout the app in both local db
/// storage and sync operations for consistency.
class NoteStorageFormat {
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
  // static QuillController createControllerFromNote(String? noteText) {
  //   if (noteText == null || noteText.trim().isEmpty) {
  //     // Create empty document
  //     final document = Document();
  //     return QuillController(
  //       document: document,
  //       selection: const TextSelection.collapsed(offset: 0),
  //     );
  //   }

  //   if (isDeltaFormat(noteText)) {
  //     // Load Delta format directly
  //     final delta = Delta.fromJson(jsonDecode(noteText));
  //     return QuillController(
  //       document: Document.fromDelta(delta),
  //       selection: const TextSelection.collapsed(offset: 0),
  //     );
  //   }

  //   // Unexpected format - treat as plain text for backwards compatibility
  //   final operations = [
  //     {'insert': noteText}
  //   ];
  //   return QuillController(
  //     document: Document.fromDelta(Delta.fromJson(operations)),
  //     selection: const TextSelection.collapsed(offset: 0),
  //   );
  // }

  /// Creates a QuillController from note text with clipboard config to disable rich paste
  static QuillController createControllerFromNoteWithConfig(String? noteText) {
    if (noteText == null || noteText.trim().isEmpty) {
      // Create empty document
      final document = Document();

      // Define custom rules so we can for example disable the automatic link creation
      // which causes a bug when <img> tags are used (the link within the src="" gets
      // turned into an <a href INSIDE of the <img> tag and then of course the <img> doesn't
      // load because it's not valid HTML)
      document.setCustomRules([
        //FormatLinkAtCaretPositionRule(),
        ResolveLineFormatRule(),
        ResolveInlineFormatRule(),
        ResolveImageFormatRule(),
        InsertEmbedsRule(),
        AutoExitBlockRule(),
        PreserveBlockStyleOnInsertRule(),
        PreserveLineStyleOnSplitRule(),
        ResetLineFormatOnNewLineRule(),
        // OMITTED: AutoFormatLinksRule()
        // OMITTED: AutoFormatMultipleLinksRule()
        PreserveInlineStylesRule(),
        CatchAllInsertRule(),
        EnsureEmbedLineRule(),
        PreserveLineStyleOnMergeRule(),
        CatchAllDeleteRule(),
        EnsureLastLineBreakDeleteRule(),
      ]);
      return QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
        config: QuillControllerConfig(
          clipboardConfig: QuillClipboardConfig(enableExternalRichPaste: false),
        ),
      );
    }

    if (isDeltaFormat(noteText)) {
      // Load Delta format directly
      final normalizedText = normalizeLegacyStrongsLinks(noteText);
      final delta = Delta.fromJson(jsonDecode(normalizedText));
      return QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
        config: QuillControllerConfig(
          clipboardConfig: QuillClipboardConfig(enableExternalRichPaste: false),
        ),
      );
    }

    // Unexpected format - treat as plain text for backwards compatibility
    final operations = [
      {'insert': noteText}
    ];
    return QuillController(
      document: Document.fromDelta(Delta.fromJson(operations)),
      selection: const TextSelection.collapsed(offset: 0),
      config: QuillControllerConfig(
        clipboardConfig: QuillClipboardConfig(enableExternalRichPaste: false),
      ),
    );
  }

  /// Converts a Delta document to JSON string for storage
  static String deltaToJsonString(Document document) {
    return jsonEncode(document.toDelta().toJson());
  }

  /// Converts legacy Strong's link attributes to the canonical scheme.
  static String normalizeLegacyStrongsLinks(String text) {
    final deltaText = ensureDeltaFormat(text);
    if (!isDeltaFormat(deltaText)) {
      return deltaText;
    }

    final operations = (jsonDecode(deltaText) as List)
        .map((operation) => Map<String, dynamic>.from(operation as Map))
        .toList();
    var changed = false;

    for (final operation in operations) {
      final attributes = operation['attributes'];
      if (attributes is! Map) continue;

      final link = attributes['link'];
      if (link is String && link.startsWith('strongs://')) {
        operation['attributes'] = {
          ...Map<String, dynamic>.from(attributes),
          'link': 's://${link.substring('strongs://'.length)}',
        };
        changed = true;
      }
    }

    return changed ? jsonEncode(operations) : deltaText;
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
