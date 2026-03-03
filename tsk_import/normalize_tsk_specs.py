#!/usr/bin/env python3
"""Normalize any remaining display-style refs inside tsk_data_specs.dart."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


FIELD_RE = re.compile(r"(^\s+\d+:\s*(?:\n\s+)?)'((?:\\'|[^'])*)'(,)", re.MULTILINE)
BOOK_RE = re.compile(r"^  '([^']+)': \{$", re.MULTILINE)
CHAPTER_RE = re.compile(r"^    (\d+): \{$", re.MULTILINE)
VERSE_PREFIX_RE = re.compile(r"^\s+(\d+):\s*(?:\n\s+)?$")
SPEC_RE = re.compile(r"^[1-3]?[A-Za-z]{2,4}/\d+/[0-9,\-]+$")
DISPLAY_RE = re.compile(r"^([1-3]?[A-Za-z]{2,4})\s+(\d+):([0-9,\-]+)$")
UNDERSCORE_RE = re.compile(r"^([1-3]?[A-Za-z]{1,4})(\d+)_(\d+(?:[-,]\d+)*)$")
BARE_SPEC_RE = re.compile(r"^[0-9,\-]+$")

BOOK_ALIASES = {
    'Ge': 'Gen',
    'Ex': 'Exo',
    'Le': 'Lev',
    'Nu': 'Num',
    'Lu': 'Luk',
    'Ro': 'Rom',
}


@dataclass(frozen=True)
class RefContext:
    book: str
    chapter: str


@dataclass(frozen=True)
class TokenIssue:
    line_number: int
    book: str | None
    chapter: str | None
    verse: str | None
    token: str
    reason: str


def normalize_book(book: str) -> str:
    return BOOK_ALIASES.get(book, book)


def escape_dart_single_quote(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'")


def build_line_index(text: str) -> list[int]:
    starts = [0]
    for match in re.finditer(r'\n', text):
        starts.append(match.end())
    return starts


def offset_to_line(offset: int, line_starts: list[int]) -> int:
    low = 0
    high = len(line_starts) - 1
    while low <= high:
        mid = (low + high) // 2
        if line_starts[mid] <= offset:
            low = mid + 1
        else:
            high = mid - 1
    return high + 1


def escape_token_for_report(token: str) -> str:
    return token.replace('\n', '\\n')


def build_section_index(text: str) -> dict[int, tuple[str | None, str | None]]:
    section_index: dict[int, tuple[str | None, str | None]] = {}
    current_book: str | None = None
    current_chapter: str | None = None

    for line_number, line in enumerate(text.splitlines(), start=1):
        book_match = BOOK_RE.match(line)
        if book_match:
            current_book = book_match.group(1)
        chapter_match = CHAPTER_RE.match(line)
        if chapter_match:
            current_chapter = chapter_match.group(1)
        section_index[line_number] = (current_book, current_chapter)

    return section_index


def normalize_token(
    token: str,
    previous_ref: RefContext | None,
) -> tuple[str | None, RefContext | None]:
    if SPEC_RE.match(token):
        parts = token.split('/', 2)
        return token, RefContext(parts[0], parts[1])

    match = DISPLAY_RE.match(token)
    if match:
        book = normalize_book(match.group(1))
        chapter = match.group(2)
        verse_spec = match.group(3)
        return f'{book}/{chapter}/{verse_spec}', RefContext(book, chapter)

    match = UNDERSCORE_RE.match(token)
    if match:
        book = normalize_book(match.group(1))
        chapter = match.group(2)
        verse_spec = match.group(3)
        return f'{book}/{chapter}/{verse_spec}', RefContext(book, chapter)

    if previous_ref is not None and BARE_SPEC_RE.match(token):
        return (
            f'{previous_ref.book}/{previous_ref.chapter}/{token}',
            previous_ref,
        )

    return None, previous_ref


def normalize_specs_file(
    input_path: Path,
    output_path: Path,
    report_path: Path,
) -> tuple[int, int, list[TokenIssue]]:
    text = input_path.read_text(encoding='utf-8')
    line_starts = build_line_index(text)
    section_index = build_section_index(text)
    converted_token_count = 0
    unchanged_field_count = 0
    issues: list[TokenIssue] = []

    rebuilt: list[str] = []
    cursor = 0

    for match in FIELD_RE.finditer(text):
        rebuilt.append(text[cursor:match.start(2)])
        raw_value = match.group(2)
        field_offset = match.start(2)
        line_number = offset_to_line(field_offset, line_starts)
        book, chapter = section_index.get(line_number, (None, None))
        verse_match = VERSE_PREFIX_RE.match(match.group(1))
        verse = verse_match.group(1) if verse_match else None

        tokens = [token.strip() for token in raw_value.split(';') if token.strip()]
        previous_ref: RefContext | None = None
        normalized_tokens: list[str] = []
        changed = False

        for token in tokens:
            normalized, previous_ref = normalize_token(token, previous_ref)
            if normalized is None:
                issues.append(
                    TokenIssue(
                        line_number=line_number,
                        book=book,
                        chapter=chapter,
                        verse=verse,
                        token=token,
                        reason='Unrecognized token',
                    )
                )
                normalized_tokens.append(token)
                continue

            normalized_tokens.append(normalized)
            if normalized != token:
                converted_token_count += 1
                changed = True

        if not changed:
            unchanged_field_count += 1

        rebuilt.append(escape_dart_single_quote(';'.join(normalized_tokens)))
        cursor = match.end(2)

    rebuilt.append(text[cursor:])
    output_path.write_text(''.join(rebuilt), encoding='utf-8')

    report_lines = [
        f'Input: {input_path}',
        f'Output: {output_path}',
        f'Converted tokens: {converted_token_count}',
        f'Fields unchanged: {unchanged_field_count}',
        f'Unrecognized tokens: {len(issues)}',
        '',
    ]

    for issue in issues:
        location = (
            f'{issue.book} {issue.chapter}:{issue.verse}'
            if issue.book and issue.chapter and issue.verse
            else 'unknown location'
        )
        report_lines.append(
            f'line {issue.line_number} | {location} | '
            f'{issue.reason} | {escape_token_for_report(issue.token)}'
        )

    report_path.write_text('\n'.join(report_lines) + '\n', encoding='utf-8')
    return converted_token_count, unchanged_field_count, issues


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Normalize remaining legacy TSK refs inside tsk_data_specs.dart.'
    )
    parser.add_argument(
        '--input',
        default='tsk_data_specs.dart',
        help='Input spec-format Dart file.',
    )
    parser.add_argument(
        '--output',
        default='output.txt',
        help='Output spec-format Dart file.',
    )
    parser.add_argument(
        '--report',
        default='tsk_specs_normalize_report.txt',
        help='Path to write the normalization report.',
    )
    args = parser.parse_args()

    converted_token_count, unchanged_field_count, issues = normalize_specs_file(
        Path(args.input).resolve(),
        Path(args.output).resolve(),
        Path(args.report).resolve(),
    )

    print(f'Converted tokens: {converted_token_count}')
    print(f'Fields unchanged: {unchanged_field_count}')
    print(f'Unrecognized tokens: {len(issues)}')
    print(f'Report: {Path(args.report).resolve()}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
