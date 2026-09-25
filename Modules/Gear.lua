--[[ FycoPvE - Modules/Gear.lua
     "Am I wearing my best in slot?"

     Judges every equipped item against the BiS lists for your spec and the
     phase you chose, and shows the answer in four places:
       - the Gear tab of the FycoPvE window, one row per slot, with the next
         upgrade and where it comes from
       - a badge on each slot of the character sheet
       - a chat line whenever you equip something
       - /fpve gear
     Rings and trinkets are judged as pairs against one list. A two-hander
     switches the weapon row to the two-hand list and retires the off hand. ]]

local ADDON, ns = ...
local M = ns:Module("gear", 20)
local UI = ns.UI

local ROW_H = 21

----------------------------------------------------------------------
-- evaluation
----------------------------------------------------------------------

local function EquippedID(inv)
	local link = GetInventoryItemLink("player", inv)
	return link and tonumber(link:match("item:(%d+)")), link
end

local function IsTwoHand(id)
	if not id then return false end
	local loc = select(9, GetItemInfo(id))
	if loc then return loc == "INVTYPE_2HWEAPON" end
	local it = ns.Items[id]
	return it and it.inv == 17 or false
end

--- Can the player use this item? Faction-locked items (PvP gear, some
--- reputation rewards) exist in both versions on every list.
local function Eligible(id)
	if ns:Get("gear", "otherFaction") then return true end
	local it = ns.Items[id]
	return not (it and it.side) or it.side == UnitFactionGroup("player")
end

function ns:TierText(tier, pos, count)
	local t = ns.Tiers[tier]
	if not t then return "" end
	return "|cff" .. t.color .. t.name .. " #" .. pos .. "|r|cff808080/" .. count .. "|r"
end

--- One record per ns.GearRows entry:
---   id, link   what is equipped (nil when empty)
---   key, list  which BiS list judges it (nil when there is none)
---   pos, tier  where the equipped item sits on that list (nil if absent)
---   isBiS      tier is within the "counts as BiS" setting
---   upgrade    the best eligible item on the list you are not wearing
---   na         the off hand while a two-hander is equipped
function ns:EvaluateGear(lists)
	local threshold = ns:Get("gear", "bisTier")
	local twoHand = IsTwoHand((EquippedID(16)))
	local rows, byInv = {}, {}

	for i = 1, #ns.GearRows do
		local def = ns.GearRows[i]
		local id, link = EquippedID(def.inv)
		local key = def.list
		if key == "Weapon" then
			if twoHand or not lists.MainHand then key = "TwoHand" else key = "MainHand" end
		end

		local r = { def = def, id = id, link = link, key = key, list = lists[key] }
		if def.list == "OffHand" and twoHand then
			r.na, r.list = true, nil
		end
		if r.list and id then
			for pos = 1, #r.list do
				if r.list[pos][1] == id then
					r.pos, r.tier = pos, r.list[pos][2]
					break
				end
			end
		end
		r.count = r.list and #r.list or 0
		r.isBiS = (r.tier and r.tier <= threshold) and true or false
		rows[i], byInv[def.inv] = r, r
	end

	-- Suggest upgrades after every slot is known, so the two rings (or two
	-- trinkets) never suggest the same item, nor the one already worn in the
	-- other slot.
	local taken = {}
	for i = 1, #rows do
		local r = rows[i]
		if r.list and not r.isBiS then
			taken[r.key] = taken[r.key] or {}
			local t = taken[r.key]
			if r.id then t[r.id] = true end
			if r.def.pair and byInv[r.def.pair].id then t[byInv[r.def.pair].id] = true end
			for pos = 1, #r.list do
				local cand, tier = r.list[pos][1], r.list[pos][2]
				if r.tier and tier >= r.tier then break end   -- nothing better left
				if not t[cand] and Eligible(cand) then
					r.upgrade, t[cand] = cand, true
					break
				end
			end
		end
	end
	return rows
end

--- Lists for the current profile, or nil with a reason.
local function CurrentLists()
	local class, spec, phase = ns:PlayerClass(), ns:Spec(), ns:Phase()
	local lists = ns:BiSLists(class, spec, phase)
	if lists then return lists end
	return nil, "There is no BiS list for " .. ns:ProfileText() .. " yet."
end

local function StatusText(r)
	if r.na then return "|cff808080not used with a two-hander|r" end
	if not r.list then return "|cff808080no list for this slot|r" end
	if not r.id then return "|cff808080empty|r" end
	if not r.pos then return "|cffff4040not on the list|r" end
	return (r.isBiS and "|cff40ff40BiS|r  " or "") .. ns:TierText(r.tier, r.pos, r.count)
end

----------------------------------------------------------------------
-- the Gear tab
----------------------------------------------------------------------

local pane

local function RefreshPane()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	pane.phase.Refresh()

	local lists, why = CurrentLists()
	if not lists then
		pane.summary:SetText(ns:ProfileText())
		pane.empty:SetText(why .. "\n\nPick another spec or phase above. More classes, specs and phases "
			.. "are added in later versions.")
		pane.empty:Show()
		for i = 1, #pane.rows do pane.rows[i]:Hide() end
		return
	end
	pane.empty:Hide()

	local rows = ns:EvaluateGear(lists)
	local bis, total = 0, 0
	for i = 1, #rows do
		local r, w = rows[i], pane.rows[i]
		if r.list then
			total = total + 1
			if r.isBiS then bis = bis + 1 end
		end
		w.label:SetText(r.def.label)
		w.have:SetItem(r.id, r.link)
		w.haveName:SetText(r.id and UI.ItemName(r.id) or "")
		w.status:SetText(StatusText(r))
		if r.upgrade then
			w.up:SetItem(r.upgrade)
			w.up:Show()
			w.upName:SetText("|cff808080->|r " .. UI.ItemName(r.upgrade))
		else
			w.up:Hide()
			w.upName:SetText("")
		end
		w:Show()
	end

	local tiers = ns.Tiers[ns:Get("gear", "bisTier")]
	pane.summary:SetText(string.format("%s:  |cff40ff40%d|r of %d slots BiS  |cff808080(counting %s%s as BiS)|r",
		ns:ProfileText(), bis, total, tiers and tiers.name or "?",
		ns:Get("gear", "bisTier") > 1 and " and better" or " only"))
end

local function BuildPane(p)
	pane = p

	local function Caption(text, x)
		local fs = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", x, 0)
		fs:SetText(text)
	end

	Caption("Spec", 4)
	p.spec = UI.Dropdown(p, "FycoPvEGearSpec", 150, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)

	Caption("Phase", 204)
	p.phase = UI.Dropdown(p, "FycoPvEGearPhase", 300, {
		items = UI.PhaseItems, get = function() return ns:Phase() end, set = function(v) ns:SetPhase(v) end,
	})
	p.phase:SetPoint("TOPLEFT", 188, -12)

	p.summary = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.summary:SetPoint("TOPLEFT", 4, -50)
	p.summary:SetPoint("RIGHT", p, "RIGHT", -4, 0)
	p.summary:SetJustifyH("LEFT")

	p.empty = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.empty:SetPoint("TOPLEFT", 4, -90)
	p.empty:SetWidth(600)
	p.empty:SetJustifyH("LEFT")

	-- columns: slot | equipped | status | next upgrade
	p.rows = {}
	for i = 1, #ns.GearRows do
		local w = CreateFrame("Frame", nil, p)
		w:SetHeight(ROW_H)
		w:SetPoint("TOPLEFT", 0, -70 - (i - 1) * ROW_H)
		w:SetPoint("RIGHT", p, "RIGHT")

		if i % 2 == 0 then
			local bg = w:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(w)
			bg:SetTexture(1, 1, 1, 0.04)
		end

		w.label = w:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		w.label:SetPoint("LEFT", 4, 0)
		w.label:SetWidth(64)
		w.label:SetJustifyH("LEFT")

		w.have = UI.ItemButton(w, 18)
		w.have:SetPoint("LEFT", 70, 0)
		w.haveName = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		w.haveName:SetPoint("LEFT", 92, 0)
		w.haveName:SetWidth(180)
		w.haveName:SetHeight(ROW_H)
		w.haveName:SetJustifyH("LEFT")

		w.status = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		w.status:SetPoint("LEFT", 278, 0)
		w.status:SetWidth(130)
		w.status:SetHeight(ROW_H)
		w.status:SetJustifyH("LEFT")

		-- clicking the upgrade opens it in Search, with every source listed
		w.up = UI.ItemButton(w, 18, function(self) ns:ShowItem(self.itemID) end)
		w.up:SetPoint("LEFT", 412, 0)
		w.upName = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		w.upName:SetPoint("LEFT", 434, 0)
		w.upName:SetWidth(190)
		w.upName:SetHeight(ROW_H)
		w.upName:SetJustifyH("LEFT")

		p.rows[i] = w
	end

	local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 4, 2)
	hint:SetText("Click an upgrade to see every place it comes from. Shift-click links it.")
end

ns:AddTab("gear", "Gear", 10, BuildPane, RefreshPane)

----------------------------------------------------------------------
-- character sheet: a badge on every slot, and a button to the Gear tab
----------------------------------------------------------------------

local badges = {}

local function RefreshSheet()
	if not (PaperDollFrame and PaperDollFrame:IsVisible()) then return end
	local on = ns:Enabled("gear") and ns:Get("gear", "sheetMarkers")
	local lists = on and CurrentLists()
	local rows = lists and ns:EvaluateGear(lists)

	for i = 1, #ns.GearRows do
		local fs = badges[i]
		if fs then
			local r = rows and rows[i]
			if not (r and r.list and r.id) then
				fs:SetText("")
			elseif r.isBiS then
				fs:SetText("|cff40ff40BiS|r")
			elseif r.tier then
				fs:SetText("|cff" .. ns.Tiers[r.tier].color .. "#" .. r.pos .. "|r")
			else
				fs:SetText("|cffff4040x|r")
			end
		end
	end
end

local function BuildSheet()
	if not PaperDollFrame then return end
	for i = 1, #ns.GearRows do
		local btn = _G[ns.GearRows[i].button]
		if btn then
			local fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
			badges[i] = fs
		end
	end

	local b = CreateFrame("Button", "FycoPvESheetButton", PaperDollFrame, "UIPanelButtonTemplate")
	b:SetWidth(44)
	b:SetHeight(20)
	b:SetPoint("TOPRIGHT", PaperDollFrame, "TOPRIGHT", -42, -40)
	b:SetText("BiS")
	b:SetScript("OnClick", function() ns:OpenWindow("gear") end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("FycoPvE - best in slot")
		GameTooltip:AddLine(ns:ProfileText(), 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	M.sheetButton = b

	PaperDollFrame:HookScript("OnShow", RefreshSheet)
end

local function UpdateSheetButton()
	if not M.sheetButton then return end
	if ns:Enabled("gear") and ns:Get("gear", "sheetButton") then M.sheetButton:Show() else M.sheetButton:Hide() end
end

----------------------------------------------------------------------
-- chat
----------------------------------------------------------------------

--- /fpve gear
function ns:GearReport()
	local lists, why = CurrentLists()
	if not lists then ns:Print(why) return end
	local rows = ns:EvaluateGear(lists)
	local bis, total = 0, 0
	for i = 1, #rows do
		if rows[i].list then
			total = total + 1
			if rows[i].isBiS then bis = bis + 1 end
		end
	end
	ns:Print(string.format("%s: |cff40ff40%d|r of %d slots BiS", ns:ProfileText(), bis, total))
	for i = 1, #rows do
		local r = rows[i]
		if r.list and not r.isBiS then
			local line = "  " .. r.def.label .. ": " .. (r.link or "|cff808080empty|r") .. " " .. StatusText(r)
			if r.upgrade then
				line = line .. " -> " .. UI.ItemLink(r.upgrade)
				local src = ns:SourceSummary(r.upgrade)
				if src then line = line .. "  " .. src end
			end
			ns:Print(line)
		end
	end
end

-- Equip reports are collected for a moment and printed together: swapping a
-- whole set fires one event per slot, and nobody wants seventeen lines.
local pending, pendingAt = {}, nil

local function FlushEquipReport()
	local lists = CurrentLists()
	if not lists then pending = {} return end
	local rows = ns:EvaluateGear(lists)
	for i = 1, #rows do
		local r = rows[i]
		if pending[r.def.inv] and r.id and r.list then
			local line = r.link .. " (" .. r.def.label .. "): "
			if r.isBiS then
				line = line .. "|cff40ff40BiS|r " .. ns:TierText(r.tier, r.pos, r.count)
			elseif r.tier then
				line = line .. ns:TierText(r.tier, r.pos, r.count)
			else
				line = line .. "|cffff4040not on the " .. (ns.PhaseName[ns:Phase()] or "") .. " list|r"
			end
			if r.upgrade then line = line .. "  better: " .. UI.ItemLink(r.upgrade) end
			ns:Print(line)
		end
	end
	pending = {}
end

----------------------------------------------------------------------

local dirty = false
-- Some servers fire an equipment change for every slot while the world
-- loads; that is not the player equipping anything, so stay quiet then.
local quietUntil = 0

function M:OnLoad()
	BuildSheet()
	UpdateSheetButton()

	quietUntil = GetTime() + 5
	ns:On("PLAYER_ENTERING_WORLD", function() quietUntil = GetTime() + 5 end)

	ns:On("PLAYER_EQUIPMENT_CHANGED", function(_, slot, hasItem)
		dirty = true
		if hasItem and GetTime() > quietUntil and ns:Enabled("gear") and ns:Get("gear", "equipReport") then
			pending[slot] = true
			pendingAt = GetTime()
		end
	end)
	ns:On("UNIT_INVENTORY_CHANGED", function(_, unit)
		if unit == "player" then dirty = true end
	end)
	ns:Subscribe("ProfileChanged", function() dirty = true end)
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "gear" or section == "enabled" then dirty = true end
		if key == "sheetButton" or (section == "enabled" and key == "gear") then UpdateSheetButton() end
	end)

	ns:OnTick(function(now)
		if pendingAt and now - pendingAt > 0.4 then
			pendingAt = nil
			FlushEquipReport()
		end
		if dirty then
			dirty = false
			RefreshPane()
			RefreshSheet()
		end
	end)
end

----------------------------------------------------------------------
-- settings panel
----------------------------------------------------------------------

local THRESHOLDS = {
	{ value = 1, text = "Best only" },
	{ value = 2, text = "Best and Great" },
	{ value = 3, text = "Best, Great and Good" },
	{ value = 4, text = "Anything on the list" },
}

ns:RegisterOptions("gear", "BiS and Gear", 10, function(L, R)
	L:Title("Best in slot")
	L:Note("Guides rank each slot Best, Great, Good or Mediocre, and often list "
	    .. "several items at the same rank. Choose which ranks count as BiS.")
	L:Dropdown("Counts as BiS", 180, {
		items = function() return THRESHOLDS end,
		get = function() return ns:Get("gear", "bisTier") end,
		set = function(v) ns:Set("gear", "bisTier", v) end,
	})
	L:Check("Suggest the other faction's items", "PvP and some reputation items "
	     .. "come in a Horde and an Alliance version",
		function() return ns:Get("gear", "otherFaction") end,
		function(v) ns:Set("gear", "otherFaction", v) end)

	L:Gap(8)
	L:Title("When you equip something")
	L:Check("Say in chat how it ranks", "One line per item, with the next upgrade",
		function() return ns:Get("gear", "equipReport") end,
		function(v) ns:Set("gear", "equipReport", v) end)

	R:Title("Character sheet")
	R:Check("Rank badge on each slot", "BiS, #rank, or x when not on the list",
		function() return ns:Get("gear", "sheetMarkers") end,
		function(v) ns:Set("gear", "sheetMarkers", v) end)
	R:Check("BiS button on the sheet", "Opens the Gear tab",
		function() return ns:Get("gear", "sheetButton") end,
		function(v) ns:Set("gear", "sheetButton", v) end)

	R:Gap(8)
	R:Title("Check now")
	R:Buttons("Open Gear tab", function() ns:OpenWindow("gear") end,
	          "Report in chat", function() ns:GearReport() end)
end)
