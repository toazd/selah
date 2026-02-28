#!/usr/bin/env python3
"""
Convert plain-text TSK values in lib/data/tsk_data_delta.dart to Quill Delta JSON strings
with pre-linked verse references.

Important behavior:
- Only transforms lines that match a verse value field:
    <spaces><digits>: '<value>',
- Only parses and links text inside that single-quoted value.
- Leaves delimiter commas (", ") outside links by design.
- Processes longer reference forms first (mixed/comma+range, then dash range, then single).
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


# Match exactly a verse data line with a single-quoted value.
FIELD_RE = re.compile(r"^(\s+)(\d+):\s+'(.*)',\s*$")

# Priority order: longer/more complex first.
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    (
        "mixed_or_comma",
        re.compile(
            r"\b([1-3]?[A-Za-z]{2,4})\s+(\d+):(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)+)\b"
        ),
    ),
    (
        "dash_range",
        re.compile(r"\b([1-3]?[A-Za-z]{2,4})\s+(\d+):(\d+-\d+)\b"),
    ),
    (
        "single",
        re.compile(r"\b([1-3]?[A-Za-z]{2,4})\s+(\d+):(\d+)\b"),
    ),
]


def _is_delta_json(value: str) -> bool:
    value = value.strip()
    if not value.startswith("[") or not value.endswith("]"):
        return False
    try:
        decoded = json.loads(value)
    except Exception:
        return False
    if not isinstance(decoded, list):
        return False
    for op in decoded:
        if not isinstance(op, dict) or "insert" not in op:
            return False
    return True


def _find_references(text: str) -> list[dict[str, object]]:
    used = [False] * len(text)
    refs: list[dict[str, object]] = []

    for _, pattern in PATTERNS:
        matches = list(pattern.finditer(text))
        # Longer matches first, then left-to-right.
        matches.sort(key=lambda m: (-(m.end() - m.start()), m.start()))

        for match in matches:
            start, end = match.span()
            if any(used[i] for i in range(start, end)):
                continue

            for i in range(start, end):
                used[i] = True

            book = match.group(1)
            chapter = match.group(2)
            verse_spec = match.group(3).replace(" ", "")

            refs.append(
                {
                    "start": start,
                    "end": end,
                    "text": match.group(0),
                    "book": book,
                    "chapter": chapter,
                    "verse_spec": verse_spec,
                }
            )

    refs.sort(key=lambda r: int(r["start"]))  # type: ignore[arg-type]
    return refs


def _to_delta_ops(text: str) -> list[dict[str, object]]:
    refs = _find_references(text)
    if not refs:
        return [{"insert": text}]

    ops: list[dict[str, object]] = []
    cursor = 0

    for ref in refs:
        start = int(ref["start"])
        end = int(ref["end"])
        ref_text = str(ref["text"])
        link = f'v://{ref["book"]}/{ref["chapter"]}/{ref["verse_spec"]}'

        if start > cursor:
            ops.append({"insert": text[cursor:start]})

        ops.append({"insert": ref_text, "attributes": {"link": link}})
        cursor = end

    if cursor < len(text):
        ops.append({"insert": text[cursor:]})

    return ops


def _escape_for_dart_single_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def convert_file(input_path: Path, output_path: Path) -> tuple[int, int, int]:
    lines = input_path.read_text(encoding="utf-8").splitlines(keepends=True)
    converted = 0
    skipped_delta = 0
    unchanged = 0
    out_lines: list[str] = []

    for line in lines:
        match = FIELD_RE.match(line)
        if not match:
            out_lines.append(line)
            continue

        indent, verse, raw_value = match.group(1), match.group(2), match.group(3)

        # Skip values that already look like delta JSON.
        if _is_delta_json(raw_value):
            skipped_delta += 1
            out_lines.append(line)
            continue

        text = raw_value
        ops = _to_delta_ops(text)
        delta_json = json.dumps(ops, ensure_ascii=False, separators=(",", ":"))
        escaped = _escape_for_dart_single_quote(delta_json)
        new_line = f"{indent}{verse}: '{escaped}',\n"

        if new_line == line:
            unchanged += 1
            out_lines.append(line)
            continue

        converted += 1
        out_lines.append(new_line)

    output_path.write_text("".join(out_lines), encoding="utf-8")
    return converted, skipped_delta, unchanged


def _default_output_for(input_path: Path) -> Path:
    # lib/data/tsk_data_delta.dart -> lib/data/tsk_data.delta.dart
    if input_path.name.endswith(".dart"):
        return input_path.with_name(input_path.name[:-5] + ".delta.dart")
    return input_path.with_name(input_path.name + ".delta")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert tsk_data_delta.dart plain-text values to pre-linked Quill Delta JSON values."
    )
    parser.add_argument(
        "--input",
        default="lib/data/tsk_data_delta.dart",
        help="Path to input Dart map file (default: lib/data/tsk_data_delta.dart)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Path to output file (default: <input>.delta.dart). Ignored with --in-place.",
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="Rewrite the input file in place.",
    )
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        raise SystemExit(f"Input file does not exist: {input_path}")

    output_path = input_path if args.in_place else (
        Path(args.output).resolve() if args.output else _default_output_for(input_path)
    )

    converted, skipped_delta, unchanged = convert_file(input_path, output_path)
    print(f"Input:  {input_path}")
    print(f"Output: {output_path}")
    print(f"Converted lines: {converted}")
    print(f"Skipped (already delta): {skipped_delta}")
    print(f"Unchanged matched lines: {unchanged}")


if __name__ == "__main__":
    main()
