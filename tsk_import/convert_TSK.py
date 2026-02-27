import csv
import sys

# Mapping 1-66 to KJV 3-letter abbreviations (Bibleanalyzer style)
BOOKS = {
    1: "Gen", 2: "Exo", 3: "Lev", 4: "Num", 5: "Deu", 6: "Jos", 7: "Jdg", 8: "Rth",
    9: "1Sa", 10: "2Sa", 11: "1Ki", 12: "2Ki", 13: "1Ch", 14: "2Ch", 15: "Ezr", 16: "Neh",
    17: "Est", 18: "Job", 19: "Psa", 20: "Pro", 21: "Ecc", 22: "Son", 23: "Isa", 24: "Jer",
    25: "Lam", 26: "Eze", 27: "Dan", 28: "Hos", 29: "Joe", 30: "Amo", 31: "Oba", 32: "Jon",
    33: "Mic", 34: "Nah", 35: "Hab", 36: "Zep", 37: "Hag", 38: "Zec", 39: "Mal", 40: "Mat",
    41: "Mar", 42: "Luk", 43: "Joh", 44: "Act", 45: "Rom", 46: "1Co", 47: "2Co", 48: "Gal",
    49: "Eph", 50: "Phi", 51: "Col", 52: "1Th", 53: "2Th", 54: "1Ti", 55: "2Ti", 56: "Tit",
    57: "Phm", 58: "Heb", 59: "Jam", 60: "1Pe", 61: "2Pe", 62: "1Jo", 63: "2Jo", 64: "3Jo",
    65: "Jud", 66: "Rev"
}

def convert_tsk(input_file, output_file):
    # Dictionary to hold the nested structure: {Book: {Chapter: {Verse: "Refs"}}}
    data = {}

    try:
        with open(input_file, mode='r', encoding='utf-8') as f:
            # Using tab delimiter as specified
            reader = csv.reader(f, delimiter='\t')
            next(reader)  # Skip header row

            for row in reader:
                if not row or len(row) < 4:
                    continue
                
                # Parse fields
                book_num = int(row[0])
                chapter = int(row[1])
                verse = int(row[2])
                refs = row[3].strip()

                book_name = BOOKS.get(book_num, f"B{book_num}")

                # Initialize nested levels
                if book_name not in data:
                    data[book_name] = {}
                if chapter not in data[book_name]:
                    data[book_name][chapter] = {}
                
                # If verse already exists (like Gen 1:1 in your example), append with semicolon
                if verse in data[book_name][chapter]:
                    data[book_name][chapter][verse] += f"; {refs}"
                else:
                    data[book_name][chapter][verse] = refs

        # Write to Dart file
        with open(output_file, mode='w', encoding='utf-8') as f:
            f.write("const Map<String, Map<int, Map<int, String>>> tskData = {\n")
            
            for book, chapters in data.items():
                f.write(f"  '{book}': {{\n")
                for chap, verses in chapters.items():
                    f.write(f"    {chap}: {{\n")
                    for vs, ref_str in verses.items():
                        # Escape single quotes for Dart string safety
                        safe_refs = ref_str.replace("'", "\\'")
                        f.write(f"      {vs}: '{safe_refs}',\n")
                    f.write("    },\n")
                f.write("  },\n")
            
            f.write("};\n")

        print(f"Success! Data written to {output_file}")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # Usage: python convert_tsk.py input.csv tsk_data.dart
    if len(sys.argv) > 2:
        convert_tsk(sys.argv[1], sys.argv[2])
    else:
        print("Usage: python convert_tsk.py <input_tab_file> <output_dart_file>")

