--[[ FycoPvE - Modules/Enchants.lua
     Gems & Enchants: the guide's enchant for every slot next to the one
     actually on your gear, and the guide's gems next to your sockets.

     An equipped enchant is read from the item link ("item:ID:ENCHANT:gem1:
     gem2:gem3:..."), and the guide's options were resolved at build time to
     the same enchant IDs, so "is this the right enchant" is an exact
     comparison. Profession-only enchants (Lightweave, Fur Lining, the
     Inscription shoulders) are only expected if you have the profession.  ]]

local ADDON, ns = ...
local M = ns:Module("enchants", 27)
local UI = ns.UI

local SLOT_INV = {
	Head = { 1 }, Shoulder = { 3 }, Back = { 15 }, Chest = { 5 }, Wrist = { 9 }, Hands = { 10 },
	Waist = { 6 }, Legs = { 7 }, Feet = { 8 }, Ring = { 11, 12 }, Weapon = { 16 }, OffHand = { 17 },
	Ranged = { 18 },
}
local INV_NAME = { [1] = "Head", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist",
	[10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring 1", [12] = "Ring 2",
	[16] = "Main hand", [17] = "Off hand", [18] = "Ranged", [2] = "Neck", [13] = "Trinket 1", [14] = "Trinket 2" }
local SOCKET_KEYS = { "EMPTY_SOCKET_META", "EMPTY_SOCKET_RED", "EMPTY_SOCKET_YELLOW", "EMPTY_SOCKET_BLUE",
	"EMPTY_SOCKET_PRISMATIC" }

local function OptionName(o)
	if o.name then return o.name end
	return (GetSpellInfo(o.id)) or ("spell " .. o.id)
end

--- enchant id, gem ids and link of what is in an inventory slot.
local function Worn(inv)
	local link = GetInventoryItemLink("player", inv)
	if not link then return nil end
	local id, ench, g1, g2, g3 = link:match("item:(%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)")
	return tonumber(id), tonumber(ench) or 0, { tonumber(g1) or 0, tonumber(g2) or 0, tonumber(g3) or 0 }, link
end

--- The best option this player can actually use: profession-only ones are
--- skipped unless the profession is known.
local function BestFor(options, profs)
	for i, o in ipairs(options) do
		if not o.skill or profs[o.skill] then return o, i end
	end
	return options[#options], #options
end

--- One row per enchantable slot: { inv, slot, best, bestIndex, have (enchant id), status, text }.
--- status: "best", "option" (a listed but not the best one), "other", "missing", "unknown".
function ns:AuditEnchants(guide)
	guide = guide or ns:SpecGuide()
	local out = {}
	if not (guide and guide.enchants) then return out end
	local profs = ns:PlayerProfessions()
	for _, e in ipairs(guide.enchants) do
		for _, inv in ipairs(SLOT_INV[e.slot] or {}) do
			local id, have = Worn(inv)
			-- rings are enchanter-only, the off hand only when something is there
			local applies = id and (e.slot ~= "Ring" or profs["Enchanting"])
			if applies then
				local best, bi = BestFor(e.options, profs)
				local r = { inv = inv, slot = INV_NAME[inv] or e.slot, entry = e, best = best, have = have }
				if have == 0 then
					r.status = "missing"
				elseif best.enchant and have == best.enchant then
					r.status = "best"
				else
					r.status = "other"
					for i, o in ipairs(e.options) do
						if o.enchant == have and i ~= bi then r.status = "option" end
					end
					if not best.enchant then r.status = "unknown" end
				end
				out[#out + 1] = r
			end
		end
	end
	return out
end

--- Empty gem sockets on worn gear: { { inv, slot, empty }, ... }.
function ns:AuditSockets()
	local out = {}
	for inv = 1, 18 do
		local id, _, gems, link = Worn(inv)
		if id and GetItemStats then
			local stats = GetItemStats(link) or {}
			local sockets = 0
			for _, k in ipairs(SOCKET_KEYS) do sockets = sockets + (stats[k] or 0) end
			local filled = 0
			for _, g in ipairs(gems) do if g > 0 then filled = filled + 1 end end
			if sockets > filled then
				out[#out + 1] = { inv = inv, slot = INV_NAME[inv] or ("slot " .. inv), empty = sockets - filled }
			end
		end
	end
	return out
end

local STATUS = {
	best = "|cff40ff40Best|r",
	option = "|cffffd200Listed, not the best|r",
	other = "|cffff9020Not in the guide|r",
	missing = "|cffff4040Missing|r",
	unknown = "|cff808080Can't check|r",
}

----------------------------------------------------------------------
-- the page
----------------------------------------------------------------------

local pane
local rows = {}

local function Row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, pane.child)
	r:SetHeight(20)
	r:SetWidth(600)
	r.slot = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	r.slot:SetPoint("LEFT", 2, 0)
	r.slot:SetWidth(70)
	r.slot:SetJustifyH("LEFT")
	r.want = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.want:SetPoint("LEFT", 76, 0)
	r.want:SetWidth(250)
	r.want:SetHeight(20)
	r.want:SetJustifyH("LEFT")
	r.have = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.have:SetPoint("LEFT", 332, 0)
	r.have:SetWidth(150)
	r.have:SetHeight(20)
	r.have:SetJustifyH("LEFT")
	r.status = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.status:SetPoint("LEFT", 486, 0)
	r:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		for i, line in ipairs(self.tip) do
			if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

local function OptionsTip(entry, profs)
	local tip = { entry.slot .. " - the guide's options, best first" }
	for i, o in ipairs(entry.options) do
		local extra = ""
		if o.skill then extra = extra .. " (" .. o.skill .. (profs[o.skill] and ", you have it)" or " only)") end
		if o.tag then extra = extra .. " [" .. o.tag .. "]" end
		tip[#tip + 1] = i .. ". " .. OptionName(o) .. extra
	end
	if entry.note and entry.note ~= "" then tip[#tip + 1] = " "; tip[#tip + 1] = ns:GuideText(entry.note) end
	return tip
end

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	for _, r in ipairs(rows) do r:Hide() end
	local guide = ns:SpecGuide()
	if not guide then
		pane.empty:SetText("There is no enchant and gem guide for this spec yet.")
		pane.empty:Show()
		return
	end
	pane.empty:Hide()
	local profs = ns:PlayerProfessions()
	local n, y = 0, -2

	local function Line(slot, want, have, status, tip)
		n = n + 1
		local r = Row(n)
		r.slot:SetText(slot)
		r.want:SetText(want)
		r.have:SetText(have or "")
		r.status:SetText(status or "")
		r.tip = tip
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, y)
		r:Show()
		y = y - 20
	end

	Line("|cffffd200Slot|r", "|cffffd200Guide's best for you|r", "|cffffd200On your gear|r", "")
	for _, r in ipairs(ns:AuditEnchants(guide)) do
		local haveText = r.have == 0 and "|cff808080none|r" or (ns.EnchantNames[r.have] or ("enchant " .. r.have))
		Line(r.slot, OptionName(r.best) .. (r.best.skill and (" |cff808080(" .. r.best.skill .. ")|r") or ""),
			haveText, STATUS[r.status], OptionsTip(r.entry, profs))
	end

	y = y - 10
	Line("|cffffd200Gems|r", "|cffffd200Guide's picks|r", "", "")
	if #(guide.gems or {}) == 0 then
		Line("", "|cff808080The guide names no specific gems.|r", "", "")
	end
	for _, g in ipairs(guide.gems or {}) do
		local names = {}
		for i = 1, math.min(3, #g.options) do
			local o = g.options[i]
			names[#names + 1] = OptionName(o) .. (o.tag and (" |cff808080" .. o.tag .. "|r") or "")
				.. (o.skill and (" |cff808080(" .. o.skill .. ")|r") or "")
		end
		Line(g.slot, table.concat(names, " > "), "", "", OptionsTip(g, profs))
	end

	y = y - 10
	local empty = ns:AuditSockets()
	Line("|cffffd200Sockets|r", #empty == 0 and "|cff40ff40Every socket on your gear has a gem.|r"
		or "|cffff4040Empty sockets:|r", "", "")
	for _, s in ipairs(empty) do
		Line(s.slot, s.empty .. " empty socket" .. (s.empty == 1 and "" or "s"), "", STATUS.missing)
	end
	pane.child:SetHeight(-y + 10)
end

local function BuildPane(p)
	pane = p
	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvEEnchantSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)
	local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 190, -20)
	hint:SetText("Hover a row for every option and why the guide picks it.")

	p.empty = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.empty:SetPoint("TOPLEFT", 4, -60)

	local scroll = CreateFrame("ScrollFrame", "FycoPvEEnchantScroll", p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -48)
	scroll:SetPoint("BOTTOMRIGHT", -26, 2)
	p.child = CreateFrame("Frame", nil, scroll)
	p.child:SetWidth(600)
	p.child:SetHeight(100)
	scroll:SetScrollChild(p.child)
end

ns:AddTab("enchants", "Gems & Enchants", 35, BuildPane, Refresh)

function M:OnLoad()
	ns:On("PLAYER_EQUIPMENT_CHANGED", Refresh)
	ns:On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then Refresh() end end)
	ns:Subscribe("ProfileChanged", Refresh)
end
