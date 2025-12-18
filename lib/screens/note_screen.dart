import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../database/notes_database.dart';
import '../main.dart';
import '../utils/book_name_converter.dart';
import '../utils/preferences_constants.dart';
import '../utils/note_storage_format.dart';
import '../utils/verse_reference_linker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../utils/font_size_adjustments.dart';

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor) {
  final hsl = HSLColor.fromColor(backgroundColor);
  // If lightness > 0.5 (light color), make slightly darker; otherwise make slightly lighter
  final adjustedLightness = hsl.lightness > 0.5
      ? (hsl.lightness - 0.03).clamp(0.0, 1.0) // Darker for light backgrounds
      : (hsl.lightness + 0.03).clamp(0.0, 1.0); // Lighter for dark backgrounds
  return hsl.withLightness(adjustedLightness).toColor();
}

class NoteScreen extends StatefulWidget {
  final String book;
  final int chapter;
  final int verse;
  final String? existingNote;

  const NoteScreen({
    super.key,
    required this.book,
    required this.chapter,
    required this.verse,
    this.existingNote,
  });

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  int _existingCreatedAt = 0;
  late String _originalContentHash;
  late QuillController _quillController;
  late FocusNode _focusNode;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();

    // Create QuillController from existing note, auto-detecting format
    _quillController = NoteStorageFormat.createControllerFromNoteWithConfig(
        widget.existingNote);

    // If this is an existing note, clean verse links to prevent stale links during editing
    if (widget.existingNote != null && widget.existingNote!.isNotEmpty) {
      final cleanedDocument = VerseReferenceLinker.removeVerseLinksForEditing(
          _quillController.document);

      _quillController.document = cleanedDocument;
    }

    // Create focus node for auto-focus
    _focusNode = FocusNode();

    // Create scroll controller
    _scrollController = ScrollController();

    // Auto-focus the editor after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    // Set created_at for sync operations and store original content hash
    if (widget.existingNote != null && widget.existingNote!.isNotEmpty) {
      try {
        NotesDatabase.getNoteForVerse(widget.book, widget.chapter, widget.verse)
            .then((existingRecord) {
          if (existingRecord != null && mounted) {
            setState(
                () => _existingCreatedAt = existingRecord['created_at'] as int);
            // Store original content hash for change detection
            setState(() => _originalContentHash =
                widget.existingNote!.hashCode.toString());
          }
        });
      } catch (e) {
        _existingCreatedAt = 0;
      }
    } else {
      // New note - no original content
      _originalContentHash = '';
    }
  }

  @override
  void dispose() {
    _quillController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _contentHasChanged() {
    final currentContent =
        NoteStorageFormat.deltaToJsonString(_quillController.document);
    return _originalContentHash != currentContent.hashCode.toString();
  }

  Widget _buildToolbar(Color iconColor) {
    return Wrap(
      spacing: 0.0,
      runSpacing: 0.0,
      children: [
        QuillToolbarHistoryButton(
          controller: _quillController,
          isUndo: true,
          options: QuillToolbarHistoryButtonOptions(
            tooltip: 'Undo',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        QuillToolbarHistoryButton(
          controller: _quillController,
          isUndo: false,
          options: QuillToolbarHistoryButtonOptions(
            tooltip: 'Redo',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        const SizedBox(width: 4),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.bold,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Bold',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.italic,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Italic',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.underline,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Underline',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        const SizedBox(width: 4),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.subscript,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Subscript',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.superscript,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Superscript',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),

        const SizedBox(width: 4),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.ol,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Numbered List',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        QuillToolbarToggleStyleButton(
          attribute: Attribute.ul,
          controller: _quillController,
          options: QuillToolbarToggleStyleButtonOptions(
            tooltip: 'Bullet List',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        const SizedBox(width: 4),
        QuillToolbarClearFormatButton(
          controller: _quillController,
          options: QuillToolbarClearFormatButtonOptions(
            tooltip: 'Clear Format',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        // Indenting doesn't display correctly with the html widget
        /*
        const SizedBox(width: 4),
        QuillToolbarIndentButton(
          controller: _quillController,
          isIncrease: true,
          options: QuillToolbarIndentButtonOptions(
            tooltip: 'Increase Indent',
            iconSize: 18,
            afterButtonPressed: () {
              _focusNode.requestFocus();
            },
            iconTheme: QuillIconTheme(
                iconButtonUnselectedData: IconButtonData(color: iconColor),
                iconButtonSelectedData: IconButtonData(color: iconColor)),
          ),
        ),
        QuillToolbarIndentButton(
          controller: _quillController,
          isIncrease: false,
          options: QuillToolbarIndentButtonOptions(
              tooltip: 'Decrease Indent',
              iconSize: 18,
              afterButtonPressed: () {
                _focusNode.requestFocus();
              },
              iconTheme: QuillIconTheme(
                  iconButtonUnselectedData: IconButtonData(color: iconColor),
                  iconButtonSelectedData: IconButtonData(color: iconColor))),
        ),
        const SizedBox(width: 4),
        */
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String bookLongName =
        BookNameConverter.shortNameToLongName(widget.book);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgNotifier = isDark ? darkBackgroundColor : lightBackgroundColor;
        final textNotifier = isDark ? darkTextColor : lightTextColor;
        return ValueListenableBuilder<Color>(
          valueListenable: bgNotifier,
          builder: (context, bgColor, __) {
            return ValueListenableBuilder<Color>(
              valueListenable: textNotifier,
              builder: (context, textColor, ___) {
                final bool isMobile =
                    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
                final Color topColor =
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
                return Shortcuts(
                    shortcuts: <LogicalKeySet, Intent>{
                      LogicalKeySet(LogicalKeyboardKey.control,
                          LogicalKeyboardKey.keyS): VoidCallbackIntent(() {
                        _saveAndExit();
                      }),
                      LogicalKeySet(
                              LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS):
                          VoidCallbackIntent(() {
                        _saveAndExit();
                      }),
                    },
                    child: Actions(
                        actions: <Type, Action<Intent>>{
                          VoidCallbackIntent:
                              CallbackAction<VoidCallbackIntent>(
                                  onInvoke: (intent) => intent.callback()),
                        },
                        child: PopScope(
                          canPop:
                              false, // Prevent default pop to handle custom logic
                          onPopInvokedWithResult: _handlePopInvoked,
                          child: Scaffold(
                            resizeToAvoidBottomInset: true,
                            appBar: AppBar(
                              scrolledUnderElevation: 0,
                              iconTheme: IconThemeData(
                                size: 32,
                                color: isDark
                                    ? darkPrimaryColor.value
                                    : lightPrimaryColor.value,
                              ),
                              title: Text(
                                '$bookLongName ${widget.chapter}:${widget.verse}',
                                style: TextStyle(
                                    fontFamily: uiFontFamily,
                                    fontSize: uiFontSize + 6,
                                    color: getAdaptiveTextColor(context)),
                              ),
                              backgroundColor: _adjustBarColor(bgColor),
                              foregroundColor: textColor,
                              actions: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    semanticLabel: 'Delete Note',
                                  ),
                                  onPressed: _deleteNote,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.save,
                                    semanticLabel: 'Save Note',
                                  ),
                                  onPressed: _saveAndExit,
                                ),
                              ],
                            ),
                            backgroundColor: bgColor,
                            body: SafeArea(
                              //bottom: false,
                              child: Column(children: [
                                Expanded(
                                    child: Column(
                                        children: isMobile
                                            ? [
                                                Expanded(
                                                    child: QuillEditor(
                                                  controller: _quillController,
                                                  focusNode: _focusNode,
                                                  scrollController:
                                                      _scrollController,
                                                  config: QuillEditorConfig(
                                                      customStyles:
                                                          DefaultStyles(
                                                              paragraph: DefaultTextBlockStyle(
                                                                  TextStyle(fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value), fontFamily: fontFamilyNotifier.value, color: isDark ? darkTextColor.value : lightTextColor.value),
                                                                  const HorizontalSpacing(15, 15),
                                                                  const VerticalSpacing(0, 0),
                                                                  const VerticalSpacing(0, 0),
                                                                  null)),
                                                      customLinkPrefixes: const [
                                                        'verse://',
                                                        'verse:'
                                                      ]),
                                                )),
                                                const SizedBox(height: 8),
                                                _buildToolbar(topColor)
                                              ]
                                            : [
                                                _buildToolbar(topColor),
                                                const SizedBox(height: 8),
                                                Expanded(
                                                  child: QuillEditor(
                                                    controller:
                                                        _quillController,
                                                    focusNode: _focusNode,
                                                    scrollController:
                                                        _scrollController,
                                                    config: QuillEditorConfig(
                                                      customStyles: DefaultStyles(
                                                          paragraph: DefaultTextBlockStyle(
                                                              TextStyle(
                                                                  fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value),
                                                                  // Don't pass a list here because then it won't use the first one
                                                                  fontFamily: fontFamilyNotifier.value,
                                                                  color: isDark ? darkTextColor.value : lightTextColor.value),
                                                              const HorizontalSpacing(15, 15),
                                                              const VerticalSpacing(0, 0),
                                                              const VerticalSpacing(0, 0),
                                                              null)),
                                                      customLinkPrefixes: const [
                                                        'verse://',
                                                        'verse:'
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              ]))
                              ]),
                            ),
                          ),
                        )));
              },
            );
          },
        );
      },
    );
  }

  Future<void> _saveAndExit() async {
    // Always close UI for both save and back buttons
    if (mounted) {
      Navigator.of(context).pop();
    }

    // Get the plain text content (single extraction)
    final plainText = _quillController.document
        .getPlainText(0, _quillController.document.length);

    //if (kDebugMode) debugPrint('_saveAndExit document: ${_quillController.document.toDelta().toJson()}');
    //if (kDebugMode) debugPrint('_saveAndExit document: ${_quillController.document.toPlainText()}');

    // Save if: non-empty AND (new note OR content actually changed)
    if (plainText.trim().isNotEmpty &&
        (_existingCreatedAt == 0 || _contentHasChanged())) {
      Document finalDocument = _quillController.document;

      // If there's no colon in the plain text there's no reason to run the verse linker
      if (plainText.contains(':')) {
        finalDocument = VerseReferenceLinker.addVerseReferenceLinks(
            _quillController.document);
      }

      // String debugNoteText = NoteStorageFormat.deltaToJsonString(finalDocument);
      // if (kDebugMode) debugPrint('_saveAndExit BeforeNewlineTrimming: ${debugNoteText}');

      // // Apply newline trimming
      // final normalizedDocument = Document.fromDelta(NoteStorageFormat.normalizeNewlines(finalDocument.toDelta()));

      // debugNoteText = NoteStorageFormat.deltaToJsonString(normalizedDocument);
      // if (kDebugMode) debugPrint('_saveAndExit AfterNewlineTrimming: $debugNoteText');

      // Save with proper timestamp handling (preserve created_at if exists)
      NotesDatabase.addOrUpdateNote(
        book: widget.book,
        chapter: widget.chapter,
        verse: widget.verse,
        noteText: NoteStorageFormat.deltaToJsonString(
            finalDocument), //NoteStorageFormat.deltaToJsonString(normalizedDocument),
        createdAt: _existingCreatedAt > 0 ? _existingCreatedAt : null,
        skipSync: false,
      );
    }
  }

  Future<void> _deleteNote() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text(
            'Are you sure you want to delete this note? This action cannot be undone.',
            style: TextStyle(
                fontSize: uiFontSize + 6,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final existing = await NotesDatabase.getNoteForVerse(
          widget.book, widget.chapter, widget.verse);
      if (existing != null) {
        // deleteNote() now handles queuing sync operations, no need for additional marking
        await NotesDatabase.deleteNote(existing['id']);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handlePopInvoked(bool didPop, void result) async {
    if (!didPop) {
      await _saveAndExit(); // Same method as save button
    }
  }
}
