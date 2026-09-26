--[[ FycoPvE - Modules/Stats.lua
     Stats & caps: the guide's stat priority for your spec, and how far you
     are from every cap that matters for your role, read live from the game.

       Spell hit 17%  (casters)       446 rating at level 80
       Melee/ranged hit 8% (physical) 263 rating
       Expertise 26  (melee, tanks)   214 rating
       Defense 540   (tanks)          689 defense rating over the base 400

     Hit from talents and racials counts toward the cap. The game reports
     some of it (GetSpellHitModifier / GetHitModifier); talents it may not
     (e.g. Suppression, which only helps Affliction spells) are read from
     your talent tree by name. Raid buffs from other players are yours to
     tick, because the addon cannot know who you will raid with.         ]]

local ADDON, ns = ...
local M = ns:Module("stats", 28)
local UI = ns.UI

-- level 80 conversions
local SPELL_HIT_PER_PCT, MELEE_HIT_PER_PCT = 26.232, 32.79
local EXPERTISE_PER_POINT, DEFENSE_PER_POINT = 8.1974, 4.9184
local CR_DEFENSE, CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL, CR_EXPERTISE = 2, 6, 7, 8, 24

-- hit talents by name: % per rank, and which kind of hit they add
local HIT_TALENTS = {
	WARLOCK = { { "Suppression", 1, "spell" } },
	PRIEST = { { "Shadow Focus", 1, "spell" } },
	MAGE = { { "Precision", 1, "spell" } },
	DRUID = { { "Balance of Power", 2, "spell" } },
	SHAMAN = { { "Elemental Precision", 1, "spell" }, { "Dual Wield Specialization", 2, "melee" } },
	DEATHKNIGHT = { { "Nerves of Cold Steel", 1, "melee" }, { "Virulence", 1, "spell" } },
	ROGUE = { { "Precision", 1, "melee" } },
	WARRIOR = { { "Precision", 1, "melee" } },
	HUNTER = { { "Focused Aim", 1, "melee" } },
	PALADIN = {},
}

local function TalentHit(kind)
	local total = 0
	for _, t in ipairs(HIT_TALENTS[ns:PlayerClass()] or {}) do
		if t[3] == kind then
			for tab = 1, (GetNumTalentTabs() or 0) do
				for i = 1, (GetNumTalents(tab) or 0) do
					local name, _, _, _, rank = GetTalentInfo(tab, i)
					if name == t[1] and rank and rank > 0 then total = total + rank * t[2] end
				end
			end
		end
	end
	return total
end

local function Opt(key) return ns:Get("stats", key) end

--- Every cap for the current spec's role:
--- { { key, label, have, cap, unit, missingRating, parts = {text...} }, ... }
function ns:StatCaps()
	local guide = ns:SpecGuide()
	local role = guide and guide.role or "caster"
	local caps = {}

	local function Hit(kind, cr, perPct, cap, label)
		local fromRating = GetCombatRatingBonus(cr) or 0
		local api = (kind == "spell" and GetSpellHitModifier and GetSpellHitModifier())
			or (kind ~= "spell" and GetHitModifier and GetHitModifier()) or 0
		local talents = TalentHit(kind == "spell" and "spell" or "melee")
		-- the larger of what the game reports and what the talents add, so
		-- nothing counts twice
		local bonus = math.max(api, talents)
		local buffs = 0
		if kind == "spell" and Opt("buffSpellHit") then buffs = buffs + 3 end
		if Opt("buffPresence") then buffs = buffs + 1 end
		local have = fromRating + bonus + buffs
		caps[#caps + 1] = {
			key = kind .. "hit", label = label, have = have, cap = cap, unit = "%",
			missingRating = math.max(0, math.ceil((cap - have) * perPct)),
			parts = {
				string.format("%.2f%% from %d hit rating", fromRating, GetCombatRating(cr) or 0),
				string.format("%.0f%% from talents and racials", bonus),
				buffs > 0 and string.format("%.0f%% from raid buffs you ticked", buffs) or nil,
			},
		}
	end

	if role == "caster" then
		Hit("spell", CR_HIT_SPELL, SPELL_HIT_PER_PCT, 17, "Spell hit (raid bosses)")
	elseif role == "ranged" then
		Hit("ranged", CR_HIT_RANGED, MELEE_HIT_PER_PCT, 8, "Ranged hit (raid bosses)")
	elseif role == "melee" or role == "tank" then
		Hit("melee", CR_HIT_MELEE, MELEE_HIT_PER_PCT, 8, "Melee hit (raid bosses)")
		local exp = (GetExpertise and GetExpertise()) or 0
		caps[#caps + 1] = {
			key = "expertise", label = "Expertise (no dodges)", have = exp, cap = 26, unit = "",
			missingRating = math.max(0, math.ceil((26 - exp) * EXPERTISE_PER_POINT)),
			parts = { string.format("%d expertise rating", GetCombatRating(CR_EXPERTISE) or 0) },
		}
	end
	if role == "tank" then
		local base, mod = UnitDefense("player")
		local def = (base or 0) + (mod or 0)
		caps[#caps + 1] = {
			key = "defense", label = "Defense (crit immune)", have = def, cap = 540, unit = "",
			missingRating = math.max(0, math.ceil((540 - def) * DEFENSE_PER_POINT)),
			parts = { string.format("%d defense rating", GetCombatRating(CR_DEFENSE) or 0) },
		}
	end
	return caps, role
end

--- Caps not reached, for the Overview.
function ns:AuditCaps()
	local out = {}
	for _, c in ipairs((ns:StatCaps())) do
		if c.have < c.cap then out[#out + 1] = c end
	end
	return out
end

----------------------------------------------------------------------
-- the page
----------------------------------------------------------------------

local pane

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	for _, w in ipairs(pane.widgets) do if w.Refresh then w.Refresh() end end
	local caps, role = ns:StatCaps()
	local guide = ns:SpecGuide()

	local capped = {}
	for i, b in ipairs(pane.bars) do
		local c = caps[i]
		if c then
			local done = c.have >= c.cap
			if done then capped[c.key] = true end
			b:SetMinMaxValues(0, c.cap)
			b:SetValue(math.min(c.have, c.cap))
			b:SetStatusBarColor(done and 0.2 or 1, done and 0.8 or 0.7, done and 0.2 or 0.1)
			b.label:SetText(c.label)
			b.value:SetText(string.format(c.unit == "%" and "%.2f%% / %d%%" or "%d / %d", c.have, c.cap))
			local detail = table.concat(c.parts, ", ")
			b.detail:SetText(done and ("|cff40ff40Capped.|r " .. detail)
				or string.format("|cffffd200%d more rating needed.|r %s", c.missingRating, detail))
			b:Show()
		else
			b:Hide()
		end
	end
	if #caps == 0 then
		pane.nocaps:SetText("Healers have no hard caps. Follow the stat priority on the left.")
		pane.nocaps:Show()
	else
		pane.nocaps:Hide()
	end

	local lines = {}
	for i, s in ipairs(guide and guide.stats or {}) do
		local mark = ""
		local low = s:lower()
		if low:find("hit") and (capped.spellhit or capped.meleehit or capped.rangedhit) then mark = "  |cff40ff40capped|r" end
		if low:find("expertise") and capped.expertise then mark = "  |cff40ff40capped|r" end
		if low:find("defense") and capped.defense then mark = "  |cff40ff40capped|r" end
		lines[#lines + 1] = i .. ".  " .. s .. mark
	end
	pane.priority:SetText(#lines > 0 and table.concat(lines, "\n")
		or "|cff808080The guide gives no stat priority list for this spec.|r")
	pane.role:SetText("Role: " .. role)
end

local function BuildPane(p)
	pane = p
	p.widgets = {}
	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvEStatsSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)
	p.role = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	p.role:SetPoint("TOPLEFT", 190, -20)

	local h1 = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	h1:SetPoint("TOPLEFT", 4, -52)
	h1:SetText("Stat priority")
	p.priority = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.priority:SetPoint("TOPLEFT", 8, -80)
	p.priority:SetWidth(200)
	p.priority:SetJustifyH("LEFT")
	p.priority:SetSpacing(4)

	local h2 = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	h2:SetPoint("TOPLEFT", 240, -52)
	h2:SetText("Caps")
	p.nocaps = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.nocaps:SetPoint("TOPLEFT", 240, -80)
	p.nocaps:SetWidth(380)
	p.nocaps:SetJustifyH("LEFT")

	p.bars = {}
	for i = 1, 3 do
		local b = CreateFrame("StatusBar", nil, p)
		b:SetPoint("TOPLEFT", 240, -96 - (i - 1) * 62)
		b:SetWidth(380)
		b:SetHeight(18)
		b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(b)
		bg:SetTexture(1, 1, 1, 0.08)
		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b.label:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
		b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.value:SetPoint("CENTER")
		b.detail = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.detail:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -3)
		b.detail:SetWidth(380)
		b.detail:SetJustifyH("LEFT")
		b:Hide()
		p.bars[i] = b
	end

	-- raid buffs the addon cannot know about
	local function Check(y, label, key, tip)
		local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
		cb:SetWidth(22)
		cb:SetHeight(22)
		cb:SetPoint("TOPLEFT", 236, y)
		local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		fs:SetText(label)
		cb.tooltipText = tip
		cb:SetScript("OnClick", function(self) ns:Set("stats", key, self:GetChecked() and true or false) end)
		cb.Refresh = function() cb:SetChecked(Opt(key)) end
		p.widgets[#p.widgets + 1] = cb
	end
	Check(-300, "Count +3% spell hit from a Balance Druid or Shadow Priest", "buffSpellHit",
		"Improved Faerie Fire or Misery on the target")
	Check(-324, "Count +1% hit from a Draenei's Heroic Presence", "buffPresence",
		"Only if a Draenei is in your party (Alliance)")
end

ns:AddTab("stats", "Stats & caps", 40, BuildPane, Refresh)

function M:OnLoad()
	ns:On("COMBAT_RATING_UPDATE", Refresh)
	ns:On("PLAYER_EQUIPMENT_CHANGED", Refresh)
	ns:Subscribe("ProfileChanged", Refresh)
	ns:Subscribe("SettingChanged", function(section) if section == "stats" then Refresh() end end)
end
