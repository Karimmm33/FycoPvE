--[[ FycoPvE - Modules/Overview.lua
     The character check-up: everything the guide pages would flag, on one
     page, worst first, each with a button to the page that fixes it.
       gear below BiS, missing or weaker enchants, empty sockets, missing
       glyphs, talents that differ from the build, caps not reached, and how
       your professions rank for your spec.                              ]]

local ADDON, ns = ...
local M = ns:Module("overview", 22)
local UI = ns.UI

local RED, YELLOW, GREEN, GREY = "|cffff4040", "|cffffd200", "|cff40ff40", "|cff808080"

--- { { level ("fix", "improve", "ok", "info"), text, page }, ... }
function ns:Checkup()
	local out = {}
	local function Add(level, text, page) out[#out + 1] = { level = level, text = text, page = page } end

	-- gear
	local lists = ns:BiSLists(ns:PlayerClass(), ns:Spec(), ns:Phase())
	if lists and ns.EvaluateGear then
		local rows = ns:EvaluateGear(lists)
		local below, empty, total = 0, 0, 0
		for _, r in ipairs(rows) do
			if r.list then
				total = total + 1
				if not r.id then empty = empty + 1 elseif not r.isBiS then below = below + 1 end
			end
		end
		if empty > 0 then Add("fix", empty .. " gear slot" .. (empty == 1 and " is" or "s are") .. " empty.", "gear") end
		if below > 0 then
			Add("improve", string.format("%d of %d slots are below BiS for %s.", below, total,
				ns.PhaseName[ns:Phase()] or ns:Phase()), "gear")
		elseif total > 0 then
			Add("ok", "Every slot is BiS for " .. (ns.PhaseName[ns:Phase()] or ns:Phase()) .. ".", "gear")
		end
	else
		Add("info", "No BiS list for this spec and phase yet.", "gear")
	end

	-- enchants and sockets
	if ns.AuditEnchants then
		local bad = 0
		for _, r in ipairs(ns:AuditEnchants()) do
			if r.status == "missing" then
				Add("fix", r.slot .. " has no enchant.", "enchants")
				bad = bad + 1
			elseif r.status == "other" or r.status == "option" then
				Add("improve", r.slot .. " enchant: " .. (ns.EnchantNames[r.have] or "?") .. " - the guide's best for you is "
					.. (r.best.name or GetSpellInfo(r.best.id) or "?") .. ".", "enchants")
				bad = bad + 1
			end
		end
		if bad == 0 and ns:SpecGuide() then Add("ok", "Every enchant matches the guide.", "enchants") end
		local sockets = ns:AuditSockets()
		for _, s in ipairs(sockets) do
			Add("fix", s.slot .. " has " .. s.empty .. " empty gem socket" .. (s.empty == 1 and "" or "s") .. ".", "enchants")
		end
	end

	-- glyphs
	if ns.MissingGlyphs and ns:TalentGuide() then
		local missing = ns:MissingGlyphs()
		if #missing > 0 then
			local names = {}
			for _, g in ipairs(missing) do names[#names + 1] = g[1] end
			Add("improve", "Glyphs the guide recommends that you don't have: " .. table.concat(names, ", ") .. ".", "glyphs")
		else
			Add("ok", "You have every glyph the guide recommends.", "glyphs")
		end
	end

	-- talents
	local build = ns.CurrentBuild and ns:CurrentBuild()
	if build then
		local missing, extra = ns:TalentDiff(build)
		if missing + extra > 0 then
			Add("improve", string.format("Talents differ from \"%s\": %d point%s to add, %d not in the build.",
				build.name, missing, missing == 1 and "" or "s", extra), "talents")
		else
			Add("ok", "Your talents match \"" .. build.name .. "\".", "talents")
		end
	end

	-- caps
	if ns.StatCaps then
		local caps = ns:StatCaps()
		for _, c in ipairs(caps) do
			if c.have < c.cap then
				Add("fix", string.format("%s: %s of %s - %d more rating needed.", c.label,
					c.unit == "%" and string.format("%.2f%%", c.have) or tostring(c.have),
					c.unit == "%" and (c.cap .. "%") or tostring(c.cap), c.missingRating), "stats")
			else
				Add("ok", c.label .. " is capped.", "stats")
			end
		end
	end

	-- professions
	if ns.ProfessionAdvice then
		local have, top, role = ns:ProfessionAdvice()
		if #have > 0 then
			local names = {}
			for _, h in ipairs(have) do names[#names + 1] = h.name .. " (#" .. h.rank .. ")" end
			Add("info", "Your professions for a " .. role .. ": " .. table.concat(names, ", ") .. ". The best two are "
				.. top[1] .. " and " .. top[2] .. ".", "professions")
		end
	end

	-- rotation
	if ns.RotationSupported and ns.RotationSupported() then
		Add("info", "The rotation helper covers your spec - it shows while you fight.", "rotation")
	end

	local rank = { fix = 1, improve = 2, info = 3, ok = 4 }
	table.sort(out, function(a, b)
		if rank[a.level] ~= rank[b.level] then return rank[a.level] < rank[b.level] end
		return false
	end)
	return out
end

----------------------------------------------------------------------
-- the page
----------------------------------------------------------------------

local pane
local rows = {}
local MARK = { fix = RED .. "Fix|r", improve = YELLOW .. "Improve|r", ok = GREEN .. "OK|r", info = GREY .. "Info|r" }

local function Row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Frame", nil, pane.child)
	r:SetWidth(600)
	r.mark = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	r.mark:SetPoint("TOPLEFT", 2, -4)
	r.mark:SetWidth(52)
	r.mark:SetJustifyH("LEFT")
	r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.text:SetPoint("TOPLEFT", 56, -4)
	r.text:SetWidth(460)
	r.text:SetJustifyH("LEFT")
	r.open = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.open:SetWidth(70)
	r.open:SetHeight(18)
	r.open:SetPoint("TOPRIGHT", -2, -1)
	r.open:SetText("Open")
	r.open:SetScript("OnClick", function(self) ns:OpenWindow(self.page) end)
	rows[i] = r
	return r
end

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	pane.phase.Refresh()
	for _, r in ipairs(rows) do r:Hide() end
	local list = ns:Checkup()
	local fix, improve = 0, 0
	local y = -2
	for i, c in ipairs(list) do
		if c.level == "fix" then fix = fix + 1 elseif c.level == "improve" then improve = improve + 1 end
		local r = Row(i)
		r.mark:SetText(MARK[c.level])
		r.text:SetText(c.text)
		r.open.page = c.page
		local h = math.max(22, math.ceil(r.text:GetStringHeight() or 12) + 8)
		r:SetHeight(h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, y)
		r:Show()
		y = y - h
	end
	pane.child:SetHeight(-y + 10)
	if fix + improve == 0 then
		pane.summary:SetText(GREEN .. "Nothing to fix - your character matches the guide.|r")
	else
		pane.summary:SetText(string.format("%s%d to fix|r, %s%d to improve|r for %s", RED, fix, YELLOW, improve,
			ns:ProfileText()))
	end
end

local function BuildPane(p)
	pane = p
	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvEOverviewSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)
	local pcap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	pcap:SetPoint("TOPLEFT", 184, 0)
	pcap:SetText("Phase")
	p.phase = UI.Dropdown(p, "FycoPvEOverviewPhase", 230, {
		items = UI.PhaseItems, get = function() return ns:Phase() end, set = function(v) ns:SetPhase(v) end,
	})
	p.phase:SetPoint("TOPLEFT", 168, -12)

	p.summary = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.summary:SetPoint("TOPLEFT", 4, -50)

	local scroll = CreateFrame("ScrollFrame", "FycoPvEOverviewScroll", p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -72)
	scroll:SetPoint("BOTTOMRIGHT", -26, 2)
	p.child = CreateFrame("Frame", nil, scroll)
	p.child:SetWidth(600)
	p.child:SetHeight(100)
	scroll:SetScrollChild(p.child)
end

ns:AddTab("overview", "Overview", 5, BuildPane, Refresh)

function M:OnLoad()
	ns:On("PLAYER_EQUIPMENT_CHANGED", Refresh)
	ns:On("CHARACTER_POINTS_CHANGED", Refresh)
	ns:On("GLYPH_UPDATED", Refresh)
	ns:Subscribe("ProfileChanged", Refresh)
end
