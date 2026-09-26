--[[ FycoPvE - Modules/Search.lua
     "Where do I get this?"

     Type part of an item name, a slot ("wrist", "bracers"), a boss, a vendor
     or a zone ("halls of stone") and every matching item is listed, best for
     your spec first. Click one to see every place it comes from: which boss
     and difficulty, which vendor, what it costs, what reputation it needs.

     0.1 searches the items that appear on any BiS list the addon ships. The
     search runs over ns.Items, so a bigger item database later needs no
     change here.                                                           ]]

local ADDON, ns = ...
local M = ns:Module("search", 40)
local UI = ns.UI

local ROW_H, ROWS = 20, 17
local LIST_W = 286

-- slot filter -> inventory types it covers
local SLOTS = {
	{ value = "any",      text = "Any slot" },
	{ value = "head",     text = "Head",      inv = { 1 } },
	{ value = "neck",     text = "Neck",      inv = { 2 } },
	{ value = "shoulder", text = "Shoulder",  inv = { 3 } },
	{ value = "back",     text = "Back",      inv = { 16 } },
	{ value = "chest",    text = "Chest",     inv = { 5, 20 } },
	{ value = "wrist",    text = "Wrist",     inv = { 9 } },
	{ value = "hands",    text = "Hands",     inv = { 10 } },
	{ value = "waist",    text = "Waist",     inv = { 6 } },
	{ value = "legs",     text = "Legs",      inv = { 7 } },
	{ value = "feet",     text = "Feet",      inv = { 8 } },
	{ value = "finger",   text = "Ring",      inv = { 11 } },
	{ value = "trinket",  text = "Trinket",   inv = { 12 } },
	{ value = "weapon",   text = "Weapon",    inv = { 13, 17, 21 } },
	{ value = "offhand",  text = "Off hand",  inv = { 14, 22, 23 } },
	{ value = "ranged",   text = "Ranged",    inv = { 15, 25, 26, 28 } },
}

----------------------------------------------------------------------
-- search
----------------------------------------------------------------------

local index   -- { { id, name, nameHay, srcHay } } sorted by name

local function BuildIndex()
	index = {}
	for id, it in pairs(ns.Items) do
		local src = {}
		for i = 1, #(it.src or {}) do
			local s = it.src[i]
			src[#src + 1] = (s.who or "") .. " " .. (s.zone or "") .. " " .. (s.title or "") .. " " .. (s.mode or "")
		end
		if it.g then src[#src + 1] = it.g end
		if it.rep then src[#src + 1] = it.rep[1] end
		index[#index + 1] = {
			id = id, name = it.n,
			nameHay = (it.n .. " " .. ((ns.InvTypes[it.inv] or {})[2] or "")):lower(),
			srcHay = table.concat(src, " "):lower(),
		}
	end
	table.sort(index, function(a, b) return a.name < b.name end)
end

--- Rank on the current spec+phase list, lower is better; nil when absent.
local function MyRank(id)
	local entries = ns.BiSIndex[id]
	local class, spec, phase = ns:PlayerClass(), ns:Spec(), ns:Phase()
	for i = 1, #(entries or {}) do
		local e = entries[i]
		if e.class == class and e.spec == spec and e.phase == phase then
			return e.tier * 1000 + e.pos, e
		end
	end
end

local function ForMyClass(id)
	local entries = ns.BiSIndex[id]
	local class = ns:PlayerClass()
	for i = 1, #(entries or {}) do
		if entries[i].class == class then return true end
	end
	return false
end

--- Every item matching all words of `query`, filtered by slot. An empty
--- query with a slot chosen lists that whole slot.
function ns:SearchItems(query, slot, myClassOnly)
	if not index then BuildIndex() end
	local words = {}
	for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end

	local invOK
	for i = 1, #SLOTS do
		if SLOTS[i].value == slot and SLOTS[i].inv then
			invOK = {}
			for _, t in ipairs(SLOTS[i].inv) do invOK[t] = true end
		end
	end
	if #words == 0 and not invOK then return {} end

	local withSources = ns:Get("search", "matchSources")
	local out = {}
	for i = 1, #index do
		local e = index[i]
		local ok = true
		if invOK and not invOK[ns.Items[e.id].inv] then ok = false end
		for w = 1, #words do
			if not ok then break end
			if not (e.nameHay:find(words[w], 1, true) or (withSources and e.srcHay:find(words[w], 1, true))) then
				ok = false
			end
		end
		if ok and myClassOnly and not ForMyClass(e.id) then ok = false end
		if ok then out[#out + 1] = e.id end
	end

	-- your own list first, best rank first; everything else alphabetical
	table.sort(out, function(a, b)
		local ra, rb = MyRank(a) or 99999, MyRank(b) or 99999
		if ra ~= rb then return ra < rb end
		return ns.Items[a].n < ns.Items[b].n
	end)
	return out
end

--- /fpve find
function ns:SearchToChat(text)
	local ids = ns:SearchItems(text, "any", false)
	if #ids == 0 then
		ns:Print("nothing matches |cffffff00" .. text .. "|r. 0.1 knows the items on the BiS lists it ships; "
		      .. "search matches item names, slots, bosses, vendors and zones.")
		return
	end
	local max = ns:Get("search", "chatResults")
	ns:Print(#ids .. " match" .. (#ids == 1 and "" or "es") .. " for |cffffff00" .. text .. "|r:")
	if #ids == 1 then
		ns:Print("  " .. UI.ItemLink(ids[1]))
		local lines = ns:SourceLines(ids[1])
		for i = 1, #lines do ns:Print("    " .. lines[i]) end
		return
	end
	for i = 1, math.min(#ids, max) do
		ns:Print("  " .. UI.ItemLink(ids[i]) .. "  " .. (ns:SourceSummary(ids[i]) or ""))
	end
	if #ids > max then
		ns:Print("  ...and " .. (#ids - max) .. " more. |cffffff00/fpve|r and the Search tab list them all.")
	end
end

----------------------------------------------------------------------
-- the Search tab
----------------------------------------------------------------------

local pane
local results, selected = {}, nil
local slotFilter = "any"

local function RankBadge(id)
	local _, e = MyRank(id)
	if not e then return "" end
	local t = ns.Tiers[e.tier]
	return "|cff" .. t.color .. t.name .. "|r"
end

local function ShowDetail()
	local d = pane.detail
	local id = selected
	if not (id and ns.Items[id]) then
		d.icon:Hide()
		d.name:SetText("")
		d.info:SetText("")
		d.body:SetText("|cff808080Pick an item on the left.|r")
		d.child:SetHeight(40)
		return
	end
	local it = ns.Items[id]
	d.icon:SetItem(id)
	d.icon:Show()
	d.name:SetText(UI.ItemName(id))
	d.info:SetText("Item level " .. it.lvl .. " - " .. ((ns.InvTypes[it.inv] or {})[1] or "?"))

	local lines = {}
	local entries = ns.BiSIndex[id] or {}
	local class = ns:PlayerClass()
	local threshold = ns:Get("gear", "bisTier")
	local listed = false
	for i = 1, #entries do
		local e = entries[i]
		if e.class == class then
			if not listed then
				lines[#lines + 1] = "|cffffd200On your BiS lists|r"
				listed = true
			end
			lines[#lines + 1] = string.format("%s%s %s  |cff808080%s, %s|r",
				e.tier <= threshold and "|cff40ff40BiS|r " or "",
				ns.ListName[e.list] or e.list, ns:TierText(e.tier, e.pos, e.count),
				e.spec, ns.PhaseName[e.phase] or e.phase)
		end
	end
	if listed then lines[#lines + 1] = " " end

	lines[#lines + 1] = "|cffffd200Where to get it|r"
	local src = ns:SourceLines(id)
	if #src == 0 then src = { "|cff808080No source known.|r" } end
	for i = 1, #src do lines[#lines + 1] = src[i] end

	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cff808080Sources are from the stock 3.3.5 game database. A custom realm can "
		.. "change drops and prices.|r"

	d.body:SetText(table.concat(lines, "\n"))
	d.child:SetHeight(math.ceil(d.body:GetStringHeight() or 200) + 10)
	d.scroll:SetVerticalScroll(0)
end

local function UpdateList()
	local offset = FauxScrollFrame_GetOffset(pane.scroll)
	for i = 1, ROWS do
		local row = pane.rows[i]
		local id = results[i + offset]
		if id then
			row.id = id
			row.icon:SetTexture(UI.ItemIcon(id))
			row.name:SetText(UI.ItemName(id))
			row.badge:SetText(RankBadge(id))
			if id == selected then row.sel:Show() else row.sel:Hide() end
			row:Show()
		else
			row.id = nil
			row:Hide()
		end
	end
	FauxScrollFrame_Update(pane.scroll, #results, ROWS, ROW_H)
end

local function Run()
	if not pane then return end
	results = ns:SearchItems(pane.box:GetText(), slotFilter, ns:Get("search", "myClassOnly"))
	local q = pane.box:GetText()
	if q == "" and slotFilter == "any" then
		pane.count:SetText("|cff808080type to search|r")
	else
		pane.count:SetText(#results .. " found")
	end
	FauxScrollFrame_SetOffset(pane.scroll, 0)
	_G[pane.scroll:GetName() .. "ScrollBar"]:SetValue(0)
	UpdateList()
end

local function Select(id)
	selected = id
	UpdateList()
	ShowDetail()
end

local function BuildPane(p)
	pane = p

	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Item name, slot, boss, vendor or zone")

	local box = CreateFrame("EditBox", "FycoPvESearchBox", p, "InputBoxTemplate")
	box:SetWidth(210)
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", 10, -14)
	box:SetAutoFocus(false)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	p.box = box

	local scap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	scap:SetPoint("TOPLEFT", 244, 0)
	scap:SetText("Slot")
	p.slot = UI.Dropdown(p, "FycoPvESearchSlot", 100, {
		items = function() return SLOTS end,
		get = function() return slotFilter end,
		set = function(v) slotFilter = v; Run() end,
	})
	p.slot:SetPoint("TOPLEFT", 226, -12)

	local mine = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
	mine:SetWidth(24)
	mine:SetHeight(24)
	mine:SetPoint("TOPLEFT", 390, -12)
	local mineLabel = mine:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	mineLabel:SetPoint("LEFT", mine, "RIGHT", 0, 0)
	mineLabel:SetText("My class only")
	mine:SetScript("OnClick", function(self)
		ns:Set("search", "myClassOnly", self:GetChecked() and true or false)
		Run()
	end)
	p.mine = mine

	p.count = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.count:SetPoint("TOPRIGHT", -4, -18)

	-- result list
	p.scroll = CreateFrame("ScrollFrame", "FycoPvESearchScroll", p, "FauxScrollFrameTemplate")
	p.scroll:SetPoint("TOPLEFT", 0, -44)
	p.scroll:SetWidth(LIST_W)
	p.scroll:SetHeight(ROWS * ROW_H)
	p.scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateList)
	end)

	local function Wheel(_, delta)
		local sb = _G["FycoPvESearchScrollScrollBar"]
		sb:SetValue(sb:GetValue() - delta * ROW_H * 3)
	end

	p.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, p)
		row:SetHeight(ROW_H)
		row:SetWidth(LIST_W)
		row:SetPoint("TOPLEFT", 0, -44 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", Wheel)

		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints(row)
		row.sel:SetTexture(0.4, 0.8, 1, 0.18)
		row.sel:Hide()

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(16)
		row.icon:SetHeight(16)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 24, 0)
		row.name:SetWidth(200)
		row.name:SetHeight(ROW_H)
		row.name:SetJustifyH("LEFT")

		row.badge = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.badge:SetPoint("RIGHT", -4, 0)

		row:SetScript("OnClick", function(self)
			if not self.id then return end
			if HandleModifiedItemClick(UI.ItemLink(self.id)) then return end
			Select(self.id)
		end)
		row:SetScript("OnEnter", function(self)
			if not self.id then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:" .. self.id .. ":0:0:0:0:0:0:0:0")
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		p.rows[i] = row
	end

	-- detail pane: scrolls, so a long list of sources can never spill out
	local d = CreateFrame("Frame", nil, p)
	d:SetPoint("TOPLEFT", LIST_W + 30, -44)
	d:SetPoint("BOTTOMRIGHT", 0, 0)
	local bg = d:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(d)
	bg:SetTexture(0, 0, 0, 0.25)
	p.detail = d

	d.icon = UI.ItemButton(d, 36)
	d.icon:SetPoint("TOPLEFT", 8, -8)
	d.name = d:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	d.name:SetPoint("TOPLEFT", 52, -10)
	d.name:SetPoint("RIGHT", d, "RIGHT", -8, 0)
	d.name:SetJustifyH("LEFT")
	d.info = d:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	d.info:SetPoint("TOPLEFT", 52, -30)

	d.scroll = CreateFrame("ScrollFrame", "FycoPvESearchDetail", d, "UIPanelScrollFrameTemplate")
	d.scroll:SetPoint("TOPLEFT", 8, -52)
	d.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	d.child = CreateFrame("Frame", nil, d.scroll)
	d.child:SetWidth(250)
	d.child:SetHeight(40)
	d.scroll:SetScrollChild(d.child)
	d.body = d.child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	d.body:SetPoint("TOPLEFT", 0, 0)
	d.body:SetWidth(250)
	d.body:SetJustifyH("LEFT")
	d.body:SetJustifyV("TOP")
	d.body:SetSpacing(2)

	-- bound last: Run reads the list and scroll frame built above
	box:SetScript("OnTextChanged", Run)
	ShowDetail()
end

local function OnShow(p)
	p.mine:SetChecked(ns:Get("search", "myClassOnly"))
	p.slot.Refresh()
	Run()
	ShowDetail()
end

ns:AddTab("search", "Item search", 90, BuildPane, OnShow)

--- Open the Search tab on one item, e.g. from a Gear-tab upgrade.
function ns:ShowItem(id)
	if not ns.Items[id] then return end
	ns:OpenWindow("search")
	slotFilter = "any"
	pane.slot.Refresh()
	pane.box:SetText(ns.Items[id].n)
	Run()
	Select(id)
end

function M:OnLoad()
	-- the ranking depends on spec and phase, so re-sort when they change
	ns:Subscribe("ProfileChanged", function()
		if pane and pane:IsVisible() then Run() ShowDetail() end
	end)
	ns:Subscribe("SettingChanged", function(section)
		if section == "search" and pane and pane:IsVisible() then Run() end
	end)
end

----------------------------------------------------------------------
-- settings panel
----------------------------------------------------------------------

ns:RegisterOptions("search", "Search", 30, function(L, R)
	L:Title("Item search")
	L:Note("Search the FycoPvE item database from the window's Search tab or with "
	    .. "/fpve find <text>. 0.1 covers every item on the BiS lists it ships.")
	L:Check("Also match bosses, vendors and zones", "Off matches item names and slots only",
		function() return ns:Get("search", "matchSources") end,
		function(v) ns:Set("search", "matchSources", v) end)
	L:Check("Only items on my class's lists", nil,
		function() return ns:Get("search", "myClassOnly") end,
		function(v) ns:Set("search", "myClassOnly", v) end)

	R:Title("Chat results")
	R:Slider("Items listed by /fpve find", 3, 25, 1,
		function() return ns:Get("search", "chatResults") end,
		function(v) ns:Set("search", "chatResults", v) end)
	R:Button("Open Search tab", function() ns:OpenWindow("search") end, 160)
end)
