"""Talent trees as this realm ships them, and what the realm changed.

    python scripts/extract_talents.py "D:/Whitemane/Frostmourne/FrostmourneRebuffed"

Frostmourne Rebuffed is a class-rebalance realm, so Wowhead's builds and
rotations may not match it everywhere. This reads the realm's own talent
and spell tables (Data/rebuffed.mpq) and compares them with the stock 3.3.5
ones (Data/enGB/locale-enGB.MPQ):

  scripts/ref/talents.json        every class's trees: tab order, and each
                                  talent's tier, column and rank spells
  scripts/ref/realm_changes.json  talents the realm moved or re-ranked, and
                                  spells whose numbers or text it changed

Needs mpyq (pip install mpyq). Re-run only when the realm patches its client.
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ref")

CLASS_BITS = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 6: "DEATHKNIGHT",
              7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}

# Spell.dbc (3.3.5a, 234 fields): the localised strings sit in 136..203
# (name 136, rank 153, description 170, tooltip 187 -- enUS/enGB slot first).
# Everything else is numeric. String offsets differ between files, so strings
# are compared as text and only those four; every other field by value.
SPELL_STRINGS = range(136, 204)
PROFESSIONS = {164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 197: "Tailoring", 202: "Engineering",
               333: "Enchanting", 755: "Jewelcrafting", 773: "Inscription", 185: "Cooking", 129: "First Aid"}
SPELL_TEXT = {136: "name", 153: "rank", 170: "description", 187: "tooltip"}


def read_dbc(blob):
    magic, n, fields, rec_size, _ = struct.unpack_from("<4s4i", blob, 0)
    if magic != b"WDBC":
        raise ValueError("not a WDBC file")
    recs = [struct.unpack_from("<%di" % fields, blob, 20 + i * rec_size) for i in range(n)]
    strings = blob[20 + n * rec_size:]

    def s(off):
        if off <= 0 or off >= len(strings):
            return ""
        end = strings.find(b"\0", off)
        return strings[off:end].decode("utf-8", "replace")

    return recs, s


def load(archive, name):
    blob = archive.read_file("DBFilesClient\\" + name)
    if blob is None:
        sys.exit("%s is missing from an archive" % name)
    return read_dbc(blob)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        import mpyq
    except ImportError:
        sys.exit("mpyq is not installed: pip install mpyq")
    client = sys.argv[1]
    realm = mpyq.MPQArchive(os.path.join(client, "Data", "rebuffed.mpq"), listfile=False)
    stock = mpyq.MPQArchive(os.path.join(client, "Data", "enGB", "locale-enGB.MPQ"), listfile=False)

    # --- trees, as the realm has them ---------------------------------------
    tabs, s = load(realm, "TalentTab.dbc")
    # TalentTab: 0 id, 1 name, 20 class mask, 21 pet mask, 22 order index
    tab_info = {}
    for r in tabs:
        if r[21]:
            continue   # hunter pet trees
        for bit, cls in CLASS_BITS.items():
            if r[20] & (1 << (bit - 1)):
                tab_info[r[0]] = {"class": cls, "name": s(r[1]), "order": r[22]}

    # Talent: 0 id, 1 tab, 2 tier, 3 column, 4..12 rank spells, 13..15 prereq talents
    talents, _ = load(realm, "Talent.dbc")
    trees = {}
    for r in talents:
        t = tab_info.get(r[1])
        if not t:
            continue
        ranks = [x for x in r[4:13] if x]
        tree = trees.setdefault(t["class"], {}).setdefault(r[1], {"name": t["name"], "order": t["order"], "talents": []})
        tree["talents"].append({"id": r[0], "tier": r[2], "col": r[3], "ranks": ranks,
                                "req": [x for x in r[13:16] if x]})
    # Wowhead's talent strings give one digit per talent of the STOCK tree, in
    # row-then-column order. The realm adds talents (Protection warriors got
    # three), so decoding a string needs the stock order, not the realm's.
    stock_talents, _ = load(stock, "Talent.dbc")
    stock_order = {}
    for r in stock_talents:
        if r[1] in tab_info:
            stock_order.setdefault(r[1], []).append((r[2], r[3], r[0]))

    out = {}
    for cls, tabs_ in trees.items():
        lst = []
        for tab_id, t in sorted(tabs_.items(), key=lambda kv: kv[1]["order"]):
            t["talents"].sort(key=lambda x: (x["tier"], x["col"]))
            t["stock_order"] = [tid for _, _, tid in sorted(stock_order.get(tab_id, []))]
            del t["order"]
            lst.append(t)
        out[cls] = lst

    # --- what the realm changed ---------------------------------------------
    stock_by_id = {r[0]: r for r in stock_talents}
    changed_talents = []
    for r in talents:
        o = stock_by_id.get(r[0])
        if r[1] in tab_info and (not o or o[1:13] != r[1:13]):
            changed_talents.append(r[0])

    print("reading Spell.dbc from both archives (large)...")
    rs, rstr = load(realm, "Spell.dbc")
    ss, sstr = load(stock, "Spell.dbc")
    stock_spells = {r[0]: r for r in ss}
    # Only changes a player would notice: text, cast/cooldown/duration/range
    # and effect values (fields 28-120). Flag-only edits and the realm's
    # thousands of brand-new spells (its own content) are left out.
    changed_spells = {}
    for r in rs:
        o = stock_spells.get(r[0])
        if not o:
            continue
        diff = []
        for i in range(1, len(r)):
            if i in SPELL_STRINGS:
                if i in SPELL_TEXT and rstr(r[i]) != sstr(o[i]):
                    diff.append(SPELL_TEXT[i])
            elif r[i] != o[i] and 28 <= i <= 120:
                diff.append(i)
        if diff:
            changed_spells[r[0]] = diff

    # --- enchants: which enchant each enchanting spell puts on an item -----
    # Spell.dbc 71..73 Effect, 110..112 EffectMiscValue; effect 53 is
    # ENCHANT_ITEM (permanent). The enchant id is what an item link carries
    # in its second field, so this is how an equipped enchant is recognised.
    spell_enchant = {}
    for r in rs:
        for k in range(3):
            if r[71 + k] == 53 and r[110 + k]:
                spell_enchant[r[0]] = r[110 + k]
    # SpellItemEnchantment.dbc: 0 id, 14 name (enUS/enGB slot)
    ench, estr = load(realm, "SpellItemEnchantment.dbc")
    enchant_names = {r[0]: estr(r[14]) for r in ench if estr(r[14])}
    # GemProperties.dbc: 0 id, 1 enchant id, 4 colour mask (1 meta, 2 red, 4 yellow, 8 blue)
    gems, _ = load(realm, "GemProperties.dbc")
    gem_colors = {r[0]: r[4] for r in gems}

    # --- crafting: which profession spell makes which item ---------------
    # Spell.dbc 71..73 Effect (24 = CREATE_ITEM), 107..109 EffectItemType.
    # SkillLineAbility.dbc: 1 skill line, 2 spell, 7 minimum skill.
    sla, _ = load(realm, "SkillLineAbility.dbc")
    spell_skill = {}
    for r in sla:
        if r[1] in PROFESSIONS:
            spell_skill[r[2]] = [PROFESSIONS[r[1]], r[7]]
    crafted_by = {}
    for r in rs:
        if r[0] in spell_skill:
            for k in range(3):
                if r[71 + k] == 24 and r[107 + k]:
                    crafted_by.setdefault(r[107 + k], []).append(r[0])

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "crafts.json"), "w", encoding="utf-8") as f:
        json.dump({"spell_skill": spell_skill, "crafted_by": crafted_by}, f, sort_keys=True, separators=(",", ":"))
    with open(os.path.join(OUT, "enchants.json"), "w", encoding="utf-8") as f:
        json.dump({"spell_enchant": spell_enchant, "names": enchant_names, "gem_colors": gem_colors},
                  f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    with open(os.path.join(OUT, "talents.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    with open(os.path.join(OUT, "realm_changes.json"), "w", encoding="utf-8") as f:
        json.dump({"talents": sorted(changed_talents), "spells": changed_spells}, f, sort_keys=True,
                  separators=(",", ":"))
    print("classes %d, talents changed %d, spells changed or new %d"
          % (len(out), len(changed_talents), len(changed_spells)))


if __name__ == "__main__":
    main()
