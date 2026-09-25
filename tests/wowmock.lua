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
function GetTalentTabInfo(i) return "Tree" .. i, "icon", MOCK.talents[i] or 0, "bg", 0 end
function IsShiftKeyDown() return MOCK.shift end
function GetInventoryItemLink(unit, slot)
	local id = MOCK.inventory[slot]
	if not id then return nil end
	return "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[Item " .. id .. "]|h|r"
end

-- the client item cache: tests put equipLoc in for items it "has seen"
function GetItemInfo(id)
	if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
	local it = MOCK.items[id]
	if not it then return nil end
	return it.name or ("Item " .. id), "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[Item]|h|r",
		4, 200, 80, "Armor", "Cloth", 1, it.equipLoc or "", "Interface\\Icons\\X"
end
function GetItemIcon(id) return "Interface\\Icons\\Item" .. tostring(id) end
function GetSpellInfo(id) return "Spell " .. tostring(id) end
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
