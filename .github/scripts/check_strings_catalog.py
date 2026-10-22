#!/usr/bin/env python3
"""Checks Berynda/Resources/Localizable.xcstrings against the Swift sources.

1. Every key has an English translation (every plural variant too), marked
   translated and non-empty, with the same format specifiers as the key.
2. Every Ukrainian string literal in the app (Berynda/, except the UI-test
   doubles in Berynda/Testing/) and in the core package's sources is a key in
   the catalog. Interpolations (`\\(value)`) match any format specifier, the
   way SwiftUI and `String(localized:)` turn them into `%lld` / `%@`.
   A literal that is deliberately not user-facing copy is skipped when its
   line carries the marker `l10n-ignore`.

Runs in CI (.github/workflows/ios.yml); exits non-zero on any problem.
`--missing` prints the untranslated literals only, for authoring.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Berynda" / "Resources" / "Localizable.xcstrings"
SOURCE_DIRS = [ROOT / "Berynda", ROOT / "BeryndaCore" / "Sources"]
EXCLUDED_DIRS = [ROOT / "Berynda" / "Testing"]
IGNORE_MARKER = "l10n-ignore"
CYRILLIC = re.compile(r"[\u0400-\u04FF]")
SPECIFIER = re.compile(
    r"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(lld|llu|ld|lu|d|u|i|@|lf|f|e|g|%)"
)
PLACEHOLDER = r"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|i|@|lf|f|\.\d+f|\.\d+lf)"


class Literal:
    """One string literal: alternating text and interpolation placeholders."""

    def __init__(self, path: Path, line: int, line_text: str):
        self.path = path
        self.line = line
        self.line_text = line_text
        self.parts: list[str | None] = []  # None marks an interpolation

    @property
    def text(self) -> str:
        return "".join(p if p is not None else "\\(…)" for p in self.parts)

    @property
    def has_interpolation(self) -> bool:
        return any(p is None for p in self.parts)

    def pattern(self) -> re.Pattern[str]:
        pieces = []
        for part in self.parts:
            if part is None:
                pieces.append(PLACEHOLDER)
            else:
                # With interpolations the key is a format string, so a literal
                # percent sign appears doubled.
                escaped = re.escape(part)
                if self.has_interpolation:
                    escaped = escaped.replace("%", "%%")
                pieces.append(escaped)
        return re.compile("".join(pieces), re.DOTALL)


ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


class Scanner:
    """A small Swift lexer: enough to find string literals outside comments,
    including literals nested inside interpolations."""

    def __init__(self, path: Path, source: str):
        self.path = path
        self.src = source
        self.lines = source.split("\n")
        self.i = 0
        self.literals: list[Literal] = []

    def line_of(self, index: int) -> int:
        return self.src.count("\n", 0, index) + 1

    def scan(self) -> list[Literal]:
        self.scan_code(top_level=True)
        return self.literals

    def scan_code(self, top_level: bool) -> None:
        """Scans code until the closing parenthesis of an interpolation (or
        the end of the file at the top level)."""
        depth = 0
        src = self.src
        while self.i < len(src):
            c = src[self.i]
            if src.startswith("//", self.i):
                end = src.find("\n", self.i)
                self.i = len(src) if end == -1 else end
            elif src.startswith("/*", self.i):
                self.skip_block_comment()
            elif c == "#" and re.match(r'#+"', src[self.i:]):
                self.scan_raw_string()
            elif c == '"':
                self.scan_string()
            elif c == "(":
                depth += 1
                self.i += 1
            elif c == ")":
                if not top_level and depth == 0:
                    self.i += 1
                    return
                depth -= 1
                self.i += 1
            else:
                self.i += 1

    def skip_block_comment(self) -> None:
        nesting = 0
        while self.i < len(self.src):
            if self.src.startswith("/*", self.i):
                nesting += 1
                self.i += 2
            elif self.src.startswith("*/", self.i):
                nesting -= 1
                self.i += 2
                if nesting == 0:
                    return
            else:
                self.i += 1

    def scan_raw_string(self) -> None:
        hashes = re.match(r"#+", self.src[self.i:]).group(0)
        multiline = self.src.startswith('"""', self.i + len(hashes))
        opener = hashes + ('"""' if multiline else '"')
        closer = ('"""' if multiline else '"') + hashes
        start = self.i
        self.i += len(opener)
        end = self.src.find(closer, self.i)
        end = len(self.src) if end == -1 else end
        literal = self.new_literal(start)
        literal.parts.append(self.src[self.i:end])
        self.i = end + len(closer)
        self.literals.append(literal)

    def new_literal(self, start: int) -> Literal:
        line = self.line_of(start)
        return Literal(self.path, line, self.lines[line - 1])

    def scan_string(self) -> None:
        src = self.src
        start = self.i
        multiline = src.startswith('"""', self.i)
        self.i += 3 if multiline else 1
        literal = self.new_literal(start)
        buffer = []
        while self.i < len(src):
            c = src[self.i]
            if c == "\\":
                nxt = src[self.i + 1] if self.i + 1 < len(src) else ""
                if nxt == "(":
                    literal.parts.append("".join(buffer))
                    buffer = []
                    literal.parts.append(None)
                    self.i += 2
                    self.scan_code(top_level=False)
                    continue
                if nxt == "u":
                    match = re.match(r"\\u\{([0-9a-fA-F]+)\}", src[self.i:])
                    if match:
                        buffer.append(chr(int(match.group(1), 16)))
                        self.i += len(match.group(0))
                        continue
                if multiline and nxt in "\r\n":
                    # Line continuation inside a multi-line literal.
                    self.i += 2 if src[self.i + 1:self.i + 3] != "\r\n" else 3
                    continue
                buffer.append(ESCAPES.get(nxt, nxt))
                self.i += 2
                continue
            if multiline and src.startswith('"""', self.i):
                self.i += 3
                break
            if not multiline and c == '"':
                self.i += 1
                break
            if not multiline and c == "\n":
                break
            buffer.append(c)
            self.i += 1
        literal.parts.append("".join(buffer))
        if multiline:
            literal.parts = [dedent_multiline(p) if p is not None else None for p in literal.parts]
        self.literals.append(literal)


def dedent_multiline(text: str) -> str:
    return "\n".join(line.strip() for line in text.strip("\r\n").splitlines())


def source_files() -> list[Path]:
    files = []
    for directory in SOURCE_DIRS:
        for path in sorted(directory.rglob("*.swift")):
            if any(path.is_relative_to(excluded) for excluded in EXCLUDED_DIRS):
                continue
            files.append(path)
    return files


def ukrainian_literals() -> list[Literal]:
    found = []
    for path in source_files():
        source = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        for literal in Scanner(path, source).scan():
            if IGNORE_MARKER in literal.line_text:
                continue
            if CYRILLIC.search(literal.text):
                found.append(literal)
    return found


def specifiers(text: str) -> list[str]:
    """Format specifiers in argument order, `%%` excluded."""
    found = []
    for index, match in enumerate(m for m in SPECIFIER.finditer(text) if m.group(2) != "%"):
        position = int(match.group(1)) if match.group(1) else index + 1
        found.append((position, match.group(2)))
    return [kind for _, kind in sorted(found)]


def string_units(localization: dict) -> list[tuple[str, dict]]:
    """Every string unit in a localization, with a label for messages."""
    units = []
    if "stringUnit" in localization:
        units.append(("", localization["stringUnit"]))
    for kind, variants in localization.get("variations", {}).items():
        for name, variant in variants.items():
            for label, unit in string_units(variant):
                units.append((f"{kind}.{name}{label}", unit))
    return units


def check_catalog(catalog: dict) -> list[str]:
    problems = []
    if catalog.get("sourceLanguage") != "uk":
        problems.append("sourceLanguage must be 'uk'")
    for key, entry in catalog.get("strings", {}).items():
        if not key.strip():
            problems.append("empty key")
            continue
        if entry.get("shouldTranslate") is False:
            continue
        english = entry.get("localizations", {}).get("en")
        if not english:
            problems.append(f"no English translation: {key!r}")
            continue
        units = string_units(english)
        if not units:
            problems.append(f"English translation has no strings: {key!r}")
        key_specifiers = specifiers(key)
        for label, unit in units:
            value = unit.get("value", "")
            where = f"{key!r}{' [' + label + ']' if label else ''}"
            if unit.get("state") != "translated":
                problems.append(f"English not marked translated: {where}")
            if not value.strip():
                problems.append(f"empty English value: {where}")
            if specifiers(value) != key_specifiers:
                problems.append(
                    f"format specifiers differ: {where}: key {key_specifiers}, "
                    f"English {specifiers(value)}"
                )
        source = entry.get("localizations", {}).get("uk")
        for label, unit in string_units(source or {}):
            if specifiers(unit.get("value", "")) != key_specifiers:
                problems.append(f"Ukrainian variant specifiers differ: {key!r} [{label}]")
    return problems


def check_sources(catalog: dict) -> tuple[list[str], list[Literal]]:
    keys = list(catalog.get("strings", {}).keys())
    exact = set(keys)
    missing = []
    for literal in ukrainian_literals():
        if not literal.has_interpolation and literal.text in exact:
            continue
        pattern = literal.pattern()
        if any(pattern.fullmatch(key) for key in keys):
            continue
        missing.append(literal)
    problems = [
        f"{m.path.relative_to(ROOT)}:{m.line}: not in the String Catalog: {m.text!r}"
        for m in missing
    ]
    return problems, missing


def main(argv: list[str]) -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    source_problems, missing = check_sources(catalog)
    if "--missing" in argv:
        seen = set()
        for literal in missing:
            if literal.text not in seen:
                seen.add(literal.text)
                print(f"{literal.path.relative_to(ROOT)}:{literal.line}\t{literal.text}")
        return 0
    problems = check_catalog(catalog) + source_problems
    for problem in problems:
        print(problem)
    count = len(catalog.get("strings", {}))
    if problems:
        print(f"{len(problems)} problem(s) in {count} catalog strings.")
        return 1
    print(f"String Catalog OK: {count} strings, all translated to English.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
