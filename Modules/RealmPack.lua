--[[ FycoPvE - Modules/RealmPack.lua
     Server packs: custom gear a particular server sells, merged into the
     BiS lists -- only on that server, and only if you want it.

     A pack (Data/Realm/<Server>.lua, built by scripts/build_realm_pack.py
     from what the scanner recorded) carries the custom items and, for each
     spec it covers, the complete merged list per phase and slot. Switching
     the pack on swaps those lists in; switching it off puts the guide's
     lists back exactly. Nothing else in the addon needs to know.

     "Auto" turns a pack on only when the realm you are on is the pack's
     realm, so the same addon on another server never shows custom gear. ]]

local ADDON, ns = ...
local M = ns:Module("realmpack", 3)

ns.RealmPacks = {}

function ns:RegisterRealmPack(key, pack)
	pack.key = key
	ns.RealmPacks[#ns.RealmPacks + 1] = pack
end

local function RealmMatches(pack)
	local realm = (GetRealmName and GetRealmName() or ""):lower()
	return realm ~= "" and realm:find(pack.key:lower(), 1, true) ~= nil
end

--- Is this pack in use right now?
function ns:RealmPackActive(pack)
	local mode = ns:Get("general", "realmPack")
	if mode == "off" then return false end
	if mode == "on" then return true end
	return RealmMatches(pack)
end

--- Swap every pack's lists and items in or out to match the setting.
function ns:ApplyRealmPacks()
	for _, pack in ipairs(ns.RealmPacks) do
		local on = ns:RealmPackActive(pack)
		pack.orig = pack.orig or {}
		for class, specs in pairs(pack.lists or {}) do
			for spec, phases in pairs(specs) do
				for phase, slots in pairs(phases) do
					local lists = ns:BiSLists(class, spec, phase)
					if lists then
						for slot, merged in pairs(slots) do
							local key = class .. "/" .. spec .. "/" .. phase .. "/" .. slot
							if pack.orig[key] == nil then pack.orig[key] = lists[slot] or false end
							if on then
								lists[slot] = merged
							else
								lists[slot] = pack.orig[key] or nil
							end
						end
					end
				end
			end
		end
		-- A pack item may be a normal item the addon already knows (on this
		-- server, Emblem gear sold for renamed currency); keep that record so
		-- switching the pack off gives the normal entry back, not a hole.
		pack.origItems = pack.origItems or {}
		for id, rec in pairs(pack.items or {}) do
			rec.custom = pack.name
			if pack.origItems[id] == nil then pack.origItems[id] = ns.Items[id] or false end
			if on then
				ns.Items[id] = rec
			elseif ns.Items[id] == rec then
				ns.Items[id] = pack.origItems[id] or nil
			end
		end
		pack.on = on
	end
	ns:RebuildBiSIndex()
	if ns.SearchReset then ns:SearchReset() end
	ns:Fire("ProfileChanged")
end

--- "Frostmourne Rebuffed - on (12 custom items)" for the settings page.
function ns:RealmPackStatus()
	if #ns.RealmPacks == 0 then return "No server packs are installed." end
	local out = {}
	for _, pack in ipairs(ns.RealmPacks) do
		local n = 0
		for _ in pairs(pack.items or {}) do n = n + 1 end
		out[#out + 1] = string.format("%s: %s (%d custom item%s)%s", pack.name,
			pack.on and "|cff40ff40on|r" or "|cff808080off|r", n, n == 1 and "" or "s",
			RealmMatches(pack) and "" or " |cff808080- not this realm|r")
	end
	return table.concat(out, "\n")
end

function M:OnLoad()
	ns:ApplyRealmPacks()
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "general" and key == "realmPack" then ns:ApplyRealmPacks() end
	end)
end

----------------------------------------------------------------------
-- settings page: the pack switch and the scanner
----------------------------------------------------------------------

local MODES = {
	{ value = "auto", text = "Auto - only on that server" },
	{ value = "on", text = "Always on" },
	{ value = "off", text = "Off" },
}

ns:RegisterOptions("server", "Server data", 70, function(L, R)
	L:Title("Custom server gear")
	L:Note("Some servers sell custom gear (Frostmourne Rebuffed has a Valor Points vendor). A server pack "
	    .. "adds the pieces that beat the guide's to your BiS lists, marked as custom. Auto uses a pack only "
	    .. "on its own server.")
	L:Dropdown("Server packs", 200, {
		items = function() return MODES end,
		get = function() return ns:Get("general", "realmPack") end,
		set = function(v) ns:Set("general", "realmPack", v) end,
	})
	local status = L:Note(ns:RealmPackStatus())
	status.Refresh = function() status:SetText(ns:RealmPackStatus()) end
	L:track(status)
	L:Note("Custom items are ranked by FycoPvE's stat weights, not by a simulation - treat their place as "
	    .. "an estimate. So far the pack covers Affliction and Destruction warlocks.")

	R:Title("Record server data")
	R:Check("Record every vendor I open", "Every item a vendor sells, with stats and cost",
		function() return ns:Get("scan", "vendors") end, function(v) ns:Set("scan", "vendors", v) end)
	R:Buttons("Scan BiS items", function() ns:ScanBiS(false) end,
	          "All phases", function() ns:ScanBiS(true) end)
	R:Note("Records this server's stats for the items on your class's BiS lists (this phase, or all), so "
	    .. "custom and guide items are compared on the same numbers.")
	R:Buttons("Show recorded", function() ns:ScanReport() end,
	          "Clear recorded", function() ns:ScanClear() end)
	R:Note("Recorded data is saved when you /reload or log out.")
end)
