--[[ FycoPvE - Modules/Options.lua
     Settings panels under Interface -> AddOns -> FycoPvE. Every setting the
     addon has lives here; slash commands are a shortcut, never the only way.

     This file builds the main panel. Every other panel is contributed by the
     module it configures, through ns:RegisterOptions(key, title, order,
     build) -- so a new module brings its own settings page without anyone
     editing this file.

     LAYOUT. The same rules as FycoPvP, learned there the hard way: the
     Interface Options content area is about 500x500 and does NOT clip, so a
     widget placed past the bottom renders over the game world.
       1. Nothing writes a literal Y offset. Column:Check, :Slider, :Title,
          :Note, :Button, :Buttons and :Dropdown place their widget at a cursor
          and advance it by that widget's real height.
       2. Every panel is a scroll frame, and Finish() sizes its content to the
          deepest column, so a panel that outgrows the view scrolls.
       3. Two columns, 230 wide. A third runs off the right edge.         ]]

local ADDON, ns = ...
local M = ns:Module("options", 90)
local UI = ns.UI

-- Column geometry is measured, not assumed. The 3.3.5a options area is only
-- about 410 wide (the old "500" was a guess), and two 230-wide columns ran
-- past its right edge, where nothing could be clicked. Layout() sizes both
-- columns to the real width before any panel is built.
local SCROLL_INSET = 4 + 28          -- scroll frame's left inset + scroll bar
local FALLBACK_W = 410               -- the container's width in the stock 3.3.5a UI
local COL_GAP = 12
local COL1, COL2, COL_W = 8, 0, 0
local SLIDER_W, CONTENT_W = 0, 0

local function Layout()
	local c = InterfaceOptionsFramePanelContainer
	local w = c and c.GetWidth and c:GetWidth() or 0
	if not w or w < 200 then w = FALLBACK_W end
	CONTENT_W = math.floor(w - SCROLL_INSET)
	COL_W = math.floor((CONTENT_W - COL1 - COL_GAP - 4) / 2)
	COL2 = COL1 + COL_W + COL_GAP
	SLIDER_W = COL_W - 30
end

--- The widest a widget may be in one column, for tests and callers.
function ns:OptionsColumnWidth()
	return COL_W, CONTENT_W
end

local H_CHECK, H_TITLE, H_BTN = 24, 34, 28
local H_SLIDER_TOP, H_SLIDER_BODY = 16, 36
local H_DD_TOP, H_DD_BODY = 14, 34

local panels = {}
local main

----------------------------------------------------------------------
-- panel scaffolding
----------------------------------------------------------------------

local function MakePanel(key, displayName, parentName)
	local p = CreateFrame("Frame", ADDON .. "Opt" .. key, UIParent)
	p.name = displayName
	if parentName then p.parent = parentName end

	local scroll = CreateFrame("ScrollFrame", ADDON .. "Opt" .. key .. "Scroll", p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(CONTENT_W)
	content:SetHeight(500)
	scroll:SetScrollChild(content)

	p.scroll, p.content, p.widgets = scroll, content, {}

	p.refresh = function()
		for i = 1, #p.widgets do
			if p.widgets[i].Refresh then p.widgets[i].Refresh() end
		end
	end

	p:SetScript("OnShow", function()
		local w = scroll:GetWidth()
		if w and w > 50 then content:SetWidth(w) end
		p.refresh()
	end)

	panels[#panels + 1] = p
	return p
end

----------------------------------------------------------------------
-- the layout cursor
----------------------------------------------------------------------

local Column = {}
Column.__index = Column

local sliderN, ddN = 0, 0

local function NewColumn(panel, x)
	return setmetatable({ panel = panel, frame = panel.content, x = x, y = -12 }, Column)
end

function Column:advance(h)
	self.y = self.y - h
	return self
end

function Column:track(w)
	self.panel.widgets[#self.panel.widgets + 1] = w
	return w
end

--- Record the right edge a widget reaches, so a test can prove nothing
--- sticks out past the content area.
function Column:reach(right)
	if right > (self.panel.reach or 0) then self.panel.reach = right end
end

function Column:Gap(h)
	return self:advance(h or 10)
end

function Column:Title(text)
	local fs = self.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", self.x, self.y)
	fs:SetText(text)
	self:advance(H_TITLE)
	return fs
end

function Column:Note(text)
	local fs = self.frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	fs:SetPoint("TOPLEFT", self.x, self.y)
	fs:SetWidth(COL_W)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	-- measure the wrapped height; if the client has not laid it out yet,
	-- estimate from the length -- erring long, never short
	local h = fs:GetStringHeight() or 0
	if h < 1 then h = 11 * math.max(1, math.ceil(#text / math.floor(COL_W / 5.5))) end
	self:reach(self.x + COL_W)
	self:advance(math.ceil(h) + 8)
	return fs
end

function Column:Check(label, tooltip, get, set)
	local cb = CreateFrame("CheckButton", nil, self.frame, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", self.x + 4, self.y)
	cb:SetWidth(24)
	cb:SetHeight(24)

	local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetWidth(COL_W - 34)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)

	cb.tooltipText = tooltip
	cb:SetScript("OnClick", function(self2) set(self2:GetChecked() and true or false) end)
	cb.Refresh = function() cb:SetChecked(get()) end

	self:reach(self.x + 4 + 24 + 2 + COL_W - 34)
	self:track(cb)
	self:advance(H_CHECK)
	return cb
end

function Column:Slider(label, minV, maxV, step, get, set)
	sliderN = sliderN + 1
	self:advance(H_SLIDER_TOP)

	local s = CreateFrame("Slider", ADDON .. "OptSlider" .. sliderN, self.frame, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", self.x + 14, self.y)
	s:SetWidth(SLIDER_W)
	self:reach(self.x + 14 + SLIDER_W)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	_G[s:GetName() .. "Low"]:SetText(tostring(minV))
	_G[s:GetName() .. "High"]:SetText(tostring(maxV))

	local caption = _G[s:GetName() .. "Text"]
	s:SetScript("OnValueChanged", function(self2, v)
		v = math.floor(v / step + 0.5) * step
		v = math.floor(v * 100 + 0.5) / 100
		caption:SetText(label .. ": " .. v)
		if not self2.loading then set(v) end
	end)
	s.Refresh = function()
		s.loading = true
		local v = get()
		s:SetValue(v)
		caption:SetText(label .. ": " .. v)
		s.loading = false
	end

	self:track(s)
	self:advance(H_SLIDER_BODY)
	return s
end

--- A captioned dropdown. The template carries ~16px of empty space on its
--- left, so it is pulled left by that much to line up with the caption.
--- Its frame is about 50 wider than the width asked for (the end caps), so
--- the width is capped to keep the arrow button inside the column.
local DD_CAPS = 50

function Column:Dropdown(label, width, opts)
	width = math.min(width, COL_W - DD_CAPS + 12)
	self:reach(self.x - 12 + width + DD_CAPS)
	ddN = ddN + 1
	local fs = self.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", self.x + 4, self.y)
	fs:SetText(label)
	self:advance(H_DD_TOP)

	local dd = UI.Dropdown(self.frame, ADDON .. "OptDD" .. ddN, width, opts)
	dd:SetPoint("TOPLEFT", self.x - 12, self.y)
	self:track(dd)
	self:advance(H_DD_BODY)
	return dd
end

function Column:Button(label, fn, w)
	local b = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", self.x + 4, self.y)
	w = math.min(w or 150, COL_W - 4)
	b:SetWidth(w)
	self:reach(self.x + 4 + w)
	b:SetHeight(22)
	b:SetText(label)
	b:SetScript("OnClick", fn)
	self:advance(H_BTN)
	return b
end

--- Two buttons side by side, costing one row, splitting the column.
function Column:Buttons(l1, f1, l2, f2)
	local bw = math.floor((COL_W - 4 - 4) / 2)
	local a = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	a:SetPoint("TOPLEFT", self.x + 4, self.y)
	a:SetWidth(bw)
	a:SetHeight(22)
	a:SetText(l1)
	a:SetScript("OnClick", f1)

	local b = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", self.x + 4 + bw + 4, self.y)
	b:SetWidth(bw)
	self:reach(self.x + 4 + bw + 4 + bw)
	b:SetHeight(22)
	b:SetText(l2)
	b:SetScript("OnClick", f2)

	self:advance(H_BTN)
	return a, b
end

--- Size the scroll child to whichever column ran deepest, then register the
--- panel. Skipping this leaves it unscrollable however long it grows.
local function Finish(panel, ...)
	local deepest = 0
	for i = 1, select("#", ...) do
		local col = select(i, ...)
		if -col.y > deepest then deepest = -col.y end
	end
	panel.content:SetHeight(deepest + 24)
	InterfaceOptions_AddCategory(panel)
end

----------------------------------------------------------------------
-- main panel
----------------------------------------------------------------------

local function BuildMain()
	main = MakePanel("Main", "FycoPvE")
	local L, R = NewColumn(main, COL1), NewColumn(main, COL2)

	L:Title("FycoPvE")
	L:Note("PvE companion for 3.3.5a. Every setting is on these pages; the "
	    .. "sub-pages on the left hold each feature's own settings.")
	L:Gap(4)

	L:Title("Your profile")
	L:Dropdown("Spec", 170, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	L:Note("Auto follows your talents, including a dual-spec swap. Pick a spec "
	    .. "to look at its lists instead.")
	L:Dropdown("Content phase", 200, {
		items = UI.PhaseItems, get = function() return ns:Phase() end, set = function(v) ns:SetPhase(v) end,
	})
	L:Note("The game cannot tell an addon which phase a server is on, so set it "
	    .. "here and change it when the server moves on. Shared by all your characters.")

	L:Gap(4)
	L:Title("Features")
	local mods = {
		{ "gear",    "Gear - BiS check of what you wear" },
		{ "tooltip", "Tooltips - BiS lines on items" },
		{ "search",  "Search - where items come from" },
		{ "rotation", "Rotation helper - next spell to cast" },
		{ "threat",  "Threat - meter and pull warning" },
		{ "meter",   "Meter - damage and healing" },
		{ "bosses",  "Boss alerts - casts, debuffs, timers" },
	}
	for i = 1, #mods do
		local key = mods[i][1]
		L:Check(mods[i][2], nil,
			function() return FycoPvEDB.enabled[key] ~= false end,
			function(v)
				FycoPvEDB.enabled[key] = v
				ns:Fire("SettingChanged", "enabled", key, v)
			end)
	end

	R:Title("Window")
	R:Check("Minimap button", "Left-click opens FycoPvE, right-click opens these settings",
		function() return ns:Get("general", "minimap") end,
		function(v) ns:Set("general", "minimap", v) end)
	R:Check("Greeting in chat at login", nil,
		function() return ns:Get("general", "loginMessage") end,
		function(v) ns:Set("general", "loginMessage", v) end)
	R:Slider("Window scale", 0.6, 1.4, 0.05,
		function() return ns:Get("general", "windowScale") end,
		function(v) ns:Set("general", "windowScale", v) end)
	R:Buttons("Open FycoPvE", function() ns:OpenWindow() end,
	          "Reset position", function() ns:ResetWindow() end)

	R:Gap(10)
	R:Title("About the data")
	R:Note("BiS rankings come from Wowhead's Wrath of the Lich King guides. Drop, "
	    .. "vendor, reputation and quest data come from the AzerothCore 3.3.5 "
	    .. "database, and map, zone and currency names from this realm's own "
	    .. "client files.")
	R:Note("A custom realm can change drops, prices or item stats. When something "
	    .. "in game disagrees with FycoPvE, the game is right.")

	Finish(main, L, R)
end

----------------------------------------------------------------------

function ns:OpenOptions()
	if not main then return end
	InterfaceOptionsFrame_OpenToCategory(main)
	InterfaceOptionsFrame_OpenToCategory(main)   -- 3.3.5a needs it twice
end

function M:OnLoad()
	Layout()
	BuildMain()

	table.sort(ns.OptionPanels, function(a, b) return a.order < b.order end)
	for i = 1, #ns.OptionPanels do
		local def = ns.OptionPanels[i]
		-- one bad panel must not cost the others their settings page
		local ok, err = pcall(function()
			local p = MakePanel(def.key, def.title, "FycoPvE")
			local L, R = NewColumn(p, COL1), NewColumn(p, COL2)
			def.build(L, R, p)
			Finish(p, L, R)
		end)
		if not ok then ns:Print("|cffff4444settings page '" .. def.title .. "' failed:|r " .. tostring(err)) end
	end

	-- a change made elsewhere (window dropdown, slash command) shows up the
	-- next time a panel is looked at, and at once on one that is open
	local function RefreshOpen()
		for i = 1, #panels do
			if panels[i]:IsVisible() then panels[i].refresh() end
		end
	end
	ns:Subscribe("ProfileChanged", RefreshOpen)
	ns:Subscribe("SettingChanged", RefreshOpen)
end
