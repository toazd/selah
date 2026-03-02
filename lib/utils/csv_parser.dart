/// Utility class for parsing CSV data, specifically designed to handle
/// Olive Tree Bible export format with proper quote handling
/// The Olive Tree Bible export function does not ensure that the resulting CSV
/// is spec-compliant so a little fudging was necessary to make this work (and it
/// may require more but I only have one large sample to test with)
/// In my test sample the user (me) mistakenly entered double-quotes into some of
/// the note title fields and the app and export functions do not santize typos
/// like that (eg. so "Judges 20:1 instead of Judges 20:1 is inserted into a CSV field
/// resulting in a triple quote as their exporting doesn't expect this kind of input).
class CsvParser {
  /// Parse CSV content into a list of maps
  /// Handles quoted fields and embedded newlines properly
  static List<Map<String, String>> parse(String csvContent,
      {List<String>? headers}) {
    // Preprocess Olive Tree's malformed CSV format
    csvContent = _preprocessOliveTreeCsv(csvContent);

    final records = <List<String>>[];
    List<String> currentRecord = [];
    final buffer = StringBuffer();
    bool inQuotes = false;

    // Parse the entire CSV as a stream, respecting quoted fields
    for (int i = 0; i < csvContent.length; i++) {
      final char = csvContent[i];
      final nextChar = i + 1 < csvContent.length ? csvContent[i + 1] : null;

      if (char == '"') {
        if (inQuotes && nextChar == '"') {
          // Escaped quote within quoted field
          buffer.write('"');
          i++; // Skip next quote
        } else {
          // Toggle quote state
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Field separator - add field to current record
        currentRecord.add(buffer.toString());
        buffer.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        // Record separator (handle both \n and \r\n)
        if (char == '\r' && nextChar == '\n') {
          i++; // Skip \n in \r\n
        }
        // Add the last field of this record
        currentRecord.add(buffer.toString());
        buffer.clear();

        // Save the complete record
        if (currentRecord.isNotEmpty) {
          records.add(currentRecord);
          currentRecord = [];
        }
      } else {
        buffer.write(char);
      }
    }

    // Add final field/record
    if (buffer.isNotEmpty) {
      currentRecord.add(buffer.toString());
    }
    if (currentRecord.isNotEmpty) {
      records.add(currentRecord);
    }

    if (records.isEmpty) return [];

    // Parse header row
    final headerLine = headers ?? records[0];
    final dataRecords = headers != null ? records : records.sublist(1);

    // Parse data rows
    final result = <Map<String, String>>[];
    for (final record in dataRecords) {
      if (record.length != headerLine.length) {
        // Skip malformed records
        continue;
      }

      final row = <String, String>{};
      for (int i = 0; i < headerLine.length; i++) {
        row[headerLine[i]] = record[i];
      }
      result.add(row);
    }

    return result;
  }

  /// Preprocess Olive Tree's malformed CSV format
  /// These malformed csv fields result from a typo on the user's part but
  /// given how common they can be we'll leave it here
  static String _preprocessOliveTreeCsv(String csvContent) {
    // Replace triple quotes with single quotes (Olive Tree's malformed quoting)
    csvContent = csvContent.replaceAll('"""', '"');

    // Convert vertical tab to newline (special character in Olive Tree exports)
    csvContent = csvContent.replaceAll('\v', '\n');

    return csvContent;
  }
}
