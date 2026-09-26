"""Build the talent and glyph guides (and later the other per-spec guides).

    python scripts/build_guides.py

Inputs
  scripts/guides.json          'pages.talents': each spec's Wowhead talent/glyph guide
  scripts/ref/talents.json     the realm's talent trees + the stock order (extract_talents.py)
  scripts/ref/realm_changes.json  what the realm changed
  .cache/acore/item_template.sql  glyph names

Outputs -- GENERATED, never edit by hand
  Data/Guides/<Class>.lua      builds (decoded to tier/column/points) and glyphs, per spec
  Data/Realm.lua               talents and spells this realm changed from stock

A Wowhead talent string ("warlock/2350002030023510253500331151--550000051_...")
has one digit per talent of each STOCK tree, in row-then-column order, trees
separated by "-". It is decoded against the stock order and placed on the
realm's own trees by talent ID, so realm-added talents cannot shift it.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_data as bd  # noqa: E402  (shared downloader, SQL reader, markup helpers)

ROOT = bd.ROOT
CACHE = os.path.join(ROOT, ".cache", "pages")
NOTE_MAX = 1400


def lua_str(s):
    s = bd.ascii_only(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def prose(markup, item_names):
    """Guide markup -> plain text, keeping paragraphs; spells become {spell:N}
    so the client names them, items are named here."""
    s = markup.replace("\r", "")
    s = re.sub(r"\[spell=(\d+)[^\]]*\]", r"{spell:\1}", s)
    s = re.sub(r"\[item=(\d+)[^\]]*\]", lambda m: item_names.get(int(m.group(1)), "an item"), s)
    s = re.sub(r"\[url[^\]]*\](.*?)\[/url\]", r"\1", s, flags=re.S)
    s = re.sub(r"\[icon[^\]]*\](.*?)\[/icon\]", r"\1", s, flags=re.S)
    s = re.sub(r"\[li\]", "\n- ", s)
    s = re.sub(r"\[[^\]]*\]", "", s)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n\s*\n\s*(\n\s*)+", "\n\n", s)
    s = s.strip()
    if len(s) > NOTE_MAX:
        s = s[:NOTE_MAX].rsplit(" ", 1)[0] + " ..."
    return s


def split_sections(text):
    """[(heading, body)] for every h2/h3/h4 section."""
    parts = re.split(r"\[h[234][^\]]*\](.*?)\[/h[234]\]", text)
    out = [("", parts[0])]
    for k in range(1, len(parts), 2):
        out.append((bd.plain(parts[k]), parts[k + 1]))
    return out


def decode(cls, code, trees, changed):
    """'2350002...--550000051' -> ({tab: [(tier, col, pts, changed)]}, points per tree)."""
    by_id = {}
    for ti, tree in enumerate(trees):
        for t in tree["talents"]:
            by_id[t["id"]] = (ti, t)
    out, pts = [[], [], []], [0, 0, 0]
    for ti, digits in enumerate(code.split("-")[:3]):
        order = trees[ti]["stock_order"]
        for j, ch in enumerate(digits):
            if not ch.isdigit() or ch == "0":
                continue
            if j >= len(order):
                raise ValueError("%s: talent string longer than tree %d" % (cls, ti))
            tab, t = by_id.get(order[j], (None, None))
            if t is None:
                print("  WARNING %s: stock talent %d is not on this realm" % (cls, order[j]))
                continue
            p = min(int(ch), len(t["ranks"]))
            out[tab].append((t["tier"] + 1, t["col"] + 1, p, t["id"] in changed))
            pts[tab] += p
    return out, pts


def glyph_rows(body, item_names):
    """[(itemID, name, note)] in a Major/Minor glyph section."""
    rows = []
    for chunk in body.split("[tr]")[1:]:
        cells = bd.CELL.findall(chunk)
        items = [int(x) for c in cells for x in re.findall(r"\[item=(\d+)", c)[:1]]
        if not items:
            continue
        item = items[0]
        note_cells = [c for c in cells if "[quote" not in c]
        note = prose(note_cells[-1], item_names) if note_cells else ""
        rows.append((item, item_names.get(item, "Glyph"), note))
    if not rows and "[li]" in body:   # "[li][b][item=41536][/b] - why it is good[/li]"
        for li in re.findall(r"\[li\](.*?)(?=\[/li\]|\[li\]|\Z)", body, re.S):
            m = re.search(r"\[item=(\d+)[^\]]*\]", li)
            if m:
                item = int(m.group(1))
                note = prose(li[:m.start()] + li[m.end():], item_names).lstrip(" -:")
                rows.append((item, item_names.get(item, "Glyph"), note))
    if not rows:   # some guides use a plain list instead of a table
        for m in re.finditer(r"\[item=(\d+)[^\]]*\](.*?)(?=\[item=\d+|\Z)", body, re.S):
            item = int(m.group(1))
            if item_names.get(item, "").startswith("Glyph"):
                rows.append((item, item_names[item], prose(m.group(2), item_names)))
    seen, out = set(), []
    for r in rows:
        if r[0] not in seen and r[1].startswith("Glyph"):
            seen.add(r[0])
            out.append(r)
    return out


def main():
    cfg = json.load(open(os.path.join(HERE, "guides.json"), encoding="utf-8"))
    trees_all = json.load(open(os.path.join(HERE, "ref", "talents.json"), encoding="utf-8"))
    changes = json.load(open(os.path.join(HERE, "ref", "realm_changes.json"), encoding="utf-8"))
    changed_spells = {int(k) for k in changes["spells"]}
    changed_talents = set(changes["talents"])
    for cls, trees in trees_all.items():
        for tree in trees:
            for t in tree["talents"]:
                if changed_spells & set(t["ranks"]):
                    changed_talents.add(t["id"])

    print("reading item names")
    item_names = {r["entry"]: r["name"] for r in bd.read_table("item_template")}

    per_class = {}
    for page in cfg["pages"]["talents"]:
        cls, spec = page["class"], page["spec"]
        path = os.path.join(CACHE, "talents-%s-%s.html" % (cls, spec))
        bd.fetch("https://web.archive.org/web/%sid_/%s" % (page["snapshot"], page["url"]), path, False)
        text = bd.guide_markup(open(path, encoding="utf-8", errors="replace").read())
        trees = trees_all[cls]

        builds, glyphs = [], {"major": [], "minor": []}
        for heading, body in split_sections(text):
            for m in re.finditer(r"\[talent=[a-z-]+/([0-9-]+)[^\]]*\]", body):
                decoded, pts = decode(cls, m.group(1), trees, changed_talents)
                if sum(pts) == 0:
                    continue
                after = body[m.end():]
                name = re.sub(r"\s*(Warlock|Warrior|Paladin|Hunter|Rogue|Priest|Death Knight|Shaman|Mage|Druid)"
                              r".*$", "", heading).strip() or spec
                if any(b["code"] == m.group(1) for b in builds):
                    continue
                builds.append({"name": name, "code": m.group(1), "pts": pts, "trees": decoded,
                               "note": prose(after, item_names)})
            low = heading.lower()
            if low.startswith("major") or ("major" in low and "glyph" in low):
                glyphs["major"] += glyph_rows(body, item_names)
            elif low.startswith("minor") or ("minor" in low and "glyph" in low):
                glyphs["minor"] += glyph_rows(body, item_names)
            elif "glyph" in low:
                # one "Glyphs" section with [h5]Major Glyphs[/h5] / [h5]Minor Glyphs[/h5] inside
                sub = re.split(r"\[h5[^\]]*\](.*?)\[/h5\]", body)
                for k in range(1, len(sub), 2):
                    sl = bd.plain(sub[k]).lower()
                    if "major" in sl:
                        glyphs["major"] += glyph_rows(sub[k + 1], item_names)
                    elif "minor" in sl:
                        glyphs["minor"] += glyph_rows(sub[k + 1], item_names)
        if not builds:
            print("  WARNING no talent build found for %s %s" % (cls, spec))
        per_class.setdefault(cls, []).append((spec, page["url"], builds, glyphs))
        print("%-12s %-14s builds %d  glyphs %d/%d" % (cls, spec, len(builds), len(glyphs["major"]),
                                                       len(glyphs["minor"])))

    header = ("-- GENERATED by scripts/build_guides.py -- do not edit by hand.\n"
              "-- Source: Wowhead WotLK talent and glyph guides (see scripts/guides.json),\n"
              "-- decoded against this realm's own talent trees.\n")
    for cls, specs in per_class.items():
        lines = [header, "local _, ns = ...\n"]
        for spec, url, builds, glyphs in specs:
            lines.append("\n-- %s\nns:RegisterTalentGuide(%s, %s, {\n" % (url, lua_str(cls), lua_str(spec)))
            lines.append("\tbuilds = {\n")
            for b in builds:
                lines.append("\t\t{\n\t\t\tname = %s,\n\t\t\tpts = { %d, %d, %d },\n" % ((lua_str(b["name"]),) + tuple(b["pts"])))
                lines.append("\t\t\ttrees = {\n")
                for tab in b["trees"]:
                    cells = ", ".join("{ %d, %d, %d%s }" % (t, c, p, ", true" if ch else "") for t, c, p, ch in tab)
                    lines.append("\t\t\t\t{ %s },\n" % cells)
                lines.append("\t\t\t},\n\t\t\tnote = %s,\n\t\t},\n" % lua_str(b["note"]))
            lines.append("\t},\n\tglyphs = {\n")
            for kind in ("major", "minor"):
                lines.append("\t\t%s = {\n" % kind)
                for item, name, note in glyphs[kind]:
                    lines.append("\t\t\t{ %d, %s, %s },\n" % (item, lua_str(name), lua_str(note)))
                lines.append("\t\t},\n")
            lines.append("\t},\n})\n")
        bd.write(os.path.join(ROOT, "Data", "Guides", cls.capitalize() + ".lua"), "".join(lines))

    # what the realm changed, for "changed on this realm" marks in the UI
    lines = [header.replace("talent and glyph guides (see scripts/guides.json),\n-- decoded against this realm's own talent trees.",
                            "comparison of the realm's client data with stock 3.3.5 (extract_talents.py)."),
             "local _, ns = ...\n\nns.Realm = {\n\t-- spells whose numbers or text differ from stock\n\tspells = {\n"]
    ids = sorted(changed_spells)
    for i in range(0, len(ids), 12):
        lines.append("\t\t" + " ".join("[%d] = true," % x for x in ids[i:i + 12]) + "\n")
    lines.append("\t},\n\t-- talents the realm added or changed: class -> \"tab:tier:col\"\n\ttalents = {\n")
    for cls, trees in sorted(trees_all.items()):
        keys = ['["%d:%d:%d"] = true' % (ti + 1, t["tier"] + 1, t["col"] + 1)
                for ti, tree in enumerate(trees) for t in tree["talents"] if t["id"] in changed_talents]
        if keys:
            lines.append("\t\t%s = { %s },\n" % (cls, ", ".join(keys)))
    lines.append("\t},\n}\n")
    bd.write(os.path.join(ROOT, "Data", "Realm.lua"), "".join(lines))

    toc = open(os.path.join(ROOT, "FycoPvE.toc"), encoding="ascii").read()
    for cls in list(per_class) + ["Realm"]:
        entry = ("Data\\Guides\\%s.lua" % cls.capitalize()) if cls != "Realm" else "Data\\Realm.lua"
        if entry not in toc:
            print("WARNING: add '%s' to FycoPvE.toc or the game never loads it" % entry)


if __name__ == "__main__":
    main()
