import re

def remove_unmatched_bold_closures(dart_file_path, output_file_path):
    # Regex to find definition blocks in the Dart file
    # Captures the definition content inside the single quotes
    definition_line_re = re.compile(r"^(\s*'definition':\s*')(.*)('(,\s*|)?)$")

    cleaned_lines = []
    fixed_count = 0

    with open(dart_file_path, 'r', encoding='utf-8') as f:
        for line in f:
            # Check if this line contains a definition string
            match = definition_line_re.match(line)

            if match:
                prefix = match.group(1)   # e.g.,   'definition': '
                content = match.group(2)  # The actual dictionary text
                suffix = match.group(3)   # e.g., ',

                # Check if there are any </b> tags to evaluate
                if '</b>' in content:
                    # Tokenize the content into bold open tags, close tags, and regular text
                    # This allows us to track tag state accurately
                    tokens = re.split(r'(<b>|</b>)', content)

                    is_bold_open = False
                    rebuilt_content = []

                    for token in tokens:
                        if token == '<b>':
                            is_bold_open = True
                            rebuilt_content.append(token)
                        elif token == '</b>':
                            if is_bold_open:
                                # Safe, matched tag pair. Close it and reset state.
                                is_bold_open = False
                                rebuilt_content.append(token)
                            else:
                                # Slay the beast! This is an unmatched </b> tag.
                                fixed_count += 1
                                continue
                        else:
                            # Standard text token
                            rebuilt_content.append(token)

                    # Reconstruct the cleaned text content
                    new_content = "".join(rebuilt_content)
                    line = f"{prefix}{new_content}{suffix}\n"

            cleaned_lines.append(line)

    # Write the cleaned contents to the new file
    with open(output_file_path, 'w', encoding='utf-8') as f:
        f.writelines(cleaned_lines)

    print(f"✨ Operation Complete!")
    print(f"⚔️  Successfully removed {fixed_count} unmatched </b> tags without touching your Dart code syntax.")

# Execute the cleanup script
# Replace 'websters_data.dart' with your actual filename
remove_unmatched_bold_closures('websters_1828.dart', 'websters_data_clean.dart')
