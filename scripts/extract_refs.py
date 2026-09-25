"""Pull the handful of client-side lookup tables the data build needs.

The server database (AzerothCore) names creatures, items and quests, but map
names, zone names, faction names and vendor currency costs live in the
CLIENT's DBC files. This reads those four tables and writes small JSON files
to scripts/ref/, which are committed -- so the normal data build never needs
the client, and this only has to be re-run if the client data changes.

Reads from the realm's own rebuffed.mpq rather than a stock 3.3.5 archive, so
costs and names match what this server actually ships.

Needs the pure-Python MPQ reader: pip install mpyq

    python scripts/extract_refs.py "D:/Whitemane/Frostmourne/FrostmourneRebuffed/Data/rebuffed.mpq"
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ref")


def read_dbc(blob):
    """Return (records, string lookup) for a WDBC blob. Every field is read as
    int32; string fields are offsets into the trailing string block."""
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


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        import mpyq
    except ImportError:
        sys.exit("mpyq is not installed: pip install mpyq")

    archive = mpyq.MPQArchive(sys.argv[1], listfile=False)

    def dbc(name):
        blob = archive.read_file("DBFilesClient\\" + name)
        if blob is None:
            sys.exit("%s is not in %s" % (name, sys.argv[1]))
        return read_dbc(blob)

    os.makedirs(OUT, exist_ok=True)

    # Map.dbc: 0 id, 2 instance type (0 world, 1 dungeon, 2 raid, 3 bg, 4 arena), 5 name (enUS/enGB slot)
    recs, s = dbc("Map.dbc")
    maps = {r[0]: {"name": s(r[5]), "type": r[2]} for r in recs}

    # AreaTable.dbc: 0 id, 1 map, 2 parent zone, 11 name
    recs, s = dbc("AreaTable.dbc")
    areas = {r[0]: {"name": s(r[11]), "map": r[1], "zone": r[2]} for r in recs}

    # Faction.dbc: 0 id, 23 name
    recs, s = dbc("Faction.dbc")
    factions = {r[0]: s(r[23]) for r in recs}

    # ItemExtendedCost.dbc: 0 id, 1 honor, 2 arena, 4-8 items, 9-13 counts, 14 personal rating
    recs, _ = dbc("ItemExtendedCost.dbc")
    costs = {}
    for r in recs:
        items = [[r[4 + i], r[9 + i]] for i in range(5) if r[4 + i]]
        costs[r[0]] = {"honor": r[1], "arena": r[2], "items": items, "rating": r[14]}

    for name, data in (("maps", maps), ("areas", areas), ("factions", factions), ("extcost", costs)):
        path = os.path.join(OUT, name + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        print("wrote %-40s %6d rows" % (os.path.relpath(path), len(data)))


if __name__ == "__main__":
    main()
