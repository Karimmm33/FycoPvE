--[[ FycoPvE - Modules/Window.lua
     The main FycoPvE window and the minimap button that opens it.

     The window is a shell: it owns the frame, the tab row and a Settings
     button, and nothing else. Features add themselves as tabs with
     ns:AddTab(key, label, order, build, onShow) at file load, and each tab's
     content is only built the first time it is opened. Later modules (threat,
     meters, boss timers) plug in the same way without touching this file.   ]]

local ADDON, ns = ...
local M = ns:Module("window", 5)

local W, H = 660, 520
local TAB_W = 110

local tabs = {}          -- { key, label, order, build, onShow, pane, button }
local win, current

function ns:AddTab(key, label, order, build, onShow)
	tabs[#tabs + 1] = { key = key, label = label, order = order, build = build, onShow = onShow }
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------

local function SavePosition()
	local point, _, relPoint, x, y = win:GetPoint()
	ns:Set("general", "windowPos", { point, relPoint, x, y })
end

local function Restore()
	win:ClearAllPoints()
	local p = ns:Get("general", "windowPos")
	if p then
		win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	win:SetScale(ns:Get("general", "windowScale") or 1)
end

local function Select(key)
	for i = 1, #tabs do
		local t = tabs[i]
		if t.key == key then
			if not t.pane then
				t.pane = CreateFrame("Frame", nil, win.content)
				t.pane:SetAllPoints(win.content)
				t.build(t.pane)
			end
			t.pane:Show()
			t.button:Disable()
			current = key
			if t.onShow then t.onShow(t.pane) end
		else
			if t.pane then t.pane:Hide() end
			t.button:Enable()
		end
	end
end

local function Build()
	table.sort(tabs, function(a, b) return a.order < b.order end)

	win = CreateFrame("Frame", "FycoPvEWindow", UIParent)
	win:SetWidth(W)
	win:SetHeight(H)
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	-- Escape closes it, like every Blizzard panel
	tinsert(UISpecialFrames, "FycoPvEWindow")

	local title = win:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 22, -18)
	title:SetText("FycoPvE |cff808080v" .. (GetAddOnMetadata(ADDON, "Version") or "?") .. "|r")

	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local settings = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	settings:SetWidth(90)
	settings:SetHeight(22)
	settings:SetPoint("TOPRIGHT", -36, -14)
	settings:SetText("Settings")
	settings:SetScript("OnClick", function() ns:OpenOptions() end)

	for i = 1, #tabs do
		local t = tabs[i]
		local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
		b:SetWidth(TAB_W)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", 18 + (i - 1) * (TAB_W + 4), -44)
		b:SetText(t.label)
		b:SetScript("OnClick", function() Select(t.key) end)
		t.button = b
	end

	local line = win:CreateTexture(nil, "ARTWORK")
	line:SetTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 16, -72)
	line:SetPoint("TOPRIGHT", -16, -72)

	win.content = CreateFrame("Frame", nil, win)
	win.content:SetPoint("TOPLEFT", 18, -80)
	win.content:SetPoint("BOTTOMRIGHT", -18, 16)

	win:SetScript("OnShow", function()
		for i = 1, #tabs do
			if tabs[i].key == current and tabs[i].onShow and tabs[i].pane then tabs[i].onShow(tabs[i].pane) end
		end
	end)

	Restore()
	win:Hide()
end

--- Open the window, optionally on a given tab.
function ns:OpenWindow(key)
	if not win then Build() end
	win:Show()
	Select(key or current or (tabs[1] and tabs[1].key))
end

function ns:ToggleWindow()
	if win and win:IsShown() then win:Hide() else ns:OpenWindow() end
end

function ns:WindowShown(key)
	return win and win:IsShown() and (not key or current == key)
end

function ns:ResetWindow()
	ns:Set("general", "windowPos", nil)
	if win then Restore() end
end

----------------------------------------------------------------------
-- minimap button
----------------------------------------------------------------------

local mini

local function PlaceMini()
	local a = math.rad(ns:Get("general", "minimapAngle") or 200)
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

local function BuildMini()
	mini = CreateFrame("Button", "FycoPvEMinimapButton", Minimap)
	mini:SetWidth(31)
	mini:SetHeight(31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = mini:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", 7, -5)

	local border = mini:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns:OpenOptions() else ns:ToggleWindow() end
	end)

	-- dragging walks the button round the minimap's edge
	mini:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			local angle = math.deg(math.atan2(py / s - my, px / s - mx))
			FycoPvEDB.general = FycoPvEDB.general or {}
			FycoPvEDB.general.minimapAngle = angle
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("FycoPvE")
		GameTooltip:AddLine(ns:ProfileText(), 1, 1, 1)
		GameTooltip:AddLine("|cffffff00Left-click|r open    |cffffff00Right-click|r settings", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffff00Drag|r to move", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	PlaceMini()
end

local function UpdateMini()
	if ns:Get("general", "minimap") then mini:Show() else mini:Hide() end
end

function M:OnLoad()
	BuildMini()
	UpdateMini()
	ns:Subscribe("SettingChanged", function(section, key)
		if section ~= "general" then return end
		if key == "minimap" then UpdateMini() end
		if key == "windowScale" and win then win:SetScale(ns:Get("general", "windowScale")) end
	end)
end
