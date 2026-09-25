--[[ FycoPvE - Modules/Bosses.lua
     Boss alerts that never guess.

     Hand-written boss timers are only as good as whoever typed them, and a
     wrong timer is worse than none. So everything here comes from what the
     game reports, or from what this addon has measured itself:

       Cast alerts    a boss starts casting -> the spell's name, big, mid-screen
       On YOU         a boss puts a debuff on you -> red alert and a sound
       Learned timers every ability a boss uses is timed; from the next pull
                      on, bars count down to when it came last time
                      ("~ Frost Breath 12s"). Saved between sessions, averaged
                      over every pull, so they sharpen as you go.

     A "boss" is anything the client reports as a boss or world boss (the
     boss1-4 units, or a target classified "worldboss"), plus, if chosen,
     elite targets in dungeons.                                            ]]

local ADDON, ns = ...
local M = ns:Module("bosses", 70)

local band = bit.band
local TYPE_NPC = 0x00000800
local REACT_HOSTILE = 0x00000040

local BAR_H, MAX_BARS = 16, 8
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local SOUND_ALERT = "Sound\\Interface\\RaidWarning.wav"
local SOUND_ON_YOU = "Sound\\Interface\\AlarmClockWarning3.wav"

-- a spell cast faster than this, or more often than this, is noise, not a timer
local MIN_INTERVAL, MAX_CASTS = 4, 40

local function Opt(key) return ns:Get("bosses", key) end

----------------------------------------------------------------------
-- the encounter
----------------------------------------------------------------------

local fight          -- { boss, pull, bosses = {name=true}, casts = {spell={times}}, next = {spell=time} }
local playerGUID

local function Learned(boss)
	FycoPvEDB.bossTimers = FycoPvEDB.bossTimers or {}
	return FycoPvEDB.bossTimers[boss]
end

--- The boss we can see right now, if any.
local function VisibleBoss()
	for i = 1, 4 do
		local u = "boss" .. i
		if UnitExists(u) and not UnitIsDead(u) then return UnitName(u) end
	end
	for _, u in ipairs({ "target", "focus", "targettarget" }) do
		if UnitExists(u) and UnitCanAttack("player", u) and not UnitIsDead(u) then
			local c = UnitClassification(u)
			if c == "worldboss" or (c == "elite" and Opt("elites") and IsInInstance()) then
				return UnitName(u)
			end
		end
	end
end

local function Start(boss)
	fight = { boss = boss, pull = GetTime(), bosses = { [boss] = true }, casts = {}, next = {} }
	-- seed the countdowns from what earlier pulls taught us
	local learned = Opt("timers") and Learned(boss)
	if learned then
		for spell, t in pairs(learned) do
			if t.first then fight.next[spell] = fight.pull + t.first end
		end
	end
	ns:Debug("encounter start:", boss)
end

--- Fold this pull's timings into the saved averages.
local function Learn()
	if not (fight and Opt("timers")) then return end
	FycoPvEDB.bossTimers = FycoPvEDB.bossTimers or {}
	local store = FycoPvEDB.bossTimers[fight.boss] or {}
	for spell, times in pairs(fight.casts) do
		if #times <= MAX_CASTS then
			local t = store[spell] or { n = 0 }
			local first = times[1] - fight.pull
			local gaps, sum = 0, 0
			for i = 2, #times do
				local g = times[i] - times[i - 1]
				if g >= MIN_INTERVAL then gaps, sum = gaps + 1, sum + g end
			end
			local n = t.n
			t.first = ((t.first or first) * n + first) / (n + 1)
			if gaps > 0 then
				local avg = sum / gaps
				t.interval = t.interval and ((t.interval * n + avg) / (n + 1)) or avg
			end
			t.n = n + 1
			store[spell] = t
		end
	end
	FycoPvEDB.bossTimers[fight.boss] = store
end

local function Stop()
	if not fight then return end
	Learn()
	ns:Debug("encounter end:", fight.boss)
	fight = nil
end

----------------------------------------------------------------------
-- alerts
----------------------------------------------------------------------

local alert, alertUntil = nil, 0
local lastSound = 0

local function Alert(text, r, g, b, sound)
	alert:SetText(text)
	alert:SetTextColor(r, g, b)
	alert:Show()
	alertUntil = GetTime() + Opt("alertSeconds")
	if sound and Opt("sound") and GetTime() - lastSound > 1 then
		lastSound = GetTime()
		PlaySoundFile(sound)
	end
end

local function Recorded(spell, now)
	local list = fight.casts[spell] or {}
	list[#list + 1] = now
	fight.casts[spell] = list
	-- restart this ability's countdown from the interval learned so far
	local learned = Learned(fight.boss)
	local t = learned and learned[spell]
	if Opt("timers") and t and t.interval then
		fight.next[spell] = now + t.interval
	else
		fight.next[spell] = nil
	end
end

local function OnCombatLog(_, _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if not (fight and ns:Enabled("bosses")) then return end
	local hostileNPC = band(srcFlags or 0, TYPE_NPC) ~= 0 and band(srcFlags or 0, REACT_HOSTILE) ~= 0
	if not hostileNPC then
		if event == "UNIT_DIED" and dstName and fight.bosses[dstName] then Stop() end
		return
	end
	local fromBoss = fight.bosses[srcName]
	local now = GetTime()

	if event == "SPELL_CAST_START" and fromBoss then
		local _, spell = ...
		Recorded(spell, now)
		if Opt("casts") then Alert(srcName .. ": " .. spell, 1, 0.6, 0.1, SOUND_ALERT) end

	elseif event == "SPELL_CAST_SUCCESS" and fromBoss then
		local _, spell = ...
		-- instant casts have no CAST_START; count them once, here
		local list = fight.casts[spell]
		if not (list and now - list[#list] < 1) then Recorded(spell, now) end

	elseif event == "SPELL_AURA_APPLIED" and dstGUID == playerGUID and Opt("onYou") then
		local _, spell, _, auraType = ...
		if auraType == "DEBUFF" then
			Alert(spell .. " on YOU", 1, 0.1, 0.1, SOUND_ON_YOU)
		end
	end
end

----------------------------------------------------------------------
-- timer bars
----------------------------------------------------------------------

local frame, bars = nil, {}
local unlocked, testMode = false, false

local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ns:Set("bosses", "pos", { point, relPoint, x, y })
end

local function Build()
	frame = CreateFrame("Frame", "FycoPvEBossBars", UIParent)
	frame:SetWidth(220)
	frame:SetHeight(MAX_BARS * BAR_H + 4)
	frame:SetClampedToScreen(true)
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
		frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
	end

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints(frame)
	frame.bg:SetTexture(0, 0, 0, 0.4)
	frame.bg:Hide()

	for i = 1, MAX_BARS do
		local b = CreateFrame("StatusBar", nil, frame)
		b:SetHeight(BAR_H - 1)
		b:SetWidth(216)
		b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * BAR_H)
		b:SetStatusBarTexture(TEXTURE)
		b:SetStatusBarColor(0.9, 0.5, 0.1)
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.name:SetPoint("LEFT", 3, 0)
		b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.time:SetPoint("RIGHT", -3, 0)
		b:Hide()
		bars[i] = b
	end

	alert = UIParent:CreateFontString("FycoPvEBossAlert", "OVERLAY", "GameFontNormalHuge")
	alert:SetPoint("CENTER", UIParent, "CENTER", 0, 240)
	alert:Hide()

	frame:SetScale(Opt("scale"))
	frame:Hide()
end

local TEST = { { "Frost Breath", 6 }, { "Blistering Cold", 14 }, { "Air Phase", 38 } }

local function DrawBars(now)
	local rows = {}
	if testMode then
		for i, t in ipairs(TEST) do
			rows[i] = { spell = t[1], left = t[2] - (now % t[2]), interval = t[2] }
		end
	elseif fight then
		local learned = Learned(fight.boss) or {}
		for spell, at in pairs(fight.next) do
			local left = at - now
			if left > -2 then
				local t = learned[spell] or {}
				rows[#rows + 1] = { spell = spell, left = left, interval = t.interval or t.first or 30 }
			end
		end
	end
	table.sort(rows, function(a, b) return a.left < b.left end)

	local n = math.min(#rows, Opt("bars"))
	for i = 1, MAX_BARS do
		local b, r = bars[i], rows[i]
		if i <= n and r then
			b:SetMinMaxValues(0, r.interval)
			b:SetValue(math.max(0, r.interval - r.left))
			b.name:SetText("~ " .. r.spell)
			b.time:SetText(r.left > 0 and string.format("%.0f", r.left) or "now")
			b:Show()
		else
			b:Hide()
		end
	end
	return n
end

local function Update(now)
	if alert:IsShown() and now > alertUntil then alert:Hide() end
	if not ns:Enabled("bosses") then
		frame:Hide()
		return
	end

	-- start when a boss shows up while the group fights; stop when it is over
	if not fight then
		local boss = UnitAffectingCombat("player") and VisibleBoss()
		if boss then Start(boss) end
	else
		for i = 1, 4 do
			local u = "boss" .. i
			if UnitExists(u) then fight.bosses[UnitName(u)] = true end
		end
		if not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player") then Stop() end
	end

	local n = DrawBars(now)
	if unlocked then frame.bg:Show() else frame.bg:Hide() end
	if n > 0 or unlocked then frame:Show() else frame:Hide() end
end

----------------------------------------------------------------------
-- controls
----------------------------------------------------------------------

function ns:BossUnlock()
	unlocked = not unlocked
	frame:EnableMouse(unlocked)
	ns:Print("boss timer bars " .. (unlocked and "|cff40ff40unlocked|r - drag them, then lock again" or "locked"))
end

function ns:BossTest()
	testMode = not testMode
	if testMode then Alert("Sapphiron: Frost Breath", 1, 0.6, 0.1, SOUND_ALERT) end
	ns:Print("boss test " .. (testMode and "on" or "off"))
end

function ns:BossForget(boss)
	FycoPvEDB.bossTimers = FycoPvEDB.bossTimers or {}
	if boss and boss ~= "" then
		local found
		for name in pairs(FycoPvEDB.bossTimers) do
			if name:lower() == boss:lower() then found = name end
		end
		if found then FycoPvEDB.bossTimers[found] = nil end
		ns:Print(found and ("forgot the timers learned for " .. found) or ("no timers learned for " .. boss))
	else
		FycoPvEDB.bossTimers = {}
		ns:Print("forgot every learned boss timer")
	end
end

--- /fpve boss list
function ns:BossList()
	local names = {}
	for name, spells in pairs(FycoPvEDB.bossTimers or {}) do
		local n, pulls = 0, 0
		for _, t in pairs(spells) do
			n = n + 1
			if t.n > pulls then pulls = t.n end
		end
		names[#names + 1] = string.format("%s |cff808080(%d abilities, %d pull%s)|r", name, n, pulls, pulls == 1 and "" or "s")
	end
	table.sort(names)
	if #names == 0 then
		ns:Print("no boss timers learned yet - they are recorded the first time you fight each boss")
		return
	end
	ns:Print("learned boss timers:")
	for i = 1, #names do ns:Print("  " .. names[i]) end
end

function M:OnLoad()
	playerGUID = UnitGUID("player")
	Build()
	ns:On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)
	ns:On("PLAYER_REGEN_ENABLED", function()
		if fight and not UnitIsDeadOrGhost("player") then Stop() end
	end)
	local acc = 0
	ns:OnTick(function(now)
		acc = acc + 1
		if acc < 2 then return end
		acc = 0
		Update(now)
	end)
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "bosses" and key == "scale" then frame:SetScale(Opt("scale")) end
	end)
end

----------------------------------------------------------------------
-- settings panel
----------------------------------------------------------------------

ns:RegisterOptions("bosses", "Boss alerts", 60, function(L, R)
	L:Title("Boss alerts")
	L:Note("Nothing here is typed in by hand. Alerts come straight from the combat "
	    .. "log, and timers are measured by FycoPvE itself on every pull, so the "
	    .. "first time you fight a boss there are no timer bars yet.")
	L:Check("Boss alerts on", nil,
		function() return FycoPvEDB.enabled.bosses ~= false end,
		function(v)
			FycoPvEDB.enabled.bosses = v
			ns:Fire("SettingChanged", "enabled", "bosses", v)
		end)
	L:Check("Announce boss casts", "When a boss starts casting, show its name mid-screen",
		function() return Opt("casts") end, function(v) ns:Set("bosses", "casts", v) end)
	L:Check("Warn when a boss debuffs me", "\"<debuff> on YOU\" with an alarm",
		function() return Opt("onYou") end, function(v) ns:Set("bosses", "onYou", v) end)
	L:Check("Play sounds", nil,
		function() return Opt("sound") end, function(v) ns:Set("bosses", "sound", v) end)
	L:Check("Treat dungeon elites as bosses", "Off: only real bosses (boss frames, skull-level)",
		function() return Opt("elites") end, function(v) ns:Set("bosses", "elites", v) end)
	L:Slider("Alert seconds", 1, 6, 0.5,
		function() return Opt("alertSeconds") end, function(v) ns:Set("bosses", "alertSeconds", v) end)

	R:Title("Learned timers")
	R:Check("Learn and show timers", nil,
		function() return Opt("timers") end, function(v) ns:Set("bosses", "timers", v) end)
	R:Slider("Bars shown", 1, MAX_BARS, 1,
		function() return Opt("bars") end, function(v) ns:Set("bosses", "bars", v) end)
	R:Slider("Scale", 0.6, 1.6, 0.05,
		function() return Opt("scale") end, function(v) ns:Set("bosses", "scale", v) end)
	R:Buttons("Unlock / lock", function() ns:BossUnlock() end,
	          "Test", function() ns:BossTest() end)
	R:Buttons("List learned", function() ns:BossList() end,
	          "Forget all", function() ns:BossForget() end)
	R:Note("A timer is the average of every pull so far. Bosses with random "
	    .. "timings or phase changes will drift; use /fpve boss forget <name> to "
	    .. "start one over.")
end)
