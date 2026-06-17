// Custom widget for displaying notes using QuillEditor in read-only mode
// with clickable verse reference links
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import '../utils/note_storage_format.dart';
import '../utils/verse_reference_linker.dart';
import '../main.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';
import 'dart:io';

class QuillNoteDisplay extends StatefulWidget {
  final String noteText;
  final Function(String, String?)? onLinkTap;
  final RegExp? highlightRegex;
  final Color? highlightColor;
  final VoidCallback? onTap;
  final bool autoLinkVerseReferences;

  const QuillNoteDisplay({
    super.key,
    required this.noteText,
    this.onLinkTap,
    this.highlightRegex,
    this.highlightColor,
    this.onTap,
    // Whether or not to automatically parse and create verse reference links for this data
    this.autoLinkVerseReferences = true,
  });

  @override
  State<QuillNoteDisplay> createState() => _QuillNoteDisplayState();
}

class _QuillNoteDisplayState extends State<QuillNoteDisplay> {
  late QuillController _controller;
  late FocusNode _focusNode;
  late ScrollController _scrollController;
  bool _linkWasTapped = false;

  @override
  void initState() {
    super.initState();
    _controller = _createControllerFromNote(widget.noteText);
    _focusNode = FocusNode();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(QuillNoteDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteText != widget.noteText ||
        oldWidget.autoLinkVerseReferences != widget.autoLinkVerseReferences) {
      _controller.dispose();
      _controller = _createControllerFromNote(widget.noteText);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Creates a QuillController from note text with verse links added
  QuillController _createControllerFromNote(String noteText) {
    if (noteText.trim().isEmpty) {
      return QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    }

    Document document;
    if (NoteStorageFormat.isDeltaFormat(noteText)) {
      final decoded = jsonDecode(noteText);
      final normalizedDeltaJson = _ensureDeltaHasTrailingNewline(decoded);
      final delta = Delta.fromJson(normalizedDeltaJson);
      document = Document.fromDelta(delta);
    } else {
      // Plain text fallback for backwards compatibility
      // Quill note data without a newline suffix will throw
      // an exception
      final normalizedPlainText =
          noteText.endsWith('\n') ? noteText : '$noteText\n';
      final operations = [
        {'insert': normalizedPlainText}
      ];
      document = Document.fromDelta(Delta.fromJson(operations));
    }

    // Add verse reference links only when enabled (TSK can ship pre-linked static data).
    if (widget.autoLinkVerseReferences) {
      final plainText = document.getPlainText(0, document.length);
      if (plainText.contains(':')) {
        document = VerseReferenceLinker.addVerseReferenceLinks(document);
      }
    }

    return QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  List<dynamic> _ensureDeltaHasTrailingNewline(dynamic decoded) {
    if (decoded is! List) {
      return const [
        {'insert': '\n'}
      ];
    }

    if (decoded.isEmpty) {
      return const [
        {'insert': '\n'}
      ];
    }

    final normalized = decoded
        .map((op) => op is Map
            ? Map<String, dynamic>.from(op)
            : <String, dynamic>{'insert': op.toString()})
        .toList();

    final last = normalized.last;
    final lastInsert = last['insert'];
    if (lastInsert is String) {
      if (!lastInsert.endsWith('\n')) {
        last['insert'] = '$lastInsert\n';
      }
      return normalized;
    }

    normalized.add({'insert': '\n'});
    return normalized;
  }

  void _handleLinkTap(String? link) {
    _linkWasTapped = true;
    if (link != null && widget.onLinkTap != null) {
      // Get the text of the link from the document if possible
      widget.onLinkTap!(link, null);
    }
  }

  /// Converts note text to plain text for searching/highlighting
  String _getPlainTextFromNote(String noteText) {
    if (noteText.trim().isEmpty) {
      return '';
    }

    if (NoteStorageFormat.isDeltaFormat(noteText)) {
      final delta = Delta.fromJson(jsonDecode(noteText));
      final document = Document.fromDelta(delta);
      return document
          .getPlainText(0, document.length)
          .replaceAll('¶ ', '')
          .replaceAll('\uFFFC', '');
    } else {
      return noteText.replaceAll('¶ ', '').replaceAll('\uFFFC', '');
    }
  }

  /// Builds highlighted text spans from plain text
  TextSpan _buildHighlightedTextSpan(
      String text, TextStyle baseStyle, RegExp regex, Color highlightColor) {
    final spans = <InlineSpan>[];
    int start = 0;

    // Early exit if no matches
    if (!regex.hasMatch(text)) {
      return TextSpan(text: text, style: baseStyle);
    }

    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
            text: text.substring(start, match.start), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: baseStyle.copyWith(
              backgroundColor: highlightColor, fontWeight: FontWeight.bold),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: noteFontFamilyNotifier,
      builder: (context, currentNoteFontFamily, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? darkTextColor.value : lightTextColor.value;
        final verseRefColor = isDark
            ? darkVerseReferenceColor.value
            : lightVerseReferenceColor.value;

        if (widget.noteText.trim().isEmpty) {
          return Text(
            'Error loading note (empty note detected)',
            style: TextStyle(color: Colors.red),
          );
        }

        // When highlighting is requested, show plain text with highlights
        // This is used in search results to show matching text
        if (widget.highlightRegex != null && widget.highlightColor != null) {
          final plainText = _getPlainTextFromNote(widget.noteText);
          final baseStyle = TextStyle(
            fontSize: FontSizeAdjustments.getAdjustedSize(
              currentNoteFontFamily,
              // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
              (!kIsWeb &&
                      (Platform.isLinux ||
                          Platform.isWindows ||
                          Platform.isMacOS))
                  ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                  : fontSizeNotifier.value - fontSizeAdjustmentMobile,
            ),
            fontFamily: currentNoteFontFamily,
            color: textColor,
            height: defaultLineHeight,
          );

          final highlightedSpan = _buildHighlightedTextSpan(
            plainText,
            baseStyle,
            widget.highlightRegex!,
            widget.highlightColor!,
          );

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            child: Text.rich(highlightedSpan),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            // If a link was just tapped, onLaunchUrl already handled it
            if (_linkWasTapped) {
              _linkWasTapped = false;
              return;
            }
            // No link was tapped, so open the editor
            widget.onTap?.call();
          },
          child: QuillEditor(
            controller: _controller,
            focusNode: _focusNode,
            scrollController: _scrollController,
            config: QuillEditorConfig(
              enableInteractiveSelection: false,
              enableSelectionToolbar: false,
              showCursor: false,
              autoFocus: false,
              expands: false,
              scrollable: false,
              embedBuilders: kIsWeb
                  ? FlutterQuillEmbeds.editorWebBuilders()
                  : FlutterQuillEmbeds.editorBuilders(),
              customLinkPrefixes: const ['v://', 'v:'],
              onLaunchUrl: _handleLinkTap,
              customStyles: DefaultStyles(
                paragraph: DefaultTextBlockStyle(
                  TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      currentNoteFontFamily,
                      // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
                      (!kIsWeb &&
                              (Platform.isLinux ||
                                  Platform.isWindows ||
                                  Platform.isMacOS))
                          ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                          : fontSizeNotifier.value - fontSizeAdjustmentMobile,
                    ),
                    fontFamily: currentNoteFontFamily,
                    color: textColor,
                    height: defaultLineHeight,
                  ),
                  const HorizontalSpacing(0, 0),
                  const VerticalSpacing(0, 0),
                  const VerticalSpacing(0, 0),
                  null,
                ),
                link: TextStyle(
                  color: verseRefColor,
                  decoration: TextDecoration.none,
                  fontSize: FontSizeAdjustments.getAdjustedSize(
                    currentNoteFontFamily,
                    // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
                    (!kIsWeb &&
                            (Platform.isLinux ||
                                Platform.isWindows ||
                                Platform.isMacOS))
                        ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                        : fontSizeNotifier.value - fontSizeAdjustmentMobile,
                  ),
                  fontFamily: currentNoteFontFamily,
                ),
                lists: DefaultListBlockStyle(
                  TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      currentNoteFontFamily,
                      // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
                      (!kIsWeb &&
                              (Platform.isLinux ||
                                  Platform.isWindows ||
                                  Platform.isMacOS))
                          ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                          : fontSizeNotifier.value - fontSizeAdjustmentMobile,
                    ),
                    fontFamily: currentNoteFontFamily,
                    color: textColor,
                    height: defaultLineHeight,
                  ),
                  const HorizontalSpacing(0, 0),
                  const VerticalSpacing(0, 0),
                  const VerticalSpacing(0, 0),
                  null,
                  null,
                ),
                code: DefaultTextBlockStyle(
                  TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      noteFontFamilyNotifier.value,
                      // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
                      (!kIsWeb &&
                              (Platform.isLinux ||
                                  Platform.isWindows ||
                                  Platform.isMacOS))
                          ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                          : fontSizeNotifier.value - fontSizeAdjustmentMobile,
                    ),
                    fontFamily: noteFontFamilyNotifier.value,
                    color: isDark
                        ? Colors.blue.shade200
                        : Colors.blue.shade900.withValues(alpha: 0.9),
                  ),
                  const HorizontalSpacing(0, 0),
                  const VerticalSpacing(4, 4),
                  const VerticalSpacing(0, 0),
                  BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                quote: DefaultTextBlockStyle(
                  TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      currentNoteFontFamily,
                      // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
                      (!kIsWeb &&
                              (Platform.isLinux ||
                                  Platform.isWindows ||
                                  Platform.isMacOS))
                          ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                          : fontSizeNotifier.value - fontSizeAdjustmentMobile,
                    ),
                    fontFamily: currentNoteFontFamily,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                  const HorizontalSpacing(0, 0),
                  const VerticalSpacing(4, 4),
                  const VerticalSpacing(6, 2),
                  BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 4,
                        color: isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                inlineCode: InlineCodeStyle(
                  backgroundColor:
                      isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  radius: const Radius.circular(3),
                  style: TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      noteFontFamilyNotifier.value,
                      // Adjust note/TSK font size depending on platform (-8 looks good on desktop but not on mobile)
                      (!kIsWeb &&
                              (Platform.isLinux ||
                                  Platform.isWindows ||
                                  Platform.isMacOS))
                          ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
                          : fontSizeNotifier.value - fontSizeAdjustmentMobile,
                    ),
                    fontFamily: noteFontFamilyNotifier.value,
                    color: isDark
                        ? Colors.blue.shade200
                        : Colors.blue.shade900.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
