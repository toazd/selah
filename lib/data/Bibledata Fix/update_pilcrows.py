"""Copy missing pilcrow markers from bible_data.dart to bible_data_KJPBS.dart.

Only an exact book/chapter/verse match is eligible for an update.  Existing
KJPBS verse text is otherwise left unchanged.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


# Use an escape so this remains the actual U+00B6 character regardless of
# the terminal or editor encoding used to view this file.
PILCROW = "\u00b6 "
# The two data files use different abbreviations for many books.  These
# aliases are applied to both files, making the source and target comparable.
BOOK_ALIASES = {
    "Exod": "Exo",
    "Deut": "Deu",
    "Josh": "Jos",
    "Judg": "Jdg",
    "Ruth": "Rth",
    "1Sam": "1Sa",
    "2Sam": "2Sa",
    "1Kgs": "1Ki",
    "2Kgs": "2Ki",
    "1Chr": "1Ch",
    "2Chr": "2Ch",
    "Ezra": "Ezr",
    "Esth": "Est",
    "Ps": "Psa",
    "Prov": "Pro",
    "Eccl": "Ecc",
    "Song": "Son",
    "Ezek": "Eze",
    "Joel": "Joe",
    "Amos": "Amo",
    "Obad": "Oba",
    "Jonah": "Jon",
    "Zeph": "Zep",
    "Zech": "Zec",
    "Matt": "Mat",
    "Mark": "Mar",
    "Luke": "Luk",
    "John": "Joh",
    "Acts": "Act",
    "1Cor": "1Co",
    "2Cor": "2Co",
    "Phil": "Phi",
    "1Thess": "1Th",
    "2Thess": "2Th",
    "1Tim": "1Ti",
    "2Tim": "2Ti",
    "Titus": "Tit",
    "Phlm": "Phm",
    "Jas": "Jam",
    "1Pet": "1Pe",
    "2Pet": "2Pe",
    "1John": "1Jo",
    "2John": "2Jo",
    "3John": "3Jo",
    "Jude": "Jud",
}
BOOK_RE = re.compile(r"^\s*'([^']+)'\s*:\s*\{\s*$")
CHAPTER_RE = re.compile(r"^\s*(\d+)\s*:\s*\{\s*$")
VERSE_RE = re.compile(r"^(?P<indent>\s*)(?P<verse>\d+)\s*:\s*'(?P<text>.*)'(?P<comma>,?)(?P<newline>\r?\n)?$")


def read_verses(path: Path) -> dict[tuple[str, int, int], str]:
    """Read verse text keyed by (book, chapter, verse)."""
    verses: dict[tuple[str, int, int], str] = {}
    book: str | None = None
    chapter: int | None = None

    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        book_match = BOOK_RE.match(line)
        if book_match:
            book = book_match.group(1)
            chapter = None
            continue

        chapter_match = CHAPTER_RE.match(line)
        if chapter_match and book is not None:
            chapter = int(chapter_match.group(1))
            continue

        verse_match = VERSE_RE.match(line)
        if verse_match and book is not None and chapter is not None:
            key = (BOOK_ALIASES.get(book, book), chapter, int(verse_match.group("verse")))
            if key in verses:
                raise ValueError(f"Duplicate verse key {key} at {path}:{line_number}")
            verses[key] = verse_match.group("text")

    return verses


def update_file(source_path: Path, target_path: Path, *, dry_run: bool = False) -> int:
    source = read_verses(source_path)
    lines = target_path.read_text(encoding="utf-8").splitlines(keepends=True)
    updated: list[str] = []
    book: str | None = None
    chapter: int | None = None
    changes = 0

    for line in lines:
        book_match = BOOK_RE.match(line)
        if book_match:
            book = book_match.group(1)
            chapter = None

        chapter_match = CHAPTER_RE.match(line)
        if chapter_match and book is not None:
            chapter = int(chapter_match.group(1))

        verse_match = VERSE_RE.match(line)
        if verse_match and book is not None and chapter is not None:
            key = (BOOK_ALIASES.get(book, book), chapter, int(verse_match.group("verse")))
            source_text = source.get(key)
            target_text = verse_match.group("text")

            if source_text is not None and source_text.startswith(PILCROW):
                if not target_text.startswith(PILCROW):
                    prefix = verse_match.group("indent")
                    verse = verse_match.group("verse")
                    comma = verse_match.group("comma")
                    newline = verse_match.group("newline") or ""
                    line = f"{prefix}{verse}: '{PILCROW}{target_text}'{comma}{newline}"
                    changes += 1

        updated.append(line)

    if not dry_run:
        target_path.write_text("".join(updated), encoding="utf-8", newline="")

    return changes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=Path("bible_data.dart"))
    parser.add_argument("target", nargs="?", type=Path, default=Path("bible_data_KJPBS.dart"))
    parser.add_argument("--dry-run", action="store_true", help="Report changes without modifying the target")
    args = parser.parse_args()

    changes = update_file(args.source, args.target, dry_run=args.dry_run)
    action = "would update" if args.dry_run else "updated"
    print(f"{action} {changes} verse(s) in {args.target}")


if __name__ == "__main__":
    main()
