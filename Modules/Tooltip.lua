--[[ FycoPvE - Modules/Tooltip.lua
     Adds the BiS verdict to every item tooltip: bags, links, the character
     sheet, loot windows, vendors, the auction house. So "is this worth
     taking?" is answered before you equip anything.

       FycoPvE  BiS: Head - Best #2/12 (Affliction, Pre-Raid)
       Drop: Salramm the Fleshcrafter - The Culling of Stratholme (Heroic)  ]]

local ADDON, ns = ...
local M = ns:Module("tooltip", 30)

local MAX_LINES = 6

local function Lines(tt, id)
	local entries = ns.BiSIndex[id]
	local scope = ns:Get("tooltip", "scope")
	local class, spec, phase = ns:PlayerClass(), ns:Spec(), ns:Phase()
	local threshold = ns:Get("gear", "bisTier")
	local shown = 0

	for i = 1, #(entries or {}) do
		local e = entries[i]
		local mine = e.class == class
		local ok = scope == "all"
			or (scope == "class" and mine)
			or (mine and e.spec == spec and e.phase == phase)
		if ok and shown < MAX_LINES then
			shown = shown + 1
			local who = e.spec .. ((mine and scope ~= "all") and "" or (" " .. (ns.Classes[e.class] and ns.Classes[e.class].name or e.class)))
			local label = e.tier <= threshold and "|cff40ff40BiS|r" or "Ranked"
			tt:AddLine(string.format("|cff66ccffFycoPvE|r %s: %s %s  |cff808080(%s, %s)|r",
				label, ns.ListName[e.list] or e.list, ns:TierText(e.tier, e.pos, e.count),
				who, ns.PhaseName[e.phase] or e.phase))
		end
	end

	if ns:Get("tooltip", "sources") and ns.Items[id] and (shown > 0 or scope == "all") then
		local src = ns:SourceSummary(id)
		if src then tt:AddLine(src, 1, 1, 1, true) end
		local rep = ns:RepText(id)
		if rep then tt:AddLine(rep, 1, 0.5, 0.25) end
	end
	return shown
end

local function OnSetItem(tt)
	if tt.fycopveDone or not ns:Enabled("tooltip") then return end
	if ns:Get("tooltip", "shiftOnly") and not IsShiftKeyDown() then return end
	local _, link = tt:GetItem()
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id then return end
	-- OnTooltipSetItem can fire more than once for one item (comparison
	-- tooltips re-set themselves); mark it so the lines are added once
	tt.fycopveDone = true
	Lines(tt, id)
	tt:Show()   -- resize to fit the new lines
end

local function Hook(tt)
	if not tt then return end
	tt:HookScript("OnTooltipSetItem", OnSetItem)
	tt:HookScript("OnTooltipCleared", function(self) self.fycopveDone = nil end)
end

function M:OnLoad()
	Hook(GameTooltip)
	Hook(ItemRefTooltip)
	Hook(ShoppingTooltip1)
	Hook(ShoppingTooltip2)
end

----------------------------------------------------------------------
-- settings panel
----------------------------------------------------------------------

local SCOPES = {
	{ value = "spec",  text = "My spec and phase" },
	{ value = "class", text = "Every spec and phase of my class" },
	{ value = "all",   text = "Every class" },
}

ns:RegisterOptions("tooltip", "Tooltips", 20, function(L, R)
	L:Title("Item tooltips")
	L:Note("A line on every item tooltip saying where the item ranks on your BiS "
	    .. "list. Works in bags, links, loot, vendors and the auction house.")
	L:Check("Show BiS lines on tooltips", nil,
		function() return FycoPvEDB.enabled.tooltip ~= false end,
		function(v) FycoPvEDB.enabled.tooltip = v end)
	L:Dropdown("Which lists", 200, {
		items = function() return SCOPES end,
		get = function() return ns:Get("tooltip", "scope") end,
		set = function(v) ns:Set("tooltip", "scope", v) end,
	})
	L:Check("Only while Shift is held", nil,
		function() return ns:Get("tooltip", "shiftOnly") end,
		function(v) ns:Set("tooltip", "shiftOnly", v) end)

	R:Title("Where it comes from")
	R:Check("Add a source line", "The first place it drops or is sold, and any "
	     .. "reputation it needs",
		function() return ns:Get("tooltip", "sources") end,
		function(v) ns:Set("tooltip", "sources", v) end)
	R:Note("The full list of sources is in the Search tab - click any item there.")
end)
