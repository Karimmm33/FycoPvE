--[[ FycoPvE - Data/Constants.lua
     Fixed game facts every module shares: classes and their specs, content
     phases, equipment slots and how BiS lists map onto them. Hand-maintained,
     unlike Items.lua and BiS/*.lua, which are generated.                     ]]

local _, ns = ...

-- Specs in talent-tab order. `tab` is what the detector compares against, so
-- two specs may share a tab when a guide splits one tree into two roles (a
-- feral druid tank and a feral druid cat both spend in tab 2). The first spec
-- listed for a tab is the one auto-detection picks.
ns.Classes = {
	WARRIOR     = { name = "Warrior",      specs = { { "Arms", 1 }, { "Fury", 2 }, { "Protection", 3 } } },
	PALADIN     = { name = "Paladin",      specs = { { "Holy", 1 }, { "Protection", 2 }, { "Retribution", 3 } } },
	HUNTER      = { name = "Hunter",       specs = { { "Beast Mastery", 1 }, { "Marksmanship", 2 }, { "Survival", 3 } } },
	ROGUE       = { name = "Rogue",        specs = { { "Assassination", 1 }, { "Combat", 2 }, { "Subtlety", 3 } } },
	PRIEST      = { name = "Priest",       specs = { { "Discipline", 1 }, { "Holy", 2 }, { "Shadow", 3 } } },
	DEATHKNIGHT = { name = "Death Knight", specs = { { "Blood", 1 }, { "Frost", 2 }, { "Unholy", 3 } } },
	SHAMAN      = { name = "Shaman",       specs = { { "Elemental", 1 }, { "Enhancement", 2 }, { "Restoration", 3 } } },
	MAGE        = { name = "Mage",         specs = { { "Arcane", 1 }, { "Fire", 2 }, { "Frost", 3 } } },
	WARLOCK     = { name = "Warlock",      specs = { { "Affliction", 1 }, { "Demonology", 2 }, { "Destruction", 3 } } },
	DRUID       = { name = "Druid",        specs = { { "Balance", 1 }, { "Feral", 2 }, { "Restoration", 3 } } },
}

-- Content phases, oldest first. The game cannot tell us which one a server is
-- on, so the player picks it; the key is what data files register under.
ns.Phases = {
	{ key = "PreRaid", name = "Pre-Raid" },
	{ key = "P1",      name = "Phase 1 - Naxxramas, Eye of Eternity, Obsidian Sanctum" },
	{ key = "P2",      name = "Phase 2 - Ulduar" },
	{ key = "P3",      name = "Phase 3 - Trial of the Crusader" },
	{ key = "P4",      name = "Phase 4 - Icecrown Citadel, Ruby Sanctum" },
}

ns.PhaseName = {}
for i = 1, #ns.Phases do ns.PhaseName[ns.Phases[i].key] = ns.Phases[i].name end

-- How far down a guide's ranking an item sits. Guides call the tiers by
-- these names; the numbers are what the data files store.
ns.Tiers = {
	{ name = "Best",     color = "40ff40" },
	{ name = "Great",    color = "a0ff40" },
	{ name = "Good",     color = "ffd200" },
	{ name = "Mediocre", color = "ff9020" },
}

-- One row per equipment slot on the Gear tab, in character-sheet order.
-- `list` names the BiS list the slot is judged against; paired slots (rings,
-- trinkets) share one list. Weapon and OffHand are resolved at run time,
-- because a two-hander changes which lists apply.
ns.GearRows = {
	{ inv = 1,  label = "Head",      list = "Head",     button = "CharacterHeadSlot" },
	{ inv = 2,  label = "Neck",      list = "Neck",     button = "CharacterNeckSlot" },
	{ inv = 3,  label = "Shoulder",  list = "Shoulder", button = "CharacterShoulderSlot" },
	{ inv = 15, label = "Back",      list = "Back",     button = "CharacterBackSlot" },
	{ inv = 5,  label = "Chest",     list = "Chest",    button = "CharacterChestSlot" },
	{ inv = 9,  label = "Wrist",     list = "Wrist",    button = "CharacterWristSlot" },
	{ inv = 10, label = "Hands",     list = "Hands",    button = "CharacterHandsSlot" },
	{ inv = 6,  label = "Waist",     list = "Waist",    button = "CharacterWaistSlot" },
	{ inv = 7,  label = "Legs",      list = "Legs",     button = "CharacterLegsSlot" },
	{ inv = 8,  label = "Feet",      list = "Feet",     button = "CharacterFeetSlot" },
	{ inv = 11, label = "Ring 1",    list = "Ring",     button = "CharacterFinger0Slot",  pair = 12 },
	{ inv = 12, label = "Ring 2",    list = "Ring",     button = "CharacterFinger1Slot",  pair = 11 },
	{ inv = 13, label = "Trinket 1", list = "Trinket",  button = "CharacterTrinket0Slot", pair = 14 },
	{ inv = 14, label = "Trinket 2", list = "Trinket",  button = "CharacterTrinket1Slot", pair = 13 },
	{ inv = 16, label = "Main hand", list = "Weapon",   button = "CharacterMainHandSlot" },
	{ inv = 17, label = "Off hand",  list = "OffHand",  button = "CharacterSecondaryHandSlot" },
	{ inv = 18, label = "Ranged",    list = "Ranged",   button = "CharacterRangedSlot" },
}

-- Human names for BiS list keys, used by tooltips and search results.
ns.ListName = {
	Head = "Head", Neck = "Neck", Shoulder = "Shoulder", Back = "Back", Chest = "Chest",
	Wrist = "Wrist", Hands = "Hands", Waist = "Waist", Legs = "Legs", Feet = "Feet",
	Ring = "Ring", Trinket = "Trinket", TwoHand = "Two-hand", MainHand = "One-hand",
	OffHand = "Off hand", Ranged = "Ranged",
}

-- Inventory type (item_template.InventoryType) -> display name, plus the
-- words search matches against, so typing "bracers" finds wrist items.
ns.InvTypes = {
	[1]  = { "Head",      "head helm helmet hat hood cowl circlet crown mask goggles" },
	[2]  = { "Neck",      "neck necklace amulet pendant choker chain" },
	[3]  = { "Shoulder",  "shoulder shoulders mantle pauldrons spaulders amice shawl" },
	[5]  = { "Chest",     "chest robe tunic vest breastplate" },
	[6]  = { "Waist",     "waist belt cord sash girdle" },
	[7]  = { "Legs",      "legs leggings pants trousers" },
	[8]  = { "Feet",      "feet boots shoes slippers sandals treads" },
	[9]  = { "Wrist",     "wrist wrists bracer bracers bindings cuffs wristwraps" },
	[10] = { "Hands",     "hands gloves gauntlets handwraps handguards" },
	[11] = { "Finger",    "ring rings finger band loop signet" },
	[12] = { "Trinket",   "trinket trinkets" },
	[13] = { "One-hand",  "one-hand 1h weapon dagger sword mace" },
	[14] = { "Shield",    "shield off-hand offhand" },
	[15] = { "Ranged",    "ranged bow" },
	[16] = { "Back",      "back cloak cape drape shroud" },
	[17] = { "Two-hand",  "two-hand 2h weapon staff stave" },
	[20] = { "Chest",     "chest robe" },
	[21] = { "Main hand", "main-hand mainhand weapon dagger sword mace" },
	[22] = { "Off hand",  "off-hand offhand weapon" },
	[23] = { "Held in off-hand", "off-hand offhand held tome orb book" },
	[25] = { "Thrown",    "thrown ranged" },
	[26] = { "Ranged",    "ranged wand gun crossbow" },
	[28] = { "Relic",     "relic idol totem libram sigil" },
}
