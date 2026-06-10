#!/usr/bin/env python3
"""Convert semicolon-delimited TSK refs into compact verse spec strings."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


BOOK_LINE_RE = re.compile(r"^  '([^']+)': \{$")
CHAPTER_LINE_RE = re.compile(r"^    (\d+): \{$")
VERSE_LINE_RE = re.compile(r"^(\s+)(\d+):\s+'(.*)',\s*$")
FULL_REF_RE = re.compile(r"^([1-3]?[A-Za-z]{2,4})\s+(\d+):([0-9,\-]+)$")
UNDERSCORE_REF_RE = re.compile(r"^([1-3]?[A-Za-z]{1,4})(\d+)_(\d+(?:[-,]\d+)*)$")
BARE_VERSE_SPEC_RE = re.compile(r"^[0-9,\-]+$")

BOOK_ALIASES = {
    'Ge': 'Gen',
    'Ex': 'Exo',
    'Le': 'Lev',
    'Nu': 'Num',
    'Lu': 'Luk',
    'Ro': 'Rom',
}

RAW_ARTIFACT_TOKENS = {
    'it is:',
    'SIZE=',
    'Son in:',
}


@dataclass(frozen=True)
class ConversionError:
    line_number: int
    book: str | None
    chapter: str | None
    verse: str | None
    token: str
    message: str


@dataclass(frozen=True)
class RefContext:
    book: str
    chapter: str


def escape_dart_single_quote(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'")


def normalize_book(book: str) -> str:
    return BOOK_ALIASES.get(book, book)


def convert_token(
    token: str,
    *,
    previous_ref: RefContext | None,
    allow_raw: bool,
) -> tuple[str | None, RefContext | None, str | None]:
    token = token.strip()
    if not token:
      return None, previous_ref, None

    match = FULL_REF_RE.match(token)
    if match:
        book = normalize_book(match.group(1))
        chapter = match.group(2)
        verse_spec = match.group(3)
        return f'{book}/{chapter}/{verse_spec}', RefContext(book, chapter), None

    match = UNDERSCORE_REF_RE.match(token)
    if match:
        book = normalize_book(match.group(1))
        chapter = match.group(2)
        verse_spec = match.group(3)
        return f'{book}/{chapter}/{verse_spec}', RefContext(book, chapter), None

    if previous_ref is not None and BARE_VERSE_SPEC_RE.match(token):
        return (
            f'{previous_ref.book}/{previous_ref.chapter}/{token}',
            previous_ref,
            None,
        )

    if allow_raw and token in RAW_ARTIFACT_TOKENS:
        return f'!{token}', previous_ref, None

    if allow_raw:
        return f'!{token}', previous_ref, None

    return None, previous_ref, f'Non-canonical TSK token: {token}'


def convert_file(
    input_path: Path,
    output_path: Path,
    *,
    strict: bool,
    report_only: bool,
) -> tuple[int, list[ConversionError]]:
    lines = input_path.read_text(encoding='utf-8').splitlines()
    output_lines: list[str] = []
    errors: list[ConversionError] = []
    converted_lines = 0

    current_book: str | None = None
    current_chapter: str | None = None

    output_lines.append('// Generated from tsk_import/tsk_data_semicolon.dart')
    output_lines.append('// Source script: tsk_import/convert_tsk_to_specs.py')
    output_lines.append('// Do not edit by hand.')
    output_lines.append(
        'const Map<String, Map<int, Map<int, String>>> tskData = {'
    )

    for line_number, line in enumerate(lines, start=1):
        if line.startswith('const Map<'):
            continue

        book_match = BOOK_LINE_RE.match(line)
        if book_match:
            current_book = book_match.group(1)
            output_lines.append(line)
            continue

        chapter_match = CHAPTER_LINE_RE.match(line)
        if chapter_match:
            current_chapter = chapter_match.group(1)
            output_lines.append(line)
            continue

        verse_match = VERSE_LINE_RE.match(line)
        if not verse_match:
            output_lines.append(line)
            continue

        indent, verse, raw_value = verse_match.groups()
        previous_ref: RefContext | None = None
        converted_tokens: list[str] = []

        for raw_token in raw_value.split(';'):
            token = raw_token.strip()
            if not token:
                continue

            converted_token, previous_ref, error = convert_token(
                token,
                previous_ref=previous_ref,
                allow_raw=not strict,
            )

            if error is not None:
                errors.append(
                    ConversionError(
                        line_number=line_number,
                        book=current_book,
                        chapter=current_chapter,
                        verse=verse,
                        token=token,
                        message=error,
                    )
                )
                continue

            if converted_token is not None:
                converted_tokens.append(converted_token)

        if strict and errors:
            continue

        converted_value = ';'.join(converted_tokens)
        output_lines.append(
            f"{indent}{verse}: '{escape_dart_single_quote(converted_value)}',"
        )
        converted_lines += 1

    if report_only or errors:
        return converted_lines, errors

    output_path.write_text('\n'.join(output_lines) + '\n', encoding='utf-8')
    return converted_lines, errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Convert TSK semicolon data to compact verse spec strings.'
    )
    parser.add_argument(
        '--input',
        default='tsk_import/tsk_data_semicolon.dart',
        help='Input semicolon-based Dart TSK file.',
    )
    parser.add_argument(
        '--output',
        default='lib/data/tsk_data_specs.dart',
        help='Output Dart file.',
    )
    parser.add_argument(
        '--strict',
        action=argparse.BooleanOptionalAction,
        default=True,
        help='Fail on non-canonical tokens. Disable to preserve them as !raw tokens.',
    )
    parser.add_argument(
        '--report-only',
        action='store_true',
        help='Validate and report without writing output.',
    )
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()

    converted_lines, errors = convert_file(
        input_path,
        output_path,
        strict=args.strict,
        report_only=args.report_only,
    )

    if errors:
        print(f'Encountered {len(errors)} conversion error(s):')
        for error in errors:
            location = (
                f'{error.book} {error.chapter}:{error.verse}'
                if error.book and error.chapter and error.verse
                else 'unknown location'
            )
            print(
                f'- line {error.line_number} ({location}): '
                f'{error.message} -> {error.token}'
            )
        return 1

    if args.report_only:
        print(f'Validation passed for {converted_lines} verse value lines.')
        return 0

    print(f'Wrote {converted_lines} verse value lines to {output_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
