"""Build a server pack: custom vendor gear merged into the BiS lists.

    py -3.11 scripts/build_realm_pack.py                 # finds the saved data itself
    py -3.11 scripts/build_realm_pack.py <path to WTF\\Account\\X\\SavedVariables\\FycoPvE.lua>

Needs lupa (pip install lupa) to read the game's saved data.

Input: what FycoPvE's scanner recorded in game (FycoPvEDB.serverScan):
  - every vendor opened: items, stats, green lines, cost
  - /fpve scan bis: this server's stats for the guide's items
Output: Data/Realm/Frostmourne.lua, plus a report of every decision.

"Better" is decided by stat weights, in spell power per point, for the
specs in WEIGHTS only (Affliction and Destruction warlock for now). Hit is
weighted as if you are below the hit cap -- pre-raid you almost always are;
the Stats & caps page shows where you stand. Set bonuses, procs and on-use
effects cannot be weighed from stats; items that have them are flagged in
the report and in game.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import build_data as bd  # noqa: E402

PACK_KEY, PACK_NAME = "Frostmourne", "Frostmourne Rebuffed"
DEFAULT_WTF = "D:/Whitemane/Frostmourne/FrostmourneRebuffed/WTF/Account/*/SavedVariables/FycoPvE.lua"

# Spell-power-equivalent weights. From the guides: priority Hit > Spell Power
# > Haste > Crit > Spirit > Intellect; 1 Spirit = 0.5 spell power for a
# warlock (0.2 Fel Armor + 0.3 Glyph of Life Tap); haste 32.79 and crit
# 45.91 rating per 1%, which is why haste outvalues crit point for point.
WEIGHTS = {
    ("WARLOCK", "Affliction"): {"sp": 1.00, "hit": 0.95, "haste": 0.85, "crit": 0.55, "spi": 0.50, "int": 0.30},
    ("WARLOCK", "Destruction"): {"sp": 1.00, "hit": 0.95, "haste": 0.75, "crit": 0.65, "spi": 0.45, "int": 0.30},
}
STAT_KEYS = {
    "ITEM_MOD_SPELL_POWER": "sp", "ITEM_MOD_HIT_RATING": "hit", "ITEM_MOD_HIT_SPELL_RATING": "hit",
    "ITEM_MOD_HASTE_RATING": "haste", "ITEM_MOD_HASTE_SPELL_RATING": "haste",
    "ITEM_MOD_CRIT_RATING": "crit", "ITEM_MOD_CRIT_SPELL_RATING": "crit",
    "ITEM_MOD_SPIRIT_SHORT": "spi", "ITEM_MOD_INTELLECT_SHORT": "int",
}
# a socket is worth the gem you would put in it (a rare +19 spell power gem);
# the meta socket, the meta gem's crit damage (roughly 40 spell power)
SOCKETS = {"EMPTY_SOCKET_RED": 19, "EMPTY_SOCKET_YELLOW": 19, "EMPTY_SOCKET_BLUE": 19,
           "EMPTY_SOCKET_PRISMATIC": 19, "EMPTY_SOCKET_META": 40}

SLOT_OF = {
    "INVTYPE_HEAD": "Head", "INVTYPE_NECK": "Neck", "INVTYPE_SHOULDER": "Shoulder", "INVTYPE_CLOAK": "Back",
    "INVTYPE_CHEST": "Chest", "INVTYPE_ROBE": "Chest", "INVTYPE_WRIST": "Wrist", "INVTYPE_HAND": "Hands",
    "INVTYPE_WAIST": "Waist", "INVTYPE_LEGS": "Legs", "INVTYPE_FEET": "Feet", "INVTYPE_FINGER": "Ring",
    "INVTYPE_TRINKET": "Trinket", "INVTYPE_2HWEAPON": "TwoHand", "INVTYPE_WEAPON": "MainHand",
    "INVTYPE_WEAPONMAINHAND": "MainHand", "INVTYPE_HOLDABLE": "OffHand", "INVTYPE_WEAPONOFFHAND": "OffHand",
    "INVTYPE_RANGEDRIGHT": "Ranged", "INVTYPE_RANGED": "Ranged",
}
INV_NUM = {"Head": 1, "Neck": 2, "Shoulder": 3, "Back": 16, "Chest": 5, "Wrist": 9, "Hands": 10, "Waist": 6,
           "Legs": 7, "Feet": 8, "Ring": 11, "Trinket": 12, "TwoHand": 17, "MainHand": 13, "OffHand": 23,
           "Ranged": 26}
ARMOR = {"Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet"}
# what a warlock can wear or wield
WARLOCK_WEAPONS = {"Daggers", "One-Handed Swords", "Staves", "Wands", "Miscellaneous"}


def norm(key):
    """The 3.3.5a client names stats 'ITEM_MOD_SPELL_POWER_SHORT'; accept both forms."""
    return key[:-6] if key.endswith("_SHORT") else key


def score(stats, weights):
    s = 0.0
    for k, v in (stats or {}).items():
        k = norm(k)
        if k in STAT_KEYS:
            s += weights.get(STAT_KEYS[k], 0) * v
        elif k in SOCKETS:
            s += SOCKETS[k] * v
    return s


# 3.3.5a tooltips write plain stats as green "Equip:" lines too ("Equip:
# Improves haste rating by 28."). Those are already in the stats; only what is
# left over is a real effect (a proc, an on-use, a set bonus).
STAT_LINE = re.compile(r"^Equip: (Increases|Improves|Restores) .*?(rating|spell power|mana per 5 sec)[^.]*?"
                       r"by \d+\.?$|^Equip: Restores \d+ mana per 5 sec\.?$", re.I)


def real_effects(rec):
    return [l for l in (rec.get("lines") or []) if not STAT_LINE.match(l)]


def dps_problem(rec):
    """Why a caster DPS should not be offered this item, or None. Healer gear
    scores well on spell power and intellect alone, but its mana regen and
    healing procs are worth nothing to a warlock."""
    if any(norm(k) == "ITEM_MOD_POWER_REGEN0" for k in (rec.get("stats") or {})):
        return "healer item (mana per 5)"
    for l in real_effects(rec):
        low = l.lower()
        if "heal" in low or "helpful spell" in low:
            return "healing effect: " + l
    return None


def usable_by_warlock(rec, slot):
    sub = rec.get("sub") or ""
    if slot in ARMOR or slot == "Back":
        return sub == "Cloth"
    if slot in ("Neck", "Ring", "Trinket"):
        return True
    return sub in WARLOCK_WEAPONS


def merge(guide_list, candidates, stats, weights):
    """Insert each candidate before the first scored item it beats, taking
    that item's tier. Returns (merged list, [(id, position, tier, beaten id)])."""
    merged = [list(e) for e in guide_list]
    scored = {e[0]: score(stats[e[0]]["stats"], weights) for e in guide_list if e[0] in stats}
    placed = []
    if not scored:
        return merged, placed
    for cid in sorted(candidates, key=lambda c: -score(stats[c]["stats"], weights)):
        cs = score(stats[cid]["stats"], weights)
        for j, e in enumerate(merged):
            s = scored.get(e[0])
            if s is not None and cs > s:
                merged.insert(j, [cid, e[1]])
                scored[cid] = cs
                placed.append((cid, j + 1, e[1], e[0]))
                break
    return merged, placed


def lua_table(lua, obj):
    """lupa table -> plain Python."""
    if hasattr(obj, "items") and not isinstance(obj, (dict, str)):
        keys = list(obj.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_table(lua, obj[k]) for k in sorted(keys)]
        return {k: lua_table(lua, obj[k]) for k in keys}
    return obj


def cost_text(cost):
    parts = []
    for c in (cost or {}).get("items") or []:
        parts.append("%s %s" % (c.get("count"), c.get("name")))
    if cost and cost.get("honor"):
        parts.append("%s Honor" % cost["honor"])
    if cost and cost.get("arena"):
        parts.append("%s Arena points" % cost["arena"])
    return " + ".join(parts)


def main():
    try:
        import lupa.lua51 as L
    except ImportError:
        sys.exit("lupa is not installed: pip install lupa (then run this with that Python)")
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if not path:
        found = glob.glob(DEFAULT_WTF)
        if not found:
            sys.exit("no saved FycoPvE data found under %s - scan in game, /reload, then run this" % DEFAULT_WTF)
        path = max(found, key=os.path.getmtime)
    print("reading", path)

    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(path, encoding="utf-8", errors="replace").read())
    db = lua.globals().FycoPvEDB
    scan = lua_table(lua, db.serverScan) if db and db.serverScan else None
    if not scan:
        sys.exit("the saved data has no scan yet - open the vendors and run /fpve scan bis in game first")
    items = {int(k): v for k, v in (scan.get("items") or {}).items()}
    vendors = scan.get("vendors") or {}
    print("realm %s: %d vendors, %d items with stats" % (scan.get("realm"), len(vendors), len(items)))

    lua.execute("ns = { BiS = {} } function ns:RegisterBiS(c, s, p, l) "
                "self.BiS[c] = self.BiS[c] or {} self.BiS[c][s] = self.BiS[c][s] or {} self.BiS[c][s][p] = l end")
    lua.execute('assert(loadfile("%s"))("FycoPvE", ns)' % os.path.join(ROOT, "Data", "BiS", "Warlock.lua").replace("\\", "/"))
    bis = lua_table(lua, lua.globals().ns.BiS)

    # candidates: vendor items with spell power that a caster could use. An item
    # already on a LATER phase's list still competes on an earlier one -- on this
    # server Emblem of Valor gear is buyable before raiding -- so only a list
    # that already has the item skips it (see the merge loop below).
    offers = {}
    for vname, vitems in vendors.items():
        for iid, rec in (vitems or {}).items():
            iid = int(iid)
            slot = SLOT_OF.get(rec.get("loc") or "")
            if slot and any(norm(k) == "ITEM_MOD_SPELL_POWER" for k in (rec.get("stats") or {})):
                offers[iid] = (slot, vname, rec)
                items.setdefault(iid, rec)
    skipped = []
    for iid in list(offers):
        why = dps_problem(offers[iid][2])
        if why:
            skipped.append("skipped %s: %s" % (offers[iid][2]["n"], why))
            del offers[iid]
    print("%d vendor items could go on a caster DPS's lists (%d healer items left out)" % (len(offers), len(skipped)))

    lists_out, used, report = {}, set(), []
    for (cls, spec), weights in WEIGHTS.items():
        for phase, slots in bis.get(cls, {}).get(spec, {}).items():
            for slot, lst in slots.items():
                have = {e[0] for e in lst}
                cands = [i for i, (s, _, rec) in offers.items()
                         if s == slot and i not in have and usable_by_warlock(rec, slot)]
                if not cands:
                    continue
                if not any(e[0] in items for e in lst):
                    report.append("%s %s %s %s: no guide item has recorded stats - run /fpve scan bis all"
                                  % (cls, spec, phase, slot))
                    continue
                merged, placed = merge(lst, cands, items, weights)
                if placed:
                    lists_out.setdefault(cls, {}).setdefault(spec, {}).setdefault(phase, {})[slot] = merged
                    for cid, pos, tier, beaten in placed:
                        used.add(cid)
                        report.append("%s %s %s %s: %s (%.0f) at #%d, tier %d, above %s (%.0f)%s" % (
                            cls, spec, phase, slot, items[cid]["n"], score(items[cid]["stats"], weights), pos, tier,
                            items[beaten]["n"], score(items[beaten]["stats"], weights),
                            ("  [effect not weighed: %s]" % "; ".join(real_effects(items[cid])))
                            if real_effects(items[cid]) else ""))
    report += skipped

    # --- write --------------------------------------------------------------
    L_ = ['-- GENERATED by scripts/build_realm_pack.py from a scan made in game -- do not edit by hand.\n',
          '-- Custom %s gear merged into the BiS lists; used only when the server pack is on.\n' % PACK_NAME,
          "local _, ns = ...\n\nns:RegisterRealmPack(%s, {\n\tname = %s,\n\titems = {\n"
          % (bd.lua_str(PACK_KEY), bd.lua_str(PACK_NAME))]
    for iid in sorted(used):
        slot, vname, rec = offers[iid]
        src = {"t": "vendor", "who": vname, "cost": {"text": cost_text(rec.get("cost"))}}
        entry = {"n": rec["n"], "q": rec.get("q") or 4, "lvl": rec.get("ilvl") or 0, "inv": INV_NUM[slot],
                 "lines": real_effects(rec) or None, "src": [src]}
        L_.append("\t\t[%d] = %s,\n" % (iid, bd.lua_value(entry, 2)))
    L_.append("\t},\n\tlists = %s,\n})\n" % bd.lua_value(lists_out, 1))
    out = os.path.join(ROOT, "Data", "Realm", PACK_KEY + ".lua")
    bd.write(out, "".join(L_))
    with open(os.path.join(ROOT, ".cache", "realm_pack_report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    print("\n".join(report) if report else "no custom item beat a guide item")
    print("%d custom items placed" % len(used))
    toc = open(os.path.join(ROOT, "FycoPvE.toc"), encoding="ascii").read()
    if "Data\\Realm\\%s.lua" % PACK_KEY not in toc:
        print("WARNING: add 'Data\\Realm\\%s.lua' to FycoPvE.toc after Modules\\Scanner.lua" % PACK_KEY)


if __name__ == "__main__":
    main()
