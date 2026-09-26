--[[ FycoPvE - Modules/Professions.lua
     Which professions help your spec most, and why -- with what each one
     is actually worth at 450 skill. Values are approximate (they depend on
     gem quality and uptime), and the gap between the top few is small, so
     the page says so instead of pretending to precision.              ]]

local ADDON, ns = ...
local M = ns:Module("professions", 55)
local UI = ns.UI

-- what each profession gives a character of each role at 450 skill
local BONUS = {
	Tailoring = {
		caster = "Lightweave Embroidery on the cloak: 295 spell power for 15s (about +70 on average)",
		healer = "Lightweave Embroidery on the cloak: 295 spell power for 15s (about +70 on average)",
		melee = "Swordguard Embroidery on the cloak: 400 attack power for 15s (about +60 average)",
		ranged = "Swordguard Embroidery on the cloak: 400 attack power for 15s (about +60 average)",
		tank = "Darkglow/Swordguard cloak embroidery - little for tanks",
	},
	Engineering = {
		all = "Hyperspeed Accelerators on the gloves: 340 haste for 12s every minute (about +70 haste), plus "
			.. "the cloak parachute enchant, explosives and a belt rocket",
		tank = "Hyperspeed Accelerators and Nitro Boots; the armor/agility options are weak for tanks",
	},
	Jewelcrafting = {
		caster = "Three Dragon's Eye gems: about +48 spell power over normal gems",
		healer = "Three Dragon's Eye gems: about +48 spell power over normal gems",
		melee = "Three Dragon's Eye gems: about +42 strength or agility over normal gems",
		ranged = "Three Dragon's Eye gems: about +42 agility over normal gems",
		tank = "Three Dragon's Eye gems: about +63 stamina over normal gems",
	},
	Enchanting = {
		caster = "Enchant both rings: +46 spell power", healer = "Enchant both rings: +46 spell power",
		melee = "Enchant both rings: +80 attack power", ranged = "Enchant both rings: +80 attack power",
		tank = "Enchant both rings: +60 stamina",
	},
	Blacksmithing = {
		caster = "An extra gem socket on the bracers and gloves: about +46 spell power",
		healer = "An extra gem socket on the bracers and gloves: about +46 spell power",
		melee = "An extra gem socket on the bracers and gloves: about +40 strength or agility",
		ranged = "An extra gem socket on the bracers and gloves: about +40 agility",
		tank = "An extra gem socket on the bracers and gloves: about +60 stamina",
	},
	Leatherworking = {
		caster = "Fur Lining on the bracers: +76 spell power", healer = "Fur Lining on the bracers: +76 spell power",
		melee = "Fur Lining on the bracers: +130 attack power", ranged = "Fur Lining on the bracers: +130 attack power",
		tank = "Fur Lining on the bracers: +102 stamina",
	},
	Inscription = {
		caster = "Master's Inscription on the shoulders: about +46 spell power over the reputation enchant",
		healer = "Master's Inscription on the shoulders: about +46 spell power over the reputation enchant",
		melee = "Master's Inscription on the shoulders: about +80 attack power over the reputation enchant",
		ranged = "Master's Inscription on the shoulders: about +80 attack power over the reputation enchant",
		tank = "Master's Inscription on the shoulders: extra dodge and stamina over the reputation enchant",
	},
	Alchemy = {
		all = "Mixology: stronger, longer flasks and elixirs (about +47 spell power or +80 attack power from "
			.. "a flask), and the Alchemist's Stone bonus to potions",
	},
	Skinning = { all = "Master of Anatomy: +40 critical strike rating" },
	Mining = { all = "Toughness: +60 stamina" },
	Herbalism = { all = "Lifeblood: a self-heal every 3 minutes - little value in a raid" },
}

-- best first, per role. The top three or four are within about 1% of each other.
local ORDER = {
	caster = { "Tailoring", "Engineering", "Jewelcrafting", "Enchanting", "Blacksmithing", "Leatherworking",
		"Inscription", "Alchemy", "Skinning", "Mining", "Herbalism" },
	healer = { "Tailoring", "Jewelcrafting", "Enchanting", "Blacksmithing", "Leatherworking", "Engineering",
		"Inscription", "Alchemy", "Herbalism", "Skinning", "Mining" },
	melee = { "Engineering", "Jewelcrafting", "Blacksmithing", "Enchanting", "Leatherworking", "Inscription",
		"Alchemy", "Skinning", "Tailoring", "Mining", "Herbalism" },
	ranged = { "Engineering", "Jewelcrafting", "Leatherworking", "Blacksmithing", "Enchanting", "Inscription",
		"Alchemy", "Skinning", "Tailoring", "Mining", "Herbalism" },
	tank = { "Jewelcrafting", "Blacksmithing", "Enchanting", "Leatherworking", "Mining", "Alchemy",
		"Inscription", "Engineering", "Skinning", "Tailoring", "Herbalism" },
}

local function Role()
	local g = ns:SpecGuide()
	return g and g.role or "caster"
end

local function Bonus(prof, role)
	local b = BONUS[prof]
	return b and (b[role] or b.all) or ""
end

--- Your professions with their place in your role's ranking, and the top two.
function ns:ProfessionAdvice()
	local role = Role()
	local order = ORDER[role] or ORDER.caster
	local mine = ns:PlayerProfessions()
	local have = {}
	for i, p in ipairs(order) do
		if mine[p] then have[#have + 1] = { name = p, rank = i, skill = mine[p] } end
	end
	return have, { order[1], order[2] }, role
end

----------------------------------------------------------------------
-- the page
----------------------------------------------------------------------

local pane

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	local have, top, role = ns:ProfessionAdvice()
	local order = ORDER[role] or ORDER.caster
	local mine = ns:PlayerProfessions()
	local lines = {}

	lines[#lines + 1] = "|cffffd200Your professions|r"
	if #have == 0 then
		lines[#lines + 1] = "|cff808080You have no primary professions yet.|r"
	end
	for _, h in ipairs(have) do
		lines[#lines + 1] = string.format("  %s |cff808080(%d)|r - number %d of %d for a %s. %s", h.name, h.skill,
			h.rank, #order, role, Bonus(h.name, role))
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cffffd200Best for a " .. role .. ", in order|r"
	for i, p in ipairs(order) do
		local tick = mine[p] and "  |cff40ff40you have it|r" or ""
		lines[#lines + 1] = string.format("%2d.  %s%s\n       |cffc0c0c0%s|r", i, p, tick, Bonus(p, role))
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cff808080The top three or four are within about 1% of each other: pick the two you "
		.. "enjoy among them. Gathering professions (Mining, Herbalism, Skinning) are best while levelling "
		.. "or to fund the others. Values are approximate, at 450 skill.|r"
	pane.text:SetText(table.concat(lines, "\n"))
	pane.child:SetHeight(math.ceil(pane.text:GetStringHeight() or 100) + 10)
end

local function BuildPane(p)
	pane = p
	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvEProfSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)
	local scroll = CreateFrame("ScrollFrame", "FycoPvEProfScroll", p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -48)
	scroll:SetPoint("BOTTOMRIGHT", -26, 2)
	p.child = CreateFrame("Frame", nil, scroll)
	p.child:SetWidth(600)
	p.child:SetHeight(100)
	scroll:SetScrollChild(p.child)
	p.text = p.child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.text:SetPoint("TOPLEFT", 0, 0)
	p.text:SetWidth(600)
	p.text:SetJustifyH("LEFT")
	p.text:SetSpacing(3)
end

ns:AddTab("professions", "Professions", 60, BuildPane, Refresh)

function M:OnLoad()
	ns:On("SKILL_LINES_CHANGED", Refresh)
	ns:Subscribe("ProfileChanged", Refresh)
end
