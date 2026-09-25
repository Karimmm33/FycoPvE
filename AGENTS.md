# AGENTS.md

Canonical instruction file for AI agents working in this repository.

Follow the shared repo-local rules first:

@docs/conventions/agent-global-rules.md

Then the rules specific to this addon. They are not optional:

@docs/conventions/addon-rules.md

The backend and frontend style guides do not apply here — this is Lua 5.1
against the WoW 3.3.5a client API, plus Python build scripts.

---

## What this project is

A PvE companion addon for WoW 3.3.5a (Interface 30300), the sister of FycoPvP
(https://github.com/Karimmm33/FycoPvP). It starts with a best-in-slot checker
and an item source search, and is built to grow into more modules (threat,
meters, boss timers) that plug into the same core, window and settings.

## The development loop

**This project is the source of truth. The copy inside the WoW client is
disposable.**

```powershell
# 1. edit here, in D:\Projects\FycoPvE
# 2. if BiS lists or sources changed, rebuild the data (read its UNMAPPED/dropped lines)
python scripts\discover_guides.py     # only to pick up newer archived guides
python scripts\build_data.py
# 3. check every Lua file, then run the automated suite (pip install lupa, once)
python scripts\luacheck.py Core.lua Widgets.lua Sources.lua Data\Constants.lua Data\Items.lua Modules\Gear.lua Modules\Options.lua Modules\Search.lua Modules\Threat.lua Modules\Tooltip.lua Modules\Window.lua
python tests\run_tests.py
# 4. push it into the client and test in game, following docs\TESTING.md
.\scripts\deploy.ps1          # -WhatIf to preview
#    then /reload in game
```

`deploy.ps1` **mirrors** `Data\` and `Modules\`, so anything edited in the
client folder is overwritten. `.git`, `docs\`, `scripts\`, `.cache\` and the
agent files are never deployed: the client folder looks exactly like what a
user unzips.

## Releasing

```powershell
# bump '## Version:' in FycoPvE.toc first -- package.ps1 reads it from there
.\scripts\package.ps1
gh release create v0.1.0 .\dist\FycoPvE-0.1.0.zip --title "FycoPvE 0.1.0" --notes-file notes.md
```

Never point anyone at GitHub's "Code -> Download ZIP": it extracts as
`FycoPvE-main`, which WoW does not recognise. The zip from `package.ps1` is
the only supported download.

## Before telling Karim something is done

See the checklist at the end of `docs/conventions/addon-rules.md`.
