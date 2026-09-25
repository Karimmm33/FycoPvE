--[[ FycoPvE - Modules/Meter.lua
     Damage and healing meter, from the combat log.

     Counts what your group (you, party or raid, and their pets) does:
       Damage done   (and DPS over the fight)
       Healing done  (effective: overhealing is left out)
       Overhealing
       Damage taken
     Each fight is a segment, named after the enemy that took the most
     damage; "Overall" adds every fight since the last reset, and the last
     few fights are kept to look back at.

     3.3.5a facts this relies on:
       - COMBAT_LOG_EVENT_UNFILTERED args are timestamp, event, srcGUID,
         srcName, srcFlags, dstGUID, dstName, dstFlags, then the event's own
         (no hideCaster, no raid flags -- those arrived in 4.x).
       - Absorbs (Power Word: Shield, Sacred Shield) are not in the log as
         healing, so a shield healer's number is lower than their real
         contribution. The settings page says so.                        ]]

local ADDON, ns = ...
local M = ns:Module("meter", 60)

local band = bit.band
local GetTime = GetTime

-- combat log object flags (3.3.5a)
local AFFIL_GROUP = 0x00000007   -- mine | party | raid
local TYPE_PLAYER = 0x00000400
local TYPE_PET = 0x00001000
local TYPE_GUARDIAN = 0x00002000
local REACT_HOSTILE = 0x00000040

local BAR_H, HEADER_H, MAX_BARS = 16, 18, 25
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local MODES = {
	{ key = "damage",   label = "Damage",       perSec = "DPS" },
	{ key = "heal",     label = "Healing",      perSec = "HPS" },
	{ key = "overheal", label = "Overhealing" },
	{ key = "taken",    label = "Damage taken" },
}

local function Opt(key) return ns:Get("meter", key) end

----------------------------------------------------------------------
-- data
----------------------------------------------------------------------

local current            -- the fight in progress, or nil
local overall            -- everything since the last reset
local history = {}       -- finished fights, newest first
local view = 0           -- 0 = current/last fight, -1 = overall, n = history[n]
local modeIndex = 1
local lastActivity = 0

local roster = {}        -- guid -> { name, class } for group members
local owner = {}         -- pet/guardian guid -> owner guid

local function NewSegment(name)
	return { name = name, start = GetTime(), stop = nil, actors = {}, enemies = {} }
end

local function Duration(seg)
	if not seg then return 0 end
	return math.max(1, (seg.stop or GetTime()) - seg.start)
end

--- The bucket for one actor, created on first sight.
local function Actor(seg, guid, name)
	local a = seg.actors[guid]
	if not a then
		local r = roster[guid]
		a = { name = (r and r.name) or name or "?", class = r and r.class,
		      damage = 0, heal = 0, overheal = 0, taken = 0,
		      spells = { damage = {}, heal = {}, overheal = {}, taken = {} } }
		seg.actors[guid] = a
	end
	return a
end

local function Add(guid, name, field, amount, spell)
	if amount <= 0 then return end
	for _, seg in ipairs({ current, overall }) do
		local a = Actor(seg, guid, name)
		a[field] = a[field] + amount
		local s = a.spells[field]
		s[spell] = (s[spell] or 0) + amount
	end
end

----------------------------------------------------------------------
-- who is in the group, and whose pets are whose
----------------------------------------------------------------------

local function GroupUnits()
	local units = {}
	local raid = GetNumRaidMembers() or 0
	if raid > 0 then
		for i = 1, raid do units[#units + 1] = { "raid" .. i, "raidpet" .. i } end
	else
		units[#units + 1] = { "player", "pet" }
		for i = 1, (GetNumPartyMembers() or 0) do units[#units + 1] = { "party" .. i, "partypet" .. i } end
	end
	return units
end

local function UpdateRoster()
	roster = {}
	for _, pair in ipairs(GroupUnits()) do
		local u, pet = pair[1], pair[2]
		local guid = UnitGUID(u)
		if guid then
			local _, class = UnitClass(u)
			roster[guid] = { name = UnitName(u), class = class }
			local pg = UnitExists(pet) and UnitGUID(pet)
			if pg then owner[pg] = guid end
		end
	end
end

local function GroupInCombat()
	for _, pair in ipairs(GroupUnits()) do
		if UnitExists(pair[1]) and UnitAffectingCombat(pair[1]) then return true end
	end
	return false
end

--- The group member an event is credited to: the player, or a pet's owner.
--- nil for anything outside the group.
local function Credit(guid, name, flags)
	if not guid or band(flags or 0, AFFIL_GROUP) == 0 then return nil end
	if band(flags, TYPE_PET + TYPE_GUARDIAN) ~= 0 then
		local o = owner[guid]
		if o and Opt("mergePets") then
			local r = roster[o]
			return o, r and r.name
		end
		return guid, name
	end
	if band(flags, TYPE_PLAYER) ~= 0 then return guid, name end
	return nil
end

----------------------------------------------------------------------
-- segments
----------------------------------------------------------------------

local function StartFight()
	current = NewSegment("Fight")
	view = 0
	lastActivity = GetTime()
end

local function EndFight()
	if not current then return end
	current.stop = lastActivity > current.start and lastActivity or GetTime()
	-- name it after whoever soaked the most damage
	local best, most = nil, 0
	for n, v in pairs(current.enemies) do
		if v > most then best, most = n, v end
	end
	current.name = best or "Fight"
	if next(current.actors) then
		table.insert(history, 1, current)
		while #history > Opt("keepFights") do table.remove(history) end
	end
	current = nil
end

function ns:MeterReset()
	current, history, view = nil, {}, 0
	overall = NewSegment("Overall")
	ns:Fire("MeterChanged")
end

--- The segment the meter is showing.
local function Shown()
	if view == -1 then return overall end
	if view == 0 then return current or history[1] end
	return history[view]
end

-- read-only views, for tests and anything that wants the numbers
ns.MeterShownSegment = Shown
function ns.MeterHistory() return history end
function ns.MeterOverall() return overall end

----------------------------------------------------------------------
-- combat log
----------------------------------------------------------------------

local DAMAGE = {
	SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true,
	ENVIRONMENTAL_DAMAGE = true,
}
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local function OnCombatLog(_, _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if not ns:Enabled("meter") then return end

	if event == "SPELL_SUMMON" then
		-- totems, ghouls, treants: credit them to whoever summoned them
		if band(srcFlags or 0, AFFIL_GROUP) ~= 0 then owner[dstGUID] = owner[srcGUID] or srcGUID end
		return
	end

	if DAMAGE[event] then
		local spell, amount
		if event == "SWING_DAMAGE" then
			spell, amount = "Melee", ...
		elseif event == "ENVIRONMENTAL_DAMAGE" then
			local kind, amt = ...
			spell, amount = kind or "Environment", amt
		else
			local _, name, _, amt = ...
			spell, amount = name or "?", amt
		end
		amount = amount or 0

		local who, whoName = Credit(srcGUID, srcName, srcFlags)
		if who and band(dstFlags or 0, AFFIL_GROUP) == 0 then
			-- a hit from the group on something outside it starts a fight
			if not current then StartFight() end
			lastActivity = GetTime()
			Add(who, whoName, "damage", amount, spell)
			if band(dstFlags or 0, REACT_HOSTILE) ~= 0 and dstName then
				current.enemies[dstName] = (current.enemies[dstName] or 0) + amount
			end
		end
		local victim, victimName = Credit(dstGUID, dstName, dstFlags)
		if victim and current then
			lastActivity = GetTime()
			Add(victim, victimName, "taken", amount, spell)
		end
		return
	end

	if HEAL[event] and current then
		local who, whoName = Credit(srcGUID, srcName, srcFlags)
		if not who then return end
		local _, name, _, amount, over = ...
		amount, over = amount or 0, over or 0
		lastActivity = GetTime()
		Add(who, whoName, "heal", amount - over, name or "?")
		Add(who, whoName, "overheal", over, name or "?")
	end
end

----------------------------------------------------------------------
-- ranking and reporting
----------------------------------------------------------------------

--- { { guid, name, class, value, perSec, share }, ... } highest first.
function ns:MeterRanking(seg, modeKey)
	local out, total = {}, 0
	if not seg then return out, 0 end
	local dur = Duration(seg)
	for guid, a in pairs(seg.actors) do
		local v = a[modeKey] or 0
		if v > 0 then
			out[#out + 1] = { guid = guid, name = a.name, class = a.class, value = v, perSec = v / dur }
			total = total + v
		end
	end
	table.sort(out, function(x, y)
		if x.value ~= y.value then return x.value > y.value end
		return x.name < y.name
	end)
	for i = 1, #out do out[i].share = total > 0 and out[i].value / total or 0 end
	return out, total
end

local function Short(v)
	if v >= 1000000 then return string.format("%.2fm", v / 1000000) end
	if v >= 1000 then return string.format("%.1fk", v / 1000) end
	return tostring(math.floor(v + 0.5))
end
ns.MeterShort = Short

local function Clock(sec)
	sec = math.floor(sec + 0.5)
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function SegmentLabel(seg)
	if not seg then return "no fights yet" end
	if seg == overall then return "Overall" end
	return (seg == current and "* " or "") .. seg.name .. " (" .. Clock(Duration(seg)) .. ")"
end

--- Send the top `lines` of the shown mode to a chat channel.
function ns:MeterReport(channel, lines)
	channel = channel or Opt("reportChannel")
	lines = lines or Opt("reportLines")
	local mode = MODES[modeIndex]
	local seg = Shown()
	local list = ns:MeterRanking(seg, mode.key)
	if #list == 0 then
		ns:Print("nothing to report yet")
		return
	end
	if channel == "RAID" and (GetNumRaidMembers() or 0) == 0 then channel = "PARTY" end
	if channel == "PARTY" and (GetNumPartyMembers() or 0) == 0 then channel = "SAY" end
	SendChatMessage("FycoPvE " .. mode.label .. " - " .. SegmentLabel(seg):gsub("^%* ", ""), channel)
	for i = 1, math.min(lines, #list) do
		local e = list[i]
		local rate = mode.perSec and string.format(" (%s %s)", Short(e.perSec), mode.perSec) or ""
		SendChatMessage(string.format("%d. %s  %s%s  %d%%", i, e.name, Short(e.value), rate,
			math.floor(e.share * 100 + 0.5)), channel)
	end
end

----------------------------------------------------------------------
-- the meter frame
----------------------------------------------------------------------

local frame, title, bars = nil, nil, {}
local offset, unlocked, testMode = 0, false, false

local TEST_NAMES = {
	{ "Tankadin", "PALADIN" }, { "Stabsalot", "ROGUE" }, { "Frostbolt", "MAGE" },
	{ "Dotsndots", "WARLOCK" }, { "Healbot", "PRIEST" }, { "Moonfire", "DRUID" },
}

local function FillTest()
	current = nil
	history = {}
	local seg = NewSegment("Test Dummy")
	seg.start = GetTime() - 90
	seg.stop = GetTime()
	for i, t in ipairs(TEST_NAMES) do
		local guid = "test" .. i
		roster[guid] = { name = t[1], class = t[2] }
		local a = Actor(seg, guid, t[1])
		a.damage = (7 - i) * 120000 + i * 3100
		a.heal = (t[2] == "PRIEST" or t[2] == "DRUID") and 450000 - i * 1000 or i * 2000
		a.overheal = math.floor(a.heal / 4)
		a.taken = (t[2] == "PALADIN") and 600000 or i * 15000
		a.spells.damage = { ["Test Strike"] = a.damage * 0.6, ["Test Bolt"] = a.damage * 0.4 }
	end
	history[1] = seg
	view = 0
end

local function ClassColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.55, 0.55, 0.55
end

local function Layout()
	if not frame then return end
	local w, n = Opt("width"), Opt("bars")
	frame:SetWidth(w)
	frame:SetHeight(HEADER_H + n * BAR_H + 6)
	frame:SetScale(Opt("scale"))
	for i = 1, MAX_BARS do bars[i]:SetWidth(w - 8) end
end

local function Draw()
	local mode = MODES[modeIndex]
	local seg = Shown()
	local list, total = ns:MeterRanking(seg, mode.key)
	local n = Opt("bars")
	offset = math.max(0, math.min(offset, #list - n))

	title:SetText(string.format("%s: |cffffffff%s|r", mode.label, SegmentLabel(seg)))
	local top = list[1] and list[1].value or 1
	for i = 1, MAX_BARS do
		local b, e = bars[i], list[i + offset]
		if i <= n and e then
			b.entry = e
			b:SetValue(e.value / top * 100)
			b:SetStatusBarColor(ClassColor(e.class))
			b.name:SetText((i + offset) .. ". " .. e.name)
			local rate = mode.perSec and (" |cffc0c0c0(" .. Short(e.perSec) .. ")|r") or ""
			b.value:SetText(Short(e.value) .. rate .. string.format(" |cffa0a0a0%d%%|r", math.floor(e.share * 100 + 0.5)))
			b:Show()
		else
			b.entry = nil
			b:Hide()
		end
	end
	return total
end

local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ns:Set("meter", "pos", { point, relPoint, x, y })
end

local function CycleMode(step)
	modeIndex = (modeIndex - 1 + step) % #MODES + 1
	offset = 0
end

--- Current -> Overall -> older fights -> back to current.
local function CycleSegment()
	if view == 0 then view = -1
	elseif view == -1 then view = (#history > 1) and 2 or 0
	elseif view < #history then view = view + 1
	else view = 0 end
	offset = 0
end

local function BarTooltip(self)
	local e = self.entry
	if not e then return end
	local seg = Shown()
	local a = seg and seg.actors[e.guid]
	local mode = MODES[modeIndex]
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(e.name)
	GameTooltip:AddDoubleLine(mode.label, Short(e.value), 1, 1, 1, 1, 1, 1)
	if mode.perSec then GameTooltip:AddDoubleLine(mode.perSec, Short(e.perSec), 1, 1, 1, 1, 1, 1) end
	if a then
		local spells = {}
		for name, v in pairs(a.spells[mode.key] or {}) do spells[#spells + 1] = { name, v } end
		table.sort(spells, function(x, y) return x[2] > y[2] end)
		for i = 1, math.min(6, #spells) do
			GameTooltip:AddDoubleLine("  " .. spells[i][1],
				string.format("%s  %d%%", Short(spells[i][2]), math.floor(spells[i][2] / e.value * 100 + 0.5)),
				0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
		end
	end
	GameTooltip:Show()
end

local function Build()
	frame = CreateFrame("Frame", "FycoPvEMeter", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.55)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		Draw()
	end)

	local p = Opt("pos")
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 180)
	end

	-- the header is the control: left-click mode, right-click fight, shift-click report
	local head = CreateFrame("Button", "FycoPvEMeterHeader", frame)
	head:SetHeight(HEADER_H)
	head:SetPoint("TOPLEFT", 3, -1)
	head:SetPoint("TOPRIGHT", -3, -1)
	head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	head:SetScript("OnClick", function(_, button)
		if IsShiftKeyDown() then
			ns:MeterReport()
		elseif button == "RightButton" then
			CycleSegment()
		else
			CycleMode(1)
		end
		Draw()
	end)
	head:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("FycoPvE meter")
		GameTooltip:AddLine("|cffffff00Left-click|r  next mode", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffff00Right-click|r  current / overall / older fights", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffff00Shift-click|r  report to " .. Opt("reportChannel"):lower(), 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffff00Mouse wheel|r  scroll", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	head:SetScript("OnLeave", function() GameTooltip:Hide() end)

	title = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("LEFT", 4, -2)
	title:SetPoint("RIGHT", -4, -2)
	title:SetJustifyH("LEFT")

	for i = 1, MAX_BARS do
		local b = CreateFrame("StatusBar", nil, frame)
		b:SetHeight(BAR_H - 1)
		b:SetPoint("TOPLEFT", 4, -HEADER_H - 2 - (i - 1) * BAR_H)
		b:SetStatusBarTexture(TEXTURE)
		b:SetMinMaxValues(0, 100)
		b:EnableMouse(true)
		b:SetScript("OnEnter", BarTooltip)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.name:SetPoint("LEFT", 3, 0)
		b.name:SetJustifyH("LEFT")
		b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.value:SetPoint("RIGHT", -3, 0)
		b:Hide()
		bars[i] = b
	end

	Layout()
	frame:Hide()
end

local function ShouldShow()
	if not ns:Enabled("meter") then return false end
	if unlocked or testMode then return true end
	if Opt("hideOutOfCombat") and not current then return false end
	if Opt("groupOnly") and (GetNumPartyMembers() or 0) == 0 and (GetNumRaidMembers() or 0) == 0 then
		return false
	end
	return Shown() ~= nil or Opt("showEmpty")
end

----------------------------------------------------------------------
-- controls
----------------------------------------------------------------------

function ns:MeterUnlock(on)
	if on == nil then on = not unlocked end
	unlocked = on
	ns:Print("meter " .. (on and "|cff40ff40unlocked|r - drag it, then lock it again" or "locked"))
end

function ns:MeterTest(on)
	if on == nil then on = not testMode end
	testMode = on
	if on then FillTest() else ns:MeterReset() end
	ns:Print("meter test data " .. (on and "on" or "off"))
end

function ns:MeterResetPosition()
	ns:Set("meter", "pos", nil)
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 180)
	end
end

function ns:MeterMode(key)
	for i = 1, #MODES do
		if MODES[i].key == key then modeIndex = i return true end
	end
end

function M:OnLoad()
	overall = NewSegment("Overall")
	Build()
	UpdateRoster()

	ns:On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)
	for _, e in ipairs({ "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
		ns:On(e, UpdateRoster)
	end

	-- a new dungeon or raid starts from zero, if the player wants that
	local lastZone
	ns:On("PLAYER_ENTERING_WORLD", function()
		local inInstance, kind = IsInInstance()
		local zone = inInstance and (GetRealZoneText() or kind) or nil
		if zone and zone ~= lastZone and Opt("resetOnInstance") and not testMode then ns:MeterReset() end
		lastZone = zone
	end)

	-- a fight ends a moment after the whole group has left combat
	local acc, calmSince = 0, nil
	ns:OnTick(function(now)
		acc = acc + 1
		if acc < 5 then return end   -- 2 Hz
		acc = 0
		if current then
			if GroupInCombat() then
				calmSince = nil
			else
				calmSince = calmSince or now
				if now - calmSince >= 2 then
					EndFight()
					calmSince = nil
				end
			end
		end
		if ShouldShow() then
			frame:Show()
			Draw()
		else
			frame:Hide()
		end
	end)

	ns:Subscribe("SettingChanged", function(section)
		if section == "meter" then Layout() end
	end)
end

----------------------------------------------------------------------
-- settings panel
----------------------------------------------------------------------

local CHANNELS = {
	{ value = "PARTY", text = "Party" }, { value = "RAID", text = "Raid" },
	{ value = "SAY", text = "Say" }, { value = "GUILD", text = "Guild" },
}

ns:RegisterOptions("meter", "Meter", 50, function(L, R)
	L:Title("Damage and healing meter")
	L:Note("What your group did in each fight, from the combat log. Click the "
	    .. "meter's title: left for the next mode, right for the next fight, "
	    .. "shift to report.")
	L:Check("Show the meter", nil,
		function() return FycoPvEDB.enabled.meter ~= false end,
		function(v)
			FycoPvEDB.enabled.meter = v
			ns:Fire("SettingChanged", "enabled", "meter", v)
		end)
	L:Check("Only in a group", nil,
		function() return Opt("groupOnly") end, function(v) ns:Set("meter", "groupOnly", v) end)
	L:Check("Hide out of combat", nil,
		function() return Opt("hideOutOfCombat") end, function(v) ns:Set("meter", "hideOutOfCombat", v) end)
	L:Check("Count pets as their owner", "Pets, totems, ghouls and treants are added to whoever summoned them",
		function() return Opt("mergePets") end, function(v) ns:Set("meter", "mergePets", v) end)
	L:Check("Reset in each new dungeon or raid", nil,
		function() return Opt("resetOnInstance") end, function(v) ns:Set("meter", "resetOnInstance", v) end)
	L:Slider("Fights to keep", 1, 30, 1,
		function() return Opt("keepFights") end, function(v) ns:Set("meter", "keepFights", v) end)
	L:Gap(4)
	L:Buttons("Unlock / lock", function() ns:MeterUnlock() end,
	          "Test data", function() ns:MeterTest() end)
	L:Buttons("Reset data", function() ns:MeterReset() end,
	          "Reset position", function() ns:MeterResetPosition() end)

	R:Title("Look")
	R:Slider("Bars shown", 3, MAX_BARS, 1,
		function() return Opt("bars") end, function(v) ns:Set("meter", "bars", v) end)
	R:Slider("Width", 150, 400, 10,
		function() return Opt("width") end, function(v) ns:Set("meter", "width", v) end)
	R:Slider("Scale", 0.6, 1.6, 0.05,
		function() return Opt("scale") end, function(v) ns:Set("meter", "scale", v) end)

	R:Gap(6)
	R:Title("Report")
	R:Dropdown("Channel", 120, {
		items = function() return CHANNELS end,
		get = function() return Opt("reportChannel") end,
		set = function(v) ns:Set("meter", "reportChannel", v) end,
	})
	R:Slider("Lines", 1, 15, 1,
		function() return Opt("reportLines") end, function(v) ns:Set("meter", "reportLines", v) end)
	R:Button("Report now", function() ns:MeterReport() end, 150)
	R:Note("Absorbs (Power Word: Shield and similar) are not in the 3.3.5 combat log "
	    .. "as healing, so shield healers show less than they really did.")
end)
