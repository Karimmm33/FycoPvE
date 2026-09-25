--[[ FycoPvE - Core.lua
     Shared plumbing every module reads, built the same way as FycoPvP's core:
       1. one event dispatcher and one throttled ticker for the whole addon
       2. a message bus, so modules react to each other without knowing each other
       3. the module registry, and settings with per-key defaults
       4. who the player is: class, spec (detected or chosen) and content phase
       5. the BiS registry the generated Data/BiS files write into
     3.3.5a notes: no C_Timer, and no spec API -- spec is read from talent points. ]]

local ADDON, ns = ...

local tinsert = table.insert

----------------------------------------------------------------------
-- event dispatch
----------------------------------------------------------------------

local frame    = CreateFrame("Frame", ADDON .. "Core", UIParent)
local handlers = {}

--- Register fn to run on event. Several modules may take the same event.
function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	tinsert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

----------------------------------------------------------------------
-- one ticker, 10 Hz, shared
----------------------------------------------------------------------

local tickers, dead, acc = {}, {}, 0
local current

function ns:OnTick(fn)
	tinsert(tickers, fn)
end

local function RunTickers(now)
	for i = 1, #tickers do
		if not dead[i] then
			current = i
			tickers[i](now)
		end
	end
end

frame:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0

	-- One module's bug must not silently stop every other module's updates.
	-- Retire the offender, say so, let the rest run. (Lesson from FycoPvP.)
	local ok, err = pcall(RunTickers, GetTime())
	if not ok then
		dead[current or 0] = true
		ns:Print("|cffff4040a module errored and its updates were stopped:|r")
		ns:Print("  " .. tostring(err))
		ns:Print("|cff808080Everything else keeps running. |cffffff00/reload|r to try it again.|r")
	end
end)

----------------------------------------------------------------------
-- output
----------------------------------------------------------------------

function ns:Print(...)
	local msg = ""
	for i = 1, select("#", ...) do
		msg = msg .. tostring(select(i, ...)) .. " "
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffFycoPvE|r " .. msg)
end

function ns:Debug(...)
	if FycoPvEDB and FycoPvEDB.debug then self:Print("|cff808080dbg|r", ...) end
end

----------------------------------------------------------------------
-- message bus
----------------------------------------------------------------------

local subs = {}

function ns:Subscribe(msg, fn)
	if not subs[msg] then subs[msg] = {} end
	tinsert(subs[msg], fn)
end

function ns:Fire(msg, ...)
	local list = subs[msg]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end

----------------------------------------------------------------------
-- module registry
----------------------------------------------------------------------

ns.modules, ns.moduleOrder = {}, {}

--- `order` fixes load order. pairs() order is unspecified, and a module whose
--- OnLoad expects another's to have run first must not depend on luck.
function ns:Module(name, order)
	local m = { name = name, order = order or 50 }
	ns.modules[name] = m
	tinsert(ns.moduleOrder, m)
	return m
end

--- Is this module switched on right now? Checked at use time rather than only
--- at load, so the checkboxes take effect immediately.
function ns:Enabled(name)
	return FycoPvEDB and FycoPvEDB.enabled and FycoPvEDB.enabled[name] ~= false
end

--- Settings panels a module contributes. Registered at file load, built by
--- Modules/Options.lua at login -- so a new module adds its own panel without
--- touching the options file. build(L, R, panel) receives two layout columns.
ns.OptionPanels = {}

function ns:RegisterOptions(key, title, order, build)
	tinsert(ns.OptionPanels, { key = key, title = title, order = order, build = build })
end

----------------------------------------------------------------------
-- settings
----------------------------------------------------------------------

-- Every setting's default, by section. Read through ns:Get, so a key added
-- in a later version works at once without resetting saved choices.
ns.Defaults = {
	general = {
		phase = "PreRaid",
		minimap = true,
		minimapAngle = 200,
		windowScale = 1.0,
		loginMessage = true,
	},
	gear = {
		bisTier = 1,          -- tiers 1..bisTier count as "BiS"
		sheetMarkers = true,  -- rank badges on the character sheet slots
		sheetButton = true,   -- "BiS" button on the character sheet
		equipReport = true,   -- chat line when you equip something
		otherFaction = false, -- suggest the other faction's items too
	},
	tooltip = {
		scope = "spec",       -- "spec" this spec+phase, "class" my class, "all" everyone
		sources = true,       -- a "Source:" line under the BiS lines
		shiftOnly = false,
	},
	search = {
		matchSources = true,  -- also match boss, vendor and zone names
		myClassOnly = false,
		chatResults = 8,
	},
}

-- module switches, written one key at a time so a module added later turns
-- itself on without resetting what has been saved
local moduleDefaults = { gear = true, tooltip = true, search = true }

function ns:Get(section, key)
	local s = FycoPvEDB and FycoPvEDB[section]
	if s and s[key] ~= nil then return s[key] end
	local d = ns.Defaults[section]
	if d then return d[key] end
end

function ns:Set(section, key, value)
	FycoPvEDB[section] = FycoPvEDB[section] or {}
	FycoPvEDB[section][key] = value
	ns:Fire("SettingChanged", section, key, value)
end

----------------------------------------------------------------------
-- BiS registry
----------------------------------------------------------------------

-- ns.BiS[class][spec][phase][listKey] = { {itemID, tier}, ... } best first.
-- ns.BiSIndex[itemID] = every list the item appears on, so a tooltip can
-- answer "is this on a list" without scanning them all.
ns.BiS, ns.BiSIndex = {}, {}

function ns:RegisterBiS(class, spec, phase, lists)
	ns.BiS[class] = ns.BiS[class] or {}
	ns.BiS[class][spec] = ns.BiS[class][spec] or {}
	ns.BiS[class][spec][phase] = lists

	for listKey, list in pairs(lists) do
		for pos = 1, #list do
			local id = list[pos][1]
			ns.BiSIndex[id] = ns.BiSIndex[id] or {}
			tinsert(ns.BiSIndex[id], {
				class = class, spec = spec, phase = phase, list = listKey,
				pos = pos, tier = list[pos][2], count = #list,
			})
		end
	end
end

function ns:BiSLists(class, spec, phase)
	local c = ns.BiS[class]
	local s = c and c[spec]
	return s and s[phase]
end

----------------------------------------------------------------------
-- who the player is
----------------------------------------------------------------------

function ns:PlayerClass()
	local _, class = UnitClass("player")
	return class
end

--- The spec with the most talent points in it, or nil before talents load.
function ns:DetectSpec()
	local info = ns.Classes[ns:PlayerClass()]
	if not info then return nil end

	local group = GetActiveTalentGroup and GetActiveTalentGroup() or 1
	local bestTab, bestPts = nil, 0
	for tab = 1, (GetNumTalentTabs() or 0) do
		local pts = select(3, GetTalentTabInfo(tab, false, false, group)) or 0
		if pts > bestPts then bestTab, bestPts = tab, pts end
	end
	if not bestTab then return nil end

	for i = 1, #info.specs do
		if info.specs[i][2] == bestTab then return info.specs[i][1] end
	end
end

--- The spec the addon is working with: the player's choice if they made one
--- that is valid for this class, otherwise whatever the talents say.
function ns:Spec()
	local chosen = FycoPvECharDB and FycoPvECharDB.spec
	local info = ns.Classes[ns:PlayerClass()]
	if chosen and chosen ~= "auto" and info then
		for i = 1, #info.specs do
			if info.specs[i][1] == chosen then return chosen end
		end
	end
	return ns:DetectSpec() or (info and info.specs[1][1])
end

function ns:SpecIsAuto()
	local chosen = FycoPvECharDB and FycoPvECharDB.spec
	return not chosen or chosen == "auto"
end

function ns:SetSpec(spec)
	FycoPvECharDB.spec = spec or "auto"
	ns:Fire("ProfileChanged")
end

function ns:Phase()
	return ns:Get("general", "phase")
end

function ns:SetPhase(phase)
	ns:Set("general", "phase", phase)
	ns:Fire("ProfileChanged")
end

--- A short "Affliction Warlock, Pre-Raid" for headers and chat.
function ns:ProfileText()
	local class = ns.Classes[ns:PlayerClass()]
	return string.format("%s %s, %s", ns:Spec() or "?", class and class.name or "?",
		ns.PhaseName[ns:Phase()] or ns:Phase())
end

-- talent changes can change the detected spec
local function TalentsChanged()
	if ns:SpecIsAuto() then ns:Fire("ProfileChanged") end
end
ns:On("PLAYER_TALENT_UPDATE", TalentsChanged)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", TalentsChanged)

----------------------------------------------------------------------
-- saved variables + login
----------------------------------------------------------------------

ns:On("PLAYER_LOGIN", function()
	FycoPvEDB = FycoPvEDB or {}
	FycoPvECharDB = FycoPvECharDB or {}
	FycoPvEDB.enabled = FycoPvEDB.enabled or {}
	for k, v in pairs(moduleDefaults) do
		if FycoPvEDB.enabled[k] == nil then FycoPvEDB.enabled[k] = v end
	end

	-- Each OnLoad runs inside a pcall: one broken module costs that module and
	-- says so, instead of aborting this handler and every module after it --
	-- which in FycoPvP once made the whole addon vanish from Interface Options.
	table.sort(ns.moduleOrder, function(a, b) return a.order < b.order end)
	for i = 1, #ns.moduleOrder do
		local m = ns.moduleOrder[i]
		if m.OnLoad then
			local ok, err = pcall(m.OnLoad, m)
			if ok then
				ns:Debug("module loaded:", m.name)
			else
				ns:Print("|cffff4444module '" .. m.name .. "' failed to load:|r " .. tostring(err))
			end
		end
	end

	if ns:Get("general", "loginMessage") then
		ns:Print("v" .. (GetAddOnMetadata(ADDON, "Version") or "?") .. " - " .. ns:ProfileText()
		      .. ". |cffffff00/fpve|r to open.")
	end
end)

----------------------------------------------------------------------
-- slash
----------------------------------------------------------------------

SLASH_FYCOPVE1 = "/fpve"
SLASH_FYCOPVE2 = "/fycopve"

local function MatchPhase(text)
	text = text:lower()
	for i = 1, #ns.Phases do
		local p = ns.Phases[i]
		if p.key:lower() == text or p.name:lower():find(text, 1, true) then return p.key end
	end
end

local function MatchSpec(text)
	text = text:lower()
	if text == "auto" then return "auto" end
	local info = ns.Classes[ns:PlayerClass()]
	for i = 1, #(info and info.specs or {}) do
		if info.specs[i][1]:lower():find(text, 1, true) == 1 then return info.specs[i][1] end
	end
end

SlashCmdList.FYCOPVE = function(input)
	input = input or ""
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		if ns.ToggleWindow then ns:ToggleWindow() end

	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		if ns.OpenOptions then ns:OpenOptions() end

	elseif cmd == "gear" or cmd == "bis" then
		if ns.GearReport then ns:GearReport() else ns:Print("gear module is off") end

	elseif cmd == "find" or cmd == "search" or cmd == "where" then
		if rest == "" then
			ns:Print("usage: |cffffff00/fpve find <item name, slot, boss or zone>|r")
		elseif ns.SearchToChat and ns:Enabled("search") then
			ns:SearchToChat(rest)
		else
			ns:Print("search module is off")
		end

	elseif cmd == "phase" then
		local key = rest ~= "" and MatchPhase(rest)
		if key then
			ns:SetPhase(key)
			ns:Print("phase set to |cffffff00" .. ns.PhaseName[key] .. "|r")
		else
			ns:Print("current phase: |cffffff00" .. (ns.PhaseName[ns:Phase()] or ns:Phase()) .. "|r")
			for i = 1, #ns.Phases do
				ns:Print("  |cffffff00/fpve phase " .. ns.Phases[i].key .. "|r - " .. ns.Phases[i].name)
			end
		end

	elseif cmd == "spec" then
		local spec = rest ~= "" and MatchSpec(rest)
		if spec then
			ns:SetSpec(spec)
			ns:Print("spec: |cffffff00" .. (spec == "auto" and ("auto (" .. (ns:Spec() or "?") .. ")") or spec) .. "|r")
		else
			ns:Print("spec: |cffffff00" .. (ns:Spec() or "?") .. "|r" .. (ns:SpecIsAuto() and " (detected)" or " (chosen)"))
			ns:Print("usage: |cffffff00/fpve spec <name|auto>|r")
		end

	elseif cmd == "minimap" then
		ns:Set("general", "minimap", not ns:Get("general", "minimap"))
		ns:Print("minimap button " .. (ns:Get("general", "minimap") and "shown" or "hidden"))

	elseif cmd == "debug" then
		FycoPvEDB.debug = not FycoPvEDB.debug
		ns:Print("debug " .. (FycoPvEDB.debug and "on" or "off"))

	else
		ns:Print("commands:")
		ns:Print("  |cffffff00/fpve|r            - open the FycoPvE window")
		ns:Print("  |cffffff00/fpve options|r    - open the settings")
		ns:Print("  |cffffff00/fpve gear|r       - BiS check of what you are wearing, in chat")
		ns:Print("  |cffffff00/fpve find <text>|r - where an item comes from (name, slot, boss or zone)")
		ns:Print("  |cffffff00/fpve phase [key]|r - show or set the content phase")
		ns:Print("  |cffffff00/fpve spec [name|auto]|r - show or override your spec")
		ns:Print("  |cffffff00/fpve minimap|r    - show or hide the minimap button")
		ns:Print("  |cffffff00/fpve debug|r      - toggle debug output")
	end
end
