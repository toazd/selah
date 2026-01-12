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

class QuillNoteDisplay extends StatefulWidget {
  final String noteText;
  final Function(String, String?)? onLinkTap;
  final RegExp? highlightRegex;
  final VoidCallback? onTap;

  const QuillNoteDisplay({
    super.key,
    required this.noteText,
    this.onLinkTap,
    this.highlightRegex,
    this.onTap,
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
    if (oldWidget.noteText != widget.noteText) {
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
      final delta = Delta.fromJson(jsonDecode(noteText));
      document = Document.fromDelta(delta);
    } else {
      // Plain text fallback for backwards compatibility
      final operations = [
        {'insert': noteText}
      ];
      document = Document.fromDelta(Delta.fromJson(operations));
    }

    // Add verse reference links if the plain text contains a colon (potential verse reference)
    final plainText = document.getPlainText(0, document.length);
    if (plainText.contains(':')) {
      document = VerseReferenceLinker.addVerseReferenceLinks(document);
    }

    return QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  void _handleLinkTap(String? link) {
    _linkWasTapped = true;
    if (link != null && widget.onLinkTap != null) {
      // Get the text of the link from the document if possible
      widget.onLinkTap!(link, null);
    }
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
              customLinkPrefixes: const ['verse://', 'verse:'],
              onLaunchUrl: _handleLinkTap,
              customStyles: DefaultStyles(
                paragraph: DefaultTextBlockStyle(
                  TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      currentNoteFontFamily,
                      fontSizeNotifier.value - 4,
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
                    fontSizeNotifier.value - 4,
                  ),
                  fontFamily: currentNoteFontFamily,
                ),
                lists: DefaultListBlockStyle(
                  TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                      currentNoteFontFamily,
                      fontSizeNotifier.value - 4,
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
                      'Roboto Mono',
                      fontSizeNotifier.value - 4,
                    ),
                    fontFamily: 'Roboto Mono',
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
                      fontSizeNotifier.value - 4,
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
                      'Roboto Mono',
                      fontSizeNotifier.value - 4,
                    ),
                    fontFamily: 'Roboto Mono',
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
