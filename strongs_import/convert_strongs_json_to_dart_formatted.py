import json
import re
from html.parser import HTMLParser

# Fast regex to identify Strong's numbers (e.g., H44, G1118)
STRONGS_REGEX = re.compile(r'\b([HG]\d+)\b')

# Fixes cases like:
# <b>אֵב </b> -> <b>אֵב</b>
# while leaving:
# <b>Strong's: </b>
# <b>Derivation: </b>
# untouched.
HEBREW_BOLD_TAG = re.compile(r'<b>([^<]*)</b>')

def fix_hebrew_bold_spacing(html):
    def repl(match):
        content = match.group(1)

        # Only trim trailing whitespace if the bold text contains Hebrew
        if re.search(r'[\u0590-\u05FF]', content):
            content = re.sub(r'\s+$', '', content)

        return f'<b>{content}</b>'

    return HEBREW_BOLD_TAG.sub(repl, html)

class MarkdownTextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text_pieces = []
        self.is_hebrew_or_greek = False

    def handle_starttag(self, tag, attrs):
        if tag == 'br':
            self.text_pieces.append('\n')
        elif tag == 'b':
            self.text_pieces.append('**')
        elif tag == 'i':
            self.text_pieces.append('*')
        elif tag == 'hu':
            self.is_hebrew_or_greek = True
            self.text_pieces.append('')
        elif tag == 'gu':
            self.is_hebrew_or_greek = True
            self.text_pieces.append('')

    def handle_endtag(self, tag):
        if tag == 'b':
            self.text_pieces.append('**')
        elif tag == 'i':
            self.text_pieces.append('*')
        elif tag == 'hu':
            self.is_hebrew_or_greek = False
            self.text_pieces.append('')
        elif tag == 'gu':
            self.is_hebrew_or_greek = False
            self.text_pieces.append('')

    def handle_data(self, data):
        # 1. Standardize text white spaces unless it's a raw language block
        cleaned_data = re.sub(r'\s+', ' ', data) if not self.is_hebrew_or_greek else data

        # 2. Automatically wrap static Strong's links into tokens
        if not self.is_hebrew_or_greek:
            last_idx = 0
            for match in STRONGS_REGEX.finditer(cleaned_data):
                start, end = match.span()

                # Add text leading up to the Strong's number link
                if start > last_idx:
                    self.text_pieces.append(cleaned_data[last_idx:start])

                # Wrap the matching link key in tags
                #self.text_pieces.append(f"<link>{match.group(1)}</link>")
                self.text_pieces.append(f"{match.group(1)}")
                last_idx = end

            # Append remaining trailing text context
            if last_idx < len(cleaned_data):
                self.text_pieces.append(cleaned_data[last_idx:])
        else:
            self.text_pieces.append(cleaned_data)

    def get_formatted_text(self):
        full_text = "".join(self.text_pieces)

        # Clean up any duplicate newline sequences
        full_text = re.sub(r'\n{3,}', '\n\n', full_text)

        return full_text.strip()

def escape_for_dart(text):
    """
    Escapes quotes, backslashes, and newlines so that Dart treats
    the block as a standard, error-free single-line string literal.
    """
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def main():
    input_filename = "strongs_dictionary_nooccr.json"
    output_filename = "strongs_definitions.dart"

    print(f"Loading data from {input_filename}...")
    with open(input_filename, "r", encoding="utf-8") as f:
        data = json.load(f)

    hebrew_entries = {}
    greek_entries = {}

    print("Parsing definitions and applying markdown markers...")
    for item in data:
        topic = item.get("topic", "")
        definition_html = item.get("definition", "")

        if not topic or not definition_html:
            continue

        # Remove unwanted spaces before </b> in Hebrew headwords
        definition_html = fix_hebrew_bold_spacing(definition_html)

        testament = topic[0]  # "H" or "G"

        try:
            strongs_id = int(topic[1:])
        except ValueError:
            continue

        parser = MarkdownTextParser()
        parser.feed(definition_html)
        clean_string = parser.get_formatted_text()

        # Prepend Strong's number
        #final_string = f"**{topic}** {clean_string}"
        final_string = f"{clean_string}"

        # Escape for Dart
        escaped_string = escape_for_dart(final_string)

        if testament == "H":
            hebrew_entries[strongs_id] = escaped_string
        elif testament == "G":
            greek_entries[strongs_id] = escaped_string

    print(f"Writing static map data to {output_filename}...")

    with open(output_filename, "w", encoding="utf-8") as out:
        out.write("const Map<String, Map<int, String>> strongsDefinitions = {\n")

        # Hebrew Section
        out.write('  "H": {\n')
        for sid in sorted(hebrew_entries.keys()):
            out.write(f'    {sid}: "{hebrew_entries[sid]}",\n')
        out.write("  },\n")

        # Greek Section
        out.write('  "G": {\n')
        for sid in sorted(greek_entries.keys()):
            out.write(f'    {sid}: "{greek_entries[sid]}",\n')
        out.write("  },\n")

        out.write("};\n")

    print(f"Successfully generated {output_filename}")

if __name__ == "__main__":
    main()
