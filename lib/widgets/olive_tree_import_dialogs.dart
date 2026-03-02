import 'package:flutter/material.dart';
import '../models/olive_tree_data.dart';
import '../utils/color_mapper.dart';
import '../utils/preferences_constants.dart';

// Simplified adaptive text color function
Color getAdaptiveTextColor(BuildContext context,
    {Color? backgroundColor, bool usePrimaryColor = false}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white : Colors.black;
}

/// Dialog for selecting which data types to import from Olive Tree
class OliveTreeCategorySelectionDialog extends StatefulWidget {
  final OliveTreeData data;

  const OliveTreeCategorySelectionDialog({
    super.key,
    required this.data,
  });

  @override
  State<OliveTreeCategorySelectionDialog> createState() =>
      _OliveTreeCategorySelectionDialogState();
}

class _OliveTreeCategorySelectionDialogState
    extends State<OliveTreeCategorySelectionDialog> {
  bool importHighlights = true;
  bool importNotes = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Center(
        child: Text(
          'Import Olive Tree Bible Data export',
          style: TextStyle(
            fontSize: uiFontSize,
            fontFamily: uiFontFamily,
            color: getAdaptiveTextColor(context),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ℹ️ Existing data will be preserved. Imported highlights will replace existing highlights if they overlap. Imported notes will be added to existing notes.',
            style: TextStyle(
              color: Colors.blue,
              fontFamily: uiFontFamily,
              fontSize: uiFontSize,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Available data in file:',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.data.highlightCount > 0)
            CheckboxListTile(
              title: Text(
                'Highlights',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              subtitle: Text(
                '${widget.data.highlightCount}',
                style: TextStyle(
                  fontSize: uiFontSize - 2,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              value: importHighlights,
              onChanged: (value) =>
                  setState(() => importHighlights = value ?? true),
            ),
          if (widget.data.noteCount > 0)
            CheckboxListTile(
              title: Text(
                'Notes',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              subtitle: Text(
                '${widget.data.noteCount}',
                style: TextStyle(
                  fontSize: uiFontSize - 2,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              value: importNotes,
              onChanged: (value) => setState(() => importNotes = value ?? true),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            final selectedTypes = <String>[];
            if (importHighlights && widget.data.highlightCount > 0) {
              selectedTypes.add('highlights');
            }
            if (importNotes && widget.data.noteCount > 0) {
              selectedTypes.add('notes');
            }
            Navigator.pop(context, selectedTypes);
          },
          child: Text(
            'Next',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog for mapping Olive Tree highlight colors to Selah colors
class OliveTreeColorMappingDialog extends StatefulWidget {
  final List<String> oliveTreeColors;
  final Map<String, int> initialMappings;
  final List<Color> currentHighlightColors;

  const OliveTreeColorMappingDialog({
    super.key,
    required this.oliveTreeColors,
    required this.initialMappings,
    required this.currentHighlightColors,
  });

  @override
  State<OliveTreeColorMappingDialog> createState() =>
      _OliveTreeColorMappingDialogState();
}

class _OliveTreeColorMappingDialogState
    extends State<OliveTreeColorMappingDialog> {
  late Map<String, int> colorMappings;

  @override
  void initState() {
    super.initState();
    colorMappings = Map.from(widget.initialMappings);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      constraints: const BoxConstraints(maxWidth: 450),
      title: Text(
        'Choose which colors you want to map the imported Highlight categories to:',
        style: TextStyle(
          fontSize: uiFontSize,
          fontFamily: uiFontFamily,
          color: getAdaptiveTextColor(context),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          //Text('Map each Olive Tree color to a Selah highlight color:', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context),),),
          const SizedBox(height: 16),
          ...widget.oliveTreeColors.map((otColor) {
            final selahIndex = colorMappings[otColor] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  // Olive Tree color preview
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getPreviewColor(otColor),
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: Text(
                      otColor,
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '→',
                    style: TextStyle(
                      fontSize: uiFontSize + 10,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  const SizedBox(width: 32),
                  // Selah color dropdown
                  DropdownButton<int>(
                    //isExpanded: false,
                    underline: Container(),
                    value: selahIndex,
                    items: List.generate(widget.currentHighlightColors.length,
                        (index) {
                      return DropdownMenuItem(
                        value: index,
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: widget.currentHighlightColors[index],
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      );
                    }),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          colorMappings[otColor] = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, colorMappings),
          child: Text(
            'Import',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Color _getPreviewColor(String oliveTreeColor) {
    // Try to get a reasonable preview color for the Olive Tree color name
    final lowerColor = oliveTreeColor.toLowerCase();
    if (ColorMapper.commonColors.containsKey(lowerColor)) {
      return ColorMapper.commonColors[lowerColor]!;
    }
    // Default to gray for unknown colors
    return Colors.grey;
  }
}

/// Progress dialog for import operation
class OliveTreeImportProgressDialog extends StatelessWidget {
  final String message;

  const OliveTreeImportProgressDialog({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Results dialog showing import success/failure
class OliveTreeImportResultsDialog extends StatelessWidget {
  final Map<String, dynamic> results;

  const OliveTreeImportResultsDialog({
    super.key,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    final totalImported = results.entries
        .where((e) => e.key != 'failedRows' && e.value is int)
        .fold<int>(0, (sum, entry) => sum + (entry.value as int));

    final allFailedRows = <FailedRow>[];
    results.forEach((key, value) {
      if (key == 'failedRows' && value is List<FailedRow>) {
        allFailedRows.addAll(value);
      }
    });

    final hasErrors = allFailedRows.isNotEmpty;

    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 600),
      title: Text(
        hasErrors ? 'Import Completed with Errors' : 'Import Successful',
        style: TextStyle(
          fontSize: uiFontSize,
          fontFamily: uiFontFamily,
          color: hasErrors ? Colors.red : Colors.green,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import Summary:',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...results.entries
              .where((e) => e.key != 'failedRows' && e.value is int)
              .map((entry) {
            return Text(
              '${entry.key}: ${entry.value} imported',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            );
          }),
          const SizedBox(height: 16),
          Text(
            'Total items imported: $totalImported',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
              fontWeight: FontWeight.bold,
            ),
          ),
          if (hasErrors) ...[
            const SizedBox(height: 16),
            Text(
              'Failed Items (${allFailedRows.length}):',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: allFailedRows.map((failedRow) {
                    final csvLine = _formatRowAsCsv(failedRow.rowData);
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // The reason why this import failed
                            failedRow.reason,
                            style: TextStyle(
                              fontSize: uiFontSize - 1,
                              fontFamily: uiFontFamily,
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: SelectableText(
                              csvLine,
                              style: TextStyle(
                                fontSize: uiFontSize - 2,
                                fontFamily:
                                    'Courier', // Monospace for CSV formatting
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'OK',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
      ],
    );
  }

  /// Format row data as CSV line for display
  String _formatRowAsCsv(Map<String, String> rowData) {
    final columns = [
      'category_name',
      'type',
      'highlighter_name',
      'title',
      'content',
      'reference_start',
      'reference_end',
      'associated_product',
      'date_created',
      'last_modified',
      'tags',
    ];

    final values = columns.map((col) => rowData[col] ?? '').toList();
    return values.join(',');
  }
}
