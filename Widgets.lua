--[[ FycoPvE - Widgets.lua
     Small UI building blocks the window tabs and the options panels share:
     dropdowns, item buttons and item link/colour helpers. Built from stock
     3.3.5a templates only, so the addon has zero dependencies.             ]]

local ADDON, ns = ...

local UI = {}
ns.UI = UI

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

--- "|cffa335ee" for a quality number, falling back to white.
function UI.QualityHex(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	return (c and c.hex) or "|cffffffff"
end

--- A clickable item link. Uses the client's own link when the item is in its
--- cache; otherwise builds one from our data, which renders and links the same.
function UI.ItemLink(id)
	local _, link = GetItemInfo(id)
	if link then return link end
	local it = ns.Items[id]
	local name = it and it.n or ("item " .. id)
	return UI.QualityHex(it and it.q) .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
end

function UI.ItemName(id)
	local it = ns.Items[id]
	local name = (it and it.n) or GetItemInfo(id) or ("item " .. id)
	return UI.QualityHex(it and it.q) .. name .. "|r"
end

--- Icon path. GetItemIcon answers even for items the client has not cached;
--- GetItemInfo only answers once it has, so it is the fallback, not the rule.
function UI.ItemIcon(id)
	if not id then return nil end
	local tex = GetItemIcon and GetItemIcon(id)
	if not tex then tex = select(10, GetItemInfo(id)) end
	return tex or QUESTION
end

--- Which side a tooltip should open on so it does not run off the screen.
function UI.AnchorFor(frame)
	local x = frame:GetCenter()
	local w = UIParent:GetWidth()
	if not x or not w then return "ANCHOR_RIGHT" end
	return (x > w / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

----------------------------------------------------------------------
-- item button: icon, item tooltip on hover, shift-click links it
----------------------------------------------------------------------

function UI.ItemButton(parent, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(size)
	b:SetHeight(size)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints(b)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	function b:SetItem(id, link)
		self.itemID, self.link = id, link
		if id then
			self.icon:SetTexture(UI.ItemIcon(id))
			self.icon:SetVertexColor(1, 1, 1)
			self:Show()
		else
			self.icon:SetTexture(QUESTION)
			self.icon:SetVertexColor(0.3, 0.3, 0.3)
		end
	end

	b:SetScript("OnEnter", function(self)
		if not self.itemID then return end
		GameTooltip:SetOwner(self, UI.AnchorFor(self))
		GameTooltip:SetHyperlink(self.link or ("item:" .. self.itemID .. ":0:0:0:0:0:0:0:0"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self, button)
		if not self.itemID then return end
		-- shift links it into chat, ctrl opens the dressing room; returns
		-- false when no modifier is held
		if HandleModifiedItemClick(self.link or UI.ItemLink(self.itemID)) then return end
		if onClick then onClick(self, button) end
	end)
	return b
end

----------------------------------------------------------------------
-- dropdown
----------------------------------------------------------------------

--- A stock dropdown driven by three functions, so the same widget serves the
--- window header and the options panels and both always show the live value:
---   opts.items() -> { { value = v, text = "label" }, ... }
---   opts.get()   -> the selected value
---   opts.set(v)
--- The template needs a global name; `name` must be unique.
function UI.Dropdown(parent, name, width, opts)
	local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, width)

	-- Re-run by the client every time the menu opens, so the ticks are always
	-- current. Arguments are ignored on purpose: 3.3.5a passes them in a
	-- different order than later clients, and these menus have one level.
	local function init()
		local list, cur = opts.items(), opts.get()
		for i = 1, #list do
			local e = list[i]
			local info = UIDropDownMenu_CreateInfo()
			info.text = e.text
			info.value = e.value
			info.checked = (e.value == cur)
			info.func = function(btn)
				opts.set(btn.value)
				dd.Refresh()
			end
			UIDropDownMenu_AddButton(info)
		end
	end

	-- Initialise once. Doing it again on every refresh would close whatever
	-- dropdown menu the player has open at that moment.
	UIDropDownMenu_Initialize(dd, init)

	function dd.Refresh()
		local list, cur = opts.items(), opts.get()
		local text = ""
		for i = 1, #list do
			if list[i].value == cur then text = list[i].text end
		end
		UIDropDownMenu_SetText(dd, text)
	end

	return dd
end

----------------------------------------------------------------------
-- dropdown contents shared by the window and the options
----------------------------------------------------------------------

--- "Auto (Affliction)" plus every spec of the player's class, marking the
--- ones there is no list for yet so an empty result is not a surprise.
function UI.SpecItems()
	local class = ns:PlayerClass()
	local info = ns.Classes[class]
	local out = { { value = "auto", text = "Auto (" .. (ns:DetectSpec() or "?") .. ")" } }
	for i = 1, #(info and info.specs or {}) do
		local spec = info.specs[i][1]
		local has = ns.BiS[class] and ns.BiS[class][spec]
		out[#out + 1] = { value = spec, text = has and spec or (spec .. " |cff808080(no lists yet)|r") }
	end
	return out
end

function UI.SpecGet()
	return ns:SpecIsAuto() and "auto" or ns:Spec()
end

function UI.PhaseItems()
	local class, spec = ns:PlayerClass(), ns:Spec()
	local out = {}
	for i = 1, #ns.Phases do
		local p = ns.Phases[i]
		local has = ns:BiSLists(class, spec, p.key)
		out[#out + 1] = { value = p.key, text = has and p.name or (p.name .. " |cff808080(no list yet)|r") }
	end
	return out
end
