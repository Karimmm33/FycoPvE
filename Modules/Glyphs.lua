--[[ FycoPvE - Modules/Glyphs.lua
     The guide's major and minor glyphs, each with why it is picked, ticked
     when you already have it socketed. Glyphs you have that the guide does
     not list are named at the bottom, so a stale glyph is easy to spot.

     A socketed glyph is known by its spell (GetGlyphSocketInfo), a guide
     glyph by its item; both are called "Glyph of X", so they are matched
     by name.                                                           ]]

local ADDON, ns = ...
local M = ns:Module("glyphs", 26)
local UI = ns.UI

local ROW_GAP, NOTE_W = 6, 540
local pane

--- Names of the glyphs socketed in the active spec, and how many are major/minor.
function ns:SocketedGlyphs()
	local have = {}
	local group = GetActiveTalentGroup and GetActiveTalentGroup() or 1
	for s = 1, (GetNumGlyphSockets and GetNumGlyphSockets() or 0) do
		local enabled, kind, spellID = GetGlyphSocketInfo(s, group)
		if enabled and spellID then
			local name = GetSpellInfo(spellID)
			if name then have[name] = kind == 1 and "major" or "minor" end
		end
	end
	return have
end

--- Guide glyphs the player has not socketed, as { name, kind } pairs.
function ns:MissingGlyphs(guide)
	guide = guide or ns:TalentGuide()
	local have, out = ns:SocketedGlyphs(), {}
	for _, kind in ipairs({ "major", "minor" }) do
		for _, g in ipairs(guide and guide.glyphs and guide.glyphs[kind] or {}) do
			if not have[g[2]] then out[#out + 1] = { g[2], kind } end
		end
	end
	return out
end

local rows = {}

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, pane.child)
	r.icon = UI.ItemButton(r, 22)
	r.icon:SetPoint("TOPLEFT", 0, 0)
	r.name = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	r.name:SetPoint("TOPLEFT", 28, -3)
	r.status = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.status:SetPoint("TOPRIGHT", -4, -4)
	r.note = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.note:SetPoint("TOPLEFT", 28, -20)
	r.note:SetWidth(NOTE_W)
	r.note:SetJustifyH("LEFT")
	r.note:SetTextColor(0.8, 0.8, 0.8)
	rows[i] = r
	return r
end

local function Refresh()
	if not (pane and pane:IsVisible()) then return end
	pane.spec.Refresh()
	for _, r in ipairs(rows) do r:Hide() end
	for _, h in ipairs(pane.headings) do h:Hide() end

	local guide = ns:TalentGuide()
	if not (guide and guide.glyphs) then
		pane.empty:SetText("There is no glyph guide for this spec yet.")
		pane.empty:Show()
		pane.scroll:Hide()
		return
	end
	pane.empty:Hide()
	pane.scroll:Show()

	-- the heading pool is reused from the top each refresh
	local used = 0
	local function H(y, text)
		used = used + 1
		local h = pane.headings[used]
		if not h then
			h = pane.child:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
			pane.headings[used] = h
		end
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", 0, y)
		h:SetText(text)
		h:Show()
		return y - 26
	end

	local have = ns:SocketedGlyphs()
	local listed, n, y = {}, 0, -2
	for _, kind in ipairs({ "major", "minor" }) do
		y = H(y, kind == "major" and "Major glyphs" or "Minor glyphs")
		local list = guide.glyphs[kind] or {}
		if #list == 0 then
			n = n + 1
			local r = Row(n)
			r.icon:Hide()
			r.name:SetText("|cff808080The guide names no fixed " .. kind .. " glyphs for this spec: they are "
				.. "situational. See the guide's advice on Wowhead.|r")
			r.status:SetText("")
			r.note:SetText("")
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, y)
			r:SetWidth(NOTE_W + 40)
			r:SetHeight(20)
			r:Show()
			y = y - 24
		end
		for _, g in ipairs(list) do
			listed[g[2]] = true
			n = n + 1
			local r = Row(n)
			r.icon:SetItem(g[1])
			r.icon:Show()
			r.name:SetText(g[2])
			r.status:SetText(have[g[2]] and "|cff40ff40Socketed|r" or "|cffffd200Missing|r - Inscription or Auction House")
			r.note:SetText(ns:GuideText(g[3]))
			local h = math.max(22, 22 + math.ceil(r.note:GetStringHeight() or 0))
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, y)
			r:SetWidth(NOTE_W + 40)
			r:SetHeight(h)
			r:Show()
			y = y - h - ROW_GAP
		end
		y = y - 8
	end

	-- glyphs you run that the guide does not list
	local extra = {}
	for name in pairs(have) do
		if not listed[name] then extra[#extra + 1] = name end
	end
	table.sort(extra)
	if #extra > 0 then
		y = H(y, "Also socketed, not in the guide")
		n = n + 1
		local r = Row(n)
		r.icon:Hide()
		r.name:SetText("|cffff8040" .. table.concat(extra, ", ") .. "|r")
		r.status:SetText("")
		r.note:SetText("Worth checking whether these still suit your spec.")
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, y)
		r:SetWidth(NOTE_W + 40)
		r:SetHeight(40)
		r:Show()
		y = y - 44
	end
	pane.child:SetHeight(-y + 10)
end

local function BuildPane(p)
	pane = p
	p.headings = {}

	local cap = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", 4, 0)
	cap:SetText("Spec")
	p.spec = UI.Dropdown(p, "FycoPvEGlyphSpec", 130, {
		items = UI.SpecItems, get = UI.SpecGet, set = function(v) ns:SetSpec(v) end,
	})
	p.spec:SetPoint("TOPLEFT", -12, -12)

	local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 190, -20)
	hint:SetText("Hover a glyph for its tooltip; shift-click to link it.")

	p.empty = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.empty:SetPoint("TOPLEFT", 4, -60)

	p.scroll = CreateFrame("ScrollFrame", "FycoPvEGlyphScroll", p, "UIPanelScrollFrameTemplate")
	p.scroll:SetPoint("TOPLEFT", 4, -48)
	p.scroll:SetPoint("BOTTOMRIGHT", -26, 2)
	p.child = CreateFrame("Frame", nil, p.scroll)
	p.child:SetWidth(NOTE_W + 40)
	p.child:SetHeight(100)
	p.scroll:SetScrollChild(p.child)
end

ns:AddTab("glyphs", "Glyphs", 30, BuildPane, Refresh)

function M:OnLoad()
	ns:On("GLYPH_ADDED", Refresh)
	ns:On("GLYPH_REMOVED", Refresh)
	ns:On("GLYPH_UPDATED", Refresh)
	ns:Subscribe("ProfileChanged", Refresh)
end
