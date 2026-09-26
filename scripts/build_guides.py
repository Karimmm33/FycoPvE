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
FACTIONS = bd.load_ref("factions")
# Wowhead [currency=N] ids seen in these guides
CURRENCY = dict(bd.WH_CURRENCY)
CURRENCY.update({161: "Stone Keeper's Shards", 241: "Champion's Seals", 301: "Emblems of Triumph",
                 341: "Emblems of Frost", 221: "Emblems of Conquest"})


def lua_str(s):
    s = bd.ascii_only(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def prose(markup, item_names):
    """Guide markup -> plain text, keeping paragraphs; spells become {spell:N}
    so the client names them, items are named here."""
    s = markup.replace("\r", "")
    s = re.sub(r"\[skill=(\d+)[^\]]*\]", lambda m: bd.SKILLS.get(int(m.group(1)), "the profession"), s)
    s = re.sub(r"\[faction=(\d+)[^\]]*\]", lambda m: FACTIONS.get(int(m.group(1)), "the faction"), s)
    s = re.sub(r"\[currency=(\d+)[^\]]*\]", lambda m: CURRENCY.get(int(m.group(1)), "emblems"), s)
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


# --- enchants, gems, stats, rotation ------------------------------------------

SKILL_NAMES = {164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 197: "Tailoring",
               202: "Engineering", 333: "Enchanting", 755: "Jewelcrafting", 773: "Inscription"}
# enchant heading word -> the addon's slot key (Modules/Enchants.lua maps these to inventory slots)
ENCHANT_SLOTS = [("head", "Head"), ("helm", "Head"), ("shoulder", "Shoulder"), ("cloak", "Back"),
                 ("back", "Back"), ("cape", "Back"), ("chest", "Chest"), ("bracer", "Wrist"),
                 ("wrist", "Wrist"), ("glove", "Hands"), ("hand", "Hands"), ("belt", "Waist"),
                 ("waist", "Waist"), ("leg", "Legs"), ("pant", "Legs"), ("boot", "Feet"), ("feet", "Feet"),
                 ("ring", "Ring"), ("shield", "OffHand"), ("off", "OffHand"), ("ranged", "Ranged"),
                 ("bow", "Ranged"), ("gun", "Ranged"), ("scope", "Ranged"),
                 ("weapon", "Weapon"), ("staff", "Weapon"), ("two", "Weapon"), ("2h", "Weapon"),
                 ("main", "Weapon"), ("one", "Weapon"), ("1h", "Weapon")]
GEM_SLOTS = [("meta", "Meta"), ("red", "Red"), ("yellow", "Yellow"), ("blue", "Blue"),
             ("prismatic", "Prismatic")]


def parse_options(markup, item_names, item_spell, spell_enchant):
    """'[item=50368] > [spell=61120] ([skill=773]) | [item=44075] (P1-2)' -> options, best first."""
    out = []
    for part in re.split(r"&gt;|>|\|", markup):
        m = re.search(r"\[(item|spell)=(\d+)", part)
        if not m:
            continue
        kind, id_ = m.group(1), int(m.group(2))
        skill = re.search(r"\[skill=(\d+)", part)
        tag = re.search(r"\((P[^)]*)\)", bd.plain(part))
        if kind == "item":
            spell = item_spell.get(id_)
            enchant = spell_enchant.get(spell)
            name = item_names.get(id_, "item %d" % id_)
        else:
            enchant = spell_enchant.get(id_)
            name = None      # the client names spells
        out.append({"kind": kind, "id": id_, "enchant": enchant, "name": name,
                    "skill": SKILL_NAMES.get(int(skill.group(1))) if skill else None,
                    "tag": tag.group(1) if tag else None})
    return out


def parse_gear_guide(text, item_names, item_spell, spell_enchant):
    """Every '[h5]Head Enchant: A > B[/h5]' / '[h5]Red Socket: A > B[/h5]' block."""
    enchants, gems = [], []
    parts = re.split(r"\[h5[^\]]*\](.*?)\[/h5\]", text, flags=re.S)
    for k in range(1, len(parts), 2):
        head = parts[k]
        label = bd.plain(head).split(":")[0].strip().lower()
        if ":" not in bd.plain(head):
            continue
        opts = parse_options(head.split(":", 1)[1], item_names, item_spell, spell_enchant)
        if not opts:
            continue
        note = prose(re.split(r"\[h[2-5]", parts[k + 1])[0], item_names)[:700]
        if "gem" in label or "socket" in label or "meta" in label:
            slot = next((v for w, v in GEM_SLOTS if w in label), None)
            if slot:
                gems.append({"slot": slot, "options": opts, "note": note})
        else:
            slot = next((v for w, v in ENCHANT_SLOTS if w in label), None)
            if slot and not any(e["slot"] == slot for e in enchants):
                enchants.append({"slot": slot, "options": opts, "note": note})
    return enchants, gems


def parse_stats(text):
    """The first numbered list under a 'priority' heading: ['Hit Rating', 'Spell Power', ...]."""
    for heading, body in split_sections(text):
        if "priority" in heading.lower():
            m = re.search(r"\[ol\](.*?)\[/ol\]", body, re.S)
            if m:
                return [bd.plain(x) for x in re.findall(r"\[li\](.*?)\[/li\]", m.group(1), re.S) if bd.plain(x)]
            lis = [bd.plain(x) for x in re.findall(r"\[li\](.*?)(?:\[/li\]|$)", body, re.S) if bd.plain(x)]
            if lis:
                return lis[:10]
            line = bd.plain(body.split("\n\n")[0] if body.strip() else "")
            if ">" in line:
                return [x.strip() for x in line.split(">") if x.strip()][:10]
    return []


def parse_rotation(text, item_names):
    """The guide's spell priority (first spell of each list entry, in order) and its opener."""
    priority, seen, opener = [], set(), ""
    for heading, body in split_sections(text):
        low = heading.lower()
        if "opener" in low and not opener:
            opener = prose(body, item_names)[:700]
        if ("priority" in low or "standard rotation" in low or "single target" in low) and "aoe" not in low:
            for li in re.findall(r"\[li\](.*?)(?=\[/li\]|\[li\]|\[/ul\]|\[/ol\])", body, re.S):
                m = re.search(r"\[spell=(\d+)", li)
                if m and int(m.group(1)) not in seen:
                    seen.add(int(m.group(1)))
                    note = prose(li[m.end():].split("]", 1)[-1], item_names)[:160]
                    priority.append((int(m.group(1)), note))
    return priority[:14], opener


def page_markup(html):
    """Like build_data.guide_markup, but a stat-priority page may link no
    items at all, so pick the longest string that looks like guide markup."""
    chunks = [c for c in re.findall(r'"((?:[^"\\]|\\.){800,})"', html)
              if "[h2" in c or "[h3" in c or "[li]" in c or "[item=" in c]
    if not chunks:
        raise ValueError("no guide markup found")
    return json.loads('"' + max(chunks, key=len) + '"')


def spec_role(url, spec):
    page = url.rsplit("/", 1)[-1]      # "healer-enchants-gems-pve"
    if page.startswith("tank-"):
        return "tank"
    if page.startswith("healer-"):
        return "healer"
    if "/hunter/" in url:
        return "ranged"
    if spec in bd.CASTER_DPS or url.endswith("mage/frost/dps-talent-builds-glyphs-pve") or "/mage/" in url:
        return "caster"
    return "melee"


def build_spec_guides(cfg, item_names, item_spell, spell_enchant):
    per = {}
    for kind in ("enchants", "stats", "rotation"):
        for page in cfg["pages"][kind]:
            cls, spec = page["class"], page["spec"]
            path = os.path.join(CACHE, "%s-%s-%s.html" % (kind, cls, spec))
            bd.fetch("https://web.archive.org/web/%sid_/%s" % (page["snapshot"], page["url"]), path, False)
            try:
                text = page_markup(open(path, encoding="utf-8", errors="replace").read())
            except ValueError:
                print("  WARNING %s page for %s %s has no guide text" % (kind, cls, spec))
                continue
            d = per.setdefault((cls, spec), {"role": spec_role(page["url"], spec)})
            if kind == "enchants":
                d["enchants"], d["gems"] = parse_gear_guide(text, item_names, item_spell, spell_enchant)
            elif kind == "stats":
                d["stats"] = parse_stats(text)
            else:
                d["priority"], d["opener"] = parse_rotation(text, item_names)
    for (cls, spec), d in sorted(per.items()):
        print("%-12s %-14s %-7s enchants %2d  gems %d  stats %d  priority %d"
              % (cls, spec, d["role"], len(d.get("enchants", [])), len(d.get("gems", [])),
                 len(d.get("stats", [])), len(d.get("priority", []))))
    return per


def write_spec_guides(per):
    header = ("-- GENERATED by scripts/build_guides.py -- do not edit by hand.\n"
              "-- Source: Wowhead WotLK enchant/gem, stat priority and rotation guides\n"
              "-- (see scripts/guides.json).\n")

    def opt(o):
        fields = ['kind = "%s"' % o["kind"], "id = %d" % o["id"]]
        if o["enchant"]:
            fields.append("enchant = %d" % o["enchant"])
        for k in ("name", "skill", "tag"):
            if o[k]:
                fields.append("%s = %s" % (k, lua_str(o[k])))
        return "{ " + ", ".join(fields) + " }"

    by_class = {}
    for (cls, spec), d in per.items():
        by_class.setdefault(cls, []).append((spec, d))
    for cls, specs in by_class.items():
        lines = [header, "local _, ns = ...\n"]
        for spec, d in sorted(specs):
            lines.append("\nns:RegisterSpecGuide(%s, %s, {\n\trole = %s,\n" % (lua_str(cls), lua_str(spec), lua_str(d["role"])))
            lines.append("\tstats = { %s },\n" % ", ".join(lua_str(s) for s in d.get("stats", [])))
            for key in ("enchants", "gems"):
                lines.append("\t%s = {\n" % key)
                for e in d.get(key, []):
                    lines.append("\t\t{ slot = %s, options = { %s },\n\t\t  note = %s },\n"
                                 % (lua_str(e["slot"]), ", ".join(opt(o) for o in e["options"]), lua_str(e["note"])))
                lines.append("\t},\n")
            lines.append("\tpriority = {\n")
            for sid, note in d.get("priority", []):
                lines.append("\t\t{ %d, %s },\n" % (sid, lua_str(note)))
            lines.append("\t},\n\topener = %s,\n})\n" % lua_str(d.get("opener", "")))
        bd.write(os.path.join(ROOT, "Data", "Specs", cls.capitalize() + ".lua"), "".join(lines))


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
    item_names, item_spell = {}, {}
    for r in bd.read_table("item_template"):
        item_names[r["entry"]] = r["name"]
        if r["spellid_1"]:
            item_spell[r["entry"]] = r["spellid_1"]
    ench = json.load(open(os.path.join(HERE, "ref", "enchants.json"), encoding="utf-8"))
    spell_enchant = {int(k): v for k, v in ench["spell_enchant"].items()}

    write_spec_guides(build_spec_guides(cfg, item_names, item_spell, spell_enchant))

    # enchant id -> name, so the addon can say what IS on an item
    lines = ["-- GENERATED by scripts/build_guides.py from the realm's SpellItemEnchantment.dbc.\n",
             "local _, ns = ...\n\nns.EnchantNames = {\n"]
    for eid, name in sorted((int(k), v) for k, v in ench["names"].items()):
        lines.append("\t[%d] = %s,\n" % (eid, lua_str(name)))
    lines.append("}\n")
    bd.write(os.path.join(ROOT, "Data", "Enchants.lua"), "".join(lines))

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
