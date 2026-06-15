import argparse
import csv
import re
import sys

# Increase field size limit just in case the CSV contains massive fields
csv.field_size_limit(sys.maxsize)

def parse_ref(ref_str):
    """
    Parses a reference string like 'Gen 1:1' into ('Gen', 1, 1)
    """
    match = re.match(r'^([A-Za-z0-9 ]+)\s+(\d+):(\d+)$', ref_str.strip())
    if match:
        book = match.group(1).strip()
        chapter = int(match.group(2))
        verse = int(match.group(3))
        return book, chapter, verse
    return None

def convert_csv_to_dart(csv_filename, dart_filename):
    # Nested dictionary to hold data: data[book][chapter][verse] = text
    bible_data = {}

    # Read and parse CSV
    with open(csv_filename, mode='r', encoding='utf-8') as f:
        reader = csv.reader(f)
        # Skip the header row (id,ref,verse)
        next(reader, None)

        for row in reader:
            if not row or len(row) < 3:
                continue

            ref_str = row[1]
            raw_text = row[2].strip()

            ref_info = parse_ref(ref_str)
            if not ref_info:
                continue

            book, chapter, verse = ref_info

            # Escape single quotes for Dart string literal compatibility
            raw_text = raw_text.replace("'", "\\'")

            # Populate the nested dictionary structure
            if book not in bible_data:
                bible_data[book] = {}
            if chapter not in bible_data[book]:
                bible_data[book][chapter] = {}

            bible_data[book][chapter][verse] = raw_text

    # Write the Dart file
    with open(dart_filename, mode='w', encoding='utf-8') as f:
        f.write("// @dart=3.7\n")
        f.write("// dart format off\n")
        f.write("const Map<String, Map<int, Map<int, String>>> bibleDataStrongs = {\n")

        for book, chapters in bible_data.items():
            f.write(f"  '{book}': {{\n")
            for chapter, verses in chapters.items():
                f.write(f"    {chapter}: {{\n")
                for verse, text in verses.items():
                    f.write(f"      {verse}: '{text}',\n")
                f.write("    },\n")
            f.write("  },\n")

        f.write("};\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert a Bible CSV data file into a nested Dart Map.")
    parser.add_argument("-i", "--input", required=True, help="Path to the input CSV file")
    parser.add_argument("-o", "--output", required=True, help="Path to the output Dart (.dart) file")

    args = parser.parse_args()

    convert_csv_to_dart(args.input, args.output)
