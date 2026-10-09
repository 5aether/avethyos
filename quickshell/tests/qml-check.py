#!/usr/bin/env python3
"""Structural sanity check for the QML files: brace/paren/bracket balance,
statement termination, and obvious binding smells. Not a substitute for
qmllint, but catches the mistakes a text edit can introduce."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
problems = []

PAIRS = {"{": "}", "(": ")", "[": "]"}
CLOSERS = {v: k for k, v in PAIRS.items()}


def strip_code(text):
    """Remove comments, string literals and regex literals so braces inside
    them do not count. A '/' starts a regex only where an operand is expected
    (after '(', ',', '=', ':', ...), which distinguishes it from division."""
    out = []
    i = 0
    n = len(text)
    prev_significant = ""
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
        elif c == "/" and (prev_significant == "" or
                           prev_significant in "(,=:[!&|?{};+-*%~^"):
            # regex literal: consume to the next unescaped '/'
            i += 1
            in_class = False
            while i < n and text[i] != "\n":
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == "[":
                    in_class = True
                elif text[i] == "]":
                    in_class = False
                elif text[i] == "/" and not in_class:
                    i += 1
                    break
                i += 1
            while i < n and text[i].isalpha():
                i += 1
            out.append('RE')
            prev_significant = "R"
            continue
        elif c in "\"'":
            quote = c
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                i += 1
            i += 1
            out.append('""')
            prev_significant = "S"
            continue
        else:
            out.append(c)
            if not c.isspace():
                prev_significant = c
            i += 1
    return "".join(out)


def singleton_names():
    """The singleton types exported by components/qmldir."""
    names = set()
    qmldir = ROOT / "components" / "qmldir"
    if qmldir.exists():
        for line in qmldir.read_text().split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "singleton":
                names.add(parts[1])
    return names


SINGLETONS = singleton_names()
# Directory names that hold windows/UI types. Anything in these must import the
# components module explicitly: a sibling directory does not share the
# implicit same-directory scope, so a missing import is a runtime ReferenceError
# ("Theme is not defined") rather than a load-time error.
UI_DIRS = {"bar", "overlays", "background"}


def imports_components(path):
    """True if this file imports the components module by relative path."""
    return any(line.strip() == 'import "../components"'
               for line in path.read_text().split("\n"))


for path in sorted(ROOT.rglob("*.qml")):
    rel = path.relative_to(ROOT)
    raw = path.read_text()
    code = strip_code(raw)

    # Balance check
    stack = []
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in PAIRS:
            stack.append((ch, line))
        elif ch in CLOSERS:
            if not stack:
                problems.append(f"{rel}:{line}: stray '{ch}'")
                break
            opener, opened_at = stack.pop()
            if PAIRS[opener] != ch:
                problems.append(
                    f"{rel}:{line}: '{ch}' closes '{opener}' opened at line {opened_at}")
                break
    else:
        if stack:
            opener, opened_at = stack[-1]
            problems.append(f"{rel}: unclosed '{opener}' opened at line {opened_at}")

    # JS blocks inside QML must not be left as unterminated statements.
    for match in re.finditer(r"function\s+(\w+)\s*\([^)]*\)\s*\{", code):
        name = match.group(1)
        # find matching close brace
        depth = 0
        start = match.end() - 1
        for idx in range(start, len(code)):
            if code[idx] == "{":
                depth += 1
            elif code[idx] == "}":
                depth -= 1
                if depth == 0:
                    # Body excludes both the opening and closing brace.
                    body = code[start + 1:idx]
                    if body.count("{") != body.count("}"):
                        problems.append(f"{rel}: unbalanced body in function {name}()")
                    if body.count("(") != body.count(")"):
                        problems.append(f"{rel}: unbalanced parens in function {name}()")
                    break
        else:
            problems.append(f"{rel}: unterminated function {name}()")

    # A TextInput that binds `text:` without guarding against its own edits has
    # its binding dropped on the first keystroke (and warns in qmllint).
    for m in re.finditer(r"TextInput\s*\{", code):
        start = m.end() - 1
        depth = 0
        for idx in range(start, len(code)):
            if code[idx] == "{":
                depth += 1
            elif code[idx] == "}":
                depth -= 1
                if depth == 0:
                    body = code[start:idx]
                    bound = re.search(r"(?<![\w.])text\s*:\s*[\w.]", body)
                    edits = "onAccepted" in body or "onTextChanged" in body \
                        or "onActiveFocusChanged" in body
                    guarded = "activeFocus ? text" in body or "activeFocus ?" in body
                    if bound and edits and not guarded:
                        problems.append(
                            f"{rel}: TextInput binds text: and also edits it "
                            f"without an activeFocus guard")
                    break

    if not raw.endswith("\n"):
        problems.append(f"{rel}: missing trailing newline")

    # A file outside components/ that uses a singleton must import the module.
    # Files inside components/ get the singletons implicitly, so the rule only
    # applies to the other directories.
    if rel.parts and rel.parts[0] in UI_DIRS:
        uses = sorted(n for n in SINGLETONS
                      if re.search(rf"(?<![\w.]){n}\s*[.\[\)]", code))
        if uses and not imports_components(path):
            problems.append(
                f"{rel}: uses {', '.join(uses)} but does not "
                f'import "../components" - runtime ReferenceError')

    for lineno, text in enumerate(raw.split("\n"), 1):
        if text.rstrip() != text:
            problems.append(f"{rel}:{lineno}: trailing whitespace")
        if "\t" in text:
            problems.append(f"{rel}:{lineno}: tab character")

if problems:
    print(f"{len(problems)} problem(s):")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("all QML files structurally clean")
