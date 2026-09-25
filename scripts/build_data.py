"""Build FycoPvE's data files from their sources.

    python scripts/build_data.py            # uses cached downloads when present
    python scripts/build_data.py --refresh  # re-download everything

Inputs
  scripts/guides.json   which Wowhead BiS guides to import (archived captures)
  scripts/ref/*.json    client lookup tables -- see scripts/extract_refs.py
  AzerothCore world DB  item, loot, vendor and quest tables, downloaded to
                        .cache/acore/ (git-ignored)

Outputs -- GENERATED, never edit by hand, the next build overwrites them
  Data/BiS/<Class>.lua  ranked lists per spec and phase
  Data/Items.lua        every item on any list, with where it comes from

Why AzerothCore: it is the open 3.3.5 database closest to what TrinityCore-style
private servers run, so drop, vendor and quest data match the game version.
Individual servers do customise, and the addon says so in its UI.
"""
import gzip
import json
import os
import re
import sys
import unicodedata
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
CACHE = os.path.join(ROOT, ".cache")
ACORE_URL = "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/master/data/sql/base/db_world/%s.sql"
ACORE_TABLES = [
    "item_template", "creature_template", "creature", "creature_loot_template",
    "reference_loot_template", "gameobject_template", "gameobject",
    "gameobject_loot_template", "npc_vendor", "quest_template",
]

# guide heading -> the addon's slot key (Data/Constants.lua ns.SlotGroups)
HEADINGS = {
    "Head": "Head", "Neck": "Neck", "Shoulders": "Shoulder", "Back": "Back",
    "Chest": "Chest", "Wrist": "Wrist", "Hands": "Hands", "Waist": "Waist",
    "Legs": "Legs", "Feet": "Feet", "Rings": "Ring", "Trinkets": "Trinket",
    "2-Handed Weapons": "TwoHand", "1-Handed Weapons": "MainHand",
    "Offhand": "OffHand", "Wand": "Ranged",
}
SLOT_ORDER = ["Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
              "Legs", "Feet", "Ring", "Trinket", "TwoHand", "MainHand", "OffHand", "Ranged"]
TIERS = {"Best": 1, "Great": 2, "Good": 3, "Mediocre": 4}

# Wowhead [currency=N] ids that appear in guide source notes
WH_CURRENCY = {101: "Emblem of Heroism", 102: "Emblem of Valor", 126: "Wintergrasp Mark of Honor",
               1900: "Arena Points", 1901: "Honor Points"}
SKILLS = {164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 197: "Tailoring",
          202: "Engineering", 333: "Enchanting", 755: "Jewelcrafting", 773: "Inscription"}

# raids whose creature difficulty entries mean 10 / 25 / 10H / 25H
WOTLK_RAIDS = {249, 533, 603, 615, 616, 624, 631, 649, 724}
REP_RANKS = {3: "Neutral", 4: "Friendly", 5: "Honored", 6: "Revered", 7: "Exalted"}
ALLIANCE_RACES = 1 | 4 | 8 | 64 | 1024
HORDE_RACES = 2 | 16 | 32 | 128 | 512

# an item dropped by more distinct creatures than this is a world drop
WORLD_DROP_CREATURES = 12
MAX_VENDORS = 4


# ---------------------------------------------------------------------------
# downloads
# ---------------------------------------------------------------------------

def fetch(url, path, refresh):
    if os.path.exists(path) and not refresh:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print("  downloading", url)
    req = urllib.request.Request(url, headers={"User-Agent": "FycoPvE-build/0.1"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    with open(path, "wb") as f:
        f.write(data)


# ---------------------------------------------------------------------------
# SQL dump reader
# ---------------------------------------------------------------------------

TOKEN = re.compile(r"'(?:[^'\\]|\\.|'')*'|NULL|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[(),;]")


def unquote(s):
    s = s[1:-1].replace("''", "'")
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "", "t": "\t", "0": ""}.get(m.group(1), m.group(1)), s)


def read_table(name):
    """Yield each row of an AzerothCore dump as a dict keyed by column name."""
    src = open(os.path.join(CACHE, "acore", name + ".sql"), encoding="utf-8", errors="replace").read()
    create = src[src.index("CREATE TABLE"):]
    create = create[:create.index("ENGINE")]
    cols = re.findall(r"^\s*`(\w+)`", create, re.M)

    pos = 0
    while True:
        i = src.find("INSERT INTO", pos)
        if i == -1:
            break
        j = src.index("VALUES", i) + 6
        row, depth = None, 0
        for m in TOKEN.finditer(src, j):
            t = m.group(0)
            if t == "(":
                row, depth = [], 1
            elif t == ")":
                yield dict(zip(cols, row))
                row, depth = None, 0
            elif t == ";":
                pos = m.end()
                break
            elif t == ",":
                continue
            elif depth:
                if t == "NULL":
                    row.append(None)
                elif t[0] == "'":
                    row.append(unquote(t))
                elif "." in t or "e" in t or "E" in t:
                    row.append(float(t))
                else:
                    row.append(int(t))
        else:
            break


# ---------------------------------------------------------------------------
# guides
# ---------------------------------------------------------------------------

ROW = re.compile(r"\[tr\]\s*\[td\](Best|Great|Good|Mediocre)\[/td\]\s*\[td\]\[item=(\d+)\]\[/td\](.*?)\[/tr\]", re.S)


def guide_markup(html):
    """The guide body is a JSON string literal inside the page's script."""
    chunks = [c for c in re.findall(r'"((?:[^"\\]|\\.){2000,})"', html) if "[item=" in c]
    if not chunks:
        raise ValueError("no guide markup found")
    return json.loads('"' + max(chunks, key=len) + '"')


def parse_guide(text):
    """Return {slot: [(itemID, tier, sourceMarkup)]} in the guide's order."""
    slots = {}
    parts = re.split(r"\[h4\](.*?)\[/h4\]", text)
    for k in range(1, len(parts), 2):
        heading, body = parts[k].strip(), parts[k + 1]
        rows = ROW.findall(body)
        if not rows:
            continue
        if heading not in HEADINGS:
            raise ValueError("guide heading not mapped to a slot: %r" % heading)
        out, seen = [], set()
        for tier, item, rest in rows:
            item = int(item)
            if item in seen:
                continue
            seen.add(item)
            cells = re.findall(r"\[td\](.*?)\[/td\]", rest, re.S)
            out.append((item, TIERS[tier], cells[-1] if cells else ""))
        slots[HEADINGS[heading]] = out
    return slots


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def ascii_only(s):
    """The 3.3.5a client renders anything outside ASCII as mojibake."""
    s = unicodedata.normalize("NFKD", s or "")
    return s.encode("ascii", "ignore").decode("ascii")


def lua_str(s):
    s = ascii_only(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def lua_value(v, indent):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(lua_value(x, 0) for x in v) + " }"
        return "{\n" + "".join(pad + "\t" + lua_value(x, indent + 1) + ",\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        keys = [k for k in v if v[k] is not None]
        flat = all(not isinstance(v[k], (dict, list)) or
                   (isinstance(v[k], list) and all(not isinstance(x, (dict, list)) for x in v[k]))
                   for k in keys)
        if flat:
            return "{ " + ", ".join("%s = %s" % (k, lua_value(v[k], 0)) for k in keys) + " }"
        return "{\n" + "".join("%s\t%s = %s,\n" % (pad, k, lua_value(v[k], indent + 1)) for k in keys) + pad + "}"
    raise TypeError(v)


# AzerothCore leaves zoneId/areaId at 0 on most spawn rows, which would label
# every Dalaran vendor just "Northrend". Recognise the cities that matter by
# their bounding box instead: (map, x range, y range) -> AreaTable id.
CITY_BOXES = [
    (571, (5500, 6100), (250, 1000), 4395),   # Dalaran
]


def city_at(map_id, x, y):
    for m, (x0, x1), (y0, y1), area in CITY_BOXES:
        if m == map_id and x0 <= x <= x1 and y0 <= y <= y1:
            return area
    return 0


def load_ref(name):
    with open(os.path.join(SCRIPTS, "ref", name + ".json"), encoding="utf-8") as f:
        return {int(k): v for k, v in json.load(f).items()}


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------

def main():
    refresh = "--refresh" in sys.argv
    maps, areas = load_ref("maps"), load_ref("areas")
    factions, extcost = load_ref("factions"), load_ref("extcost")

    print("sources")
    for t in ACORE_TABLES:
        fetch(ACORE_URL % t, os.path.join(CACHE, "acore", t + ".sql"), refresh)

    cfg = json.load(open(os.path.join(SCRIPTS, "guides.json"), encoding="utf-8"))["guides"]
    lists = []   # (class, spec, phase, url, {slot: [(id, tier, srcMarkup)]})
    for g in cfg:
        path = os.path.join(CACHE, "guides", "%s-%s-%s.html" % (g["class"], g["spec"], g["phase"]))
        fetch("https://web.archive.org/web/%sid_/%s" % (g["snapshot"], g["url"]), path, refresh)
        html = open(path, encoding="utf-8", errors="replace").read()
        lists.append((g["class"], g["spec"], g["phase"], g["url"], parse_guide(guide_markup(html))))

    wanted = set()
    for *_, slots in lists:
        for rows in slots.values():
            wanted.update(r[0] for r in rows)
    print("guides: %d lists, %d distinct items" % (len(lists), len(wanted)))

    # --- server tables ------------------------------------------------------
    print("reading database")
    items = {}
    for r in read_table("item_template"):
        items[r["entry"]] = r

    ctpl = {}
    diff_parent = {}   # heroic / raid-size entry -> (base entry, difficulty index)
    for r in read_table("creature_template"):
        ctpl[r["entry"]] = (r["name"], r["subname"], r["lootid"])
        for k in (1, 2, 3):
            d = r["difficulty_entry_%d" % k]
            if d:
                diff_parent[d] = (r["entry"], k)

    cspawn = {}        # creature entry -> (map, zone)
    for r in read_table("creature"):
        e = r["id1"]
        if e not in cspawn:
            zone = r["zoneId"] or r["areaId"] or city_at(r["map"], r["position_x"], r["position_y"])
            cspawn[e] = (r["map"], zone)

    loot_by_id = {}    # lootid -> [creature entries]
    for e, (_, _, lootid) in ctpl.items():
        if lootid:
            loot_by_id.setdefault(lootid, []).append(e)

    # item -> direct loot rows, and reference id -> templates pulling it in
    def index_loot(table):
        direct, refs = {}, {}
        for r in read_table(table):
            if r["Reference"]:
                refs.setdefault(r["Reference"], []).append((r["Entry"], r["Chance"]))
            else:
                direct.setdefault(r["Item"], []).append((r["Entry"], r["Chance"]))
        return direct, refs

    c_direct, c_refs = index_loot("creature_loot_template")
    r_direct, r_refs = index_loot("reference_loot_template")
    g_direct, g_refs = index_loot("gameobject_loot_template")

    gtpl = {}          # gameobject loot id -> [(entry, name)]
    for r in read_table("gameobject_template"):
        if r["type"] == 3 and r["Data1"]:
            gtpl.setdefault(r["Data1"], []).append((r["entry"], r["name"]))
    gspawn = {}
    for r in read_table("gameobject"):
        e = r["id"]
        if e not in gspawn:
            gspawn[e] = (r["map"], r["zoneId"], r["spawnMask"])

    vendor_items = {}  # vendor entry -> [(item, extcost)]
    for r in read_table("npc_vendor"):
        vendor_items.setdefault(r["entry"], []).append((r["item"], r["ExtendedCost"]))
    sold_by = {}       # item -> [(vendor, extcost)]
    for v, rows in vendor_items.items():
        for item, ec in rows:
            if item > 0:
                sold_by.setdefault(item, []).append((v, ec))
    for v, rows in vendor_items.items():          # negative item = another vendor's list
        for item, _ in rows:
            if item < 0:
                for it, ec in vendor_items.get(-item, []):
                    if it > 0:
                        sold_by.setdefault(it, []).append((v, ec))

    rewarded_by = {}   # item -> [(quest row, is choice)]
    for r in read_table("quest_template"):
        for k in range(1, 5):
            if r["RewardItem%d" % k] in wanted:
                rewarded_by.setdefault(r["RewardItem%d" % k], []).append((r, False))
        for k in range(1, 7):
            if r["RewardChoiceItemID%d" % k] in wanted:
                rewarded_by.setdefault(r["RewardChoiceItemID%d" % k], []).append((r, True))

    # --- resolution ---------------------------------------------------------
    def place(map_id, zone_id):
        m = maps.get(map_id)
        if m and m["type"] in (1, 2):
            return m["name"], m["type"]
        a = areas.get(zone_id)
        if a and a["name"]:
            return a["name"], 0
        # a bare continent ("Kalimdor") reads as an answer but tells you
        # nothing -- better to show no zone than a misleading one
        return None, 0

    def mode_label(map_id, map_type, k):
        if map_type == 1:
            return "Heroic" if k else "Normal"
        if map_type == 2 and map_id in WOTLK_RAIDS:
            return ["10", "25", "10 Heroic", "25 Heroic"][k]
        return None

    def loot_holders(item):
        """Every (kind, lootid, chance) whose table can produce this item,
        following reference tables upward. Chance is only meaningful when the
        item sits directly in that table rather than behind a reference."""
        out = [("c", e, ch) for e, ch in c_direct.get(item, [])]
        out += [("g", e, ch) for e, ch in g_direct.get(item, [])]
        todo = [e for e, _ in r_direct.get(item, [])]
        seen = set()
        while todo:
            ref = todo.pop()
            if ref in seen:
                continue
            seen.add(ref)
            out += [("c", e, 0) for e, _ in c_refs.get(ref, [])]
            out += [("g", e, 0) for e, _ in g_refs.get(ref, [])]
            todo += [e for e, _ in r_refs.get(ref, [])]
        return out

    def cost_of(item_row, ec):
        c = {}
        x = extcost.get(ec) if ec else None
        if x:
            if x["honor"]:
                c["honor"] = x["honor"]
            if x["arena"]:
                c["arena"] = x["arena"]
            if x["rating"]:
                c["rating"] = x["rating"]
            if x["items"]:
                c["items"] = [v for pair in x["items"] for v in pair]
        # gold is charged alongside an extended cost only when the item is
        # flagged for it (FlagsExtra 0x4), which is how the core decides too
        if item_row["BuyPrice"] and (not ec or item_row["FlagsExtra"] & 4):
            c["gold"] = item_row["BuyPrice"]
        return c

    currency = set()
    guide_zone = {}    # item -> AreaTable id the guide's source note names

    def fallback_map(item):
        """Bosses summoned by script (Kil'jaeden, Salramm) have no spawn row,
        so take the map from the zone the guide names for this item instead.
        Without a map there is no instance name and no Heroic / 25 label."""
        z = guide_zone.get(item)
        a = areas.get(z) if z else None
        return (a["map"], z) if a else (None, None)

    def sources(item):
        row = items[item]
        src = []

        # creature and chest drops
        creatures, chests = {}, {}
        for kind, lootid, chance in loot_holders(item):
            if kind == "c":
                for e in loot_by_id.get(lootid, []):
                    base, k = diff_parent.get(e, (e, 0))
                    creatures.setdefault(base, set()).add((k, chance))
            else:
                for e, name in gtpl.get(lootid, []):
                    chests[e] = name

        if len(creatures) > WORLD_DROP_CREATURES:
            src.append({"t": "world", "n": len(creatures)})
        else:
            merged = {}
            for base, hits in creatures.items():
                name = ctpl.get(base, ("?",))[0]
                map_id, zone_id = cspawn.get(base) or fallback_map(item)
                where, mtype = place(map_id, zone_id)
                key = (name, where)
                m = merged.setdefault(key, {"t": "drop", "who": name, "zone": where, "modes": set(), "pct": 0})
                for k, chance in hits:
                    label = mode_label(map_id, mtype, k)
                    if label:
                        m["modes"].add((k, label))
                    if chance and abs(chance) > m["pct"]:
                        m["pct"] = abs(chance)
            for m in merged.values():
                modes = [lbl for _, lbl in sorted(m.pop("modes"))]
                if modes and modes != ["Normal"]:
                    m["mode"] = ", ".join(modes)
                m["pct"] = round(m["pct"], 1) if m["pct"] else None
                src.append(m)

        chest_merged = {}
        for e, name in chests.items():
            map_id, zone_id, mask = gspawn.get(e, (None, None, 0))
            where, mtype = place(map_id, zone_id)
            c = chest_merged.setdefault((name, where), {"t": "chest", "who": name, "zone": where, "modes": set()})
            if mtype == 1:
                if mask & 2:
                    c["modes"].add((1, "Heroic"))
                if mask & 1:
                    c["modes"].add((0, "Normal"))
            elif mtype == 2 and map_id in WOTLK_RAIDS:
                for bit, lbl in ((1, "10"), (2, "25"), (4, "10 Heroic"), (8, "25 Heroic")):
                    if mask & bit:
                        c["modes"].add((bit, lbl))
        for c in chest_merged.values():
            modes = [lbl for _, lbl in sorted(c.pop("modes"))]
            if modes and modes != ["Normal"]:
                c["mode"] = ", ".join(modes)
            src.append(c)

        # vendors, collapsing the same NPC name + price sold in several places
        vend = {}
        for v, ec in sold_by.get(item, []):
            name, title, _ = ctpl.get(v, ("?", None, 0))
            map_id, zone_id = cspawn.get(v, (None, None))
            where, _ = place(map_id, zone_id)
            cost = cost_of(row, ec)
            for i in range(0, len(cost.get("items", [])), 2):
                currency.add(cost["items"][i])
            key = (name, json.dumps(cost, sort_keys=True))
            s = vend.setdefault(key, {"t": "vendor", "who": name, "title": title or None,
                                      "zone": where, "cost": cost})
            if where and s["zone"] and where not in s["zone"].split(" / "):
                s["zone"] = s["zone"] + " / " + where
        vlist = list(vend.values())
        src += vlist[:MAX_VENDORS]
        if len(vlist) > MAX_VENDORS:
            src.append({"t": "more", "n": len(vlist) - MAX_VENDORS})

        # quests
        for q, choice in rewarded_by.get(item, []):
            races = q["AllowableRaces"] or 0
            side = None
            if races and not races & HORDE_RACES:
                side = "Alliance"
            elif races and not races & ALLIANCE_RACES:
                side = "Horde"
            zone = areas.get(q["QuestSortID"], {}).get("name") if q["QuestSortID"] > 0 else None
            src.append({"t": "quest", "who": q["LogTitle"], "zone": zone, "lvl": q["QuestLevel"],
                        "side": side, "choice": choice or None})
        return src

    def guide_note(markup):
        s = markup
        s = re.sub(r"\[npc=(\d+)\]", lambda m: ctpl.get(int(m.group(1)), ("an NPC",))[0], s)
        s = re.sub(r"\[zone=(\d+)\]", lambda m: areas.get(int(m.group(1)), {}).get("name", "a zone"), s)
        s = re.sub(r"\[item=(\d+)\]", lambda m: items.get(int(m.group(1)), {}).get("name", "an item"), s)
        s = re.sub(r"\[currency=(\d+)\]", lambda m: WH_CURRENCY.get(int(m.group(1)), "currency"), s)
        s = re.sub(r"\[skill=(\d+)\]", lambda m: SKILLS.get(int(m.group(1)), "a profession"), s)
        s = re.sub(r"\[spell=(\d+)\]", r"{spell:\1}", s)
        s = re.sub(r"\[icon[^\]]*\](.*?)\[/icon\]", r"\1", s)
        s = re.sub(r"\[[^\]]*\]", "", s)
        s = re.sub(r"(\d) (\d{3})", r"\1\2", s)
        return re.sub(r"\s+", " ", s).strip(" -")

    def side_of(row):
        if row["FlagsExtra"] & 1:
            return "Horde"
        if row["FlagsExtra"] & 2:
            return "Alliance"
        races = row["AllowableRace"]
        if races and races != -1:
            if not races & HORDE_RACES:
                return "Alliance"
            if not races & ALLIANCE_RACES:
                return "Horde"
        return None

    # --- items --------------------------------------------------------------
    notes = {}
    for *_, slots in lists:
        for rows in slots.values():
            for item, _, markup in rows:
                if item not in notes and markup.strip():
                    notes[item] = guide_note(markup)
                z = re.search(r"\[zone=(\d+)\]", markup)
                if z and item not in guide_zone:
                    guide_zone[item] = int(z.group(1))

    missing = sorted(i for i in wanted if i not in items)
    if missing:
        print("WARNING: not in item_template, skipped:", missing)

    out_items = {}
    stats = {"drop": 0, "chest": 0, "vendor": 0, "quest": 0, "world": 0, "none": 0}
    for item in sorted(wanted):
        if item not in items:
            continue
        row = items[item]
        src = sources(item)
        rep = None
        if row["RequiredReputationFaction"]:
            rep = [factions.get(row["RequiredReputationFaction"], "?"),
                   REP_RANKS.get(row["RequiredReputationRank"], "?")]
        out_items[item] = {
            "n": row["name"], "q": row["Quality"], "lvl": row["ItemLevel"], "inv": row["InventoryType"],
            "side": side_of(row), "rep": rep, "g": notes.get(item) or None, "src": src,
        }
        kinds = {s["t"] for s in src}
        for k in stats:
            if k in kinds:
                stats[k] += 1
        if not src:
            stats["none"] += 1

    # --- write --------------------------------------------------------------
    header = ("-- GENERATED by scripts/build_data.py -- do not edit by hand; the next build\n"
              "-- overwrites it. Sources: AzerothCore world DB, the realm client's DBC files,\n"
              "-- and the Wowhead guides listed in scripts/guides.json.\n")

    lines = [header, "local _, ns = ...\n",
             "-- currencies named in vendor costs: item ID -> name\n",
             "ns.Currency = {\n"]
    for c in sorted(currency):
        lines.append("\t[%d] = %s,\n" % (c, lua_str(items.get(c, {}).get("name", "item %d" % c))))
    lines.append("}\n\n")
    lines.append("-- n name, q quality, lvl item level, inv inventory type, side faction-only,\n"
                 "-- rep {faction, standing}, g the guide's own source note, src where it comes from\n")
    lines.append("ns.Items = {\n")
    for item, rec in out_items.items():
        lines.append("\t[%d] = %s,\n" % (item, lua_value(rec, 1)))
    lines.append("}\n")
    write(os.path.join(ROOT, "Data", "Items.lua"), "".join(lines))

    by_class = {}
    for cls, spec, phase, url, slots in lists:
        by_class.setdefault(cls, []).append((spec, phase, url, slots))
    for cls, entries in by_class.items():
        lines = [header, "local _, ns = ...\n"]
        for spec, phase, url, slots in entries:
            lines.append("\n-- %s\nns:RegisterBiS(%s, %s, %s, {\n" % (url, lua_str(cls), lua_str(spec), lua_str(phase)))
            for slot in SLOT_ORDER:
                if slot not in slots:
                    continue
                lines.append("\t%s = {\n" % slot)
                for item, tier, _ in slots[slot]:
                    if item in out_items:
                        lines.append("\t\t{ %d, %d }, -- %s\n" % (item, tier, ascii_only(out_items[item]["n"])))
                lines.append("\t},\n")
            lines.append("})\n")
        write(os.path.join(ROOT, "Data", "BiS", cls.capitalize() + ".lua"), "".join(lines))

    # a generated file the .toc does not load is silently ignored by the game
    toc = open(os.path.join(ROOT, "FycoPvE.toc"), encoding="ascii").read()
    for cls in by_class:
        entry = "Data\\BiS\\" + cls.capitalize() + ".lua"
        if entry not in toc:
            print("WARNING: add '%s' to FycoPvE.toc or the game never loads it" % entry)

    print("items: %d | with drop %d, chest %d, vendor %d, quest %d, world %d, NO source %d"
          % (len(out_items), stats["drop"], stats["chest"], stats["vendor"], stats["quest"],
             stats["world"], stats["none"]))
    nosrc = [i for i, r in out_items.items() if not r["src"]]
    for i in nosrc:
        print("  no DB source: %d %s | guide: %s" % (i, out_items[i]["n"], out_items[i]["g"]))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write(text)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
