--[[ FycoPvE - Modules/Rotation.lua
     Rotation helper: what to cast next.

     A small movable panel: one big icon for the spell to cast now, then two
     smaller ones for what comes after, each counting down when it is not
     ready yet ("Haunt  2.3"). It only suggests -- 3.3.5a does not let an
     addon cast for you, and it should not.

     Each spec's priority is data (ns.Rotations[class][spec]), read by one
     small engine, so a spec is added by writing its list, not new code.
     Rule kinds:
       dot       keep my debuff on the target; refresh when it has less time
                 left than the spell's cast time (+ a little), or never
                 (noRefresh: Corruption, which Everlasting Affliction renews)
       cooldown  cast whenever it is off cooldown (Haunt)
       curse     like dot, but any curse of mine counts as "cursed"
       debuffany keep a debuff up that anyone may supply (Shadow Mastery)
       buff      keep a buff of mine up on myself (Life Tap's glyph buff)
       execute   only under a target health % (Drain Soul)
       filler    when nothing else is due
     The suggested spell is the first rule that is due; the next ones are
     whatever comes due soonest after it.                                 ]]

local ADDON, ns = ...
local M = ns:Module("rotation", 45)
local UI = ns.UI

local LATENCY = 0.3   -- seconds of slack when refreshing a DoT before it falls off

ns.Rotations = {
	WARLOCK = {
		Affliction = {
			{ kind = "buff", spell = 57946, aura = 63321, glyph = "Glyph of Life Tap", lead = 3 },  -- Life Tap
			{ kind = "debuffany", spell = 47809, aura = 17800, talent = "Improved Shadow Bolt" },  -- Shadow Bolt for Shadow Mastery
			{ kind = "cooldown", spell = 59164 },                -- Haunt
			{ kind = "dot", spell = 47843 },                     -- Unstable Affliction
			{ kind = "dot", spell = 47813, noRefresh = true },   -- Corruption
			{ kind = "curse", spell = 47864 },                   -- Curse of Agony
			{ kind = "execute", spell = 47855, below = 25 },     -- Drain Soul
			{ kind = "filler", spell = 47809 },                  -- Shadow Bolt
		},
	},
}

-- any of these on the target, cast by me, means "my curse is up"
local CURSES = { 47864, 47867, 47865, 11719, 50511, 18223 }

local function Supported(class, spec)
	local c = ns.Rotations[class or ns:PlayerClass()]
	return c and c[spec or ns:Spec()]
end
ns.RotationSupported = Supported

local function Opt(key) return ns:Get("rotation", key) end

----------------------------------------------------------------------
-- the engine
----------------------------------------------------------------------

--- Name of the highest rank the player knows, or nil if not learned.
local function Known(id)
	local name = GetSpellInfo(id)
	return name and GetSpellInfo(name) and name
end

local function MyDebuffLeft(unit, name, now)
	local _, _, _, _, _, _, expires = UnitAura(unit, name, nil, "HARMFUL|PLAYER")
	if not expires then return nil end
	return expires > 0 and (expires - now) or 999
end

local function AnyDebuffLeft(unit, name, now)
	local _, _, _, _, _, _, expires = UnitAura(unit, name, nil, "HARMFUL")
	if not expires then return nil end
	return expires > 0 and (expires - now) or 999
end

local function MyBuffLeft(name, now)
	local _, _, _, _, _, _, expires = UnitAura("player", name, nil, "HELPFUL|PLAYER")
	if not expires then return nil end
	return expires > 0 and (expires - now) or 999
end

local function CooldownLeft(name, now)
	local start, dur = GetSpellCooldown(name)
	if not start or start == 0 then return 0 end
	return math.max(0, start + dur - now)
end

local function CastTime(name)
	return ((select(7, GetSpellInfo(name))) or 0) / 1000
end

local function HasTalent(name)
	for tab = 1, (GetNumTalentTabs() or 0) do
		for i = 1, (GetNumTalents(tab) or 0) do
			local n, _, _, _, rank = GetTalentInfo(tab, i)
			if n == name then return (rank or 0) > 0 end
		end
	end
	return false
end

--- How long until this rule wants its spell cast (0 = now), or nil if the
--- rule does not apply at all right now.
local function Due(rule, now, casting)
	local name = Known(rule.spell)
	if not name then return nil end
	if casting == name and rule.kind ~= "filler" then return nil end   -- already on its way
	local cd = CooldownLeft(name, now)

	if rule.kind == "cooldown" then
		return cd, name
	elseif rule.kind == "dot" then
		local left = MyDebuffLeft("target", name, now)
		if not left then return cd, name end
		if rule.noRefresh then return nil end
		return math.max(cd, left - CastTime(name) - LATENCY), name
	elseif rule.kind == "curse" then
		for _, id in ipairs(CURSES) do
			local cname = GetSpellInfo(id)
			local left = cname and MyDebuffLeft("target", cname, now)
			if left then
				if cname ~= name then return nil end    -- another curse of mine is the player's choice
				return math.max(cd, left - LATENCY), name
			end
		end
		return cd, name
	elseif rule.kind == "debuffany" then
		if rule.talent and not HasTalent(rule.talent) then return nil end
		local aura = GetSpellInfo(rule.aura)
		local left = aura and AnyDebuffLeft("target", aura, now)
		if not left then return cd, name end
		return math.max(cd, left - CastTime(name) - LATENCY - 0.8), name   -- bolt travel time
	elseif rule.kind == "buff" then
		if rule.glyph and not (ns.SocketedGlyphs and ns:SocketedGlyphs()[rule.glyph]) then return nil end
		local aura = GetSpellInfo(rule.aura)
		local left = aura and MyBuffLeft(aura, now)
		if not left then return cd, name end
		return math.max(cd, left - (rule.lead or 0)), name
	elseif rule.kind == "execute" then
		local hp, max = UnitHealth("target"), UnitHealthMax("target")
		if max and max > 0 and hp / max * 100 < rule.below then return cd, name end
		return nil
	elseif rule.kind == "filler" then
		return cd, name
	end
end

--- { { spell, name, icon, wait }, ... } -- the spell to cast now first, then
--- the next ones by when they come due. `count` entries at most.
function ns:RotationQueue(count)
	local rules = Supported()
	if not rules then return {} end
	local now = GetTime()
	local _, _, _, _, _, castEnd = UnitCastingInfo("player")
	local casting = UnitCastingInfo("player")
	local from = castEnd and math.max(now, castEnd / 1000) or now
	local lead = from - now          -- anything is at least this far off

	local due = {}
	for i, rule in ipairs(rules) do
		local wait, name = Due(rule, from, casting)
		if wait then
			due[#due + 1] = { index = i, spell = rule.spell, name = name, wait = wait + lead,
				filler = rule.kind == "filler" or rule.kind == "execute" }
		end
	end

	-- now: the highest-priority rule that is due by the time the global
	-- cooldown (read off the filler, which has no cooldown of its own) ends
	local out, used = {}, {}
	local gcd = 0
	for _, rule in ipairs(rules) do
		local fname = rule.kind == "filler" and Known(rule.spell)
		if fname then gcd = math.min(1.5, CooldownLeft(fname, now)) end
	end
	local gcdLeft = math.max(lead, gcd)
	table.sort(due, function(a, b) return a.index < b.index end)
	for _, d in ipairs(due) do
		if d.wait <= gcdLeft + 0.05 then
			out[1] = d
			used[d.name] = true
			break
		end
	end
	-- next: whatever is due soonest, fillers last
	table.sort(due, function(a, b)
		if a.filler ~= b.filler then return not a.filler end
		if math.abs(a.wait - b.wait) > 0.05 then return a.wait < b.wait end
		return a.index < b.index
	end)
	for _, d in ipairs(due) do
		if #out >= count then break end
		if not used[d.name] then
			out[#out + 1] = d
			used[d.name] = true
		end
	end
	for _, d in ipairs(out) do d.icon = select(3, GetSpellInfo(d.spell)) end
	return out
end

----------------------------------------------------------------------
-- the panel
----------------------------------------------------------------------

local frame, icons = nil, {}
local unlocked = false

local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ns:Set("rotation", "pos", { point, relPoint, x, y })
end

local function Icon(size)
	local b = CreateFrame("Frame", nil, frame)
	b:SetWidth(size)
	b:SetHeight(size)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints(b)
	b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.wait = b:CreateFontString(nil, "OVERLAY", size > 40 and "NumberFontNormalHuge" or "NumberFontNormal")
	b.wait:SetPoint("CENTER")
	b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.name:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b:Hide()
	return b
end

local function Build()
	frame = CreateFrame("Frame", "FycoPvERotation", UIParent)
	frame:SetWidth(160)
	frame:SetHeight(70)
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
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
	end
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints(frame)
	frame.bg:SetTexture(0, 0, 0, 0.4)
	frame.bg:Hide()

	icons[1] = Icon(52)
	icons[1]:SetPoint("LEFT", 0, 0)
	icons[2] = Icon(34)
	icons[2]:SetPoint("BOTTOMLEFT", icons[1], "BOTTOMRIGHT", 8, 0)
	icons[3] = Icon(34)
	icons[3]:SetPoint("LEFT", icons[2], "RIGHT", 6, 0)
	frame:SetScale(Opt("scale"))
	frame:Hide()
end

local function ShouldShow()
	if not ns:Enabled("rotation") or not Supported() then return false end
	if unlocked then return true end
	if not (UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")) then
		return false
	end
	return Opt("outOfCombat") or UnitAffectingCombat("player")
end

local function Update()
	if not frame then return end
	if not ShouldShow() then
		frame:Hide()
		return
	end
	frame:Show()
	local queue = ns:RotationQueue(1 + Opt("upcoming"))
	for i = 1, 3 do
		local b, q = icons[i], queue[i]
		if q and i <= 1 + Opt("upcoming") then
			b.tex:SetTexture(q.icon)
			local w = q.wait
			if i > 1 and w > 0.1 then
				b.wait:SetText(string.format(w < 10 and "%.1f" or "%.0f", w))
				b.tex:SetVertexColor(0.55, 0.55, 0.55)
			else
				b.wait:SetText("")
				b.tex:SetVertexColor(1, 1, 1)
			end
			b.name:SetText(Opt("names") and q.name or "")
			b:Show()
		else
			b:Hide()
		end
	end
end

function ns:RotationUnlock()
	unlocked = not unlocked
	frame:EnableMouse(unlocked)
	if unlocked then frame.bg:Show() else frame.bg:Hide() end
	ns:Print("rotation helper " .. (unlocked and "|cff40ff40unlocked|r - drag it, then lock it again" or "locked"))
end

function ns:RotationResetPosition()
	ns:Set("rotation", "pos", nil)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
end

----------------------------------------------------------------------
-- the Rotation page: the guide's priority and opener
----------------------------------------------------------------------

local pane

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	local guide = ns:SpecGuide()
	local lines = {}
	if Supported() then
		lines[#lines + 1] = "|cff40ff40The rotation helper supports this spec.|r It shows while you fight a hostile target."
	else
		lines[#lines + 1] = "|cffffd200The rotation helper does not cover this spec yet|r - the guide's priority is below."
	end
	lines[#lines + 1] = " "
	if guide and #(guide.priority or {}) > 0 then
		lines[#lines + 1] = "|cffffd200The guide's spell priority|r"
		for i, p in ipairs(guide.priority) do
			local name = GetSpellInfo(p[1]) or ("spell " .. p[1])
			lines[#lines + 1] = string.format("%d.  |cff71d5ff%s|r  |cffa0a0a0%s|r", i, name, ns:GuideText(p[2]))
		end
	else
		lines[#lines + 1] = "|cff808080The guide gives no priority list for this spec.|r"
	end
	if guide and guide.opener and guide.opener ~= "" then
		lines[#lines + 1] = " "
		lines[#lines + 1] = "|cffffd200Opener|r"
		lines[#lines + 1] = ns:GuideText(guide.opener)
	end
	pane.text:SetText(table.concat(lines, "\n"))
	pane.child:SetHeight(math.ceil(pane.text:GetStringHeight() or 100) + 10)
end

local function BuildPane(p)
	pane = p
	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvERotationSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)
	local b1 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b1:SetWidth(130)
	b1:SetHeight(22)
	b1:SetPoint("TOPRIGHT", -2, -14)
	b1:SetText("Move the helper")
	b1:SetScript("OnClick", function() ns:RotationUnlock() end)

	local scroll = CreateFrame("ScrollFrame", "FycoPvERotationScroll", p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -48)
	scroll:SetPoint("BOTTOMRIGHT", -26, 2)
	p.child = CreateFrame("Frame", nil, scroll)
	p.child:SetWidth(600)
	p.child:SetHeight(100)
	scroll:SetScrollChild(p.child)
	p.text = p.child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.text:SetPoint("TOPLEFT", 0, 0)
	p.text:SetWidth(600)
	p.text:SetJustifyH("LEFT")
	p.text:SetSpacing(3)
end

ns:AddTab("rotation", "Rotation", 50, BuildPane, Refresh)

function M:OnLoad()
	Build()
	ns:OnTick(function() Update() end)   -- 10 Hz, so countdowns tick smoothly
	ns:Subscribe("ProfileChanged", Refresh)
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "rotation" and key == "scale" then frame:SetScale(Opt("scale")) end
	end)
end

ns:RegisterOptions("rotation", "Rotation helper", 45, function(L, R)
	L:Title("Rotation helper")
	L:Note("Shows the next spell to cast, and the two after it with a countdown. It suggests; it "
	    .. "never casts. Specs covered so far: Affliction Warlock.")
	L:Check("Show the rotation helper", nil,
		function() return FycoPvEDB.enabled.rotation ~= false end,
		function(v)
			FycoPvEDB.enabled.rotation = v
			ns:Fire("SettingChanged", "enabled", "rotation", v)
		end)
	L:Check("Show out of combat too", "With a hostile target selected",
		function() return Opt("outOfCombat") end, function(v) ns:Set("rotation", "outOfCombat", v) end)
	L:Check("Spell names under the icons", nil,
		function() return Opt("names") end, function(v) ns:Set("rotation", "names", v) end)
	L:Slider("Upcoming spells", 0, 2, 1,
		function() return Opt("upcoming") end, function(v) ns:Set("rotation", "upcoming", v) end)

	R:Title("Position")
	R:Slider("Scale", 0.6, 2.0, 0.05,
		function() return Opt("scale") end, function(v) ns:Set("rotation", "scale", v) end)
	R:Buttons("Unlock / lock", function() ns:RotationUnlock() end,
	          "Reset position", function() ns:RotationResetPosition() end)
end)
