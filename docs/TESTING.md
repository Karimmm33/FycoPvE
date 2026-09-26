# FycoPvE in-game testing sheet

> **Status:** sections A–N (0.1–0.6) were tested in game on 2026-09-25
> (Whitemane, Frostmourne Rebuffed) and passed. **To test now: sections O–T**
> (0.7–0.11: talents, glyphs, overview, gems & enchants, stats & caps,
> rotation helper, professions).

Work through the sections in order. For each test, do exactly what the **How**
column says, compare with **Expected**, and report back by ID, for example:

> A1 ok, A2 ok, C3 FAIL - the Ranged row says "no list" on my warlock, screenshot attached

Anything marked **auto** has already been checked by the automated test suite
(`python tests/run_tests.py`, see the bottom of this file), so for those you
only need to confirm that the game agrees with the mock. If you see red error
text anywhere, copy it into your report exactly.

---

## Setup (once)

1. Close the game.
2. In PowerShell:
   ```powershell
   cd D:\Projects\FycoPvE
   .\scripts\deploy.ps1
   ```
   It must end with a green **Deployed.** line. It creates
   `Interface\AddOns\FycoPvE` and does not touch FycoPvP.
3. Start the game. On the character select screen, click **AddOns** and make
   sure **FycoPvE** is listed and ticked.
4. Log in on your warlock.

To report a Lua error with its full text, you can run `/console scriptErrors 1`
once and `/reload`. Errors then pop up in a window you can screenshot.

---

## A. Loading

| ID | How | Expected |
|---|---|---|
| A1 | Log in and look at chat. | One line: `FycoPvE v0.x - <Spec> Warlock, Pre-Raid. /fpve to open.` The spec should match your talents. |
| A2 | Look at the edge of the minimap. | A round book-icon button. |
| A3 | Type `/fpve help`. | A list of commands, with no red text. |
| A4 | Type `/reload`. | The same greeting again, and no errors. |

## B. Main window

| ID | How | Expected |
|---|---|---|
| B1 | Type `/fpve`. | A window titled **FycoPvE v0.x**, with tab buttons along the top and a **Settings** button top-right. |
| B2 | Drag the window by its title area, close it with X, then `/fpve` again. | It reopens where you left it. |
| B3 | With the window open, press **Escape**. | It closes. |
| B4 | Left-click the minimap button. Then right-click it. | Left opens and closes the window. Right opens *Interface → AddOns → FycoPvE*. |
| B5 | Drag the minimap button around the minimap. | It slides along the minimap's edge and stays there after `/reload`. |
| B6 | Hover the minimap button. | A tooltip with your spec and phase, and click hints. |

## C. Gear tab

| ID | How | Expected |
|---|---|---|
| C1 | `/fpve`, then click **Gear**. | Spec and Phase dropdowns at the top, a summary line (`... X of 17 slots BiS`), and 17 rows from Head to Ranged. Nothing overlaps or runs off the window. |
| C2 | Look at a row with an item. | Its icon, its name, and a status such as `BiS Best #1/12`, `Good #5/12` or `not on the list`. |
| C3 | Hover an item icon in a row. | The normal item tooltip. |
| C4 | Find a row with an upgrade (`-> name`). Hover its icon, then click it. | Hover shows the upgrade's tooltip. Click switches to **Search** with that item selected and every source listed on the right. |
| C5 | Shift-click an upgrade icon with the chat box open. | The item link goes into chat. |
| C6 | Change the **Spec** dropdown to Destruction, then back to Auto. | Rows and summary change at once. Auto shows your talent spec in brackets. |
| C7 | Change **Phase** to Phase 1. | The rows re-rank against the Phase 1 list (from 0.3 on). |
| C8 | Pick a spec whose lists aren't in yet, if one exists. | A message saying there is no list yet, instead of rows. |
| C9 | If you have a staff: equip it. | Main hand is judged on the two-hand list. Off hand says `not used with a two-hander`. |

## D. Character sheet

| ID | How | Expected |
|---|---|---|
| D1 | Press **C**. | Each equipped slot has a small badge in its top-left corner: green `BiS`, a coloured `#n`, or a red `x`. Empty slots have none. |
| D2 | Look for a **BiS** button on the character sheet. | A small button near the top right. **Tell me exactly where it lands**, or whether it covers anything. Its position is a guess, because the realm's UI is modified. |
| D3 | Click the **BiS** button. | The FycoPvE window opens on the Gear tab. |
| D4 | Settings → BiS and Gear → untick *Rank badge on each slot*, then reopen C. | The badges are gone. Tick it again and they come back. |

## E. Equip report

| ID | How | Expected |
|---|---|---|
| E1 | Take off a piece of gear and put it back on. | One chat line: `[item] (Slot): BiS Best #1/12`, or its rank, or `not on the Pre-Raid list`, plus `better: [item]` when there is an upgrade. |
| E2 | Log in or `/reload`. | **No** flood of equip lines at login. |
| E3 | Settings → BiS and Gear → untick *Say in chat how it ranks*, then swap an item. | No chat line. |

## F. Tooltips

| ID | How | Expected |
|---|---|---|
| F1 | Hover one of your equipped items that is on the list. | A line like `FycoPvE BiS: Head Best #1/12 (Pre-Raid)`, then a source line such as `Drop: Boss - Dungeon (Heroic)`. |
| F2 | Hover an item that is on no list. | No FycoPvE lines. |
| F3 | Link an item from the Search tab into chat, then click the link. | The chat link's tooltip has the same FycoPvE lines. |
| F4 | Hover an item at a vendor or in the Auction House, if it's on a list. | FycoPvE lines appear there too. |
| F5 | Settings → Tooltips → *Which lists* = *Every spec and phase of my class*. Hover a listed item. | One line per spec and phase that lists it. |
| F6 | Settings → Tooltips → *Only while Shift is held*. Hover the item, then hold Shift. | No lines until Shift is held. |
| F7 | Hover the same item several times, and with a comparison tooltip open. | The FycoPvE line appears **once** per tooltip, never doubled. |

## G. Search

| ID | How | Expected |
|---|---|---|
| G1 | Search tab: type `wrist`. | Only wrist items. Items on your own list come first with a `Best`/`Good` badge. The count shows at top right. |
| G2 | Type `halls of stone`. | Items that drop in Halls of Stone. |
| G3 | Clear the box and set **Slot** to *Trinket*. | Every trinket. |
| G4 | Click any result. | The right pane shows the icon, name, item level and slot, **On your BiS lists** (if any), and **Where to get it** with every source. Vendor sources show the cost, for example `40 Emblem of Heroism`. |
| G5 | Scroll the result list with the mouse wheel. | It scrolls. |
| G6 | Tick **My class only**. | Only items on your class's lists remain. |
| G7 | Type `/fpve find emblem` in chat. | Up to 8 items with links and a first source each, and "...and N more" if there are more. |
| G8 | Type `/fpve find zzzz`. | A "nothing matches" message. |
| G9 | Pick an item and compare its source with what you know from the game. | Tell me about anything that's wrong. The data is from the stock 3.3.5 database, so Rebuffed changes will show up here. |

## H. Settings

| ID | How | Expected |
|---|---|---|
| H1 | Esc → Interface → AddOns → **FycoPvE**. | A main page plus sub-pages: *BiS and Gear*, *Tooltips*, *Search*, *Threat*, *Meter*, *Boss alerts*. |
| H2 | Open every page and scroll each one to the bottom. | **Nothing is drawn outside the settings frame**, and no text overlaps. |
| H3 | Main page: change Spec and Content phase. Open `/fpve`. | The window shows the same spec and phase. |
| H4 | Main page: untick *Minimap button*. | The button disappears. Tick it and it's back. |
| H5 | Main page: move *Window scale*. | The window resizes. |
| H6 | Main page: *Reset position*. | The window returns to the centre of the screen. |
| H7 | Change some settings, `/reload`, and look again. | Everything is still set. |

## I. Spec and phase

| ID | How | Expected |
|---|---|---|
| I1 | If you have dual spec, swap to your other spec. | Within a moment the Gear tab and badges follow the new spec (while Spec is on Auto). |
| I2 | `/fpve spec destruction`, then `/fpve spec auto`. | Chat confirms each change, and the window follows. |
| I3 | `/fpve phase P3`, then `/fpve phase`. | The first sets Phase 3. The second prints the current phase and the list of keys. |
| I4 | Log onto a second character. | Phase is the same as on the first character (it's account-wide). A spec override is per character. |

## J. Every class (0.2)

The pre-raid lists now cover every class and spec. If you have alts, log onto
as many different classes as you can. Each check takes a minute.

| ID | How | Expected |
|---|---|---|
| J1 | On each alt, read the login line. | It names the alt's real spec, e.g. `Frost Death Knight, Pre-Raid`. |
| J2 | `/fpve`, Gear tab, Phase = Pre-Raid. | Rows show ranks, not "no list for this slot", for every slot the class uses. Relic, idol, libram, totem and sigil classes get a judged **Ranged** row. |
| J3 | Druid only: open the Spec dropdown. | Balance, Feral DPS, Feral Tank and Restoration are listed. Auto picks **Feral DPS** for a feral build; choose Feral Tank by hand for bear gear. |
| J4 | Death Knight only: open the Spec dropdown. | Blood, Blood DPS, Frost and Unholy. Auto picks **Blood** (the tank list) for a blood build. Blood DPS has a Phase 4 list only. |
| J5 | Dual-wield class (Rogue, Frost DK, Enhancement Shaman, Fury Warrior): look at the Main hand and Off hand rows. | Both are judged, each against its own list. |
| J6 | Tank (Protection Warrior or Paladin): look at Off hand. | Shields are on the list. |

## K. Raid phases (0.3)

Phases 1 to 4 now have lists for every spec.

| ID | How | Expected |
|---|---|---|
| K1 | Gear tab: step Phase through Pre-Raid → Phase 1 → 2 → 3 → 4. | Each one re-ranks your gear, and none says "no list". Your pre-raid items should mostly drop to `not on the list` or low ranks by Phase 3–4. |
| K2 | Phase 1: click the upgrade on any row. | The Search pane lists a Naxxramas, Eye of Eternity, Obsidian Sanctum, Vault of Archavon, or Emblem of Valor/Heroism source. |
| K3 | Phase 3, Search: `trial of the crusader`, then click an item. | Sources show modes like `(10, 25)` or `(25 Heroic)`. |
| K4 | Phase 4, Search: `icecrown`, then `emblem of frost`. | ICC drops, and Emblem of Frost vendor items with costs. |
| K5 | Hover a tier token or tier piece in Phase 1–4. | A tooltip line appears if the guide lists it. |
| K6 | Settings → Tooltips → *Which lists* = *Every spec and phase of my class*. Hover a Phase 2 item. | A line for each phase that lists it. |

## L. Threat meter (0.4)

Best tested in a dungeon group. Solo, use test mode.

| ID | How | Expected |
|---|---|---|
| L1 | `/fpve threat test`. | A small bar list: Tankadin `[T]` 100%, you (with `>` before your name) 92%, then three more. A big red **THREAT 92%** appears mid-screen for a moment, with a raid-warning sound. `/fpve threat test` again turns it off. |
| L2 | `/fpve threat unlock`, drag the meter, `/fpve threat lock`, `/reload`. | It stays where you left it. |
| L3 | Settings → Threat → *Bars shown*, *Width*, *Scale*, with test bars on. | The meter changes as you drag the sliders. |
| L4 | In a group, attack a mob. | Everyone who has threat on it gets a bar, highest first. The tank is marked `[T]`. The bars are class-coloured. |
| L5 | In combat, target the tank (a friendly player). | The meter shows the tank's target's threat, because *Use target's target* is on. |
| L6 | Get close to pulling off the tank (warning at 90% by default). | **THREAT nn%** mid-screen, plus the sound, at most once every 3 seconds. |
| L7 | Leave combat, or clear your target. | The meter hides. |
| L8 | Settings → Threat → untick *Only in a group*, and tick *Warn when solo too*. Fight solo. | The meter shows while solo. The warning never fires while **you** are the one tanking. |
| L9 | Settings → main page → untick *Threat*. | The meter never shows. |

## M. Damage and healing meter (0.5)

| ID | How | Expected |
|---|---|---|
| M1 | `/fpve meter test`. | A meter bottom-right with 6 test players, class-coloured, each showing damage, DPS in grey and a share %. The title reads `Damage: Test Dummy (1:30)`. `/fpve meter test` again clears it. |
| M2 | Left-click the meter's title a few times. | It cycles Damage → Healing → Overhealing → Damage taken. |
| M3 | Hover a bar. | A tooltip with the total, per-second (for damage and healing), and top spells with their share. |
| M4 | `/fpve meter unlock`, drag, `/fpve meter unlock` again, `/reload`. | The meter stays where you put it. |
| M5 | Fight a mob solo. | The title shows `* <mob name>` during the fight. Your damage matches what you'd expect. About 2 seconds after combat ends, the `*` disappears. |
| M6 | With a pet class (warlock): fight with your pet. | The pet's damage is added to yours. Settings → Meter → untick *Count pets as their owner* and the pet gets its own bar. |
| M7 | Do two fights, then right-click the title repeatedly. | It cycles last fight → **Overall** → older fights, each named after the main enemy. |
| M8 | In a group, after a fight: Shift-click the title. | A report in party chat: a header and 5 lines. `/fpve meter report say` sends it to /say. |
| M9 | A healer in the group heals. | Healing shows *effective* healing, and Overhealing shows the rest. Shields (Power Word: Shield) are **not** counted; that's a limit of the 3.3.5 combat log. |
| M10 | Settings → Meter: try every slider and checkbox, plus *Reset data*. | Each takes effect immediately. |
| M11 | Scroll the mouse wheel over the meter with more players than bars. | It scrolls. |
| M12 | Queue with the dungeon finder into a dungeon, and after its last boss queue straight into the next one **without leaving** (0.12.3). | The meter works in both dungeons with no relog. If the client ever drops the combat log anyway, within a second of your next cast chat says `the combat log had stopped (a 3.3.5 client bug, usually after a teleport) - restarted it.` and the meter picks up again. |

## N. Boss alerts (0.6)

Alerts come from the combat log and timers are **learned**, so the first pull
on each boss has alerts but no timer bars.

| ID | How | Expected |
|---|---|---|
| N1 | `/fpve boss test`. | An orange **Sapphiron: Frost Breath** mid-screen with a sound, and three test timer bars near the top of the screen. `/fpve boss test` again turns the bars off. |
| N2 | `/fpve boss unlock`, drag the bars, unlock again. | They stay where you put them. |
| N3 | Fight a dungeon boss. | Each cast the boss *starts* (one with a cast bar) flashes its name mid-screen. |
| N4 | Get hit by a boss debuff. | A red **<debuff> on YOU** with an alarm sound. |
| N5 | After the boss dies or you wipe: `/fpve boss list`. | That boss is listed with the number of abilities and pulls. |
| N6 | Fight the same boss again. | Timer bars `~ Ability  12` count down to when each ability came last time. They get more accurate with each pull. |
| N7 | Trash packs. | No alerts, unless *Treat dungeon elites as bosses* is ticked in settings. |
| N8 | `/fpve boss forget <boss name>`, then `/fpve boss list`. | That boss is gone. `/fpve boss forget` alone clears all of them. |
| N9 | Settings → Boss alerts: switch off casts, "on YOU", sounds. | Each stops. |

## O. Talents and glyphs (0.7)

The window now has a **sidebar** on the left (Gear, Talents, Glyphs, Item
search…) instead of buttons along the top.

| ID | How | Expected |
|---|---|---|
| O1 | `/fpve`. | The pages are listed down the left. Everything fits and nothing overlaps; the Gear and Item search pages look as before, just shifted right. |
| O2 | Talents page. | Your three talent trees, drawn with the real icons. The tree titles read e.g. `Affliction  55 (you 55)`. Each talent the guide uses shows its points. Talents neither of you use are greyed out. |
| O3 | Compare with your own talents. | Green border: you match the guide. Yellow `1/3`: the guide wants more. Red: you have points the guide doesn't use. The summary at the top right says either "match" or how many points differ. |
| O4 | Hover any talent. | The normal talent tooltip, plus `FycoPvE guide x/y  you x/y`. |
| O5 | If the guide has more than one build, pick another in **Build**. | The trees and the text below change. |
| O6 | Read the text under the trees. | The guide's explanation of the build, with spell names in blue. It scrolls. |
| O7 | Click **Preview in talent frame**. With free talent points (for example on a fresh spec, or after a respec): | The talent frame opens with the guide's points shown as a **preview**. Chat says `placed X of Y`. **Nothing is learned** until you click Learn in the talent frame, and Reset there cancels it. |
| O8 | Click Preview when your points are already spent differently. | Chat explains how many points couldn't be placed and that your talents have points the guide doesn't use. Nothing breaks. |
| O9 | Spec dropdown → another spec. | That spec's build shows against your current talents. |
| O10 | Glyphs page. | Major and Minor glyphs, each with its icon, a **Socketed** or **Missing** tag, and why the guide picks it. Glyphs you have that the guide doesn't list appear at the bottom under "Also socketed". |
| O11 | Socket or remove a glyph (or swap spec). | The Glyphs page updates. |
| O12 | `/fpve talents`, `/fpve talents preview`, `/fpve glyphs`. | They open the pages, or run the preview. |
| O13 | On a Protection Warrior, if you have one: Talents page. | Painkiller, Unbroken Rage, Blood and Thunder and the other reworked talents have an orange **!**. Their tooltips say they were changed on this realm. |

## P. Overview, the character check-up (0.8)

| ID | How | Expected |
|---|---|---|
| P1 | `/fpve`. | The window opens on **Overview**, the first page in the sidebar. |
| P2 | Read the list. | One line per issue, worst first: red **Fix** (empty slots, missing enchants, empty sockets, caps not reached), then yellow **Improve** (non-BiS gear, weaker enchants, missing glyphs, talents that differ), then grey **Info**, then green **OK**. The summary at the top counts the Fix and Improve lines. |
| P3 | Click **Open** on a few lines. | Each one jumps to the page that fixes it (Gear, Gems & Enchants, Glyphs, Talents, Stats & caps, Professions). |
| P4 | Fix something (enchant an item, socket a glyph) and come back. | That line turns to OK or disappears. |
| P5 | Change Spec or Phase at the top. | The whole list is recomputed. |
| P6 | `/fpve overview`. | Opens this page. |

## Q. Gems & Enchants (0.8)

| ID | How | Expected |
|---|---|---|
| Q1 | Gems & Enchants page. | A row per enchantable slot you wear: **Guide's best for you**, **On your gear** (the real enchant name) and a status: green **Best**, yellow **Listed, not the best**, orange **Not in the guide**, red **Missing**. |
| Q2 | Look at Back, Wrist, Shoulder. | If you **don't** have Tailoring, Leatherworking or Inscription, it recommends the scroll or reputation enchant, **not** Lightweave, Fur Lining or the Inscription shoulders. If you have the profession, the profession enchant is the best. |
| Q3 | Rings. | Only listed if you're an Enchanter. |
| Q4 | Hover a row. | Every option the guide lists for that slot, best first, with profession and phase tags, and the guide's explanation. |
| Q5 | Gems section. | The guide's gem picks per colour (for warlocks: meta, red, yellow, blue), with phase tags like `P1-2` and `P3`. |
| Q6 | Sockets section. | "Every socket on your gear has a gem", or a red line per item with empty sockets. |
| Q7 | Enchant or gem something while the page is open. | It updates. |
| Q8 | Hover the small **icon** next to an enchant (0.12.2). | The game's own tooltip for that scroll or enchant, showing its real stats (e.g. `+63 Spell Power`), then where to get it: e.g. `Vendor: … - Requires Kirin Tor - Revered` for an arcanum, `Crafted: Enchanting - from a player with it, or the Auction House` for a scroll, `Profession perk: Tailoring` for Lightweave. |
| Q9 | Under each enchant row. | A grey line with the short version of where to get it. |
| Q10 | Gems: hover each of the up-to-3 gem icons in a row. | Each gem's real stats and its source, e.g. Runed Dragon's Eye: `Crafted: Jewelcrafting - bind on pickup: only someone with Jewelcrafting can use it`. Shift-click links it into chat. |
| Q11 | Hover a crafted BiS item in the Gear tab or Search (e.g. Visage Liquification Goggles). | Its source now reads `Crafted: Engineering`, instead of only the guide's note. |

## R. Stats & caps (0.9)

| ID | How | Expected |
|---|---|---|
| R1 | Stats & caps page, as Affliction. | Left: the guide's stat priority (Hit Rating, Spell Power, Haste…). Right: a **Spell hit** bar `x.xx% / 17%`, with a line saying what it's made of (rating, talents and racials, raid buffs) and how much more rating you need. |
| R2 | Check the numbers against your character sheet's spell hit. | The "from hit rating" % matches the game's. Suppression (3/3) counts as 3%. |
| R3 | Tick **+3% spell hit from a Balance Druid or Shadow Priest**. | The bar grows by 3%. Once at 17%, it turns green and says **Capped**, and "Hit Rating" in the priority list gets a `capped` tag. |
| R4 | On a melee alt, or pick a melee spec. | Melee hit 8% and Expertise 26. |
| R5 | On a tank alt. | Defense 540 as well. Healers see "no hard caps". |
| R6 | Swap a piece of gear with hit on it. | The bar updates. |

## S. Rotation helper, Affliction (0.10)

| ID | How | Expected |
|---|---|---|
| S1 | As Affliction, target a training dummy or mob and start combat. | A panel appears (centre, a bit below the middle): one **big icon** (cast this now) and **two smaller icons** after it. |
| S2 | Fresh target, nothing on it. | The big icon goes Haunt → Unstable Affliction → Corruption → Curse of Agony as you cast each. |
| S3 | Everything up and Haunt on cooldown. | Big icon **Shadow Bolt**. A small **Haunt** icon, greyed, counting down (`2.3`, `2.2`…). When it reaches zero, Haunt becomes the big icon. |
| S4 | Let Unstable Affliction run low. | It becomes the big icon just before it falls off, early enough to cast it in time. While you're casting it, it isn't suggested again. |
| S5 | Corruption. | Never suggested again while it's up, because Haunt and Shadow Bolt refresh it through Everlasting Affliction. |
| S6 | Put Curse of the Elements on instead. | Curse of Agony isn't suggested, since your own curse choice is respected. |
| S7 | Target below 25% health. | **Drain Soul** replaces Shadow Bolt as the filler. |
| S8 | With Glyph of Life Tap socketed. | **Life Tap** comes up when the glyph's buff is missing or about to expire (about 3s left). Without the glyph it's never suggested. |
| S9 | Improved Shadow Bolt talented, no Shadow Mastery on the boss. | **Shadow Bolt** is suggested early to put the debuff up. |
| S10 | Clear your target, or leave combat. | The panel hides. Settings → Rotation helper → *Show out of combat too* keeps it shown with a hostile target. |
| S11 | `/fpve rotation unlock`, drag it, `/fpve rotation unlock` again, `/reload`. | It stays where you left it. |
| S12 | Settings → Rotation helper: *Upcoming spells* 0/1/2, *Spell names*, *Scale*. | Each takes effect. |
| S13 | Switch to a spec without a helper (e.g. Destruction). | The panel never shows. The **Rotation** page says the helper doesn't cover that spec yet. |
| S14 | Rotation page. | The guide's spell priority for your spec (spell names in blue with short notes) and the opener. |
| S15 | **Most important:** follow it for a whole boss fight. | Tell me every time it suggested something you think was wrong, and what it should have been. |

## T. Professions (0.11)

| ID | How | Expected |
|---|---|---|
| T1 | Professions page. | **Your professions**, each with its place for your role (e.g. `Tailoring (450) - number 1 of 11 for a caster`) and what it's worth. |
| T2 | Below that. | All 11 professions ranked for your role, each with its bonus, and `you have it` next to yours. |
| T3 | Switch to a melee or tank spec. | The ranking and the bonuses change (e.g. Jewelcrafting first for tanks). |

## U. Server data and custom gear (0.12)

This section is also the **collection run** for the Frostmourne Rebuffed
pack: after U1–U5, tell me, and I build the pack from what was recorded.

| ID | How | Expected |
|---|---|---|
| U1 | Talk to the **Valor Points vendor**. | Chat: `recorded N items from <vendor name>`. If it adds "still loading", wait a few seconds; they're picked up without reopening. |
| U2 | Do the same for any other custom vendor you know of. | One chat line per vendor. |
| U3 | On your warlock: `/fpve scan bis all`. | `recording this server's stats for ~600 BiS items (about 120 seconds)...`, then after about 2 minutes `BiS scan done: X of Y items recorded`. Keep playing normally meanwhile. |
| U4 | `/fpve scan`. | Lists the vendors and item counts recorded. |
| U5 | `/reload` (this writes the data to disk), then tell me. | — (I then build the pack.) |
| U6 | Settings → **Server data**. | The *Server packs* dropdown (Auto / Always on / Off), the pack status, *Record every vendor I open*, and the scan buttons. |
| U7 | Gear tab as Affliction, Pre-Raid (the pack is built from your scan). | **Wrist:** Wraps of the Astral Traveler is #1 BiS. **Ring:** Band of Channeled Magic is #1 BiS. **Back:** Disguise of the Kumiho ranks Good. **Feet:** Xintor's Expeditionary Boots and Slippers of the Holy Light rank Good or Mediocre. Search one of them: it says **Custom Frostmourne Rebuffed item**, sold by Magister Brasael for **1250 (or 1650) Valor**. |
| U8 | *After the pack:* Settings → Server data → *Off*. | The custom items vanish and the lists are exactly Wowhead's again. *Auto* brings them back (because you're on Frostmourne). |

---

## Automated tests

`python tests/run_tests.py` (needs `pip install lupa`) loads the real addon in
Lua 5.1 against a mock 3.3.5a client and checks the logic. It runs every time
something changes; the latest result is recorded in the milestone log below.
It cannot check how anything looks, where frames sit, or that the real client
behaves like the mock. That is what the sections above are for.

## Milestone log

| Version | What it adds | Automated tests | In-game sections (all passed 2026-09-25) |
|---|---|---|---|
| 0.1 | Core, window, Gear, tooltips, Search, settings; Warlock Affliction and Destruction pre-raid | — | A–I |
| 0.2 | Pre-raid lists for every class and spec | | J |
| 0.3 | Phase 1–4 lists for every spec; tier tokens resolved to the pieces you wear | | K |
| 0.4 | Threat meter and pull warning | | L |
| **0.4.0 build** | everything above | **25 / 25 pass** (2026-09-25) | A–L |
| 0.5 | Damage and healing meter | | M |
| 0.6 | Boss alerts: cast alerts, "on YOU" debuffs, learned timers | | N |
| **0.6.0 build** | everything above | **31 / 31 pass** (2026-09-25) | **A–N passed** |
| 0.7 | Sidebar window, Talents page with talent-frame preview, Glyphs page, Rebuffed change detection | **35 / 35 pass** (2026-09-26) | O (and O1 re-checks B, C, G) |

| 0.8 | Overview check-up; Gems & Enchants page | | P, Q |
| 0.9 | Stats & caps page | | R |
| 0.10 | Rotation helper (Affliction) and Rotation page | | S |
| 0.11 | Professions page | | T |
| **0.11.0 build** | everything above | **40 / 40 pass** (2026-09-26) | O–T |
| 0.12 | Vendor and BiS scanner; server packs with an Auto/On/Off switch | **44 / 44 pass** (2026-09-26) | U |
| 0.12.1 | The Frostmourne Rebuffed pack, built from your scan | **45 / 45 pass** (2026-09-26) | U7, U8 |
| 0.12.2 | Gems & Enchants: hoverable icons with real stats and where to get each; crafted sources for every item | **46 / 46 pass** (2026-09-26) | Q8–Q11 |
| 0.12.3 | Fix: meter (and boss alerts) dead after a dungeon-finder teleport until relog -- combat log watchdog | **47 / 47 pass** (2026-09-26) | M12 |

**What the scan showed (0.12.1).** The two vendors (Magister Brasael, Magistrix Lambriesse) sell **standard** WotLK emblem gear, with stats unchanged from the normal game. What's custom is the **currency**: "Valor" is the old Emblem of Valor and "Justice" is the old Emblem of Heroism, with prices in the thousands. The Valor items are item level 213 and count as **Phase 1** gear on Wowhead, so they never appear on its pre-raid lists; on this server you can buy them before raiding. The pack adds the five that beat pre-raid picks for Affliction and Destruction. **14 healer items were left out** (mana per 5, or healing procs such as The Egg of Mortal Essence and Soul Preserver) because their stats score well but their effects do nothing for a warlock.

Added for 0.12: a vendor's items are recorded with stats and a Valor cost, and items the server hadn't sent yet are picked up a moment later; the BiS scan records guide items' stats; a pack switches on for its realm in Auto, off elsewhere, and on/off by hand, and Off restores the guide's lists exactly; a custom item shows its Valor cost and becomes the upgrade over a non-listed helm; the merge rule places items by score and takes the tier of the item they displace, skips items that beat nothing, counts gem sockets, and refuses plate for a warlock. A dry run on a synthetic scan placed a cloth Valor hood #1 on the Affliction pre-raid head list, above the Goggles.

Added for 0.8–0.11:
- **Rotation:** Haunt comes first on a fresh target; with every DoT up and Haunt on a 2.3s cooldown it says Shadow Bolt now, **Haunt in 2.3**; Unstable Affliction is refreshed when it has less than its cast time left, but not while you're already casting it; Drain Soul below 25%; Curse of Agony is skipped when another curse of yours is up; Corruption is never refreshed; Life Tap appears only with its glyph. The panel shows in combat with a hostile target and hides otherwise.
- **Enchants:** exact enchant IDs are compared (best, missing, other); a non-tailor is not told to use Lightweave, but a tailor is; rings only count for enchanters; empty sockets are counted per item.
- **Caps:** 12% from rating + 3% Suppression = 15% spell hit, **53 rating short**; the +3% buff tick caps it; melee specs get hit and expertise; a tank at 530 defense is 50 rating short.
- **Overview:** issues sorted worst first. Every guide page opens without error for six different classes.

Added for 0.7: the Affliction build is recognised as a match and a moved point is counted as 1 missing and 1 extra; the preview places all 71 points into the *preview* without learning any, and reports when points are short; the Glyphs page marks Socketed and Missing and lists extra glyphs; all **73 builds of all 30 specs** land on real talents of this realm's trees, within rank limits and 71 points.

**What Rebuffed changes, from its own client files:** 3 new Protection Warrior talents, and about 144 changed spells, mostly Protection Warrior talents, rogue poison durations, Windfury and Tricks of the Trade. **No warlock spells or talents differ from the standard game.** Protection Warrior builds put a few points in two stock talents this realm removed; those points are skipped.

Added for 0.5 and 0.6: the meter counts damage, effective healing, overhealing and damage taken correctly, with pets merged or kept apart; ignores players outside the group; splits fights, keeps Overall and history, and resets; reports to chat with no `|` characters (the server rejects them). Boss alerts: an encounter starts only on a real boss; cast and "on YOU" alerts fire and clear; buffs and trash never alert; timers are learned on the first pull (first cast about 10s, interval about 20s in the test) and count down on the second; the commands work.

What the automated suite checked for 0.4.0, so you don't have to:

- every file in the `.toc` exists and loads; login works for all 10 classes, with 4 talent layouts each
- spec detection, override, relog, and the dual-spec swap; phase via command and dropdown
- BiS vs. not-listed, the "counts as BiS" setting, rings never suggesting the same item twice, two-handers retiring the off hand, faction filtering
- equip reports, including the quiet period after login; tooltip lines appear once and respect Shift-only
- search by slot, zone, empty and nonsense input, `/fpve find`; the Search tab and jumping to an item
- window, minimap button, character-sheet badges on and off, every settings page building and refreshing
- the threat meter's order, hiding (no target, combat-only, module off), pull warning (threshold, never for the tank, solo off by default), test mode and commands
- data: every spec has every phase with all 12 armour slots filled; every listed item fits its slot; every source formats without error (9 of 3,687 items have no known source)

**Known data limits.** These come from the sources, not bugs to report:

- When a caster or healer guide lists only a tier *token*, both of that class's spell sets are kept for the slot (e.g. Balance and Restoration pieces), because the database can't tell them apart. Where the guide names the exact piece, only that piece is listed.
- 3 items the Destruction guide lists under Back (necklaces) are dropped.
- About 175 crafted or PvP items have no database source. Their tooltip and Search entry show the guide's own note instead ("Tailoring", "Arena Season 7"…).
