import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:selah/utils/book_name_converter.dart';
import 'package:selah/utils/snackbar_notification.dart';
import '../utils/preferences_constants.dart';
import '../main.dart';

class MultipleVersesDialog extends StatefulWidget {
  final String book;
  final int chapter;
  final int initialVerse;
  final List<Map<String, dynamic>> verses;

  const MultipleVersesDialog({
    super.key,
    required this.book,
    required this.chapter,
    required this.initialVerse,
    required this.verses,
  });

  @override
  State<MultipleVersesDialog> createState() => _MultipleVersesDialogState();
}

class _MultipleVersesDialogState extends State<MultipleVersesDialog> {
  late int startVerse;
  late int endVerse;
  late List<int> availableVerses;
  late TextEditingController startController;
  late TextEditingController endController;

  @override
  void initState() {
    super.initState();
    availableVerses = widget.verses.map((v) => v['verse'] as int).toList()..sort();
    startVerse = widget.initialVerse;
    endVerse = availableVerses.last;
    startController = TextEditingController(text: startVerse.toString());
    endController = TextEditingController(text: endVerse.toString());
  }

  @override
  void dispose() {
    startController.dispose();
    endController.dispose();
    super.dispose();
  }

  Future<void> _copyVerses() async {
    final fullName = BookNameConverter.shortNameToLongName(widget.book);

    final range = startVerse == endVerse ? startVerse.toString() : '$startVerse-$endVerse';
    String text = '$fullName ${widget.chapter}:$range\n';

    final selectedVerses = widget.verses
        .where((v) => v['verse'] as int >= startVerse && v['verse'] as int <= endVerse)
        .toList()
      ..sort((a, b) => (a['verse'] as int).compareTo(b['verse'] as int));

    for (final verse in selectedVerses) {
      final num = verse['verse'] as int;
      String verseText = verse['text'] as String;

      // Clean Strong's and red letter tags
      //verseText = verseText.replaceAll(RegExp(r'\[\(?[GH]\d{1,4}\)?\]'), '').replaceAll(RegExp(r'</?r>'), '');

      // Clean red letter tags only
      verseText = verseText.replaceAll(RegExp(r'</?r>'), '');
      text += '$num $verseText\n';
    }

    try {
      await Clipboard.setData(ClipboardData(text: text.trim()));
      if (mounted) {
        showStyledSnackBar(context, 'Verse(s) Copied');
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Copy Failed', isError: true);
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookDisplayFullName = BookNameConverter.shortNameToLongName(widget.book);

    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                '$bookDisplayFullName ${widget.chapter}',
                style: TextStyle(
                    fontSize: uiFontSize + 4,
                    fontFamily: uiFontFamily,
                    fontWeight: FontWeight.normal,
                    color: getAdaptiveTextColor(context)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: startVerse,
                  items: availableVerses
                      .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('$v',
                              style: TextStyle(
                                  fontSize: uiFontSize + 10,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context)))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    startVerse = v!;
                    if (endVerse < startVerse) endVerse = startVerse;
                  }),
                  underline: Container(),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(' to ',
                      style: TextStyle(
                          fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                ),
                DropdownButton<int>(
                  value: endVerse,
                  items: availableVerses
                      .where((v) => v >= startVerse)
                      .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('$v',
                              style: TextStyle(
                                  fontSize: uiFontSize + 10,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context)))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    endVerse = v!;
                    if (startVerse > endVerse) startVerse = endVerse;
                  }),
                  underline: Container(),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style:
                        TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: _copyVerses,
                  child: Text('Copy',
                      style: TextStyle(
                          fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
