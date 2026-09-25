# FycoPvE — rules for working in this addon

WoW 3.3.5a (Interface 30300). Read this before changing anything here. Most
of these rules were learned the hard way in FycoPvP, the sister addon.

---

## HARD RULE 1 — never hand-place an options widget

The Interface Options content area is roughly 500 x 500 pixels and **does not
clip its children**. A widget placed past the bottom renders outside the
frame, over the game world.

- Never write a literal Y offset. Use the layout cursor in
  `Modules/Options.lua` (`Column:Check`, `:Slider`, `:Title`, `:Note`,
  `:Button`, `:Buttons`, `:Dropdown`). Each advances by its real height.
- Every options panel is a scroll frame (`MakePanel()`), sized by `Finish()`.
- Two columns maximum, at `COL1 = 8` and `COL2 = 250`, each 230 wide.
- Modules add settings pages through `ns:RegisterOptions(key, title, order,
  build)`; `build(L, R)` gets the two columns. Do not add pages by editing
  `Options.lua`.

The main window's tabs are fixed-size panes; anything that can grow (a list,
a detail text) goes in a scroll frame there too.

## HARD RULE 2 — write Lua with the Write/Edit tools

Bash heredocs and `python -c` in this environment silently eat backslashes.
`"Interface\\Icons\\X"` arrives as `"Interface\Icons\X"`, an invalid escape,
and the addon refuses to load with no clue why. Author `.lua` (and `.toc`)
with Write/Edit; if a scripted patch is needed, write the script to a file.

## HARD RULE 3 — check every file before saying it is done

```
python scripts/luacheck.py Core.lua Widgets.lua Sources.lua Data/*.lua Data/BiS/*.lua Modules/*.lua
```

ASCII only (the client renders anything else as mojibake), valid escapes,
balanced blocks, no orphaned ALL_CAPS constants. It is a lexer, not a
parser: a clean run is not proof the file parses, and never proof it runs.

Then run the automated suite, which loads the real addon in Lua 5.1 against
a mock client (`tests/wowmock.lua`) and drives it:

```
pip install lupa        # once
python tests/run_tests.py
```

Every feature gets tests there, and every in-game check goes in
`docs/TESTING.md` with an ID. A new frame method the mock does not model is
listed at the end of a run; confirm it exists in 3.3.5a.

## HARD RULE 4 — generated data is never edited by hand

`Data/Items.lua` and `Data/BiS/*.lua` are written by `scripts/build_data.py`
and the next build overwrites them. To change a list, change its source
(`scripts/guides.json`) and rebuild. To fix a source record, fix the build.

The build warns when it writes a `Data/BiS/<Class>.lua` the `.toc` does not
load. Heed it: an unlisted file is silently ignored by the game.

## HARD RULE 5 — grep for orphaned references after deleting anything

Lua resolves a deleted `local` to a nil global. That parses perfectly and only
fails at runtime. After removing or renaming anything:

```
grep -rn "OLD_NAME" --include=*.lua .     # expect zero hits
```

---

## Architecture

`Core.lua` owns everything shared, and modules use it rather than duplicate it:

- **one** event dispatcher — `ns:On(event, fn)`
- **one** 10 Hz ticker — `ns:OnTick(fn)`, inside a pcall
- **one** message bus — `ns:Subscribe(msg, fn)` / `ns:Fire(msg, ...)`.
  `ProfileChanged` (spec or phase changed) and `SettingChanged(section, key,
  value)` are the two every module listens to.
- settings — `ns:Get(section, key)` / `ns:Set(section, key, value)`, with
  every default in `ns.Defaults`. Never read `FycoPvEDB` fields directly for
  a setting; the default would be missed.
- modules — `ns:Module(name, order)` with an `OnLoad`, run in `order` inside a
  pcall. `ns:Enabled(name)` is checked at use time.
- the window — `ns:AddTab(key, label, order, build, onShow)`; content is built
  the first time the tab opens.
- the BiS registry — `ns:RegisterBiS(class, spec, phase, lists)` fills
  `ns.BiS` and the reverse lookup `ns.BiSIndex[itemID]`.

Adding a feature module: new file in `Modules/`, add it to `FycoPvE.toc`,
add its switch to `moduleDefaults` in `Core.lua` and the Features list in
`Options.lua`, register a tab and/or a settings page, document it in
`README.md`.

## The data pipeline

```
scripts/guides.json ──┐
AzerothCore world DB ─┼─ scripts/build_data.py ─> Data/BiS/<Class>.lua, Data/Items.lua
scripts/ref/*.json ───┘        (ref tables: scripts/extract_refs.py, from the realm client)
```

- Wowhead's `/wotlk/` guide URLs now redirect to Cataclysm, so guides are read
  from pinned archive.org captures. `scripts/discover_guides.py` rewrites
  `guides.json` with the newest capture of every class/spec/phase guide (one
  CDX query; asking per page is far too slow).
- Guide layouts vary a lot across ~150 pages. The parser reads tables cell by
  cell, maps armour headings by their first word (`ARMOR`), sorts weapon and
  relic sections into TwoHand/MainHand/OffHand/Ranged by each item's real
  inventory type, and folds dozens of rank labels into four tiers
  (`tier_of`). Anything it cannot place is printed as `UNMAPPED` at the end of
  the build: read that output after every build.
- An item whose inventory type cannot go in its slot is dropped with a
  `dropped` line (the Destruction pre-raid guide lists necklaces under Back).
- AzerothCore spawn rows mostly have no zone, so cities are recognised by
  bounding box (`CITY_BOXES`) and anything else unresolved shows no zone
  rather than a continent name.
- Bosses spawned by script have no spawn row; their map comes from the zone
  the guide names for the item.

## 3.3.5a facts that matter here

- No C_Timer, no spec API: spec is read from talent points
  (`GetTalentTabInfo`, third return) for the active talent group.
- The game cannot report the server's content phase. The player sets it.
- `GetItemInfo` returns nil for items the client has not cached; use our own
  data for names and quality, and `GetItemIcon` for icons.
- `OnTooltipSetItem` can fire more than once per item; guard with a flag
  cleared in `OnTooltipCleared`.
- Dropdowns (`UIDropDownMenuTemplate`), edit boxes (`InputBoxTemplate`) and
  faux scroll frames need global names.

## Honesty in the UI

Source data describes the stock 3.3.5 game. This is a custom realm
(Frostmourne Rebuffed), so drops, prices and stats can differ. The UI says so
where sources are shown, and never presents a guess as fact: a vendor whose
location is unknown shows no location rather than a wrong one.

## Before telling Karim it is done

1. `scripts/luacheck.py` is clean over every `.lua` file.
2. New commands are in `Core.lua`'s slash handler *and* its help output.
3. New modules are in `FycoPvE.toc`, `moduleDefaults` and the options list.
4. Every new setting is reachable from the options UI, not only a command.
5. `README.md` covers any new feature and command.
6. Say what was actually verified. A static check is not a runtime check.
