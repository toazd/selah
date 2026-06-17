import csv
import json
import os

def escape_dart_string(text):
    """Escapes string characters to ensure it fits safely inside single quotes in Dart."""
    if not text:
        return ""
    # Escape backslashes first, then single quotes and dollar signs (used for interpolation in Dart)
    text = text.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    # Remove carriage returns to keep formatting consistent
    text = text.replace('\r', '')
    return text

def convert_csv_to_dart(csv_file_path, dart_file_path):
    print(f"Reading data from {csv_file_path}...")

    entries = []

    # Read the CSV file using standard UTF-8 encoding
    with open(csv_file_path, mode='r', encoding='utf-8') as csv_file:
        # Use csv.reader to safely handle multiline fields and escaped quotes
        reader = csv.reader(csv_file)

        # Skip the header row (id, topic, definition)
        header = next(reader, None)

        for row in reader:
            if not row or len(row) < 3:
                continue

            entry_id = row[0].strip()
            topic = row[1].strip()
            definition = row[2].strip()

            # Clean up the double-escaped quotes sometimes present in the CSV sample (e.g., """"a landlord..."""")
            if definition.startswith('"') and definition.endswith('"'):
                definition = definition[1:-1]
            definition = definition.replace('""', '"')

            entries.append({
                'id': int(entry_id),
                'topic': topic,
                'definition': escape_dart_string(definition)
            })

    print(f"Writing Dart map containing {len(entries)} entries to {dart_file_path}...")

    # Write the Dart output file
    with open(dart_file_path, mode='w', encoding='utf-8') as dart_file:
        # File headers and format constraint configurations
        dart_file.write("// @dart=3.7\n")
        dart_file.write("// dart format off\n\n")
        dart_file.write("const Map<String, Map<String, dynamic>> websters1828 = {\n")

        for entry in entries:
            topic_key = entry['topic'].replace("'", "\\'")
            dart_file.write(f"  '{topic_key}': {{\n")
            dart_file.write(f"    'id': {entry['id']},\n")
            dart_file.write(f"    'definition': '{entry['definition']}',\n")
            dart_file.write("  },\n")

        dart_file.write("};\n")

    print("Conversion completed successfully!")

if __name__ == "__main__":
    # Define file configurations relative to execution context
    input_csv = "dictionary.csv"
    output_dart = "websters_1828.dart"

    # Check if file exists before running conversion
    if os.path.exists(input_csv):
        convert_csv_to_dart(input_csv, output_dart)
    else:
        print(f"Error: Source file '{input_csv}' not found. Please place it in the same directory.")
