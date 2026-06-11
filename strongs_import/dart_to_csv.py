#!/usr/bin/env python3
import re
import csv
import sys

def convert_dart_to_csv(input_file, output_file):
    # Regex to capture the language map opening: "H": { or "G": {
    lang_pattern = re.compile(r'^\s*["\']([HG])["\']\s*:\s*\{')
    # Regex to capture individual entries: 1: "definition" or 1: 'definition'
    entry_pattern = re.compile(r'^\s*(\d+)\s*:\s*["\'](.*)["\']\s*,\s*$')

    current_lang = None

    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', encoding='utf-8', newline='') as outfile:

        writer = csv.writer(outfile, quoting=csv.QUOTE_ALL)
        writer.writerow(['Language', 'StrongsNumber', 'Definition'])

        for line in infile:
            # Check for language switch
            lang_match = lang_pattern.match(line)
            if lang_match:
                current_lang = lang_match.group(1)
                continue

            # Check for data entry
            entry_match = entry_pattern.match(line)
            if entry_match and current_lang:
                strongs_num = entry_match.group(1)
                # Unescape escaped newlines and quotes inside the Dart string
                definition = entry_match.group(2).replace('\\n', '\n').replace('\\"', '"').replace("\\'", "'")

                writer.writerow([current_lang, strongs_num, definition])

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python dart_to_csv.py input.dart output.csv")
        sys.exit(1)
    convert_dart_to_csv(sys.argv[1], sys.argv[2])
    print(f"Successfully converted {sys.argv[1]} to {sys.argv[2]}")
