"""Static sanity check for FycoPvE's Lua, standing in for luac.

Three things, matching HARD RULE 3 in CLAUDE.md:
  1. ASCII only        - the 3.3.5a client renders anything else as mojibake
  2. valid escapes     - "Fonts\\FRIZQT__.TTF" mangled to a single backslash is
                         an invalid Lua escape and the addon refuses to load
  3. block balance     - do/then/function ... end, counted on a real token
                         stream so the word "end" inside a comment or a string
                         cannot throw the count off

It is a lexer, not a parser: it will not catch every syntax error, but it does
catch the ones that have actually bitten this addon.
"""
import sys

# Lua's valid escape characters inside a quoted string.
VALID_ESCAPES = set('abfnrtv\\"\'\n0123456789xz')


class Tok:
    def __init__(self, kind, text, line):
        self.kind, self.text, self.line = kind, text, line


def long_bracket(src, i):
    """If src[i:] opens a [=*[ long bracket, return (level, index after it)."""
    if src[i] != "[":
        return None
    j = i + 1
    level = 0
    while j < len(src) and src[j] == "=":
        level += 1
        j += 1
    if j < len(src) and src[j] == "[":
        return level, j + 1
    return None


def lex(src, path, errors):
    toks = []
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]

        if c == "\n":
            line += 1
            i += 1
            continue

        if c in " \t\r":
            i += 1
            continue

        # comment
        if src.startswith("--", i):
            i += 2
            lb = long_bracket(src, i) if i < n else None
            if lb:
                level, i = lb
                close = "]" + "=" * level + "]"
                end = src.find(close, i)
                if end == -1:
                    errors.append("%s:%d: unterminated long comment" % (path, line))
                    return toks
                line += src.count("\n", i, end)
                i = end + len(close)
            else:
                nl = src.find("\n", i)
                i = n if nl == -1 else nl
            continue

        # long string
        lb = long_bracket(src, i)
        if lb:
            level, j = lb
            close = "]" + "=" * level + "]"
            end = src.find(close, j)
            if end == -1:
                errors.append("%s:%d: unterminated long string" % (path, line))
                return toks
            start_line = line
            line += src.count("\n", j, end)
            i = end + len(close)
            toks.append(Tok("string", "", start_line))
            continue

        # quoted string
        if c in "\"'":
            quote, j, start_line = c, i + 1, line
            closed = False
            while j < n:
                ch = src[j]
                if ch == "\\":
                    nxt = src[j + 1] if j + 1 < n else ""
                    if nxt not in VALID_ESCAPES:
                        errors.append(
                            "%s:%d: invalid escape backslash-%s in string"
                            % (path, line, nxt if nxt.strip() else "<eol>")
                        )
                    if nxt == "\n":
                        line += 1
                    j += 2
                    continue
                if ch == quote:
                    j += 1
                    closed = True
                    break
                if ch == "\n":
                    errors.append(
                        "%s:%d: newline inside string opened here" % (path, start_line)
                    )
                    line += 1
                j += 1
            if not closed:
                errors.append("%s:%d: unterminated string" % (path, start_line))
            i = j
            toks.append(Tok("string", "", start_line))
            continue

        # name / keyword
        if c.isalpha() or c == "_":
            j = i
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            toks.append(Tok("name", src[i:j], line))
            i = j
            continue

        # number
        if c.isdigit():
            j = i
            while j < n and (src[j].isalnum() or src[j] == "."):
                j += 1
            toks.append(Tok("number", src[i:j], line))
            i = j
            continue

        toks.append(Tok("op", c, line))
        i += 1

    return toks


# ALL_CAPS names that really are globals, provided by the 3.3.5a client or by
# this addon's own files. Anything else in that style is a module constant, and
# using one never declared local in the same file means it is nil -- which is
# how `THEIR_SIZE + MINE_SIZE` threw after MINE_SIZE was deleted.
KNOWN_GLOBALS = {
    "CLASS_ICON_TCOORDS", "RAID_CLASS_COLORS", "SLASH_FYCOPVE1",
    "SLASH_FYCOPVE2", "ITEM_QUALITY_COLORS", "COMBATLOG_OBJECT_TYPE_PLAYER",
    "COMBATLOG_OBJECT_TYPE_PET", "COMBATLOG_OBJECT_TYPE_GUARDIAN",
    "COMBATLOG_OBJECT_TYPE_NPC", "COMBATLOG_OBJECT_REACTION_HOSTILE",
    "COMBATLOG_OBJECT_REACTION_FRIENDLY", "COMBATLOG_OBJECT_REACTION_NEUTRAL",
    "COMBATLOG_OBJECT_AFFILIATION_MINE", "DEFAULT_CHAT_FRAME",
    "SOUNDKIT", "MAX_PARTY_MEMBERS", "NUM_BAG_SLOTS", "MAX_RAID_MEMBERS",
}


def undeclared_constants(toks, path, errors):
    """Flag ALL_CAPS identifiers used but never declared `local` in this file."""
    import re
    style = re.compile(r"^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$")

    declared = set()
    # A name counts as declared when it follows `local`, including every name
    # in a comma list that began with one:
    #     local THEIR_SIZE, MINE_SIZE, GAP = 34, 26, 4
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.kind == "name" and t.text == "local":
            j = i + 1
            expect_name = True
            while j < len(toks):
                u = toks[j]
                if expect_name and u.kind == "name":
                    if u.text == "function":
                        j += 1
                        continue
                    declared.add(u.text)
                    expect_name = False
                elif u.kind == "op" and u.text == ",":
                    expect_name = True
                else:
                    break
                j += 1
            i = j
            continue
        i += 1

    seen = {}
    for idx, t in enumerate(toks):
        if t.kind != "name" or not style.match(t.text) or t.text in declared:
            continue
        if t.text in KNOWN_GLOBALS:
            continue

        prev = toks[idx - 1] if idx else None
        nxt = toks[idx + 1] if idx + 1 < len(toks) else None
        nxt2 = toks[idx + 2] if idx + 2 < len(toks) else None

        # `ns.DR_RESET` / `obj:METHOD` -- a field, not a global read
        if prev is not None and prev.kind == "op" and prev.text in ".:":
            continue

        # a key in a table constructor: `{ SWING_DAMAGE = 0, SPELL_DAMAGE = 3 }`
        # (`=` is lexed one char at a time, so `==` is two tokens -- checking
        # nxt2 keeps a genuine `FOO == bar` comparison from being skipped)
        key_assign = (nxt is not None and nxt.kind == "op" and nxt.text == "="
                      and not (nxt2 is not None and nxt2.kind == "op"
                               and nxt2.text == "="))
        if key_assign and prev is not None and prev.kind == "op" \
           and prev.text in "{,;":
            continue

        seen.setdefault(t.text, t.line)

    for name in sorted(seen):
        errors.append(
            "%s:%d: '%s' looks like a module constant but is never declared "
            "local in this file (it is nil)" % (path, seen[name], name)
        )


def check(path):
    errors = []
    with open(path, "rb") as fh:
        raw = fh.read()

    for idx, byte in enumerate(bytearray(raw)):
        if byte > 127:
            line = raw.count(b"\n", 0, idx) + 1
            errors.append("%s:%d: non-ASCII byte 0x%02x" % (path, line, byte))
            break

    src = raw.decode("utf-8", "replace")
    toks = lex(src, path, errors)
    undeclared_constants(toks, path, errors)

    # Block balance. `for`/`while` open their block via their own `do`, and a
    # `then` opens the if-block, so only function/do/then need counting, plus
    # the repeat..until pair. `elseif ... then` reuses the open if-block.
    # `elseif <cond> then` reuses the if-block that is already open. The token
    # right before `then` is the end of the condition, not the `elseif`, so it
    # has to be remembered with a flag rather than looked back at.
    stack = []
    in_elseif = False
    for t in toks:
        if t.kind != "name":
            continue
        w = t.text
        if w == "elseif":
            in_elseif = True
            continue
        if w in ("function", "do", "then", "repeat"):
            if w == "then" and in_elseif:
                in_elseif = False
            else:
                stack.append((w, t.line))
        elif w == "end":
            if not stack:
                errors.append("%s:%d: 'end' with nothing open" % (path, t.line))
            else:
                opened = stack.pop()
                if opened[0] == "repeat":
                    errors.append(
                        "%s:%d: 'end' closing a repeat opened at line %d"
                        % (path, t.line, opened[1])
                    )
        elif w == "until":
            if stack and stack[-1][0] == "repeat":
                stack.pop()
            else:
                errors.append("%s:%d: 'until' with no repeat" % (path, t.line))

    for kind, line in stack:
        errors.append("%s:%d: '%s' never closed" % (path, line, kind))

    return errors


def main():
    bad = 0
    for path in sys.argv[1:]:
        errs = check(path)
        if errs:
            bad += 1
            for e in errs:
                print("FAIL " + e)
        else:
            print("ok   " + path)
    print("---")
    print("%d file(s) checked, %d with problems" % (len(sys.argv) - 1, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
