#!/usr/bin/env python3
"""Check gettext syntax and keep JavaScript strings in sync with catalogs."""

from __future__ import annotations

import ast
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "luci-app-easytier"
POT = APP_ROOT / "po/templates/easytier.pot"
PO = APP_ROOT / "po/zh_Hans/easytier.po"


def parse_catalog(text: str) -> set[tuple[str, str]]:
    entries: set[tuple[str, str]] = set()
    current: dict[str, str] = {}
    active_field: str | None = None

    def finish_entry() -> None:
        if current.get("msgid"):
            entries.add((current.get("msgctxt", ""), current["msgid"]))

    for line in text.splitlines():
        if not line or line.startswith("#~"):
            if not line:
                finish_entry()
                current.clear()
                active_field = None
            continue

        match = re.match(r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d+\])?)\s+(".*")$', line)
        if match:
            field, value = match.groups()
            try:
                decoded = ast.literal_eval(value)
            except (SyntaxError, ValueError) as error:
                raise ValueError(f"invalid quoted PO string: {line}") from error
            active_field = field.split("[", maxsplit=1)[0]
            current[active_field] = decoded
            continue

        continuation = re.match(r'^\s+(".*")$', line)
        if continuation and active_field:
            try:
                current[active_field] = current.get(active_field, "") + ast.literal_eval(continuation.group(1))
            except (SyntaxError, ValueError) as error:
                raise ValueError(f"invalid PO continuation: {line}") from error

    finish_entry()
    return entries


def extract_javascript_strings() -> set[tuple[str, str]]:
    sources = sorted((APP_ROOT / "htdocs/luci-static/resources").rglob("*.js"))
    if not sources:
        raise ValueError("no LuCI JavaScript source files were found")
    relative_sources = [str(path.relative_to(APP_ROOT)) for path in sources]
    result = subprocess.run(
        [
            "xgettext",
            "--language=JavaScript",
            "--keyword=_",
            "--from-code=UTF-8",
            "--output=-",
            *relative_sources,
        ],
        cwd=APP_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return parse_catalog(result.stdout)


def describe(entries: set[tuple[str, str]]) -> list[str]:
    return [f"{context!r}: {message!r}" for context, message in sorted(entries)]


def missing_catalog_keys(
    extracted: set[tuple[str, str]],
    catalogs: dict[str, set[tuple[str, str]]],
) -> dict[str, set[tuple[str, str]]]:
    return {name: extracted - entries for name, entries in catalogs.items() if extracted - entries}


def main() -> int:
    try:
        extracted = extract_javascript_strings()
        template = parse_catalog(POT.read_text(encoding="utf-8"))
        translated = parse_catalog(PO.read_text(encoding="utf-8"))
        errors: list[str] = []
        for catalog_name, missing in missing_catalog_keys(extracted, {"POT": template, "Chinese PO": translated}).items():
            errors.append(f"{catalog_name} is missing JavaScript keys:\n  " + "\n  ".join(describe(missing)))
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print(f"Translation keys are synchronized ({len(extracted)} strings).")
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"translation check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
