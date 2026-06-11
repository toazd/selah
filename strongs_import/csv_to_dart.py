#!/usr/bin/env python3
import csv
import sys

def convert_csv_to_dart(input_file, output_file):
    # Dictionaries to split the data correctly
    data = {'H': {}, 'G': {}}

    with open(input_file, 'r', encoding='utf-8') as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            lang = row['Language'].strip().upper()
            try:
                num = int(row['StrongsNumber'].strip())
            except ValueError:
                continue # Skip invalid rows or headers safely

            definition = row['Definition']
            # Escape newlines and quotes to match valid Dart string literal rules
            escaped_definition = definition.replace('\n', '\\n').replace('"', '\\"')

            if lang in data:
                data[lang][num] = escaped_definition

    # Write the formatted Dart file
    with open(output_file, 'w', encoding='utf-8') as outfile:
        outfile.write("const Map<String, Map<int, String>> strongsDefinitions = {\n")

        for lang in ['H', 'G']:
            outfile.write(f'  "{lang}": {{\n')
            # Sort numerically to keep your dictionary structured cleanly
            for num in sorted(data[lang].keys()):
                outfile.write(f'    {num}: "{data[lang][num]}",\n')
            outfile.write("  },\n")

        outfile.write("};\n")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python csv_to_dart.py input.csv output.dart")
        sys.exit(1)
    convert_csv_to_dart(sys.argv[1], sys.argv[2])
    print(f"Successfully converted {sys.argv[1]} to {sys.argv[2]}")
