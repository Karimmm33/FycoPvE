--[[ FycoPvE - Modules/Threat.lua
     Threat meter: how close everyone in your group is to pulling your target.

     One bar per group member (and pets), sorted highest first, from the
     client's own threat numbers (UnitDetailedThreatSituation, 3.3.5a). The
     percentage is the game's "scaled" one: 100% is the point where you take
     aggro, so it already allows for the 110% melee / 130% ranged rule.

     When YOUR threat passes the warning threshold and you are not the one
     tanking, a large warning shows in the middle of the screen, optionally
     with a sound, so you can stop before you pull.

     Nothing here is guessed: with no hostile target, or when the client
     reports no threat data (out of combat), the meter simply hides.    ]]

local ADDON, ns = ...
local M = ns:Module("threat", 50)

local BAR_H, HEADER_H, MAX_BARS = 16, 18, 10
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local WARN_SOUND = "Sound\\Interface\\RaidWarning.wav"

local frame, title, warn
local bars = {}
local unlocked, testMode = false, false
local lastWarn, warnUntil = 0, 0

local function Opt(key) return ns:Get("threat", key) end

----------------------------------------------------------------------
-- reading threat
----------------------------------------------------------------------

--- Every unit worth asking about: the raid, or the party and you, plus pets.
local function GroupUnits()
	local units = {}
	local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
	local pets = Opt("pets")
	if raid > 0 then
		for i = 1, raid do
			units[#units + 1] = "raid" .. i
			if pets then units[#units + 1] = "raidpet" .. i end
		end
	else
		units[#units + 1] = "player"
		if pets then units[#units + 1] = "pet" end
		for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
			units[#units + 1] = "party" .. i
			if pets then units[#units + 1] = "partypet" .. i end
		end
	end
	return units
end

local function Grouped()
	return (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
end

--- The mob to measure against: your target if you can attack it, else (when
--- allowed) your target's target -- so a healer targeting the tank still
--- sees the threat on the tank's mob.
local function Mob()
	if UnitExists("target") and UnitCanAttack("player", "target") then return "target" end
	if Opt("targetOfTarget") and UnitExists("targettarget") and UnitCanAttack("player", "targettarget") then
		return "targettarget"
	end
end

--- { name, class, pct, value, tanking, me } for everyone with threat, highest first.
function ns:ThreatList(mob)
	local list, seen = {}, {}
	local units = GroupUnits()
	for i = 1, #units do
		local u = units[i]
		local guid = UnitExists(u) and UnitGUID(u)
		if guid and not seen[guid] then
			seen[guid] = true
			local tanking, _, scaled, _, value = UnitDetailedThreatSituation(u, mob)
			if tanking or (value and value > 0) then
				local _, class = UnitClass(u)
				list[#list + 1] = {
					name = UnitName(u) or "?", class = class, pct = scaled or 0,
					-- the client reports threat x100
					value = (value or 0) / 100, tanking = tanking and true or false,
					me = UnitIsUnit(u, "player") and true or false,
				}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.pct ~= b.pct then return a.pct > b.pct end
		return a.value > b.value
	end)
	return list
end

local TEST = {
	{ name = "Tankadin", class = "PALADIN", pct = 100, value = 52300, tanking = true },
	{ name = UnitName("player") or "You", class = "WARLOCK", pct = 92, value = 48100, me = true },
	{ name = "Stabsalot", class = "ROGUE", pct = 71, value = 37200 },
	{ name = "Frostbolt", class = "MAGE", pct = 55, value = 28800 },
	{ name = "Healbot", class = "PRIEST", pct = 12, value = 6400 },
}

----------------------------------------------------------------------
-- frame
----------------------------------------------------------------------

local function ShortNumber(v)
	if v >= 1000000 then return string.format("%.1fm", v / 1000000) end
	if v >= 1000 then return string.format("%.1fk", v / 1000) end
	return tostring(math.floor(v))
end

local function ClassColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ns:Set("threat", "pos", { point, relPoint, x, y })
end

local function Layout()
	local w = Opt("width")
	frame:SetWidth(w)
	frame:SetHeight(HEADER_H + Opt("bars") * BAR_H + 6)
	frame:SetScale(Opt("scale"))
	for i = 1, MAX_BARS do
		bars[i]:SetWidth(w - 8)
	end
end

local function Build()
	frame = CreateFrame("Frame", "FycoPvEThreat", UIParent)
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
	frame:EnableMouse(false)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	local p = Opt("pos")
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, -120)
	end

	title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 6, -5)
	title:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
	title:SetJustifyH("LEFT")

	for i = 1, MAX_BARS do
		local b = CreateFrame("StatusBar", nil, frame)
		b:SetHeight(BAR_H - 1)
		b:SetPoint("TOPLEFT", 4, -HEADER_H - (i - 1) * BAR_H)
		b:SetStatusBarTexture(TEXTURE)
		b:SetMinMaxValues(0, 100)
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.name:SetPoint("LEFT", 3, 0)
		b.name:SetJustifyH("LEFT")
		b.pct = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.pct:SetPoint("RIGHT", -3, 0)
		b:Hide()
		bars[i] = b
	end

	-- the pull warning, big and central
	warn = UIParent:CreateFontString("FycoPvEThreatWarning", "OVERLAY", "GameFontNormalHuge")
	warn:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
	warn:SetTextColor(1, 0.15, 0.1)
	warn:Hide()

	Layout()
	frame:Hide()
end

local function Draw(list, mobName)
	local n = math.min(#list, Opt("bars"))
	title:SetText("Threat" .. (mobName and (": |cffffffff" .. mobName .. "|r") or ""))
	for i = 1, MAX_BARS do
		local b, e = bars[i], list[i]
		if i <= n and e then
			b:SetValue(math.min(e.pct, 100))
			b:SetStatusBarColor(ClassColor(e.class))
			b:SetAlpha(e.me and 1 or 0.85)
			b.name:SetText((e.tanking and "|cffffd200[T]|r " or "") .. (e.me and ("> " .. e.name) or e.name))
			b.pct:SetText(string.format("%d%%  |cffc0c0c0%s|r", math.floor(e.pct + 0.5), ShortNumber(e.value)))
			b:Show()
		else
			b:Hide()
		end
	end
end

local function Warn(list)
	if not Opt("warn") then return end
	if not (testMode or Grouped() or Opt("warnSolo")) then return end
	for i = 1, #list do
		local e = list[i]
		if e.me and not e.tanking and e.pct >= Opt("warnAt") then
			local now = GetTime()
			warn:SetText(string.format("THREAT %d%%", math.floor(e.pct + 0.5)))
			warn:Show()
			warnUntil = now + 1.5
			if Opt("warnSound") and now - lastWarn > 3 then
				lastWarn = now
				PlaySoundFile(WARN_SOUND)
			end
			return
		end
	end
end

local function Update(now)
	if not frame then return end
	if warn:IsShown() and now > warnUntil then warn:Hide() end

	if not ns:Enabled("threat") then
		frame:Hide()
		return
	end
	if testMode or unlocked then
		frame:Show()
		Draw(TEST, "Test Dummy")
		if testMode then Warn(TEST) end
		return
	end

	local mob = Mob()
	local show = mob
		and (not Opt("groupOnly") or Grouped())
		and (not Opt("combatOnly") or UnitAffectingCombat("player"))
	local list = show and ns:ThreatList(mob)
	if not (list and #list > 0) then
		frame:Hide()
		return
	end
	frame:Show()
	Draw(list, UnitName(mob))
	Warn(list)
end

----------------------------------------------------------------------
-- controls
----------------------------------------------------------------------

function ns:ThreatUnlock(on)
	if on == nil then on = not unlocked end
	unlocked = on
	if frame then frame:EnableMouse(on) end
	ns:Print("threat meter " .. (on and "|cff40ff40unlocked|r - drag it, then lock it again" or "locked"))
end

function ns:ThreatTest(on)
	if on == nil then on = not testMode end
	testMode = on
	ns:Print("threat test bars " .. (on and "on" or "off"))
end

function ns:ThreatReset()
	ns:Set("threat", "pos", nil)
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, -120)
	end
end

function M:OnLoad()
	Build()
	local acc = 0
	ns:OnTick(function(now)
		acc = acc + 1
		if acc < 2 then return end   -- 5 Hz is plenty for threat
		acc = 0
		Update(now)
	end)
	ns:Subscribe("SettingChanged", function(section)
		if section == "threat" and frame then Layout() end
	end)
end

----------------------------------------------------------------------
-- settings panel
----------------------------------------------------------------------

ns:RegisterOptions("threat", "Threat", 40, function(L, R)
	L:Title("Threat meter")
	L:Note("Everyone's threat on your target, from the game's own numbers. 100% is "
	    .. "the point where you pull aggro.")
	L:Check("Show the threat meter", nil,
		function() return FycoPvEDB.enabled.threat ~= false end,
		function(v)
			FycoPvEDB.enabled.threat = v
			ns:Fire("SettingChanged", "enabled", "threat", v)
		end)
	L:Check("Only in a group", nil,
		function() return Opt("groupOnly") end, function(v) ns:Set("threat", "groupOnly", v) end)
	L:Check("Only in combat", nil,
		function() return Opt("combatOnly") end, function(v) ns:Set("threat", "combatOnly", v) end)
	L:Check("Include pets", nil,
		function() return Opt("pets") end, function(v) ns:Set("threat", "pets", v) end)
	L:Check("Use target's target for a friend", "When you target a friendly player, "
	     .. "measure the mob they are targeting",
		function() return Opt("targetOfTarget") end, function(v) ns:Set("threat", "targetOfTarget", v) end)
	L:Gap(6)
	L:Buttons("Unlock / lock", function() ns:ThreatUnlock() end,
	          "Test bars", function() ns:ThreatTest() end)
	L:Button("Reset position", function() ns:ThreatReset() end, 150)

	R:Title("Look")
	R:Slider("Bars shown", 3, MAX_BARS, 1,
		function() return Opt("bars") end, function(v) ns:Set("threat", "bars", v) end)
	R:Slider("Width", 120, 320, 10,
		function() return Opt("width") end, function(v) ns:Set("threat", "width", v) end)
	R:Slider("Scale", 0.6, 1.6, 0.05,
		function() return Opt("scale") end, function(v) ns:Set("threat", "scale", v) end)

	R:Gap(6)
	R:Title("Pull warning")
	R:Check("Warn before I pull aggro", nil,
		function() return Opt("warn") end, function(v) ns:Set("threat", "warn", v) end)
	R:Slider("Warn at %", 50, 100, 5,
		function() return Opt("warnAt") end, function(v) ns:Set("threat", "warnAt", v) end)
	R:Check("Play a sound", nil,
		function() return Opt("warnSound") end, function(v) ns:Set("threat", "warnSound", v) end)
	R:Check("Warn when solo too", nil,
		function() return Opt("warnSolo") end, function(v) ns:Set("threat", "warnSolo", v) end)
end)
