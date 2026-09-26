"""Find every archived Wowhead WotLK BiS guide and write scripts/guides.json.

    python scripts/discover_guides.py

wowhead.com/wotlk/guide/... now redirects to the Cataclysm guides, so the
WotLK versions only survive on archive.org. This asks the archive for every
captured guide URL, keeps the pre-raid and phase 1-4 PvE lists, and pins the
newest capture of each -- the version Wowhead last updated during WotLK.

Re-run it only to pick up newer captures; it rewrites guides.json.
"""
import json
import os
import re
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ALL = ("https://web.archive.org/cdx/search/cdx?url=wowhead.com/wotlk/guide/classes/&matchType=prefix"
       "&output=json&fl=original,timestamp&filter=statuscode:200"
       "&filter=original:.*bis-gear-(pre-raid-pve|pve-phase-[1-4])$")

CLASSES = {
    "death-knight": "DEATHKNIGHT", "druid": "DRUID", "hunter": "HUNTER", "mage": "MAGE",
    "paladin": "PALADIN", "priest": "PRIEST", "rogue": "ROGUE", "shaman": "SHAMAN",
    "warlock": "WARLOCK", "warrior": "WARRIOR",
}

# guide tree + role -> the spec key the addon uses (Data/Constants.lua).
# Most trees have one role; where a tree has two, the role is in the name.
SPECS = {
    ("death-knight", "blood", "tank"): "Blood",
    ("death-knight", "blood", "dps"): "Blood DPS",
    ("death-knight", "frost", "dps"): "Frost",
    ("death-knight", "unholy", "dps"): "Unholy",
    ("druid", "balance", "dps"): "Balance",
    ("druid", "feral", "dps"): "Feral DPS",
    ("druid", "feral", "tank"): "Feral Tank",
    ("druid", "restoration", "healer"): "Restoration",
    ("hunter", "beast-mastery", "dps"): "Beast Mastery",
    ("hunter", "marksmanship", "dps"): "Marksmanship",
    ("hunter", "survival", "dps"): "Survival",
    ("mage", "arcane", "dps"): "Arcane",
    ("mage", "fire", "dps"): "Fire",
    ("mage", "frost", "dps"): "Frost",
    ("paladin", "holy", "healer"): "Holy",
    ("paladin", "protection", "tank"): "Protection",
    ("paladin", "retribution", "dps"): "Retribution",
    ("priest", "discipline", "healer"): "Discipline",
    ("priest", "holy", "healer"): "Holy",
    ("priest", "shadow", "dps"): "Shadow",
    ("rogue", "assassination", "dps"): "Assassination",
    ("rogue", "combat", "dps"): "Combat",
    ("rogue", "subtlety", "dps"): "Subtlety",
    ("shaman", "elemental", "dps"): "Elemental",
    ("shaman", "enhancement", "dps"): "Enhancement",
    ("shaman", "restoration", "healer"): "Restoration",
    ("warlock", "affliction", "dps"): "Affliction",
    ("warlock", "demonology", "dps"): "Demonology",
    ("warlock", "destruction", "dps"): "Destruction",
    ("warrior", "arms", "dps"): "Arms",
    ("warrior", "fury", "dps"): "Fury",
    ("warrior", "protection", "tank"): "Protection",
}

PAGES = {"bis-gear-pre-raid-pve": "PreRaid", "bis-gear-pve-phase-1": "P1", "bis-gear-pve-phase-2": "P2",
         "bis-gear-pve-phase-3": "P3", "bis-gear-pve-phase-4": "P4"}

# the other per-spec guide pages, one each, for the guide tabs
OTHER = {"talents": "talent-builds-glyphs-pve", "enchants": "enchants-gems-pve",
         "stats": "stat-priority-attributes-pve", "rotation": "rotation-cooldowns-abilities-pve"}
ALL_OTHER = ("https://web.archive.org/cdx/search/cdx?url=wowhead.com/wotlk/guide/classes/&matchType=prefix"
             "&output=json&fl=original,timestamp&filter=statuscode:200"
             "&filter=original:.*(talent-builds-glyphs|enchants-gems|stat-priority-attributes"
             "|rotation-cooldowns-abilities)-pve$")


def get_json(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "FycoPvE-build"}),
                                        timeout=60) as r:
                return json.loads(r.read().decode("utf-8") or "[]")
        except Exception as e:  # archive.org throttles; back off and retry
            print("  retry", attempt + 1, e)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError("archive.org did not answer: " + url)


def main():
    # One query for every capture under the guides prefix. Asking per page
    # works too, but archive.org takes many seconds per answer.
    rows = get_json(ALL)[1:] + get_json(ALL_OTHER)[1:]
    latest = {}
    for original, stamp in rows:
        key = original.replace("http://", "https://").replace("https://wowhead", "https://www.wowhead")
        if stamp > latest.get(key, ""):
            latest[key] = stamp

    guides = []
    for (cls, tree, role), spec in SPECS.items():
        for page, phase in PAGES.items():
            url = "https://www.wowhead.com/wotlk/guide/classes/%s/%s/%s-%s" % (cls, tree, role, page)
            snap = latest.get(url)
            if not snap:
                continue
            guides.append({"class": CLASSES[cls], "spec": spec, "phase": phase, "url": url, "snapshot": snap})
            print("%-12s %-14s %-8s %s" % (CLASSES[cls], spec, phase, snap))

    pages = {kind: [] for kind in OTHER}
    for (cls, tree, role), spec in SPECS.items():
        for kind, suffix in OTHER.items():
            url = "https://www.wowhead.com/wotlk/guide/classes/%s/%s/%s-%s" % (cls, tree, role, suffix)
            snap = latest.get(url)
            if snap:
                pages[kind].append({"class": CLASSES[cls], "spec": spec, "url": url, "snapshot": snap})
    for kind, lst in pages.items():
        print("%-9s %d pages" % (kind, len(lst)))

    out = {
        "_comment": "Generated by scripts/discover_guides.py. 'guides' are the BiS lists, 'pages' the other "
                    "per-spec guides (talents and glyphs, enchants and gems, stats, rotation). 'snapshot' pins "
                    "an archive.org capture, because wowhead.com/wotlk guides now redirect to the Cataclysm "
                    "versions. Re-run discover_guides.py for newer captures, then the builds.",
        "guides": guides,
        "pages": pages,
    }
    with open(os.path.join(HERE, "guides.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    print("%d guides written" % len(guides))


if __name__ == "__main__":
    main()
