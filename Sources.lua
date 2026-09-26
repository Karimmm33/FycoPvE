--[[ FycoPvE - Sources.lua
     Turns the generated source records in Data/Items.lua into readable text:
     "Drop: Salramm the Fleshcrafter - The Culling of Stratholme (Heroic)",
     "Vendor: Knight Dameron <Wintergrasp Quartermaster> - 40 Wintergrasp Mark
     of Honor". One place, so the tooltip, the gear tab and search agree.

     Everything here comes from a database of the stock 3.3.5 game, not from
     this server. Custom realms change drops and prices, and the UI says so. ]]

local _, ns = ...

local WHITE, GREY, GOLD = "|cffffffff", "|cffa0a0a0", "|cffffd200"

local function Money(copper)
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	return string.format("%dg %ds %dc", copper / 10000, (copper / 100) % 100, copper % 100)
end

--- "40 Emblem of Heroism + 25 Honor" from a cost record.
function ns:FormatCost(c)
	if not c then return nil end
	local parts = {}
	local items = c.items or {}
	for i = 1, #items, 2 do
		parts[#parts + 1] = items[i + 1] .. " " .. (ns.Currency[items[i]] or ("item " .. items[i]))
	end
	if c.honor then parts[#parts + 1] = c.honor .. " Honor" end
	if c.arena then parts[#parts + 1] = c.arena .. " Arena points" end
	if c.gold then parts[#parts + 1] = Money(c.gold) end
	if c.text then parts[#parts + 1] = c.text end   -- a server's own currency, as the vendor names it
	local text = table.concat(parts, " + ")
	if c.rating then text = text .. " (needs " .. c.rating .. " personal rating)" end
	return text ~= "" and text or nil
end

local function Where(s)
	local t = ""
	if s.zone then t = " - " .. s.zone end
	if s.mode then t = t .. " (" .. s.mode .. ")" end
	return t
end

--- One line for one source record. `short` drops the detail a tooltip has
--- no room for.
function ns:FormatSource(s, short)
	if s.t == "drop" then
		local pct = ""
		if s.pct and not short then
			pct = GREY .. string.format(s.pct < 1 and " %.1f%%" or " %.0f%%", s.pct) .. "|r"
		end
		return GOLD .. "Drop:|r " .. WHITE .. s.who .. "|r" .. Where(s) .. pct
	elseif s.t == "chest" then
		return GOLD .. "Chest:|r " .. WHITE .. s.who .. "|r" .. Where(s)
	elseif s.t == "vendor" then
		local who = WHITE .. s.who .. "|r"
		if s.title and not short then who = who .. " <" .. s.title .. ">" end
		local cost = ns:FormatCost(s.cost)
		return GOLD .. "Vendor:|r " .. who .. (s.zone and (" - " .. s.zone) or "")
			.. (cost and (": " .. cost) or "")
	elseif s.t == "quest" then
		local extra = ""
		if s.side then extra = extra .. " [" .. s.side .. "]" end
		if s.choice and not short then extra = extra .. GREY .. " (choice of reward)|r" end
		return GOLD .. "Quest:|r " .. WHITE .. s.who .. "|r" .. (s.zone and (" - " .. s.zone) or "") .. extra
	elseif s.t == "craft" then
		if s.bop then
			return GOLD .. "Crafted:|r " .. WHITE .. s.who .. "|r" .. (short and "" or (GREY
				.. " - bind on pickup: only someone with " .. s.who .. " can use it|r"))
		end
		return GOLD .. "Crafted:|r " .. WHITE .. s.who .. "|r" .. (short and "" or (GREY
			.. " - from a player with it, or the Auction House|r"))
	elseif s.t == "world" then
		return GOLD .. "World drop:|r Bind on Equip, from " .. s.n .. " kinds of creature - check the Auction House"
	elseif s.t == "more" then
		return GREY .. "...and " .. s.n .. " more vendors|r"
	end
	return GREY .. "unknown source|r"
end

--- The guide's own note, with {spell:N} resolved by the client, e.g. a
--- crafting recipe: "Visage Liquification Goggles - Engineering".
function ns:GuideNote(id)
	local it = ns.Items[id]
	local g = it and it.g
	if not g then return nil end
	return (g:gsub("{spell:(%d+)}", function(n)
		return (GetSpellInfo(tonumber(n))) or "a recipe"
	end))
end

function ns:RepText(id)
	local it = ns.Items[id]
	if it and it.rep then
		return "Requires " .. it.rep[1] .. " - " .. it.rep[2]
	end
end

--- Every line about where an item comes from, for the search detail pane.
function ns:SourceLines(id)
	local it = ns.Items[id]
	local lines = {}
	if not it then return lines end
	for i = 1, #(it.src or {}) do
		lines[#lines + 1] = ns:FormatSource(it.src[i])
	end
	local rep = ns:RepText(id)
	if rep then lines[#lines + 1] = "|cffff8040" .. rep .. "|r" end
	if it.custom then
		lines[#lines + 1] = "|cffff9020Custom " .. it.custom .. " item.|r " .. GREY .. "Ranked by FycoPvE's stat "
			.. "weights on this server's stats - an estimate, not a simulation.|r"
		for _, l in ipairs(it.lines or {}) do lines[#lines + 1] = "|cff20ff20" .. l .. "|r" end
	end
	if it.side then lines[#lines + 1] = GREY .. it.side .. " only|r" end
	local note = ns:GuideNote(id)
	if note then lines[#lines + 1] = GREY .. "Guide says: " .. note .. "|r" end
	return lines
end

--- One short line: the first real source, or the guide's note when the
--- database has none (crafted items).
function ns:SourceSummary(id)
	local it = ns.Items[id]
	if not it then return nil end
	if it.src and it.src[1] then
		local s = ns:FormatSource(it.src[1], true)
		if #it.src > 1 and it.src[2].t ~= "more" then s = s .. GREY .. " (+" .. (#it.src - 1) .. " more)|r" end
		return s
	end
	local note = ns:GuideNote(id)
	return note and (GOLD .. "Source:|r " .. note)
end
