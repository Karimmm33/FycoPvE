--[[ FycoPvE - Modules/Scanner.lua
     Records what this server actually has, for the server pack.

     Custom realms sell custom items, and their stats exist only on the
     server -- not in the client files, not in any public database. So:

       Vendor scan  every vendor you open is read in full (every page: the
                    list is not paged for an addon): name, slot, item level,
                    armour type, every stat, the green Equip/Use/Set lines,
                    and the cost (gold, honor, arena, or items/currency).
       BiS scan     /fpve scan bis asks the server for the items on your
                    class's BiS lists and records their stats the same way,
                    so custom and guide items are compared on this server's
                    numbers, not a database's.

     Saved to FycoPvEDB.serverScan. scripts/build_realm_pack.py reads it and builds
     the server pack (Data/Realm/*.lua).                                 ]]

local ADDON, ns = ...
local M = ns:Module("scanner", 80)

local tip
local function Tip()
	if not tip then
		tip = CreateFrame("GameTooltip", "FycoPvEScanTip", UIParent, "GameTooltipTemplate")
		tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	end
	return tip
end

local function Store()
	FycoPvEDB.serverScan = FycoPvEDB.serverScan or {}
	local s = FycoPvEDB.serverScan
	s.realm = GetRealmName and GetRealmName() or s.realm
	s.vendors = s.vendors or {}
	s.items = s.items or {}
	return s
end

--- Everything about one item the client can tell us, or nil if the server
--- has not sent it yet (ask again shortly).
local function Record(link)
	local name, _, quality, ilvl, _, itype, subtype, _, loc = GetItemInfo(link)
	if not name then return nil end
	local rec = { n = name, q = quality, ilvl = ilvl, loc = loc, type = itype, sub = subtype, stats = {}, lines = {} }
	for k, v in pairs(GetItemStats(link) or {}) do rec.stats[k] = v end
	-- the green lines: procs, on-use effects and set bonuses are not stats
	local t = Tip()
	t:ClearLines()
	t:SetHyperlink(link)
	for i = 2, t:NumLines() do
		local fs = _G["FycoPvEScanTipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text and (text:find("^Equip:") or text:find("^Use:") or text:find("^Chance on hit:")
			or text:find("^%(%d%) Set:") or text:find("^Set:")) then
			rec.lines[#rec.lines + 1] = text
		end
	end
	return rec
end

local function ItemID(link) return link and tonumber(link:match("item:(%d+)")) end

----------------------------------------------------------------------
-- vendors
----------------------------------------------------------------------

local pending = {}      -- merchant index -> true while the item is not cached yet
local vendorName

local function ScanVendor()
	if not ns:Get("scan", "vendors") then return end
	vendorName = UnitName("npc") or "Vendor"
	local s = Store()
	local v = s.vendors[vendorName] or {}
	s.vendors[vendorName] = v
	local got, waiting = 0, 0
	for i = 1, (GetMerchantNumItems() or 0) do
		local link = GetMerchantItemLink(i)
		local id = ItemID(link)
		local rec = id and Record(link)
		if rec then
			local _, _, price, qty, _, _, extended = GetMerchantItemInfo(i)
			local cost = { gold = (price and price > 0) and price or nil, qty = qty }
			if extended then
				local honor, arena, n = GetMerchantItemCostInfo(i)
				cost.honor = (honor and honor > 0) and honor or nil
				cost.arena = (arena and arena > 0) and arena or nil
				cost.items = {}
				for j = 1, (n or 0) do
					local _, value, clink = GetMerchantItemCostItem(i, j)
					local cname = clink and (GetItemInfo(clink) or clink:match("%[(.-)%]")) or "currency"
					cost.items[#cost.items + 1] = { name = cname, count = value, id = ItemID(clink) }
				end
			end
			rec.cost = cost
			v[id] = rec
			s.items[id] = s.items[id] or rec
			pending[i] = nil
			got = got + 1
		elseif id then
			pending[i] = true
			waiting = waiting + 1
		end
	end
	return got, waiting
end

local lastReport = 0
local function Report(got, waiting)
	if not got or GetTime() - lastReport < 2 then return end
	lastReport = GetTime()
	ns:Print(string.format("recorded %d items from |cffffff00%s|r%s", got, vendorName or "vendor",
		waiting > 0 and (" |cff808080(" .. waiting .. " still loading - they will be picked up in a moment)|r") or ""))
end

----------------------------------------------------------------------
-- BiS items
----------------------------------------------------------------------

local queue, qi, queueDone = nil, 0, 0

--- Ask the server for every item on this class's lists (the given phase,
--- or all phases) and record their stats, one item at a time so the
--- server is never flooded (0.2s per item).
function ns:ScanBiS(allPhases)
	local class = ns:PlayerClass()
	local ids, seen = {}, {}
	for _, phases in pairs(ns.BiS[class] or {}) do
		for phase, lists in pairs(phases) do
			if allPhases or phase == ns:Phase() then
				for _, list in pairs(lists) do
					for _, e in ipairs(list) do
						if not seen[e[1]] then seen[e[1]] = true; ids[#ids + 1] = e[1] end
					end
				end
			end
		end
	end
	queue, qi, queueDone = ids, 0, 0
	ns:Print(string.format("recording this server's stats for %d BiS items (about %d seconds)...", #ids,
		math.ceil(#ids * 0.2)))
end

local tries = {}
local function StepBiS()
	if not queue then return end
	qi = qi + 1
	local id = queue[qi]
	if not id then
		ns:Print(string.format("BiS scan done: %d of %d items recorded. |cffffff00/reload|r (or log out) to save them.",
			queueDone, #queue))
		queue, tries = nil, {}
		return
	end
	local link = "item:" .. id .. ":0:0:0:0:0:0:0:0"
	local rec = Record(link)
	if rec then
		Store().items[id] = rec
		queueDone = queueDone + 1
	else
		-- ask the server, then come back to it at the end of the queue
		Tip():SetHyperlink(link)
		tries[id] = (tries[id] or 0) + 1
		if tries[id] < 3 then queue[#queue + 1] = id end
	end
end

function ns:ScanStatus()
	local s = FycoPvEDB.serverScan or {}
	local vendors, vitems, items = 0, 0, 0
	for _, v in pairs(s.vendors or {}) do
		vendors = vendors + 1
		for _ in pairs(v) do vitems = vitems + 1 end
	end
	for _ in pairs(s.items or {}) do items = items + 1 end
	return vendors, vitems, items
end

function ns:ScanReport()
	local s = FycoPvEDB.serverScan or {}
	local vendors, vitems, items = ns:ScanStatus()
	ns:Print(string.format("server data for |cffffff00%s|r: %d vendor%s (%d items), %d items with stats in total",
		s.realm or "?", vendors, vendors == 1 and "" or "s", vitems, items))
	for name, v in pairs(s.vendors or {}) do
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		ns:Print("  " .. name .. ": " .. n .. " items")
	end
end

function ns:ScanClear()
	FycoPvEDB.serverScan = nil
	ns:Print("recorded server data cleared")
end

function M:OnLoad()
	ns:On("MERCHANT_SHOW", function()
		pending = {}
		Report(ScanVendor())
	end)
	ns:On("MERCHANT_UPDATE", function() ScanVendor() end)
	ns:On("MERCHANT_CLOSED", function() pending = {}; vendorName = nil end)
	local acc = 0
	ns:OnTick(function()
		acc = acc + 1
		-- items the server had not sent yet: look again every half second
		if next(pending) and acc % 5 == 0 then
			local got, waiting = ScanVendor()
			if waiting == 0 then Report(got, 0) end
		end
		if queue and acc % 2 == 0 then StepBiS() end   -- 0.2s per BiS item
	end)
end
