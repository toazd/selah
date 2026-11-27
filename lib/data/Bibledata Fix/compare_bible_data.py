"""Create an HTML diff of two Bible data Dart files.

The comparison ignores the placement of <i> and </i> tags, but reports every
other verse-text difference.  Verse keys are compared using the same book-name
aliases as update_pilcrows.py.
"""

from __future__ import annotations

import argparse
import difflib
import html
import re
from dataclasses import dataclass
from pathlib import Path

from update_pilcrows import BOOK_ALIASES


BOOK_RE = re.compile(r"^\s*'([^']+)'\s*:\s*\{\s*$")
CHAPTER_RE = re.compile(r"^\s*(\d+)\s*:\s*\{\s*$")
VERSE_RE = re.compile(
    r"^\s*(?P<verse>\d+)\s*:\s*'(?P<text>.*)'(?:,)?\s*(?:\r?\n)?$"
)
ITALIC_TAG_RE = re.compile(r"</?i>")
DIALOGUE_TAG_RE = re.compile(r"</?r>")
# Ignore ordinary hyphens, en dashes, and em dashes during comparison.
DASH_RE = re.compile(r"[-\u2013\u2014]")


@dataclass(frozen=True)
class Verse:
    book: str
    chapter: int
    number: int
    text: str


def parse_file(path: Path) -> dict[tuple[str, int, int], Verse]:
    verses: dict[tuple[str, int, int], Verse] = {}
    book: str | None = None
    chapter: int | None = None

    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        book_match = BOOK_RE.match(line)
        if book_match:
            book = BOOK_ALIASES.get(book_match.group(1), book_match.group(1))
            chapter = None
            continue

        chapter_match = CHAPTER_RE.match(line)
        if chapter_match and book is not None:
            chapter = int(chapter_match.group(1))
            continue

        verse_match = VERSE_RE.match(line)
        if verse_match and book is not None and chapter is not None:
            number = int(verse_match.group("verse"))
            key = (book, chapter, number)
            if key in verses:
                raise ValueError(f"Duplicate verse key {key} at {path}:{line_number}")
            verses[key] = Verse(book, chapter, number, verse_match.group("text"))

    return verses


def without_italics(text: str) -> str:
    text = ITALIC_TAG_RE.sub("", text)
    text = DIALOGUE_TAG_RE.sub("", text)
    text = DASH_RE.sub("", text)
    # Treat runs of spaces, tabs, and other whitespace as equivalent.
    return re.sub(r"\s+", " ", text).strip()


def code(value: str) -> str:
    return html.escape(value, quote=False)


def diff_tokens(value: str) -> list[str]:
    """Split text so tags, words, and whitespace can be highlighted cleanly."""
    return re.findall(r"<[^>]+>|\s+|[^<>\s]+", value)


def highlighted_diff(left: str, right: str) -> tuple[str, str]:
    """Return HTML for both sides with changed spans highlighted."""
    left_tokens = diff_tokens(left)
    right_tokens = diff_tokens(right)
    matcher = difflib.SequenceMatcher(None, left_tokens, right_tokens)
    left_html: list[str] = []
    right_html: list[str] = []

    for tag, start_left, end_left, start_right, end_right in matcher.get_opcodes():
        left_part = code("".join(left_tokens[start_left:end_left]))
        right_part = code("".join(right_tokens[start_right:end_right]))
        if tag == "equal":
            left_html.append(left_part)
            right_html.append(right_part)
        else:
            if left_part:
                left_html.append(f'<mark class="removed">{left_part}</mark>')
            if right_part:
                right_html.append(f'<mark class="added">{right_part}</mark>')

    return "".join(left_html), "".join(right_html)


def make_report(source_path: Path, target_path: Path, output_path: Path) -> int:
    source = parse_file(source_path)
    target = parse_file(target_path)
    keys = sorted(set(source) | set(target))
    differences: list[tuple[tuple[str, int, int], str, str, str]] = []

    for key in keys:
        left = source.get(key)
        right = target.get(key)
        if left is None:
            differences.append((key, "Missing from source", "", right.text))
        elif right is None:
            differences.append((key, "Missing from target", left.text, ""))
        elif without_italics(left.text) != without_italics(right.text):
            differences.append((key, "Text differs", left.text, right.text))

    rows = []
    for (book, chapter, number), reason, left, right in differences:
        left_display, right_display = highlighted_diff(left, right)
        rows.append(
            "<tr>"
            f"<td>{code(book)} {chapter}:{number}</td>"
            f"<td class=reason>{code(reason)}</td>"
            f"<td class=source><pre>{left_display}</pre></td>"
            f"<td class=target><pre>{right_display}</pre></td>"
            "</tr>"
        )

    body = "\n".join(rows) or (
        '<tr><td colspan="4" class="none">No differences found after ignoring italic tags.</td></tr>'
    )
    document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Bible data comparison</title>
<style>
body {{ font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #222; }}
h1 {{ margin-bottom: 4px; }}
.summary {{ color: #555; margin-bottom: 18px; }}
table {{ border-collapse: collapse; width: 100%; table-layout: fixed; }}
th, td {{ border: 1px solid #ccc; padding: 8px; vertical-align: top; text-align: left; }}
th {{ background: #333; color: white; }}
tr:nth-child(even) {{ background: #f7f7f7; }}
td:first-child {{ width: 11%; font-weight: 600; white-space: nowrap; }}
td.reason {{ width: 12%; color: #8a3b00; font-weight: 600; }}
td.source {{ background: #fff0f0; width: 38.5%; }}
td.target {{ background: #effff0; width: 38.5%; }}
mark.removed {{ background: #ff8f8f; color: #650000; }}
mark.added {{ background: #8ff0a0; color: #064d14; }}
pre {{ white-space: pre-wrap; overflow-wrap: anywhere; margin: 0; font: 13px Consolas, monospace; }}
.none {{ color: #176b2c; font-weight: 600; padding: 16px; }}
</style>
</head>
<body>
<h1>Bible data comparison</h1>
<div class="summary">{len(differences)} difference(s), ignoring italic/red-letter tag placement, whitespace, and hyphen/en-dash/em-dash differences.<br>
Source: {code(str(source_path))}<br>Target: {code(str(target_path))}</div>
<table>
<thead><tr><th>Verse</th><th>Reason</th><th>Source</th><th>Target</th></tr></thead>
<tbody>{body}</tbody>
</table>
</body>
</html>
"""
    output_path.write_text(document, encoding="utf-8")
    return len(differences)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=Path("bible_data.dart"))
    parser.add_argument("target", nargs="?", type=Path, default=Path("bible_data_KJPBS.dart"))
    parser.add_argument("-o", "--output", type=Path, default=Path("bible_data_diff.html"))
    args = parser.parse_args()

    count = make_report(args.source, args.target, args.output)
    print(f"Wrote {count} difference(s) to {args.output}")


if __name__ == "__main__":
    main()
