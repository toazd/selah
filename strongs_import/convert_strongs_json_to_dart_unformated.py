import json
import re
from html.parser import HTMLParser

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

class PlainTextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text_pieces = []
        self.is_hebrew_or_greek = False

    def handle_starttag(self, tag, attrs):
        # We only preserve line breaks from <br> tags
        if tag == 'br':
            self.text_pieces.append('\n')
        elif tag in ('hu', 'gu'):
            self.is_hebrew_or_greek = True

    def handle_endtag(self, tag):
        if tag in ('hu', 'gu'):
            self.is_hebrew_or_greek = False

    def handle_data(self, data):
        # Standardize non-Hebrew/Greek white spaces
        cleaned_data = re.sub(r'\s+', ' ', data) if not self.is_hebrew_or_greek else data
        self.text_pieces.append(cleaned_data)

    def get_plain_text(self):
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

    print("Parsing definitions into pure plain text...")
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

        parser = PlainTextParser()
        parser.feed(definition_html)
        clean_string = parser.get_plain_text()

        # Prepend the plain Strong's number without markdown characters
        final_string = f"{topic} {clean_string}"

        # Escape for Dart map format compatibility
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
