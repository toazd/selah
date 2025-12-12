import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta;
import '../database/notes_database.dart';
import '../main.dart';
import '../utils/book_name_converter.dart';
import '../utils/preferences_constants.dart';
import '../utils/note_storage_format.dart';
import '../utils/verse_reference_linker.dart';
import 'package:flutter_quill_to_pdf/flutter_quill_to_pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import '../utils/snackbar_notification.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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

class PdfExportSettings {
  final PDFPageFormat pageFormat;
  //final double topMargin;
  //final double bottomMargin;
  //final double leftMargin;
  //final double rightMargin;
  final String selectedFont;

  PdfExportSettings({
    required this.pageFormat,
    //required this.topMargin,
    //required this.bottomMargin,
    //required this.leftMargin,
    //required this.rightMargin,
    required this.selectedFont,
  });
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
    _quillController = NoteStorageFormat.createControllerFromNote(widget.existingNote);

    // If this is an existing note, clean verse links to prevent stale links during editing
    if (widget.existingNote != null && widget.existingNote!.isNotEmpty) {
      final cleanedDocument = VerseReferenceLinker.removeVerseLinksForEditing(_quillController.document);

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
        NotesDatabase.getNoteForVerse(widget.book, widget.chapter, widget.verse).then((existingRecord) {
          if (existingRecord != null && mounted) {
            setState(() => _existingCreatedAt = existingRecord['created_at'] as int);
            // Store original content hash for change detection
            setState(() => _originalContentHash = widget.existingNote!.hashCode.toString());
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
    final currentContent = NoteStorageFormat.deltaToJsonString(_quillController.document);
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
            iconTheme: QuillIconTheme(iconButtonUnselectedData: IconButtonData(color: iconColor), iconButtonSelectedData: IconButtonData(color: iconColor)),
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
    final String bookLongName = BookNameConverter.shortNameToLongName(widget.book);
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
                final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
                final Color topColor = isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
                return Shortcuts(
                    shortcuts: <LogicalKeySet, Intent>{
                      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): VoidCallbackIntent(() {
                        _saveAndExit();
                      }),
                      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS): VoidCallbackIntent(() {
                        _saveAndExit();
                      }),
                    },
                    child: Actions(
                        actions: <Type, Action<Intent>>{
                          VoidCallbackIntent: CallbackAction<VoidCallbackIntent>(onInvoke: (intent) => intent.callback()),
                        },
                        child: PopScope(
                          canPop: false, // Prevent default pop to handle custom logic
                          onPopInvokedWithResult: _handlePopInvoked,
                          child: Scaffold(
                            resizeToAvoidBottomInset: true,
                            appBar: AppBar(
                              scrolledUnderElevation: 0,
                              iconTheme: IconThemeData(
                                size: 32,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                              ),
                              title: Text(
                                '$bookLongName ${widget.chapter}:${widget.verse}',
                                style: TextStyle(fontFamily: uiFontFamily, fontSize: uiFontSize + 6, color: getAdaptiveTextColor(context)),
                              ),
                              backgroundColor: _adjustBarColor(bgColor),
                              foregroundColor: textColor,
                              actions: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.picture_as_pdf,
                                    semanticLabel: 'Export Note to PDF',
                                  ),
                                  onPressed: _exportToPdf,
                                  tooltip: 'Export to PDF',
                                ),
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
                              bottom: false,
                              child: Column(children: [
                                Expanded(
                                    child: Column(
                                        children: isMobile
                                            ? [
                                                Expanded(
                                                    child: QuillEditor(
                                                  controller: _quillController,
                                                  focusNode: _focusNode,
                                                  scrollController: _scrollController,
                                                  config: QuillEditorConfig(
                                                      customStyles: DefaultStyles(
                                                          paragraph: DefaultTextBlockStyle(
                                                              TextStyle(
                                                                  fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value),
                                                                  fontFamily: fontFamilyNotifier.value,
                                                                  color: isDark ? darkTextColor.value : lightTextColor.value),
                                                              const HorizontalSpacing(15, 15),
                                                              const VerticalSpacing(0, 0),
                                                              const VerticalSpacing(0, 0),
                                                              null)),
                                                      customLinkPrefixes: const ['verse://', 'verse:']),
                                                )),
                                                const SizedBox(height: 8),
                                                _buildToolbar(topColor)
                                              ]
                                            : [
                                                _buildToolbar(topColor),
                                                const SizedBox(height: 8),
                                                Expanded(
                                                  child: QuillEditor(
                                                    controller: _quillController,
                                                    focusNode: _focusNode,
                                                    scrollController: _scrollController,
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
                                                        customLinkPrefixes: const ['verse://', 'verse:']),
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
    final plainText = _quillController.document.getPlainText(0, _quillController.document.length);

    //if (kDebugMode) debugPrint('_saveAndExit document: ${_quillController.document.toDelta().toJson()}');

    // Save if: non-empty AND (new note OR content actually changed)
    if (plainText.trim().isNotEmpty && (_existingCreatedAt == 0 || _contentHasChanged())) {
      Document finalDocument = _quillController.document;

      // If there's no colon in the plain text there's no reason to run the verse linker
      if (plainText.contains(':')) {
        finalDocument = VerseReferenceLinker.addVerseReferenceLinks(_quillController.document);
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
        noteText: NoteStorageFormat.deltaToJsonString(finalDocument), //NoteStorageFormat.deltaToJsonString(normalizedDocument),
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
        content: Text('Are you sure you want to delete this note? This action cannot be undone.',
            style: TextStyle(fontSize: uiFontSize + 6, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final existing = await NotesDatabase.getNoteForVerse(widget.book, widget.chapter, widget.verse);
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

  /// Removes internal app links (verse:// and verse:) and converts them to plain text for PDF export
  Document _cleanDocumentForPdf(Document originalDocument) {
    // Convert document to JSON
    final jsonData = originalDocument.toDelta().toJson();

    // Process the JSON to remove verse links
    final cleanedJson = _removeVerseLinksFromJson(jsonData);

    // Create new document from cleaned JSON
    return Document.fromDelta(Delta.fromJson(cleanedJson));
  }

  /// Helper method to remove verse links from document JSON
  List<dynamic> _removeVerseLinksFromJson(List<dynamic> jsonData) {
    final cleanedData = <dynamic>[];

    for (final item in jsonData) {
      if (item is Map<String, dynamic>) {
        final attributes = item['attributes'] as Map<String, dynamic>?;
        if (attributes != null && attributes.containsKey('link')) {
          final linkValue = attributes['link'] as String?;
          if (linkValue != null && (linkValue.startsWith('verse://') || linkValue.startsWith('verse:'))) {
            // Create a copy of the item without the link attribute
            final cleanedItem = Map<String, dynamic>.from(item);
            final cleanedAttributes = Map<String, dynamic>.from(attributes);
            cleanedAttributes.remove('link');
            cleanedItem['attributes'] = cleanedAttributes.isEmpty ? null : cleanedAttributes;
            cleanedData.add(cleanedItem);
          } else {
            // Keep non-verse links as-is
            cleanedData.add(item);
          }
        } else {
          // No link attribute, keep as-is
          cleanedData.add(item);
        }
      } else {
        // Not a map, keep as-is
        cleanedData.add(item);
      }
    }

    return cleanedData;
  }

  /// Generates a clean filename for the PDF
  String _getCleanFileName() {
    final String bookName = BookNameConverter.shortNameToLongName(widget.book);
    return '$bookName ${widget.chapter}.${widget.verse}';
  }

  /// Saves PDF to user-selected location
  Future<String?> _savePdfToDevice(pw.Document? pdfDocument, String filePath) async {
    if (pdfDocument == null) return null;
    try {
      // Save the file to the user-selected path
      final File file = File(filePath);
      final List<int> bytes = await pdfDocument.save();
      await file.writeAsBytes(bytes);

      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// Shows PDF export settings dialog
  Future<PdfExportSettings?> _showPdfSettingsDialog() async {
    return showDialog<PdfExportSettings>(
      context: context,
      builder: (BuildContext context) => _PdfExportSettingsDialog(),
    );
  }

  /// Main PDF export function
  Future<void> _exportToPdf() async {
    final currentContext = context;
    final textDirection = Directionality.of(currentContext);
    try {
      // Show settings dialog first
      final settings = await _showPdfSettingsDialog();
      if (settings == null) return; // User cancelled

      // Get default directory for file picker
      String? initialDirectory;
      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          initialDirectory = '${directory.path}/Download';
        }
      } else if (Platform.isIOS) {
        final directory = await getApplicationDocumentsDirectory();
        initialDirectory = directory.path;
      } else {
        // Desktop platforms
        final directory = await getDownloadsDirectory();
        initialDirectory = directory?.path;
      }

      // Generate suggested filename
      final String suggestedFileName = '${_getCleanFileName()} note.pdf';

      // Show file picker to let user choose save location
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF',
        fileName: suggestedFileName,
        initialDirectory: initialDirectory,
        allowedExtensions: ['pdf'],
        type: FileType.custom,
      );

      if (outputFile == null) return; // User cancelled

      // Font asset mapping
      final Map<String, String> fontAssetMap = {
        'Arimo': 'assets/fonts/Arimo-VariableFont_wght.ttf',
        'Open Sans': 'assets/fonts/OpenSans-VariableFont_wdth,wght.ttf',
        'Daddy Time Mono': 'assets/fonts/DaddyTimeMono.otf',
        'Inconsolata': 'assets/fonts/Inconsolata-VariableFont_wdth,wght.ttf',
        'Roboto Mono': 'assets/fonts/RobotoMono-VariableFont_wght.ttf',
        'Gabriela': 'assets/fonts/Gabriela-Regular.ttf',
        'Caveat': 'assets/fonts/Caveat-VariableFont_wght.ttf',
        'Dancing Script': 'assets/fonts/DancingScript-VariableFont_wght.ttf',
        'Lobster Two': 'assets/fonts/LobsterTwo-Regular.ttf',
        'Ubuntu': 'assets/fonts/Ubuntu-Regular.ttf',
        'Liberation Sans': 'assets/fonts/LiberationSans-Regular.ttf',
        'Tinos': 'assets/fonts/Tinos-Regular.ttf',
        'Merriweather': 'assets/fonts/Merriweather-VariableFont_opsz,wdth,wght.ttf',
        'Liberation Serif': 'assets/fonts/LiberationSerif-Regular.ttf',
        'Special Gothic': 'assets/fonts/SpecialGothic-VariableFont_wdth,wght.ttf',
        'Rosemartin': 'assets/fonts/Rosemartin.otf',
        'Playfair Display': 'assets/fonts/PlayfairDisplay-VariableFont_wght.ttf',
        'Morris Roman': 'assets/fonts/MorrisRomanBlack.ttf',
        'JSL Ancient': 'assets/fonts/JSLancient.ttf',
        'Louis George Cafe': 'assets/fonts/LouisGeorgeCafe.ttf',
        'Comfortaa': 'assets/fonts/Comfortaa-Regular.ttf',
        'King Sans': 'assets/fonts/KingSans.otf',
        'Fauna One': 'assets/fonts/FaunaOne-Regular.ttf',
        'Hepta Slab': 'assets/fonts/HeptaSlab-Regular.ttf',
        'IBM Plex Sans': 'assets/fonts/IBMPlexSans-Regular.ttf',
        'Libertinus Sans': 'assets/fonts/LibertinusSans-Regular.ttf',
        'Montserrat': 'assets/fonts/Montserrat-Regular.ttf',
        'Noto Sans': 'assets/fonts/NotoSans-Regular.ttf',
        'Old Standard': 'assets/fonts/OldStandardTT-Regular.ttf',
        'Sanchez': 'assets/fonts/Sanchez-Regular.ttf',
        'Scope One': 'assets/fonts/ScopeOne-Regular.ttf',
        'Solway': 'assets/fonts/Solway-Regular.ttf',
      };

      // Load selected font for Unicode support
      final fontAsset = fontAssetMap[settings.selectedFont] ?? 'assets/fonts/IBMPlexSans-Regular.ttf';
      final fontData = await rootBundle.load(fontAsset);
      final selectedFont = pw.Font.ttf(fontData);
      final pdfTheme = pw.ThemeData.withFont(
        base: selectedFont,
      );

      // Clean the document by removing internal links
      final cleanDocument = _cleanDocumentForPdf(_quillController.document);

      // Create PDF converter with user-selected settings and font fallback
      final converter = PDFConverter(
        document: cleanDocument.toDelta(),
        pageFormat: settings.pageFormat,
        themeData: pdfTheme,
        textDirection: textDirection,
        fallbacks: [selectedFont],
      );

      // Generate the PDF document
      final pdfDocument = await converter.createDocument();

      // Save the file to user-selected location
      final String? filePath = await _savePdfToDevice(pdfDocument, outputFile);

      if (mounted) {
        if (filePath != null) {
          showStyledSnackBar(context, 'PDF saved successfully to: ${filePath.replaceAll('\\', '/')}');
        } else {
          showStyledSnackBar(context, 'Failed to save PDF', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Error creating PDF: $e', isError: true);
      }
    }
  }
}

/// PDF Export Settings Dialog Widget
class _PdfExportSettingsDialog extends StatefulWidget {
  @override
  _PdfExportSettingsDialogState createState() => _PdfExportSettingsDialogState();
}

class _PdfExportSettingsDialogState extends State<_PdfExportSettingsDialog> {
  String selectedFont = 'IBM Plex Sans';
  String selectedPageSize = 'Letter (8.5" x 11")';
  String selectedMarginPreset = 'Narrow';

  // Custom margin values (in points)
  double topMargin = 36.0; // 1 inch
  double bottomMargin = 36.0;
  double leftMargin = 36.0;
  double rightMargin = 36.0;

  // Controllers for margin input fields
  late TextEditingController topMarginController;
  late TextEditingController bottomMarginController;
  late TextEditingController leftMarginController;
  late TextEditingController rightMarginController;

  @override
  void initState() {
    super.initState();
    // Initialize controllers
    topMarginController = TextEditingController();
    bottomMarginController = TextEditingController();
    leftMarginController = TextEditingController();
    rightMarginController = TextEditingController();
    // Apply the default margin preset
    _applyMarginPreset(selectedMarginPreset);
  }

  @override
  void dispose() {
    // Dispose controllers
    topMarginController.dispose();
    bottomMarginController.dispose();
    leftMarginController.dispose();
    rightMarginController.dispose();
    super.dispose();
  }

  // Available page sizes
  final List<Map<String, dynamic>> pageSizes = [
    {'name': 'A4', 'format': PDFPageFormat.a4},
    {'name': 'A3', 'format': PDFPageFormat.a3},
    {'name': 'Letter (8.5" x 11")', 'format': PDFPageFormat.letter},
    {'name': 'Legal (8.5" x 14")', 'format': PDFPageFormat.legal},
  ];

  // Margin presets
  final Map<String, List<double>> marginPresets = {
    'Narrow': [36.0, 36.0, 36.0, 36.0], // 0.5 inch
    'Normal': [72.0, 72.0, 72.0, 72.0], // 1 inch
    'Wide': [108.0, 108.0, 108.0, 108.0], // 1.5 inch
  };

  void _applyMarginPreset(String preset) {
    final margins = marginPresets[preset]!;
    setState(() {
      topMargin = margins[0];
      bottomMargin = margins[1];
      leftMargin = margins[2];
      rightMargin = margins[3];
      // Update controller text values
      topMarginController.text = (topMargin / 72.0).toStringAsFixed(2);
      bottomMarginController.text = (bottomMargin / 72.0).toStringAsFixed(2);
      leftMarginController.text = (leftMargin / 72.0).toStringAsFixed(2);
      rightMarginController.text = (rightMargin / 72.0).toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'PDF Export Settings',
        style: TextStyle(
          fontFamily: uiFontFamily,
          fontSize: uiFontSize,
          color: getAdaptiveTextColor(context),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Font Selection
            DropdownButtonFormField<String>(
              initialValue: selectedFont,
              items: availableFonts
                  .map((font) => DropdownMenuItem<String>(
                      value: font,
                      child: Text(
                        font,
                        style: TextStyle(
                          fontFamily: font,
                          fontSize: uiFontSize + 2,
                          color: getAdaptiveTextColor(context),
                        ),
                      )))
                  .toList(),
              onChanged: (value) => setState(() => selectedFont = value!),
            ),

            const SizedBox(height: 16),

            // Page Size Selection
            DropdownButtonFormField<String>(
              initialValue: selectedPageSize,
              selectedItemBuilder: (BuildContext context) {
                return pageSizes.map<Widget>((size) {
                  return Text(
                    size['name'] as String,
                    style: TextStyle(
                      fontFamily: uiFontFamily,
                      fontSize: uiFontSize,
                      color: getAdaptiveTextColor(context),
                    ),
                  );
                }).toList();
              },
              items: pageSizes
                  .map((size) => DropdownMenuItem<String>(
                      value: size['name'] as String,
                      child: Text(
                        size['name'] as String,
                        style: TextStyle(
                          fontFamily: uiFontFamily,
                          fontSize: uiFontSize,
                          color: getAdaptiveTextColor(context),
                        ),
                      )))
                  .toList(),
              onChanged: (value) => setState(() => selectedPageSize = value!),
            ),

            const SizedBox(height: 16),

            // Margin Presets
            DropdownButtonFormField<String>(
              initialValue: selectedMarginPreset,
              items: marginPresets.keys
                  .map((preset) => DropdownMenuItem<String>(
                      value: preset,
                      child: Text(
                        preset,
                        style: TextStyle(
                          fontFamily: uiFontFamily,
                          fontSize: uiFontSize,
                          color: getAdaptiveTextColor(context),
                        ),
                      )))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedMarginPreset = value!);
                _applyMarginPreset(value!);
              },
            ),

            const SizedBox(height: 16),

            // Custom Margin Settings
            Text(
              'Custom Margins (inches)',
              style: TextStyle(
                fontFamily: uiFontFamily,
                fontSize: uiFontSize,
                color: getAdaptiveTextColor(context),
              ),
            ),
            Row(
              children: [
                Expanded(
                    child: _buildMarginInput('Top', topMarginController, (value) {
                  setState(() => topMargin = value * 72.0);
                })),
                Expanded(
                    child: _buildMarginInput('Bottom', bottomMarginController, (value) {
                  setState(() => bottomMargin = value * 72.0);
                })),
              ],
            ),
            Row(
              children: [
                Expanded(
                    child: _buildMarginInput('Left', leftMarginController, (value) {
                  setState(() => leftMargin = value * 72.0);
                })),
                Expanded(
                    child: _buildMarginInput('Right', rightMarginController, (value) {
                  setState(() => rightMargin = value * 72.0);
                })),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
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
          onPressed: () {
            final selectedFormat = pageSizes.firstWhere((size) => size['name'] == selectedPageSize)['format'];

            Navigator.of(context).pop(PdfExportSettings(
              pageFormat: selectedFormat,
              // topMargin: topMargin,
              // bottomMargin: bottomMargin,
              // leftMargin: leftMargin,
              // rightMargin: rightMargin,
              selectedFont: selectedFont,
            ));
          },
          child: Text(
            'Export',
            style: TextStyle(
              fontFamily: uiFontFamily,
              fontSize: uiFontSize,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarginInput(String label, TextEditingController controller, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextFormField(
        maxLength: 4,
        controller: controller,
        decoration: InputDecoration(labelText: label, suffixText: '"'),
        keyboardType: TextInputType.number,
        onChanged: (text) {
          final doubleValue = double.tryParse(text) ?? 0.0;
          onChanged(doubleValue.clamp(0.2, 3.0)); // Limit to reasonable range
        },
      ),
    );
  }
}
