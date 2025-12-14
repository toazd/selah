// Custom widget for displaying notes with clickable verse reference links using HTML
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta; // new import for Delta
import 'package:flutter_quill/flutter_quill.dart' show Document; // new import for Document
import 'package:selah/utils/preferences_constants.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import '../utils/note_storage_format.dart'; // import for note format handling
import '../utils/verse_reference_linker.dart'; // import for link creation
import '../main.dart'; // For global notifiers
import '../utils/font_size_adjustments.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:flutter_html_audio/flutter_html_audio.dart';
import 'package:flutter_html_svg/flutter_html_svg.dart';
import 'package:flutter_html_math/flutter_html_math.dart';
import 'package:flutter_html_video/flutter_html_video.dart';

class HtmlNoteDisplay extends StatelessWidget {
  final String noteText;
  //final TextStyle baseStyle;
  final Function(String, String?)? onLinkTap;

  const HtmlNoteDisplay({
    super.key,
    required this.noteText,
    //required this.baseStyle,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final html = _convertDeltaToHtml(noteText);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (html.isEmpty) {
      // Empty notes are an error and should never happen
      return Text('Error loading note (empty note detected)', style: TextStyle(color: Colors.red));
    }

    //if (kDebugMode) debugPrint('HtmlNoteDisplay html: $html');

    String cleanedHtml = html;

    // Clean out the <p> tags that are auto-inserted around each line so the display is closer to
    // what the user actually entered into the note
    //cleanedHtml = cleanedHtml.replaceAll('<p>', '').replaceAll('</p>', '<br>').replaceAll('<br/>', '<br>');

    // Fixes for vsc_quill_delta_to_html nesting <br/> tags (multiLineParagraph: true) which is the default
    // and for if multiLineParagraph is false which then nests blank lines inside of <p> tags
    //cleanedHtml = cleanedHtml.replaceAll('<p><br/>', '<br/><p>').replaceAll('<p><br/></p>', '<br/>');

    // We don't need a break at the end of single lines (the </p> gets converted to a <br> above)
    // so we fix the formatting here
    // if (cleanedHtml.endsWith("<br>")) {
    //   cleanedHtml = cleanedHtml.substring(0, cleanedHtml.length - 4);
    // }

    // Check if cleanedHtml has exactly one <p> tag and exactly one </p> tag
    /*
    final pOpenCount = RegExp(r'<p>').allMatches(cleanedHtml).length;
    final pCloseCount = RegExp(r'</p>').allMatches(cleanedHtml).length;
    final hasExactlyOneP = pOpenCount == 1 && pCloseCount == 1;

    if (hasExactlyOneP) {
      cleanedHtml = cleanedHtml.replaceAll('<p>', '').replaceAll('</p>', '');
    }
    */

    // Enable to see the html used for display
    if (kDebugMode) debugPrint('HtmlNoteDisplay cleanedHTML: $cleanedHtml');

    return Html(
      extensions: const [TableHtmlExtension(), AudioHtmlExtension(), MathHtmlExtension(), VideoHtmlExtension(), SvgHtmlExtension(), AudioHtmlExtension()],
      data: cleanedHtml,
      onLinkTap: (url, _, element) {
        if (url != null && onLinkTap != null) {
          onLinkTap!(url, element?.text);
        }
      },
      style: {
        // Explicitly set styles for every tag we use/leave so the note
        // appears closer to exactly how the user entered it
        //
        // "sup": Style(), // If the "sup" (and probably sub) class are used at all, for anything, it messes up the display of <sup> text
        //
        // "*": Style(), // If the "*" class is used at all, for anything (even blank as it is here),
        // it messes up the display of <sup> and <sub> text. Since it doesn't mess up the display of
        // anything else it's probably a bug in flutter_html 3.0.0.
        "html": Style(
          padding: HtmlPaddings.all(0.0),
          margin: Margins.all(0.0),
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 4)), // Use fontSize from baseStyle
          fontFamily: fontFamilyNotifier.value,
          lineHeight: LineHeight(defaultLineHeight),
          //border: Border.all(color: Colors.red), // For Debug use only
        ),
        "body": Style(
          padding: HtmlPaddings.all(0.0),
          margin: Margins.all(0.0),
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 4)),
          fontFamily: fontFamilyNotifier.value,
          lineHeight: LineHeight(defaultLineHeight),
        ),
        "ul": Style(
          padding: HtmlPaddings.all(0.0),
          margin: Margins.only(
            left: 28.0,
          ), // Setting this to all(0) causes the list dots to appear outside of the widget somehow so we have to add a little bit to keep it inside the html widget
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 4)),
          fontFamily: fontFamilyNotifier.value,
          lineHeight: LineHeight(defaultLineHeight),
        ),
        "ol": Style(
          padding: HtmlPaddings.all(0.0),
          margin: Margins.only(
            left: 32.0,
          ), // Setting this to all(0) causes the list numbers to appear far outside of the widget somehow so we have to add a little bit to keep it inside the html widget
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 5)),
          fontFamily: fontFamilyNotifier.value,
          lineHeight: LineHeight(defaultLineHeight),
        ),
        "li": Style(
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 6)),
          fontFamily: fontFamilyNotifier.value,
          lineHeight: LineHeight(defaultLineHeight),
        ),
        "a": Style(
          padding: HtmlPaddings.all(0.0),
          margin: Margins.all(0.0),
          color: isDark ? darkVerseReferenceColor.value : lightVerseReferenceColor.value, // Enables custom link colouring
          textDecoration: TextDecoration.none, // Removes the underlines from the links
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 4)),
          fontFamily: fontFamilyNotifier.value,
          lineHeight: LineHeight(defaultLineHeight),
        ),
        "p": Style(
          fontSize: FontSize(FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 4)),
          fontFamily: fontFamilyNotifier.value,
          margin: Margins.only(top: 4, bottom: 4),
          lineHeight: LineHeight(defaultLineHeight),
        ),
        "center": Style(
          textAlign: TextAlign.center,
          display: Display.block,
        ),
        "img": Style(
          display: Display.block,
        ),
        "code": Style(
          fontFamily: 'Roboto Mono',
        ),
        "pre": Style(
          padding: HtmlPaddings.all(0.0),
          margin: Margins.all(0.0),
          fontFamily: 'Roboto Mono',
        ),
        // "div": Style(),
        "hr": Style(
          margin: Margins.all(0.0), // the default hr has some crazy vertical margin setting, like 500px below it
        ),
      },
    );
  }

  String _convertDeltaToHtml(String deltaJson) {
    // Check if the note is already in Delta format
    if (NoteStorageFormat.isDeltaFormat(deltaJson)) {
      // Convert Delta to HTML
      final delta = Delta.fromJson(jsonDecode(deltaJson));

      // Add verse reference links if they don't already exist (now synchronous)
      final deltaWithLinks = VerseReferenceLinker.addVerseReferenceLinks(Document.fromDelta(delta));

      // Use the proper vsc_quill_delta_to_html package
      // Convert operations to the expected format
      final operations = deltaWithLinks.toDelta().toList();

      // Remove trailing newline that's added for editor compatibility but not needed for display
      if (operations.isNotEmpty && operations.last.data == '\n' && operations.last.attributes == null) {
        operations.removeLast();
      }

      final operationsMap = operations.map((op) => {'insert': op.data, if (op.attributes != null) 'attributes': op.attributes}).toList();

      //debugPrint('operationsMap: $operationsMap');

      final converter = QuillDeltaToHtmlConverter(operationsMap, ConverterOptions(converterOptions: OpConverterOptions(encodeHtml: false)));

      final html = converter.convert();
      return html;
    } else {
      // Convert plain text to Delta first, then to HTML (backwards compatibility)
      final operations = [
        {'insert': deltaJson},
      ];
      final delta = Delta.fromJson(operations);

      // Add verse reference links if they don't already exist (now synchronous)
      final deltaWithLinks = VerseReferenceLinker.addVerseReferenceLinks(Document.fromDelta(delta));

      // Convert operations to the expected format
      final operationsList = deltaWithLinks.toDelta().toList();

      final operationsMap = operationsList.map((op) => {'insert': op.data, if (op.attributes != null) 'attributes': op.attributes}).toList();

      final converter = QuillDeltaToHtmlConverter(operationsMap, ConverterOptions());

      final html = converter.convert();
      return html;
    }
  }
}
