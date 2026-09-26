--[[ FycoPvE - tests/wowmock.lua
     A stand-in for the 3.3.5a client, just enough of it to load the addon
     for real and drive it: frames, events, the ticker, tooltips, inventory,
     talents, chat. Loaded by tests/run_tests.py inside a genuine Lua 5.1.

     Any frame method the mock does not implement still works (it does
     nothing) but its name is recorded in MOCK.unknownMethods, so a test run
     lists every API the addon touched that this file cannot vouch for.   ]]

MOCK = {
	frames = {}, chat = {}, panels = {}, unknownMethods = {},
	time = 1000, inventory = {}, items = {}, talents = { 0, 0, 0 },
	class = { "Warlock", "WARLOCK" }, faction = "Horde", shift = false,
}

function GetTime() return MOCK.time end

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------

local Frame = {}

local function unknown(name)
	return function() MOCK.unknownMethods[name] = (MOCK.unknownMethods[name] or 0) + 1 end
end

-- Missing CamelCase keys are client methods the mock does not model: hand
-- back a recording no-op. Anything else is the addon's own field and must be
-- nil when unset, exactly as on a real frame -- or `if self.done then` lies.
local frameMeta = {
	__index = function(t, k)
		local v = Frame[k]
		if v ~= nil then return v end
		if type(k) == "string" and k:match("^%u") then return unknown(k) end
		return nil
	end,
}

local function newRegion(kind, name, parent)
	local f = setmetatable({
		_kind = kind, _name = name, _parent = parent, _scripts = {}, _hooks = {},
		_events = {}, _shown = true, _w = 100, _h = 20, _text = nil, _points = {},
	}, frameMeta)
	if name then _G[name] = f end
	MOCK.frames[#MOCK.frames + 1] = f
	return f
end

function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:SetScript(k, fn) self._scripts[k] = fn end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:HookScript(k, fn)
	self._hooks[k] = self._hooks[k] or {}
	table.insert(self._hooks[k], fn)
end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:Show()
	local was = self._shown
	self._shown = true
	if not was then MOCK.run(self, "OnShow") end
end
function Frame:Hide()
	local was = self._shown
	self._shown = false
	if was then MOCK.run(self, "OnHide") end
end
function Frame:IsShown() return self._shown end
function Frame:IsVisible()
	local f = self
	while f do
		if not f._shown then return false end
		f = f._parent
	end
	return true
end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Frame:ClearAllPoints() self._points = {} end
function Frame:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function Frame:GetCenter() return 500, 400 end
function Frame:GetEffectiveScale() return 1 end
function Frame:SetText(t) self._text = t; if self._kind == "EditBox" then MOCK.run(self, "OnTextChanged") end end
function Frame:GetText() return self._text or "" end
function Frame:GetStringHeight() return 12 end
function Frame:SetChecked(v) self._checked = v and true or false end
function Frame:GetChecked() return self._checked and 1 or nil end
function Frame:Enable() self._enabled = true end
function Frame:Disable() self._enabled = false end
function Frame:IsEnabled() return self._enabled ~= false end
function Frame:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Frame:SetValue(v) self._value = v; MOCK.run(self, "OnValueChanged", v) end
function Frame:GetValue() return self._value or 0 end
function Frame:SetVerticalScroll(v) self._scroll = v end
function Frame:SetScrollChild(c) self._child = c end

function Frame:CreateFontString(name, layer, template) return newRegion("FontString", name, self) end
function Frame:CreateTexture(name, layer) return newRegion("Texture", name, self) end

-- run a script and every hook on it, the way the client does
function MOCK.run(f, script, ...)
	local fn = f._scripts[script]
	if fn then fn(f, ...) end
	for _, h in ipairs(f._hooks[script] or {}) do h(f, ...) end
end

local templateChildren = {
	OptionsSliderTemplate = { "Low", "High", "Text" },
	FauxScrollFrameTemplate = { "ScrollBar" },
	UIPanelScrollFrameTemplate = { "ScrollBar" },
	InputBoxTemplate = { "Left", "Right", "Middle" },
	UIDropDownMenuTemplate = { "Text", "Button", "Left", "Middle", "Right" },
}

function CreateFrame(kind, name, parent, template)
	local f = newRegion(kind, name, parent)
	f._template = template
	for _, suffix in ipairs(templateChildren[template or ""] or {}) do
		if name then newRegion("Region", name .. suffix, f) end
	end
	if kind == "Frame" and template == nil and parent == nil then f._shown = true end
	return f
end

UIParent = newRegion("Frame", "UIParent")
Minimap = newRegion("Frame", "Minimap")
WorldFrame = newRegion("Frame", "WorldFrame")
CharacterFrame = newRegion("Frame", "CharacterFrame", UIParent)
PaperDollFrame = newRegion("Frame", "PaperDollFrame", CharacterFrame)
CharacterFrame._shown = false
for _, s in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs",
	"Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }) do
	newRegion("Button", "Character" .. s .. "Slot", PaperDollFrame)
end

----------------------------------------------------------------------
-- events and the frame clock
----------------------------------------------------------------------

function MOCK.fire(event, ...)
	for _, f in ipairs(MOCK.frames) do
		if f._events[event] then MOCK.run(f, "OnEvent", event, ...) end
	end
end

--- Advance the clock and run every OnUpdate, like frames being drawn.
function MOCK.advance(seconds)
	local step = 0.05
	local t = 0
	while t < seconds do
		MOCK.time = MOCK.time + step
		t = t + step
		for _, f in ipairs(MOCK.frames) do
			if f._scripts.OnUpdate and f:IsVisible() then f._scripts.OnUpdate(f, step) end
		end
	end
end

----------------------------------------------------------------------
-- chat, tooltips
----------------------------------------------------------------------

DEFAULT_CHAT_FRAME = newRegion("Frame", "ChatFrame1")
function DEFAULT_CHAT_FRAME:AddMessage(msg) table.insert(MOCK.chat, msg) end

local function newTooltip(name)
	local t = newRegion("GameTooltip", name, UIParent)
	t._lines = {}
	function t:SetOwner() end
	function t:ClearLines() self._lines = {}; MOCK.run(self, "OnTooltipCleared") end
	function t:AddLine(text) table.insert(self._lines, text) end
	function t:AddDoubleLine(a, b) table.insert(self._lines, a .. " " .. b) end
	function t:GetItem()
		if not self._link then return nil end
		return "item", self._link
	end
	--- what the client does when a tooltip is pointed at an item
	function t:SetHyperlink(link)
		self:ClearLines()
		self._link = link:match("|H(item:[^|]+)|h") or link
		MOCK.run(self, "OnTooltipSetItem")
	end
	return t
end
-- hidden scanning tooltips (GameTooltipTemplate) behave like the real ones
local baseCreateFrame = CreateFrame
function CreateFrame(kind, name, parent, template)
	if kind == "GameTooltip" then
		local t = newTooltip(name)
		function t:NumLines() return #self._lines end
		return t
	end
	return baseCreateFrame(kind, name, parent, template)
end

-- vendors: MOCK.merchant = { npc = name, items = { { id, price, extended, costs = { {name, count, id} }, honor, arena } } }
function GetRealmName() return MOCK.realm or "TestRealm" end
function GetMerchantNumItems() return MOCK.merchant and #MOCK.merchant.items or 0 end
function GetMerchantItemLink(i)
	local it = MOCK.merchant.items[i]
	return it and ("|cffa335ee|Hitem:" .. it.id .. ":0:0:0:0:0:0:0:0|h[Item]|h|r")
end
function GetMerchantItemInfo(i)
	local it = MOCK.merchant.items[i]
	return "Item", "icon", it.price or 0, 1, -1, true, it.extended
end
function GetMerchantItemCostInfo(i)
	local it = MOCK.merchant.items[i]
	return it.honor or 0, it.arena or 0, #(it.costs or {})
end
function GetMerchantItemCostItem(i, j)
	local c = MOCK.merchant.items[i].costs[j]
	return "icon", c[2], c[3] and ("|cffffffff|Hitem:" .. c[3] .. ":0:0:0:0:0:0:0:0|h[" .. c[1] .. "]|h|r")
end

GameTooltip = newTooltip("GameTooltip")
ItemRefTooltip = newTooltip("ItemRefTooltip")
ShoppingTooltip1 = newTooltip("ShoppingTooltip1")
ShoppingTooltip2 = newTooltip("ShoppingTooltip2")

----------------------------------------------------------------------
-- player, items, talents
----------------------------------------------------------------------

-- other units: MOCK.units[token] = { name, class, guid, hostile, threat = {tanking, status, scaled, raw, value} }
MOCK.units = {}
MOCK.party, MOCK.raid, MOCK.combat = 0, 0, false

local function U(unit) return MOCK.units[unit] end

function UnitClass(unit)
	local u = unit and unit ~= "player" and U(unit)
	if u then return u.class, u.class end
	return MOCK.class[1], MOCK.class[2]
end
function UnitName(unit)
	local u = unit and unit ~= "player" and U(unit)
	return u and u.name or "Tester"
end
function UnitGUID(unit)
	local u = unit and unit ~= "player" and U(unit)
	return u and u.guid or "0x0000000000000001"
end
function UnitExists(unit) return unit == "player" or U(unit) ~= nil end
function UnitIsUnit(a, b) return UnitGUID(a) == UnitGUID(b) end
function UnitCanAttack(_, unit) local u = U(unit); return u and u.hostile or false end
function UnitAffectingCombat() return MOCK.combat end
function UnitIsDead(unit) local u = U(unit); return u and u.dead or false end
function UnitIsDeadOrGhost(unit) if unit == "player" then return MOCK.dead or false end return UnitIsDead(unit) end
function UnitClassification(unit) local u = U(unit); return u and u.classification or "normal" end
function GetNumPartyMembers() return MOCK.party end
function GetNumRaidMembers() return MOCK.raid end
function UnitDetailedThreatSituation(unit, mob)
	local key = unit == "player" and "player" or unit
	local t = MOCK.threat and MOCK.threat[key]
	if not t then return nil end
	return t[1], t[2], t[3], t[4], t[5]
end
-- the client's bit library (plain Lua 5.1 has none)
bit = {
	band = function(a, b)
		local r, p = 0, 1
		a, b = a % 4294967296, b % 4294967296
		while a > 0 and b > 0 do
			if a % 2 == 1 and b % 2 == 1 then r = r + p end
			a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
		end
		return r
	end,
}

MOCK.sent = {}
function SendChatMessage(msg, channel) table.insert(MOCK.sent, channel .. ": " .. msg) end
MOCK.instance = false
function IsInInstance() return MOCK.instance, MOCK.instance and "party" or "none" end
function GetRealZoneText() return MOCK.zone or "Dalaran" end

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
function UnitFactionGroup() return MOCK.faction end
function GetActiveTalentGroup() return 1 end
function GetNumTalentTabs() return 3 end

-- Talent trees: MOCK.tree[tab] = { {name, icon, tier, col, rank, max, prev}, ... }
-- filled by the tests from the realm's real tree data. Without one, only
-- the per-tree point totals in MOCK.talents exist (enough to detect a spec).
MOCK.free = 0
local function TreePoints(tab)
	if not MOCK.tree then return MOCK.talents[tab] or 0 end
	local n = 0
	for _, t in ipairs(MOCK.tree[tab] or {}) do n = n + t.rank end
	return n
end
function GetTalentTabInfo(i) return "Tree" .. i, "icon", TreePoints(i), "bg", 0 end
function GetNumTalents(tab) return MOCK.tree and #(MOCK.tree[tab] or {}) or 0 end
function GetTalentInfo(tab, i)
	local t = MOCK.tree and MOCK.tree[tab] and MOCK.tree[tab][i]
	if not t then return nil end
	return t.name, t.icon, t.tier, t.col, t.rank, t.max, false, true, t.rank + (t.prev or 0), true
end
function GetUnspentTalentPoints() return MOCK.free end
function ResetGroupPreviewTalentPoints()
	for _, tab in ipairs(MOCK.tree or {}) do for _, t in ipairs(tab) do t.prev = 0 end end
end
--- Like the client: refuses points beyond the free ones, or into a tier
--- whose 5-points-per-tier requirement the tree does not meet yet.
function AddPreviewTalentPoints(tab, i, n)
	local used = 0
	for _, tb in ipairs(MOCK.tree) do for _, t in ipairs(tb) do used = used + (t.prev or 0) end end
	local t = MOCK.tree[tab][i]
	local below = 0
	for _, o in ipairs(MOCK.tree[tab]) do
		if o.tier < t.tier then below = below + o.rank + (o.prev or 0) end
	end
	if below < (t.tier - 1) * 5 then return end
	n = math.min(n, MOCK.free - used, t.max - t.rank - (t.prev or 0))
	if n > 0 then t.prev = (t.prev or 0) + n end
end
function SetCVar(k, v) MOCK.cvars = MOCK.cvars or {}; MOCK.cvars[k] = v end
function GetCVar(k) return MOCK.cvars and MOCK.cvars[k] end
function IsAddOnLoaded() return MOCK.talentUI end
function LoadAddOn() MOCK.talentUI = true end
function ToggleTalentFrame() MOCK.talentFrameOpened = true end

-- glyph sockets: MOCK.glyphSockets[s] = { kind (1 major, 2 minor), spellID }
MOCK.glyphSockets, MOCK.spellNames = {}, {}
function GetNumGlyphSockets() return 6 end
function GetGlyphSocketInfo(s)
	local g = MOCK.glyphSockets[s]
	if not g then return true, (s % 2 == 1) and 1 or 2, nil end
	return true, g[1], g[2]
end
function IsShiftKeyDown() return MOCK.shift end
-- MOCK.enchants[slot] = enchant id, MOCK.gems[slot] = { gem ids }
MOCK.enchants, MOCK.gems, MOCK.itemStats = {}, {}, {}
function GetInventoryItemLink(unit, slot)
	local id = MOCK.inventory[slot]
	if not id then return nil end
	local g = MOCK.gems[slot] or {}
	return string.format("|cffa335ee|Hitem:%d:%d:%d:%d:%d:0:0:0:0|h[Item %d]|h|r", id, MOCK.enchants[slot] or 0,
		g[1] or 0, g[2] or 0, g[3] or 0, id)
end
function GetItemStats(link)
	local id = tonumber(link:match("item:(%d+)"))
	return MOCK.itemStats[id] or (MOCK.items[id] and MOCK.items[id].stats) or {}
end

-- auras: MOCK.auras[unit] = { { name, expires (0 = no duration), mine, harmful }, ... }
MOCK.auras = {}
function UnitAura(unit, name, rank, filter)
	filter = filter or ""
	for _, a in ipairs(MOCK.auras[unit] or {}) do
		local harmful = a[4] and true or false
		if a[1] == name and (harmful == (filter:find("HARMFUL") ~= nil))
			and (not filter:find("PLAYER") or a[3]) then
			return a[1], "", "icon", 1, nil, 30, a[2], a[3] and "player" or "other"
		end
	end
end
function UnitDebuff(unit, name, rank, filter) return UnitAura(unit, name, rank, "HARMFUL|" .. (filter or "")) end

-- spells: MOCK.known[name] = cast time in ms (known spells only); MOCK.cd[name] = { start, duration }
MOCK.known, MOCK.cd = {}, {}
function GetSpellCooldown(name)
	local c = MOCK.cd[name]
	if not c then return 0, 0, 1 end
	return c[1], c[2], 1
end
function UnitCastingInfo(unit)
	local c = unit == "player" and MOCK.casting
	if not c then return nil end
	return c[1], "", c[1], "icon", MOCK.time * 1000, c[2] * 1000
end
function UnitHealth(unit) local u = U(unit); return u and u.hp or 100 end
function UnitHealthMax(unit) local u = U(unit); return u and u.maxhp or 100 end

-- professions: MOCK.skills = { { name, isHeader, rank }, ... }
MOCK.skills = {}
function GetNumSkillLines() return #MOCK.skills end
function GetSkillLineInfo(i) local s = MOCK.skills[i]; return s[1], s[2], false, s[3] end

-- ratings: MOCK.rating[cr], MOCK.ratingBonus[cr] (percent or points)
MOCK.rating, MOCK.ratingBonus = {}, {}
function GetCombatRating(cr) return MOCK.rating[cr] or 0 end
function GetCombatRatingBonus(cr) return MOCK.ratingBonus[cr] or 0 end
function GetSpellHitModifier() return MOCK.spellHitMod or 0 end
function GetHitModifier() return MOCK.hitMod or 0 end
function GetExpertise() return MOCK.expertise or 0, MOCK.expertise or 0 end
function UnitDefense() return 400, MOCK.defenseMod or 0 end

-- the client item cache: tests put equipLoc in for items it "has seen"
function GetItemInfo(id)
	if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
	local it = MOCK.items[id]
	if not it then return nil end
	return it.name or ("Item " .. id), "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[Item]|h|r",
		it.q or 4, it.ilvl or 200, 80, it.type or "Armor", it.sub or "Cloth", 1, it.equipLoc or "", "Interface\\Icons\\X"
end
function GetItemIcon(id) return "Interface\\Icons\\Item" .. tostring(id) end
--- By ID: any spell, named from MOCK.spellNames. By name: only spells the
--- player knows (MOCK.known), with their cast time -- as the client does.
function GetSpellInfo(id)
	if type(id) == "string" then
		local ms = MOCK.known and MOCK.known[id]
		if not ms then return nil end
		return id, "", "Interface\\Icons\\" .. id, 0, false, 0, ms
	end
	local name = (MOCK.spellNames and MOCK.spellNames[id]) or ("Spell " .. tostring(id))
	return name, "", "Interface\\Icons\\" .. name, 0, false, 0, (MOCK.known and MOCK.known[name]) or 0
end
function GetCoinTextureString(c) return tostring(math.floor(c / 10000)) .. "g" end
function HandleModifiedItemClick() return false end
function GetAddOnMetadata(_, key) return key == "Version" and "0.test" or nil end
function GetCursorPosition() return 0, 0 end
function PlaySoundFile() end

ITEM_QUALITY_COLORS = {}
for q = 0, 7 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffq" .. q .. "q" } end
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert

----------------------------------------------------------------------
-- stock UI helpers the addon calls
----------------------------------------------------------------------

function InterfaceOptions_AddCategory(p) table.insert(MOCK.panels, p) end
function InterfaceOptionsFrame_OpenToCategory(p) MOCK.openedPanel = p end

MOCK.dropdownButtons = {}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(dd, t) dd._ddtext = t end
function UIDropDownMenu_Initialize(dd, fn)
	dd.initialize = fn
	MOCK.dropdownButtons = {}
	fn(1)                          -- 3.3.5a calls it as initFunction(level, menuList)
end
function UIDropDownMenu_AddButton(info) table.insert(MOCK.dropdownButtons, info) end

--- Open a dropdown and click the entry whose value is v, as a player would.
function MOCK.pickDropdown(dd, v)
	MOCK.dropdownButtons = {}
	dd.initialize(1)
	for _, info in ipairs(MOCK.dropdownButtons) do
		if info.value == v then
			info.func({ value = info.value })
			return true
		end
	end
	return false
end

function FauxScrollFrame_GetOffset(f) return f._offset or 0 end
function FauxScrollFrame_SetOffset(f, o) f._offset = o end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll(f, offset, h, fn) f._offset = math.floor(offset / h + 0.5); fn() end
