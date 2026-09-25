# FycoPvE

A PvE companion addon for **World of Warcraft 3.3.5a** (Wrath of the Lich King).
It answers two questions:

- **Am I wearing my best in slot?** Every equipped item is checked against the
  BiS list for your spec and the content phase you choose.
- **Where do I get this item?** Search by item name, slot, boss, vendor or
  zone. You get every source: boss and difficulty, vendor, cost, required
  reputation, quest, or crafting profession.

It is the PvE sister of [FycoPvP](https://github.com/Karimmm33/FycoPvP), and it
will grow the same way, one module at a time.

## What's in 0.1

| | |
|---|---|
| **Gear tab** | One row per slot showing what you wear, where it ranks (`BiS Best #2/12`, `Good #5/12`, `not on the list`), and the next upgrade. Click the upgrade to see where it comes from. |
| **Character sheet** | A badge on every slot: `BiS`, `#rank`, or `x`. A **BiS** button opens the Gear tab. |
| **Equip report** | When you equip something, one chat line says how it ranks and names a better item. |
| **Tooltips** | Every item tooltip (bags, loot, links, vendors, auction house) shows its BiS rank for your spec, plus its first source. |
| **Search tab** | Type `wrist`, `bracers`, `halls of stone`, `emblem` or part of a name. Results for your own spec come first. Click one to see every source. |
| **Settings** | Everything is configurable under *Interface → AddOns → FycoPvE*, or from the window's **Settings** button. |

**BiS lists shipped:** Warlock — Affliction and Destruction, Pre-Raid.
More classes, specs and phases are data only and will follow.

## Spec and phase

- **Spec** is detected from your talents, including a dual-spec swap. You can
  override it to look at another spec's list.
- **Phase** can't be detected, because the game doesn't tell addons which
  phase a server is on. Pick it in the window or in the settings, and change
  it when the server moves on. It's shared by all your characters.

## Commands

Everything below is also in the settings UI.

| Command | |
|---|---|
| `/fpve` | open or close the window |
| `/fpve options` | open the settings |
| `/fpve gear` | BiS check of your gear, in chat |
| `/fpve find <text>` | where an item comes from, in chat |
| `/fpve phase [key]` | show or set the phase (`PreRaid`, `P1` … `P4`) |
| `/fpve spec [name\|auto]` | show or override your spec |
| `/fpve minimap` | show or hide the minimap button |

## Install

1. Download `FycoPvE-<version>.zip` from the
   [Releases](https://github.com/Karimmm33/FycoPvE/releases) page. Don't use
   the green *Code → Download ZIP* button: its folder name is wrong and WoW
   won't see the addon.
2. Extract it into `World of Warcraft\Interface\AddOns\`, so you end up with
   `Interface\AddOns\FycoPvE\FycoPvE.toc`.
3. Restart the game or `/reload`.

## Where the data comes from

- **BiS rankings:** Wowhead's Wrath of the Lich King Classic guides, read from
  archived copies because Wowhead now redirects those pages to Cataclysm.
- **Drops, vendors, costs, reputation, quests:** the
  [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) 3.3.5 world
  database.
- **Map, zone, faction and currency names:** the game client's own data files.

Private realms, and custom ones especially, can change drops, prices and item
stats. **When the game disagrees with FycoPvE, the game is right.**

## For developers

See [AGENTS.md](AGENTS.md) and [docs/conventions/addon-rules.md](docs/conventions/addon-rules.md).
In short: `python scripts/build_data.py` regenerates `Data/`,
`scripts/luacheck.py` checks the Lua, and `scripts/deploy.ps1` copies the
addon into a client for testing.

## License

MIT, see [LICENSE](LICENSE).
