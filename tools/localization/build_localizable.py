#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build the five new Localizable.strings from the English source.

Source of truth for keys/order/comments/placeholders:
    EmotionVoice/EmotionVoice/en.lproj/Localizable.strings

Translation sources (one plain-text line per key-value line, in the exact same
order as the English file, comments/blank lines excluded):
    tools/localization/translations/{ru,ko,ja,fr,de}.txt

A line in a translation file is the value body. To avoid double-escaping bugs,
use these markers instead of literal backslashes:
    <NL>  -> \\n  (newline inside the .strings value)
    <Q>   -> \\"  (literal double quote inside the .strings value)
Raw backslashes and raw double quotes are rejected by the validator.
Keep %@ / %d placeholders in the exact same order as the English value.
Do NOT add the surrounding quotes or the trailing semicolon - the script adds
those.

Usage:
    python3 tools/localization/build_localizable.py --check   # validate only
    python3 tools/localization/build_localizable.py           # validate + write
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "EmotionVoice" / "EmotionVoice"
SOURCE = BASE / "en.lproj" / "Localizable.strings"
TRANS_DIR = Path(__file__).resolve().parent / "translations"
LANGS = ("ru", "ko", "ja", "fr", "de")

LINE_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
PH_RE = re.compile(r'%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?[@dDuUfFeEgGsScCpP]|%%')


def parse_source():
    lines = SOURCE.read_text(encoding="utf-8").splitlines()
    entries = []  # (line_index, raw_key, raw_value)
    for idx, line in enumerate(lines):
        if not line.strip() or line.strip().startswith("//"):
            continue
        m = LINE_RE.match(line)
        if not m:
            raise SystemExit(f"[source] cannot parse line {idx + 1}: {line}")
        entries.append((idx, m.group(1), m.group(2)))
    return lines, entries


def read_translations(lang):
    path = TRANS_DIR / f"{lang}.txt"
    if not path.exists():
        raise SystemExit(f"[{lang}] missing translation file: {path}")
    # splitlines() drops the trailing newline; a trailing empty line is ignored
    raw = path.read_text(encoding="utf-8").split("\n")
    if raw and raw[-1] == "":
        raw.pop()
    return raw


def materialize(tr):
    """Turn the safe markers into real .strings escape sequences."""
    return tr.replace("<NL>", r"\n").replace("<Q>", r'\"')


def validate(lang, values, entries):
    errors = []
    if len(values) != len(entries):
        errors.append(
            f"[{lang}] line count {len(values)} != {len(entries)} source entries"
        )
    for n, ((line_no, key, en_value), tr) in enumerate(zip(entries, values), 1):
        tag = f"[{lang}] #{n} (en line {line_no + 1}) key={key!r}"
        if tr == "":
            errors.append(f"{tag}: empty translation")
        if tr.strip() == "":
            errors.append(f"{tag}: whitespace-only translation")
        if "\t" in tr:
            errors.append(f"{tag}: contains a raw tab")
        if '"' in tr:
            errors.append(f"{tag}: raw double quote, use <Q> -> {tr!r}")
        if "\\" in tr:
            errors.append(f"{tag}: raw backslash, use <NL>/<Q> -> {tr!r}")
        # placeholder sequence must match the English value exactly, in order
        en_ph = PH_RE.findall(en_value)
        tr_ph = PH_RE.findall(tr)
        if en_ph != tr_ph:
            errors.append(
                f"{tag}: placeholders {tr_ph} != English {en_ph} -> {tr!r}"
            )
        # stray markers that would silently corrupt the value
        if "<" in tr or ">" in tr:
            for token in ("<NL>", "<Q>"):
                tr = tr.replace(token, "")
            if "<" in tr or ">" in tr:
                errors.append(f"{tag}: suspicious angle bracket -> {tr!r}")
    return errors


def build(lang, values, entries, source_lines):
    by_line = {}
    for (line_no, _, _), tr in zip(entries, values):
        by_line[line_no] = materialize(tr)
    out = []
    for idx, line in enumerate(source_lines):
        if idx in by_line:
            m = LINE_RE.match(line)
            out.append(f'"{m.group(1)}" = "{by_line[idx]}";')
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only, do not write")
    args = ap.parse_args()

    source_lines, entries = parse_source()
    all_errors = []
    payloads = {}
    for lang in LANGS:
        values = read_translations(lang)
        errs = validate(lang, values, entries)
        all_errors.extend(errs)
        payloads[lang] = build(lang, values, entries, source_lines)
        print(f"[{lang}] {len(values)} translations, {len(errs)} validation error(s)")

    if all_errors:
        print("\n".join(all_errors[:80]))
        if len(all_errors) > 80:
            print(f"... and {len(all_errors) - 80} more")
        raise SystemExit(1)

    if not args.check:
        for lang in LANGS:
            dest = BASE / f"{lang}.lproj" / "Localizable.strings"
            dest.write_text(payloads[lang], encoding="utf-8")
            print(f"wrote {dest.relative_to(ROOT)}")
    print("OK: all languages validated")


if __name__ == "__main__":
    main()
