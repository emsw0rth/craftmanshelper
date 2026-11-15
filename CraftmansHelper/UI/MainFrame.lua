-- Main window: "My Writs" (grouped by continent, then zone A-Z) and "All Writs".
local _, ns = ...
local CH = ns.CH
local AceGUI = LibStub("AceGUI-3.0")
local STATUS = ns.STATUS

local UI = CH:NewModule("UI", "AceEvent-3.0")
CH.UI = UI

local FRAME_GLOBAL = "CraftmansHelperFrame"
local DEFAULT_ICON = 134939 -- INV_Misc_Note_01

local COLOR = {
    ready = "ff20ff20", active = "ffff5050", inbags = "ffffa020",
    available = "ffffffff", done = "ff808080", dim = "ff999999",
}

local function C(color, text) return "|c" .. color .. text .. "|r" end

local function ItemName(id, fallback)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return name or fallback
end

local function ItemIcon(id)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon or DEFAULT_ICON
end

local function SortName(a, b)
    if strcmputf8i then return strcmputf8i(a, b) < 0 end
    return a:lower() < b:lower()
end

local STATUS_ORDER = { ready = 1, active = 2, inbags = 3, available = 4, done = 5 }

local function StatusText(s)
    if s.status == STATUS.READY then
        return C(COLOR.ready, "Ready to deliver")
    elseif s.status == STATUS.ACTIVE then
        return C(COLOR.active, string.format("%d/%d", math.min(s.have, s.need), s.need))
    elseif s.status == STATUS.INBAGS then
        return C(COLOR.inbags, "Not started (use the writ)")
    elseif s.status == STATUS.DONE then
        return C(COLOR.done, "Done today")
    end
    return C(COLOR.available, "Available")
end

local function InsertLink(link)
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function ShowTooltip(widget, s)
    local w = s.writ
    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
    -- Our own rows already show the writ details; skip the item-tooltip hook here.
    CH.Tooltips.suppress = true
    GameTooltip:SetItemByID(w.item)
    CH.Tooltips.suppress = false
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Writ", ItemName(s.id, "Craftsman's Writ: " .. w.name), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Status", StatusText(s), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Have / need", string.format("%d / %d", s.have, s.need), 1, 0.82, 0, 1, 1, 1)
    local t = s.turnIn
    local where = s.zoneName or "Unknown"
    if t and t.x then where = string.format("%s (%.1f, %.1f)", where, t.x, t.y) end
    GameTooltip:AddDoubleLine("Deliver to", (t and t.name or "?") .. " - " .. where, 1, 0.82, 0, 1, 1, 1)
    if s.writsTotal > s.writsInBags then
        GameTooltip:AddDoubleLine("Writs in bank", tostring(s.writsTotal - s.writsInBags), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if t and t.x then
        GameTooltip:AddLine("Click to set a waypoint to the turn-in.", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Shift-click to link the required item.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function PointFor(s)
    local t = s.turnIn
    if not (t and t.map and t.x and t.y) then return nil end
    local who = t.name or s.zoneName or "Turn-in"
    return { map = t.map, x = t.x, y = t.y, title = who .. ": " .. ItemName(s.writ.item, s.writ.name) }
end

-- Waypoints to the turn-ins of the given writ states (one per distinct spot).
local function NavigateTo(list)
    local points, seen = {}, {}
    for _, s in ipairs(list) do
        local p = PointFor(s)
        if p then
            local key = string.format("%d:%.0f:%.0f", p.map, p.x, p.y)
            if not seen[key] then
                seen[key] = true
                table.insert(points, p)
            end
        end
    end
    CH.Nav:GoTo(points)
end

local function AddRow(parent, s, extra)
    local row = AceGUI:Create("InteractiveLabel")
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlight)
    row:SetImage(ItemIcon(s.writ.item))
    row:SetImageSize(16, 16)
    local text = "  " .. ItemName(s.writ.item, s.writ.name)
    if s.writ.count > 1 then text = text .. " x" .. s.writ.count end
    text = text .. "   " .. StatusText(s)
    if extra then text = text .. "   " .. C(COLOR.dim, extra) end
    row:SetText(text)
    row:SetCallback("OnEnter", function(widget) ShowTooltip(widget, s) end)
    row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    row:SetCallback("OnClick", function()
        if IsModifiedClick("CHATLINK") then
            local _, link = C_Item.GetItemInfo(s.writ.item)
            if link then InsertLink(link) end
        else
            NavigateTo({ s })
        end
    end)
    parent:AddChild(row)
end

local function AddHeading(parent, text)
    local h = AceGUI:Create("Heading")
    h:SetFullWidth(true)
    h:SetText(text)
    parent:AddChild(h)
end

local function AddLabel(parent, text, font)
    local l = AceGUI:Create("Label")
    l:SetFullWidth(true)
    l:SetFontObject(font or GameFontNormal)
    l:SetText(text)
    parent:AddChild(l)
    return l
end

-- Zone heading in "My Writs": click for waypoints to every writ listed under it.
local function AddZoneHeader(parent, zoneName, list)
    local l = AceGUI:Create("InteractiveLabel")
    l:SetFullWidth(true)
    l:SetFontObject(GameFontNormalLarge)
    l:SetText(zoneName)
    l:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(zoneName)
        GameTooltip:AddLine("Click to set waypoints to every writ in this zone.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    l:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    l:SetCallback("OnClick", function() NavigateTo(list) end)
    parent:AddChild(l)
end

local function AddButton(parent, text, width, onClick)
    local b = AceGUI:Create("Button")
    b:SetText(text)
    b:SetWidth(width)
    b:SetCallback("OnClick", onClick)
    parent:AddChild(b)
    return b
end

local function FormatMinutes(seconds)
    local m = math.floor((seconds or 0) / 60 + 0.5)
    if m < 1 then return "under a minute" end
    if m >= 60 then return string.format("%dh %dm", math.floor(m / 60), m % 60) end
    return m .. " min"
end

local function CreateScroll(container, key)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    UI.scrollStatus[key] = UI.scrollStatus[key] or {}
    scroll:SetStatusTable(UI.scrollStatus[key])
    container:AddChild(scroll)
    return scroll
end

---------------------------------------------------------------------------
-- Tab: My Writs
---------------------------------------------------------------------------

function UI:BuildMine(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    local toggle = AceGUI:Create("CheckBox")
    toggle:SetLabel("Include writs in bags that aren't started yet")
    toggle:SetWidth(360)
    toggle:SetValue(db.showUnstarted)
    toggle:SetCallback("OnValueChanged", function(_, _, value)
        db.showUnstarted = value
        self:Redraw()
    end)
    container:AddChild(toggle)

    local scroll = CreateScroll(container, "mine")

    -- continentID -> zoneName -> { states }
    local groups, any = {}, false
    for _, s in pairs(CH.Tracker:GetAllStates()) do
        local include = s.inLog or (db.showUnstarted and s.status == STATUS.INBAGS)
        if include then
            any = true
            local cont = groups[s.continentID] or {}
            groups[s.continentID] = cont
            local zone = cont[s.zoneName] or {}
            cont[s.zoneName] = zone
            table.insert(zone, s)
        end
    end

    if not any then
        AddLabel(scroll, "You have no Craftsman's Writs right now.\n\n" ..
            "Writs drop from creatures around the world (matching the zone's level) and can be " ..
            "bought on the Auction House. Each one can be completed once per day.", GameFontHighlight)
        return
    end

    for _, contID in ipairs(ns.CONTINENT_ORDER) do
        local cont = groups[contID]
        if cont then
            AddHeading(scroll, ns.ContinentName(contID))
            local zones = {}
            for zoneName in pairs(cont) do table.insert(zones, zoneName) end
            table.sort(zones, SortName)
            for _, zoneName in ipairs(zones) do
                local list = cont[zoneName]
                AddZoneHeader(scroll, zoneName, list)
                table.sort(list, function(a, b)
                    if a.status ~= b.status then return STATUS_ORDER[a.status] < STATUS_ORDER[b.status] end
                    return SortName(a.writ.name, b.writ.name)
                end)
                for _, s in ipairs(list) do
                    AddRow(scroll, s, s.turnIn and s.turnIn.name and ("-> " .. s.turnIn.name))
                end
            end
        end
    end
    -- Any continent not in CONTINENT_ORDER (shouldn't happen on Forever, but be safe).
    for contID, cont in pairs(groups) do
        if not tContains(ns.CONTINENT_ORDER, contID) then
            AddHeading(scroll, ns.ContinentName(contID))
            for _, list in pairs(cont) do
                for _, s in ipairs(list) do AddRow(scroll, s, s.zoneName) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tab: All Writs
---------------------------------------------------------------------------

function UI:BuildAll(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    local prof = AceGUI:Create("Dropdown")
    prof:SetLabel("Profession")
    prof:SetWidth(160)
    local profList, profOrder = { ALL = "All" }, { "ALL" }
    for _, p in ipairs(ns.PROFESSIONS) do profList[p] = ns.PROFESSION_NAMES[p]; table.insert(profOrder, p) end
    prof:SetList(profList, profOrder)
    prof:SetValue(db.professionFilter)
    prof:SetCallback("OnValueChanged", function(_, _, v) db.professionFilter = v; self:Redraw() end)
    container:AddChild(prof)

    local tier = AceGUI:Create("Dropdown")
    tier:SetLabel("Level")
    tier:SetWidth(140)
    local tierList, tierOrder = { ALL = "All" }, { "ALL" }
    for _, t in ipairs(ns.TIERS) do tierList[t] = ns.TIER_NAMES[t]; table.insert(tierOrder, t) end
    tier:SetList(tierList, tierOrder)
    tier:SetValue(db.tierFilter)
    tier:SetCallback("OnValueChanged", function(_, _, v) db.tierFilter = v; self:Redraw() end)
    container:AddChild(tier)

    local hide = AceGUI:Create("CheckBox")
    hide:SetLabel("Hide done today")
    hide:SetWidth(160)
    hide:SetValue(db.hideCompleted)
    hide:SetCallback("OnValueChanged", function(_, _, v) db.hideCompleted = v; self:Redraw() end)
    container:AddChild(hide)

    local scroll = CreateScroll(container, "all")
    local states = CH.Tracker:GetAllStates()

    for _, p in ipairs(ns.PROFESSIONS) do
        if db.professionFilter == "ALL" or db.professionFilter == p then
            local headingAdded = false
            for _, t in ipairs(ns.TIERS) do
                if db.tierFilter == "ALL" or db.tierFilter == t then
                    local list = {}
                    for _, s in pairs(states) do
                        if s.writ.tier == t and tContains(s.writ.profs, p)
                            and not (db.hideCompleted and s.status == STATUS.DONE) then
                            table.insert(list, s)
                        end
                    end
                    if #list > 0 then
                        if not headingAdded then AddHeading(scroll, ns.PROFESSION_NAMES[p]); headingAdded = true end
                        AddLabel(scroll, ns.TIER_NAMES[t], GameFontNormalLarge)
                        table.sort(list, function(a, b) return SortName(a.writ.name, b.writ.name) end)
                        for _, s in ipairs(list) do
                            AddRow(scroll, s, s.zoneName ~= "Unknown" and s.zoneName or "turn-in unknown")
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tab: Route
---------------------------------------------------------------------------

local function AddWritLines(parent, writs)
    for _, id in ipairs(writs) do
        local s = CH.Tracker:GetState(id)
        local text = "      " .. ItemName(s.writ.item, s.writ.name)
        if s.status == STATUS.INBAGS then
            text = text .. "  " .. C(COLOR.inbags, "(start the writ first)")
        elseif s.status == STATUS.DONE then
            text = text .. "  " .. C(COLOR.done, "delivered")
        end
        AddLabel(parent, text, GameFontHighlightSmall)
    end
end

local function AddStateList(parent, title, list, note)
    if #list == 0 then return end
    AddHeading(parent, title)
    if note then AddLabel(parent, C(COLOR.dim, note), GameFontHighlightSmall) end
    table.sort(list, function(a, b) return SortName(a.writ.name, b.writ.name) end)
    for _, s in ipairs(list) do
        AddRow(parent, s, s.zoneName ~= "Unknown" and s.zoneName or nil)
    end
end

function UI:BuildRoute(container)
    container:SetLayout("Flow")
    local Route = CH.Route

    AddButton(container, Route:IsActive() and "Re-plan route" or "Plan route", 150, function() Route:Plan() end)
    if Route:IsActive() then
        AddButton(container, "Clear route", 120, function() Route:Clear() end)
    end
    local hint = AceGUI:Create("Label")
    hint:SetWidth(240)
    hint:SetFontObject(GameFontHighlightSmall)
    hint:SetText(CH.Nav:HasTomTom() and C(COLOR.dim, "Waypoints via TomTom.")
        or C(COLOR.inbags, "TomTom not found: using the map pin (one stop at a time)."))
    container:AddChild(hint)

    local scroll = CreateScroll(container, "route")
    local route = Route.route

    if not route then
        AddLabel(scroll, "Plan a route to visit every turn-in for the writs you can deliver right now: writs " ..
            "that are ready, plus writs in your bags that you have the item for (start them before you arrive).\n\n" ..
            "Stops are ordered by the quickest way round from where you are, using the flight paths you know, " ..
            "boats and zeppelins, across both continents, and your Hearthstone when it saves time.\n\n" ..
            "The arrow moves on to the next stop each time you deliver.", GameFontHighlight)
        if CH.FlightPaths:Count() == 0 then
            AddLabel(scroll, "\n" .. C(COLOR.inbags, "Open a flight master's map once on each continent, so the " ..
                "addon learns which flight paths you know."), GameFontHighlight)
        end
        if CH.db.profile.useHearth and not CH.Hearth:GetSpot() then
            AddLabel(scroll, "\n" .. C(COLOR.inbags, "Use your Hearthstone once (or set it at an innkeeper), so the " ..
                "addon learns where it takes you."), GameFontHighlight)
        end
        return
    end

    if #route.stops == 0 then
        AddLabel(scroll, "Nothing to deliver right now.", GameFontHighlight)
    end

    local current = Route:GetCurrent()
    local n = 0
    for _, leg in ipairs(route.legs) do
        local pending = 0
        for _, stop in ipairs(leg.stops) do if not stop.done then pending = pending + 1 end end
        AddHeading(scroll, string.format("%s: %d stop%s, about %s", ns.ContinentName(leg.contID),
            #leg.stops, #leg.stops == 1 and "" or "s", FormatMinutes(leg.length)))
        for _, stop in ipairs(leg.stops) do
            n = n + 1
            local isCurrent = stop == current
            local label = string.format("%d. %s - %s (%.1f, %.1f)", n, stop.name or "?", stop.zoneName or "?", stop.x, stop.y)
            if stop.done then
                label = C(COLOR.done, label .. "  delivered")
            elseif isCurrent then
                label = C(COLOR.ready, label .. "  <- current")
            end
            local row = AceGUI:Create("InteractiveLabel")
            row:SetFullWidth(true)
            row:SetFontObject(isCurrent and GameFontNormal or GameFontHighlight)
            row:SetText(label)
            row:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                GameTooltip:AddLine(stop.name or "?")
                GameTooltip:AddLine(string.format("%s (%.1f, %.1f)", stop.zoneName or "?", stop.x, stop.y), 1, 1, 1)
                if not stop.done then
                    GameTooltip:AddLine("Click to point the arrow here.", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            row:SetCallback("OnClick", function()
                if not stop.done then Route:SetCurrent(stop.index, nil, true) end
            end)
            -- How to get here, when it's more than riding over (steps behind you greyed out).
            if not stop.done then
                for k, e in ipairs(stop.via or {}) do
                    local passed = isCurrent and k < (Route.viaIndex or 1)
                    AddLabel(scroll, "      " .. C(passed and COLOR.done or COLOR.inbags, e.text), GameFontHighlightSmall)
                end
            end
            scroll:AddChild(row)
            AddWritLines(scroll, stop.writs)
        end
    end

    AddStateList(scroll, "No location yet", route.unroutable,
        "These turn-ins aren't in the addon's data yet. Accepted writs show their spot on your world map.")
    AddStateList(scroll, "Not friendly to your faction", route.excluded,
        "These turn-in NPCs won't deal with your faction.")
end

---------------------------------------------------------------------------
-- Tab: Buy Writs
---------------------------------------------------------------------------

local BUY_PAGE_SIZE = 20

local function Ago(seconds)
    seconds = math.max(0, seconds)
    if seconds >= 2 * 86400 then return string.format("%d days ago", math.floor(seconds / 86400)) end
    if seconds < 60 then return "just now" end
    return ns.FormatDuration(seconds) .. " ago"
end

-- One line on where prices come from (and how fresh they are), or why there are none.
local function PriceSourceText()
    local P = ns.Prices
    local key = P.ActiveSource()
    if key == "AUCTIONATOR" then
        local t = P.LastFullScan()
        return C(COLOR.dim, "Prices from Auctionator. " ..
            (t and ("Last full Auction House scan: " .. Ago(time() - t) .. ".") or "No full Auction House scan yet."))
    elseif key == "TSM" then
        local s = CH.db.profile.tsmPrice
        if not s or s:match("^%s*$") then s = P.DEFAULT_TSM_PRICE end
        return C(COLOR.dim, "Prices from TradeSkillMaster (" .. s .. ").")
    end
    local pref = CH.db.profile.priceSource
    if pref and pref ~= "AUTO" then
        return C(COLOR.inbags, P.SOURCE_NAMES[pref] .. " isn't installed, so there are no prices.")
    end
    return C(COLOR.inbags, "No price addon found: install Auctionator or TradeSkillMaster for prices.")
end

-- Filter keys for a writ's turn-in: zone name, and NPC (name + zone, since names can repeat).
local function BuyKeys(writID)
    local s = CH.Tracker:GetState(writID)
    local t = s and s.turnIn
    local zone = (s and s.zoneName and s.zoneName ~= "") and s.zoneName or "Unknown"
    local name = t and t.name or "Unknown NPC"
    return { zone = zone, npc = name .. ";" .. zone, npcLabel = string.format("%s (%s)", name, zone) }
end

local function ShowBuyTooltip(widget, e)
    local w = ns.Writs[e.writID]
    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
    CH.Tooltips.suppress = true
    GameTooltip:SetItemByID(e.writID)
    CH.Tooltips.suppress = false
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Writ", ns.FormatMoneyIcons(e.writPrice), 1, 0.82, 0, 1, 1, 1)
    local k = BuyKeys(e.writID)
    GameTooltip:AddDoubleLine("Deliver to", k.npcLabel, 1, 0.82, 0, 1, 1, 1)
    local itemLabel = ItemName(w.item, w.name) .. " x" .. w.count
    GameTooltip:AddDoubleLine(itemLabel, e.itemCost and ns.FormatMoneyIcons(e.itemCost) or "no price",
        1, 0.82, 0, 1, 1, 1)
    if e.cost then
        GameTooltip:AddDoubleLine("Total", ns.FormatMoneyIcons(e.cost), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Rep per gold", string.format("%.1f (%d rep)", e.repPerGold, e.rep),
            1, 0.82, 0, 1, 1, 1)
    end
    if e.age and e.age > ns.Prices.STALE_DAYS then
        GameTooltip:AddLine(string.format("Oldest price is %d days old.", e.age), 1, 0.63, 0.13)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link the writ (e.g. into the Auction House search).", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function AddBuyRow(parent, e, done)
    local w = ns.Writs[e.writID]
    local row = AceGUI:Create("InteractiveLabel")
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlight)
    row:SetImage(ItemIcon(e.writID))
    row:SetImageSize(16, 16)
    -- The writ is named after the item it asks for; show how many right here.
    local text = string.format("  %s %s %s   ", ItemName(w.item, w.name), C(COLOR.ready, "x" .. w.count),
        C(COLOR.dim, "(" .. ns.TIER_NAMES[w.tier] .. ")"))
    if e.cost then
        text = text .. ns.FormatMoneyIcons(e.cost) .. "   " .. C(COLOR.ready, string.format("%.1f rep/g", e.repPerGold))
    else
        text = text .. ns.FormatMoneyIcons(e.writPrice) .. " + " .. C(COLOR.inbags, "item price unknown")
    end
    if done then text = text .. "   " .. C(COLOR.done, "done today") end
    row:SetText(text)
    row:SetCallback("OnEnter", function(widget) ShowBuyTooltip(widget, e) end)
    row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    row:SetCallback("OnClick", function()
        if IsModifiedClick("CHATLINK") then
            local _, link = C_Item.GetItemInfo(e.writID)
            if link then InsertLink(link) end
        end
    end)
    parent:AddChild(row)
end

function UI:BuildBuy(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    if not ns.Prices.IsAvailable() then
        local scroll = CreateScroll(container, "buy")
        AddLabel(scroll, "This tab needs Auction House prices from Auctionator or TradeSkillMaster.\n\n" ..
            "Install one of them and scan the Auction House to see which writs are cheapest to buy. " ..
            "You can choose the price source in the Settings tab.", GameFontHighlight)
        AddLabel(scroll, "\n" .. PriceSourceText(), GameFontHighlightSmall)
        return
    end

    -- Show another page, scrolled back to the top.
    local function GoToPage(n)
        self.buyPage = n
        self.scrollStatus.buy = nil
        self:Redraw()
    end
    local function Refilter() GoToPage(1) end

    -- Controls in four fixed rows, each sharing the window's width, so they keep their
    -- place at any window size:
    --   sort, level / zone, NPC / the two checkboxes / page buttons
    local function Row()
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        container:AddChild(row)
        return row
    end
    local HALF = 0.49 -- a little under half, so rounding never wraps the second widget
    local rowSort, rowPlace, rowHide, rowPage = Row(), Row(), Row(), Row()

    local sort = AceGUI:Create("Dropdown")
    sort:SetLabel("Sort by")
    sort:SetRelativeWidth(HALF)
    sort:SetList({ price = "Price (low to high)", rep = "Rep per gold" }, { "price", "rep" })
    sort:SetValue(db.buySort)
    sort:SetCallback("OnValueChanged", function(_, _, v) db.buySort = v; Refilter() end)
    rowSort:AddChild(sort)

    local tier = AceGUI:Create("Dropdown")
    tier:SetLabel("Level")
    tier:SetRelativeWidth(HALF)
    local tierList, tierOrder = { ALL = "All" }, { "ALL" }
    for _, t in ipairs(ns.TIERS) do tierList[t] = ns.TIER_NAMES[t]; table.insert(tierOrder, t) end
    tier:SetList(tierList, tierOrder)
    tier:SetValue(db.buyTier)
    tier:SetCallback("OnValueChanged", function(_, _, v) db.buyTier = v; Refilter() end)
    rowSort:AddChild(tier)

    local function HideBox(label, key, tip)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetRelativeWidth(HALF)
        cb:SetValue(db[key])
        cb:SetCallback("OnValueChanged", function(_, _, v) db[key] = v; Refilter() end)
        cb:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        rowHide:AddChild(cb)
    end
    HideBox("Hide done today", "buyHideDone", "Hide writs you've already turned in since the daily reset.")
    HideBox("Hide writs I have", "buyHideOwned", "Hide writs that are in your quest log, bags or bank.")

    -- Zone and turn-in NPC of every writ; the NPC list only shows NPCs in the chosen zone.
    local zoneList, zoneOrder, npcList, npcOrder = { ALL = "All zones" }, {}, { ALL = "All NPCs" }, {}
    local keyOf = {}
    for writID in pairs(ns.Writs) do
        local k = BuyKeys(writID)
        keyOf[writID] = k
        if not zoneList[k.zone] then zoneList[k.zone] = k.zone; table.insert(zoneOrder, k.zone) end
        if (db.buyZone == "ALL" or db.buyZone == k.zone) and not npcList[k.npc] then
            npcList[k.npc] = k.npcLabel
            table.insert(npcOrder, k.npc)
        end
    end
    -- Saved choices that no longer exist (or don't fit the zone) fall back to "All".
    if not zoneList[db.buyZone] then db.buyZone = "ALL" end
    if not npcList[db.buyNpc] then db.buyNpc = "ALL" end
    table.sort(zoneOrder, SortName)
    table.sort(npcOrder, function(a, b) return SortName(npcList[a], npcList[b]) end)
    table.insert(zoneOrder, 1, "ALL")
    table.insert(npcOrder, 1, "ALL")

    local zone = AceGUI:Create("Dropdown")
    zone:SetLabel("Zone")
    zone:SetRelativeWidth(HALF)
    zone:SetList(zoneList, zoneOrder)
    zone:SetValue(db.buyZone)
    zone:SetCallback("OnValueChanged", function(_, _, v) db.buyZone = v; db.buyNpc = "ALL"; Refilter() end)
    rowPlace:AddChild(zone)

    local npc = AceGUI:Create("Dropdown")
    npc:SetLabel("Turn-in NPC")
    npc:SetRelativeWidth(HALF)
    npc:SetList(npcList, npcOrder)
    npc:SetValue(db.buyNpc)
    npc:SetCallback("OnValueChanged", function(_, _, v) db.buyNpc = v; Refilter() end)
    rowPlace:AddChild(npc)

    local list = ns.Prices.GetBuyList(db.buySort, function(writID)
        if db.buyTier ~= "ALL" and ns.Writs[writID].tier ~= db.buyTier then return false end
        local k = keyOf[writID]
        if db.buyZone ~= "ALL" and k.zone ~= db.buyZone then return false end
        if db.buyNpc ~= "ALL" and k.npc ~= db.buyNpc then return false end
        local s = CH.Tracker:GetState(writID)
        if db.buyHideOwned and (s.inLog or (s.writsTotal or 0) > 0) then return false end
        return not (db.buyHideDone and s.status == STATUS.DONE)
    end)

    local pages = math.max(1, math.ceil(#list / BUY_PAGE_SIZE))
    local page = math.min(math.max(self.buyPage or 1, 1), pages)
    self.buyPage = page

    local prev = AddButton(rowPage, "< Prev", 80, function() GoToPage(page - 1) end)
    prev:SetRelativeWidth(0.2)
    prev:SetDisabled(page <= 1)
    local info = AceGUI:Create("Label")
    info:SetRelativeWidth(0.58)
    info:SetJustifyH("CENTER")
    info:SetFontObject(GameFontHighlight)
    info:SetText(string.format("Page %d of %d  (%d writ%s)", page, pages, #list, #list == 1 and "" or "s"))
    rowPage:AddChild(info)
    local nextB = AddButton(rowPage, "Next >", 80, function() GoToPage(page + 1) end)
    nextB:SetRelativeWidth(0.2)
    nextB:SetDisabled(page >= pages)

    local scroll = CreateScroll(container, "buy")
    if #list == 0 then
        AddLabel(scroll, "No writs with an Auction House price.\n\n" ..
            "Writs only show up here once your price addon has seen them for sale.", GameFontHighlight)
        AddLabel(scroll, "\n" .. PriceSourceText(), GameFontHighlightSmall)
        return
    end

    AddLabel(scroll, PriceSourceText() .. C(COLOR.dim, "  Price = the writ plus the items it asks for."),
        GameFontHighlightSmall)
    local first = (page - 1) * BUY_PAGE_SIZE + 1
    for i = first, math.min(first + BUY_PAGE_SIZE - 1, #list) do
        local e = list[i]
        AddBuyRow(scroll, e, not db.buyHideDone and CH.Tracker:GetState(e.writID).status == STATUS.DONE)
    end
end

---------------------------------------------------------------------------
-- Tab: Settings
---------------------------------------------------------------------------

local function AddCheckBox(parent, label, description, value, onChange)
    local cb = AceGUI:Create("CheckBox")
    cb:SetFullWidth(true)
    cb:SetLabel(label)
    if description then cb:SetDescription(description) end
    cb:SetValue(value)
    cb:SetCallback("OnValueChanged", function(_, _, v) onChange(v) end)
    parent:AddChild(cb)
    return cb
end

function UI:BuildSettings(container)
    local db = CH.db.profile
    container:SetLayout("Fill")
    local scroll = CreateScroll(container, "settings")

    AddHeading(scroll, "Tooltips")
    local writPrice
    AddCheckBox(scroll, "Show writ info in item tooltips",
        "Today's status, the item needed and where to deliver it on writs, and which writs want it on crafted items.",
        db.tooltips, function(v)
            db.tooltips = v
            if writPrice then writPrice:SetDisabled(not v) end
        end)

    AddHeading(scroll, "Price estimates")
    local P = ns.Prices
    local source = AceGUI:Create("Dropdown")
    source:SetLabel("Price source")
    source:SetWidth(220)
    local function Label(key)
        return P.SOURCE_NAMES[key] .. (P.IsInstalled(key) and "" or " (not installed)")
    end
    source:SetList({ AUTO = "Automatic (whichever is installed)", AUCTIONATOR = Label("AUCTIONATOR"), TSM = Label("TSM") },
        { "AUTO", "AUCTIONATOR", "TSM" })
    source:SetValue(db.priceSource or "AUTO")
    source:SetCallback("OnValueChanged", function(_, _, v) db.priceSource = v; self:Redraw() end)
    scroll:AddChild(source)

    local tsm = AceGUI:Create("EditBox")
    tsm:SetLabel("TSM price (custom price string)")
    tsm:SetWidth(320)
    tsm:SetText(db.tsmPrice or "")
    tsm:SetDisabled(not P.IsInstalled("TSM"))
    tsm:SetCallback("OnEnterPressed", function(widget, _, text)
        text = strtrim(text or "")
        local valid, err = P.CheckTSMPrice(text ~= "" and text or P.DEFAULT_TSM_PRICE)
        if not valid then
            CH:Print("TSM can't use that price: " .. tostring(err or "invalid custom price"))
            widget:SetText(db.tsmPrice or "")
            return
        end
        db.tsmPrice = text
        self:Redraw()
    end)
    scroll:AddChild(tsm)
    AddLabel(scroll, C(COLOR.dim, "Empty uses " .. P.DEFAULT_TSM_PRICE .. ". Press Enter to save."), GameFontHighlightSmall)
    AddLabel(scroll, PriceSourceText(), GameFontHighlightSmall)

    writPrice = AddCheckBox(scroll, "Include the writ's own price",
        "Add the Auction House price of the writ itself to the estimated price and rep per gold, " ..
        "for when you buy writs instead of looting them.",
        db.includeWritPrice, function(v) db.includeWritPrice = v end)
    writPrice:SetDisabled(not db.tooltips)

    AddHeading(scroll, "Route planning")
    AddCheckBox(scroll, "Use your Hearthstone",
        "When it's off cooldown and saves time, the route uses your Hearthstone once.",
        db.useHearth, function(v) db.useHearth = v end)
    local spot = CH.Hearth:GetSpot()
    AddLabel(scroll, spot and C(COLOR.dim, "Hearthstone: " .. spot.name .. " (location learned).")
        or C(COLOR.inbags, "Hearthstone location not learned yet: use your Hearthstone once, or set it at an innkeeper."),
        GameFontHighlightSmall)
    local fp = CH.FlightPaths:Count()
    AddLabel(scroll, fp > 0 and C(COLOR.dim, string.format("Flight paths known: %d.", fp))
        or C(COLOR.inbags, "No flight paths learned yet: open a flight master's map once on each continent."),
        GameFontHighlightSmall)

    AddHeading(scroll, "Route tracker")
    AddCheckBox(scroll, "Show the route tracker",
        "A small window with the next 5 steps of your route, shown while a route is active.",
        db.tracker.shown, function(v) CH.RouteTracker:SetShown(v) end)
    AddCheckBox(scroll, "Lock its position",
        "Stop the route tracker from being dragged around.",
        db.tracker.locked, function(v) CH.RouteTracker:SetLocked(v) end)

    AddHeading(scroll, "Minimap")
    AddCheckBox(scroll, "Show the minimap button",
        "Left-click opens this window, right-click plans a route. Also available in the addon compartment.",
        not db.minimap.hide, function(v) CH.Minimap:SetShown(v) end)

    AddHeading(scroll, "Credits")
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("CraftmansHelper", "Version")) or "?"
    local lines = {
        "Craftman's Helper " .. version .. " by Emsworth, released under the GPL-3.0.",
        " ",
        C(COLOR.ready, "Glyalith") .. " - boat, zeppelin, skycutter and tram connections and measured flight times, " ..
            "collected for EllesmereUI Forever Essentials and used with permission.",
        C(COLOR.ready, "Questie / QuestieDB") .. " - turn-in NPCs, flight masters and zeppelin and ship masters (GPL-3.0).",
        C(COLOR.ready, "Wowhead") .. " - the list of Craftsman's Writs.",
        C(COLOR.ready, "Ace3, LibDataBroker and LibDBIcon") .. " - the libraries this addon is built on.",
        C(COLOR.ready, "You") .. " - for every turn-in location shared with /writs export.",
        " ",
        C(COLOR.dim, "Source, issues and suggestions: github.com/emsw0rth/craftmanshelper"),
    }
    for _, line in ipairs(lines) do AddLabel(scroll, line, GameFontHighlightSmall) end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

function UI:UpdateStatusText()
    if not self.frame then return end
    local c = CH.Tracker:GetCounts()
    self.frame:SetStatusText(string.format("%d ready  -  %d in progress  -  %d done today  -  daily reset in %s",
        c.ready, c.active, c.done, ns.FormatDuration(CH.Tracker:SecondsUntilReset())))
end

function UI:Redraw()
    if not (self.frame and self.tabs) then return end
    self.tabs:SelectTab(self.currentTab or "mine")
end

function UI:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Craftman's Helper")
    frame:SetLayout("Fill")
    CH.db.profile.window = CH.db.profile.window or {}
    frame:SetStatusTable(CH.db.profile.window)
    if not CH.db.profile.window.width then frame:SetWidth(560); frame:SetHeight(520) end
    frame:SetCallback("OnClose", function(widget)
        _G[FRAME_GLOBAL] = nil
        AceGUI:Release(widget)
        self.frame, self.tabs = nil, nil
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end)

    -- Close with Escape.
    _G[FRAME_GLOBAL] = frame.frame
    if not tContains(UISpecialFrames, FRAME_GLOBAL) then table.insert(UISpecialFrames, FRAME_GLOBAL) end

    local tabs = AceGUI:Create("TabGroup")
    tabs:SetTabs({
        { text = "My Writs", value = "mine" },
        { text = "Route", value = "route" },
        { text = "Shopping", value = "shopping" },
        { text = "Buy Writs", value = "buy" },
        { text = "All Writs", value = "all" },
        { text = "Settings", value = "settings" },
    })
    tabs:SetCallback("OnGroupSelected", function(container, _, group)
        self.currentTab = group
        container:ReleaseChildren()
        if group == "all" then
            self:BuildAll(container)
        elseif group == "route" then
            self:BuildRoute(container)
        elseif group == "shopping" then
            self:BuildShopping(container)
        elseif group == "buy" then
            self:BuildBuy(container)
        elseif group == "settings" then
            self:BuildSettings(container)
        else
            self:BuildMine(container)
        end
        self:UpdateStatusText()
    end)
    frame:AddChild(tabs)

    self.frame, self.tabs = frame, tabs
    self.ticker = C_Timer.NewTicker(30, function() self:UpdateStatusText() end)
end

function UI:Show(tab)
    if tab then self.currentTab = tab end
    if not self.frame then self:Create() end
    self:Redraw()
end

function UI:Toggle()
    if self.frame then
        self.frame:Hide() -- fires OnClose -> release
    else
        self:Show()
    end
end

---------------------------------------------------------------------------
-- Tab: Shopping
---------------------------------------------------------------------------

function UI:BuildShopping(container)
    container:SetLayout("Flow")
    local scroll = CreateScroll(container, "shopping")

    -- crafted item -> { need = total, writs = { states } } for writs you hold but can't deliver yet
    local byItem, items = {}, {}
    for _, s in pairs(CH.Tracker:GetAllStates()) do
        local held = s.status == STATUS.ACTIVE or s.status == STATUS.INBAGS
        if held and s.have < s.need then
            local entry = byItem[s.writ.item]
            if not entry then
                entry = { item = s.writ.item, name = s.writ.name, need = 0, have = s.have, writs = {} }
                byItem[s.writ.item] = entry
                table.insert(items, entry)
            end
            entry.need = entry.need + s.need
            table.insert(entry.writs, s)
        end
    end

    if #items == 0 then
        AddLabel(scroll, "Nothing to buy or craft: every writ you hold has its item.\n\n" ..
            "This list shows the crafted items still missing for writs in your quest log or bags.", GameFontHighlight)
        return
    end

    table.sort(items, function(a, b) return SortName(ItemName(a.item, a.name), ItemName(b.item, b.name)) end)
    AddHeading(scroll, string.format("%d item%s missing", #items, #items == 1 and "" or "s"))

    for _, e in ipairs(items) do
        local missing = math.max(0, e.need - e.have)
        local row = AceGUI:Create("InteractiveLabel")
        row:SetFullWidth(true)
        row:SetFontObject(GameFontHighlight)
        row:SetImage(ItemIcon(e.item))
        row:SetImageSize(18, 18)
        row:SetText(string.format("  %s   %s   %s", ItemName(e.item, e.name),
            C(COLOR.active, string.format("need %d more", missing)),
            C(COLOR.dim, string.format("(have %d of %d)", e.have, e.need))))
        row:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
            CH.Tooltips.suppress = true
            GameTooltip:SetItemByID(e.item)
            CH.Tooltips.suppress = false
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click to link (e.g. into the Auction House search).", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        row:SetCallback("OnClick", function()
            if IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(e.item)
                if link then InsertLink(link) end
            end
        end)
        scroll:AddChild(row)
        for _, s in ipairs(e.writs) do
            local where = s.turnIn and s.turnIn.name and (s.turnIn.name .. ", " .. (s.zoneName or "?")) or (s.zoneName or "?")
            AddLabel(scroll, string.format("      %s writ x%d -> %s%s", ns.TIER_NAMES[s.writ.tier], s.need, where,
                s.status == STATUS.INBAGS and "  " .. C(COLOR.inbags, "(not started)") or ""), GameFontHighlightSmall)
        end
    end
end

---------------------------------------------------------------------------
-- Export window
---------------------------------------------------------------------------

function UI:ShowExport()
    local text, n = CH:BuildExport()
    if n == 0 then
        CH:Print("Nothing to share yet: no new turn-in locations recorded. Deliver or accept Expert/Artisan writs to record some.")
        return
    end
    if self.exportFrame then AceGUI:Release(self.exportFrame) end

    local f = AceGUI:Create("Frame")
    f:SetTitle("Craftman's Helper: share turn-in locations")
    f:SetLayout("List")
    f:SetWidth(520)
    f:SetHeight(360)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.exportFrame = nil
    end)
    f:SetStatusText(string.format("%d location%s recorded", n, n == 1 and "" or "s"))

    local intro = AceGUI:Create("Label")
    intro:SetFullWidth(true)
    intro:SetFontObject(GameFontHighlight)
    intro:SetText("Press Ctrl+C to copy, then paste it into a new issue at\n" ..
        C(COLOR.ready, "github.com/emsw0rth/craftmanshelper/issues") ..
        "\nso everyone gets these locations in the next release. Thank you!")
    f:AddChild(intro)

    local box = AceGUI:Create("MultiLineEditBox")
    box:SetFullWidth(true)
    box:SetNumLines(12)
    box:SetLabel("")
    box:DisableButton(true)
    box:SetText(text)
    -- Keep the text intact if someone types into the box.
    box:SetCallback("OnTextChanged", function(widget) widget:SetText(text); widget:HighlightText() end)
    f:AddChild(box)
    box:SetFocus()
    box:HighlightText()

    self.exportFrame = f
end

function UI:OnEnable()
    self.scrollStatus = {}
    self.currentTab = "mine"
    self:RegisterMessage(ns.MSG_UPDATED, "Redraw")
    self:RegisterMessage(ns.MSG_ROUTE, "Redraw")
end
