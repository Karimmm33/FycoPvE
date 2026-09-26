--[[ FycoPvE - Modules/Talents.lua
     The guide's talent build, drawn on your own talent trees.

     Every talent is taken from the client (GetTalentInfo), so the icons,
     names and positions are this realm's -- including talents Rebuffed added
     or changed, which carry an orange "!". The guide's points are laid over
     them, compared with yours:
        green   you have exactly what the guide has
        yellow  the guide puts more points here than you have
        red     you have points here the guide does not use

     "Preview in talent frame" fills the guide's build into Blizzard's own
     talent preview. Nothing is learned until YOU click Learn there.    ]]

local ADDON, ns = ...
local M = ns:Module("talents", 25)
local UI = ns.UI

local CELL, GRID_W = 26, 4 * 26
local TREE_W = 210
local chosen = {}   -- spec -> build index, for this session

local function Group() return GetActiveTalentGroup and GetActiveTalentGroup() or 1 end

--- The build the page is showing for the current spec.
function ns:CurrentBuild()
	local guide = ns:TalentGuide()
	if not (guide and guide.builds and #guide.builds > 0) then return nil, guide end
	local i = chosen[ns:Spec()] or 1
	return guide.builds[i] or guide.builds[1], guide
end

--- "tab:tier:col" -> guide points (and whether the realm changed it).
local function GuideMap(build)
	local map = {}
	for tab = 1, 3 do
		for _, t in ipairs(build.trees[tab] or {}) do
			map[tab .. ":" .. t[1] .. ":" .. t[2]] = t[3]
		end
	end
	return map
end

--- How far the player's talents are from a build.
--- Returns missing points, extra points, and the player's points per tree.
function ns:TalentDiff(build)
	local map = GuideMap(build)
	local missing, extra, mine = 0, 0, { 0, 0, 0 }
	for tab = 1, (GetNumTalentTabs() or 0) do
		for i = 1, (GetNumTalents(tab) or 0) do
			local _, _, tier, col, rank = GetTalentInfo(tab, i, false, false, Group())
			local g = map[tab .. ":" .. tier .. ":" .. col] or 0
			rank = rank or 0
			mine[tab] = mine[tab] + rank
			if rank < g then missing = missing + (g - rank) end
			if rank > g then extra = extra + (rank - g) end
		end
	end
	return missing, extra, mine
end

----------------------------------------------------------------------
-- preview in Blizzard's talent frame
----------------------------------------------------------------------

--- Put the build into the talent frame's preview, tier by tier so every
--- prerequisite and the 5-points-per-tier rule is met in order. The player
--- confirms with Learn in the frame; nothing is spent here.
function ns:PreviewTalents(build)
	build = build or ns:CurrentBuild()
	if not build then
		ns:Print("there is no talent build for " .. (ns:Spec() or "?") .. " yet")
		return
	end
	if not IsAddOnLoaded("Blizzard_TalentUI") then LoadAddOn("Blizzard_TalentUI") end
	SetCVar("previewTalents", "1")
	local group = Group()
	ResetGroupPreviewTalentPoints(false, group)

	local map = GuideMap(build)
	local free = GetUnspentTalentPoints(false, false, group) or 0
	local wanted, placed, extra = 0, 0, 0
	for tier = 1, 11 do
		for tab = 1, (GetNumTalentTabs() or 0) do
			for i = 1, (GetNumTalents(tab) or 0) do
				local _, _, t, col, rank = GetTalentInfo(tab, i, false, false, group)
				if t == tier then
					local g = map[tab .. ":" .. t .. ":" .. col] or 0
					rank = rank or 0
					if rank > g then extra = extra + rank - g end
					if g > rank then
						wanted = wanted + g - rank
						local before = select(9, GetTalentInfo(tab, i, false, false, group)) or rank
						AddPreviewTalentPoints(tab, i, g - rank, false, group)
						local after = select(9, GetTalentInfo(tab, i, false, false, group)) or before
						placed = placed + math.max(0, after - before)
					end
				end
			end
		end
	end

	if PlayerTalentFrame and not PlayerTalentFrame:IsShown() then
		if ToggleTalentFrame then ToggleTalentFrame() else ShowUIPanel(PlayerTalentFrame) end
	end

	if wanted == 0 then
		ns:Print("your talents already have every point of |cffffff00" .. build.name .. "|r.")
	else
		ns:Print(string.format("talent preview: |cff40ff40%d|r of %d guide points placed. Check them in the talent "
			.. "frame, then click |cffffff00Learn|r to keep them or |cffffff00Reset|r to cancel.", placed, wanted))
		if placed < wanted then
			ns:Print(string.format("|cffffd200%d point%s could not be placed|r - you have %d free talent point%s.",
				wanted - placed, wanted - placed == 1 and "" or "s", free, free == 1 and "" or "s"))
		end
	end
	if extra > 0 then
		ns:Print(string.format("|cffff8040Your talents have %d point%s the guide does not use.|r To follow it "
			.. "exactly, reset your talents at a class trainer first (or build it in your other spec).",
			extra, extra == 1 and "" or "s"))
	end
end

----------------------------------------------------------------------
-- the Talents page
----------------------------------------------------------------------

local pane

local function CellColor(g, rank)
	if g > 0 and rank == g then return 0.2, 0.85, 0.2, 1 end
	if g > rank then return 1, 0.8, 0, 1 end
	if rank > g then return 1, 0.2, 0.2, 1 end
	return 0, 0, 0, 0.5
end

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	local build, guide = ns:CurrentBuild()
	pane.build.Refresh()

	if not build then
		pane.empty:SetText("There is no talent guide for " .. ns:ProfileText():gsub(",.*$", "")
			.. " yet. Pick another spec above.")
		pane.empty:Show()
		pane.trees:Hide()
		pane.summary:SetText("")
		pane.preview:Disable()
		return
	end
	pane.empty:Hide()
	pane.trees:Show()
	pane.preview:Enable()

	local map = GuideMap(build)
	local changed = (ns.Realm and ns.Realm.talents[ns:PlayerClass()]) or {}
	local missing, extra, mine = ns:TalentDiff(build)

	for tab = 1, 3 do
		local tree = pane.tree[tab]
		local tabName = GetTalentTabInfo(tab)
		tree.title:SetText(string.format("%s  |cffffffff%d|r |cff808080(you %d)|r", tabName or ("Tree " .. tab),
			build.pts[tab] or 0, mine[tab]))
		for _, cell in pairs(tree.cells) do cell:Hide() end
		for i = 1, (GetNumTalents(tab) or 0) do
			local _, icon, tier, col, rank, maxRank = GetTalentInfo(tab, i, false, false, Group())
			local cell = tree.cells[tier .. ":" .. col]
			if cell then
				local key = tab .. ":" .. tier .. ":" .. col
				local g = map[key] or 0
				rank = rank or 0
				cell.tab, cell.index, cell.guide, cell.rank, cell.maxRank = tab, i, g, rank, maxRank
				cell.changed = changed[key]
				cell.icon:SetTexture(icon)
				if g == 0 and rank == 0 then
					cell.icon:SetVertexColor(0.35, 0.35, 0.35)
				else
					cell.icon:SetVertexColor(1, 1, 1)
				end
				cell.border:SetTexture(CellColor(g, rank))
				if g > 0 or rank > 0 then
					cell.count:SetText(rank == g and tostring(g) or (rank .. "/" .. g))
				else
					cell.count:SetText("")
				end
				cell.mark:SetText(cell.changed and "|cffff9020!|r" or "")
				cell:Show()
			end
		end
	end

	if missing == 0 and extra == 0 then
		pane.summary:SetText("|cff40ff40Your talents match this build.|r")
	else
		pane.summary:SetText(string.format("%s%s", missing > 0 and ("|cffffd200" .. missing .. " to add|r  ") or "",
			extra > 0 and ("|cffff4040" .. extra .. " not in the guide|r") or ""))
	end
	pane.note:SetText(ns:GuideText(build.note))
	pane.noteChild:SetHeight(math.ceil(pane.note:GetStringHeight() or 40) + 8)
end

local function CellTooltip(cell)
	if not cell.index then return end
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:SetTalent(cell.tab, cell.index, false, false, Group())
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(string.format("|cff66ccffFycoPvE|r guide |cffffffff%d/%d|r   you |cffffffff%d/%d|r",
		cell.guide, cell.maxRank or 0, cell.rank, cell.maxRank or 0))
	if cell.changed then
		GameTooltip:AddLine("Changed on this realm - the guide was written for the standard game.", 1, 0.56, 0.12, true)
	end
	GameTooltip:Show()
end

local function BuildPane(p)
	pane = p

	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvETalentSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)

	local bcap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	bcap:SetPoint("TOPLEFT", 184, 0)
	bcap:SetText("Build")
	p.build = UI.Dropdown(p, "FycoPvETalentBuild", 150, {
		items = function()
			local guide = ns:TalentGuide()
			local out = {}
			for i, b in ipairs(guide and guide.builds or {}) do
				out[#out + 1] = { value = i, text = b.name }
			end
			return out
		end,
		get = function() return chosen[ns:Spec()] or 1 end,
		set = function(v) chosen[ns:Spec()] = v; Refresh() end,
	})
	p.build:SetPoint("TOPLEFT", 168, -12)

	p.preview = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.preview:SetWidth(170)
	p.preview:SetHeight(22)
	p.preview:SetPoint("TOPRIGHT", -2, -14)
	p.preview:SetText("Preview in talent frame")
	p.preview:SetScript("OnClick", function() ns:PreviewTalents() end)
	p.preview:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Preview this build")
		GameTooltip:AddLine("Fills the build into the talent frame's preview. Nothing is learned "
			.. "until you click Learn there.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	p.preview:SetScript("OnLeave", function() GameTooltip:Hide() end)

	p.summary = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.summary:SetPoint("TOPRIGHT", -4, -40)

	p.empty = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.empty:SetPoint("TOPLEFT", 4, -70)
	p.empty:SetWidth(600)
	p.empty:SetJustifyH("LEFT")

	p.trees = CreateFrame("Frame", nil, p)
	p.trees:SetPoint("TOPLEFT", 0, -52)
	p.trees:SetWidth(3 * TREE_W)
	p.trees:SetHeight(16 + 11 * CELL)
	p.tree = {}
	for tab = 1, 3 do
		local x = (tab - 1) * (TREE_W + 4)
		local tree = { cells = {} }
		tree.title = p.trees:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		tree.title:SetPoint("TOPLEFT", x + 4, 0)
		local left = x + (TREE_W - GRID_W) / 2
		for tier = 1, 11 do
			for col = 1, 4 do
				local c = CreateFrame("Button", nil, p.trees)
				c:SetWidth(CELL - 2)
				c:SetHeight(CELL - 2)
				c:SetPoint("TOPLEFT", left + (col - 1) * CELL, -18 - (tier - 1) * CELL)
				c.border = c:CreateTexture(nil, "BACKGROUND")
				c.border:SetAllPoints(c)
				c.icon = c:CreateTexture(nil, "ARTWORK")
				c.icon:SetPoint("TOPLEFT", 2, -2)
				c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
				c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				c.count = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
				c.count:SetPoint("BOTTOMRIGHT", 2, -1)
				c.mark = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				c.mark:SetPoint("TOPLEFT", -1, 2)
				c:SetScript("OnEnter", CellTooltip)
				c:SetScript("OnLeave", function() GameTooltip:Hide() end)
				c:Hide()
				tree.cells[tier .. ":" .. col] = c
			end
		end
		p.tree[tab] = tree
	end

	-- the guide's explanation of the build, scrollable
	local scroll = CreateFrame("ScrollFrame", "FycoPvETalentNote", p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -52 - 16 - 11 * CELL - 8)
	scroll:SetPoint("BOTTOMRIGHT", -26, 2)
	p.noteChild = CreateFrame("Frame", nil, scroll)
	p.noteChild:SetWidth(600)
	p.noteChild:SetHeight(40)
	scroll:SetScrollChild(p.noteChild)
	p.note = p.noteChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.note:SetPoint("TOPLEFT", 0, 0)
	p.note:SetWidth(600)
	p.note:SetJustifyH("LEFT")
	p.note:SetJustifyV("TOP")
end

ns:AddTab("talents", "Talents", 20, BuildPane, Refresh)

function M:OnLoad()
	local function Dirty() Refresh() end
	ns:On("CHARACTER_POINTS_CHANGED", Dirty)
	ns:On("PLAYER_TALENT_UPDATE", Dirty)
	ns:Subscribe("ProfileChanged", Dirty)
end
