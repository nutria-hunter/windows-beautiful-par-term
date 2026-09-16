"""Normalize par-term config.yaml style without changing values.

Fixes: block-sequence items at column 0 -> 2-space indent, their mapping
children 2 -> 4 spaces, and the two >80-char regex scalars -> '|-' blocks.
Verifies semantic equality via yaml.safe_load before/after.
"""

import sys
from pathlib import Path

import yaml

PATH = Path("C:/Users/jky72/AppData/Roaming/par-term/config.yaml")

LONG_REGEX_PREFIXES = ("regex: \\b(?:(?:25[0-5]", "regex: \\b[0-9a-fA-F]{8}")


def normalize(lines):
    """Re-indent dash items and their children. Line count unchanged."""
    out = []
    in_seq = False
    for line in lines:
        stripped = line.strip()
        if stripped == "":
            out.append(line)
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0 and line.startswith("- "):
            out.append("  " + line)
            in_seq = True
        elif indent == 0:
            out.append(line)
            in_seq = False
        elif indent == 2 and in_seq:
            out.append("  " + line)
        else:
            out.append(line)
    return out


def quote_continuations(indent, value, width=70):
    """Emit a double-quoted scalar with backslash line continuations.

    In YAML double-quoted scalars, backslash-newline joins with no space
    and no newline, so the value is byte-identical while every physical
    line stays short.
    """
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    chunks = [escaped[idx : idx + width] for idx in range(0, len(escaped), width)]
    first_indent = indent + "  "
    cont_indent = indent + "    "
    parts = []
    for pos, chunk in enumerate(chunks):
        if pos == 0:
            parts.append(f'{first_indent}"{chunk}\\')
        elif pos < len(chunks) - 1:
            parts.append(f"{cont_indent}{chunk}\\")
        else:
            parts.append(f'{cont_indent}{chunk}"')
    return parts


def fold_long_regex(lines):
    """Re-emit the two over-long plain 'regex:' scalars as short lines."""
    out = []
    for line in lines:
        stripped = line.strip()
        if len(line) > 80 and any(stripped.startswith(p) for p in LONG_REGEX_PREFIXES):
            indent = line[: len(line) - len(line.lstrip(" "))]
            key, _, value = stripped.partition(": ")
            out.append(f"{indent}{key}:")
            out.extend(quote_continuations(indent, value))
        else:
            out.append(line)
    return out


def main() -> int:
    try:
        raw = PATH.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"FAIL: cannot read {PATH}: {exc}")
        return 1
    try:
        before = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        print(f"FAIL: original does not parse: {exc}")
        return 1
    lines = raw.split("\n")
    lines = fold_long_regex(normalize(lines))
    fixed = "\n".join(lines)
    try:
        after = yaml.safe_load(fixed)
    except yaml.YAMLError as exc:
        print(f"FAIL: fixed file does not parse: {exc}")
        return 1
    if before != after:
        print("FAIL: semantic mismatch after normalization")
        return 1
    residual_dash = [idx + 1 for idx, text in enumerate(lines) if text.startswith("- ")]
    residual_long = [
        (idx + 1, len(text)) for idx, text in enumerate(lines) if len(text) > 80
    ]
    if residual_dash or residual_long:
        print(f"FAIL: residual issues dash={residual_dash} long={residual_long}")
        return 1
    try:
        PATH.write_text(fixed, encoding="utf-8")
    except OSError as exc:
        print(f"FAIL: cannot write {PATH}: {exc}")
        return 1
    print(f"ok config.yaml normalized ({len(lines)} lines, values identical)")
    return 0


sys.exit(main())
