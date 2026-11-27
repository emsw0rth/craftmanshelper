-- The "Craftman's" tab in the Auction House: lists of writs, the items writs ask for, Waylaid
-- Crates and crate materials, searched one item at a time (AHScan.lua). Clicking a row opens that
-- item in the Auction House's own Buy screen.
--
-- The tab button comes from LibAHTab (MIT), which adds Auction House tabs without tainting the
-- game's UI.
local _, ns = ...
local CH = ns.CH
local AceGUI = LibStub("AceGUI-3.0")
local STATUS = ns.STATUS

local Tab = CH:NewModule("AuctionTab", "AceEvent-3.0")
CH.AuctionTab = Tab

local TAB_ID = "CraftmansHelper"
local REFRESH_EVERY = 8 -- redraw the list after this many searched items

-- The list buttons, in two rows: writs, then crates.
local LISTS = {
    { key = "writs", text = "Writs" },
    { key = "items", text = "Writ items" },
    { key = "myitems", text = "Items for my writs" },
    { key = "crates", text = "Crates" },
    { key = "materials", text = "Crate materials" },
    { key = "mymaterials", text = "Materials for my crates" },
}

local COLUMNS = {
    { key = "name", title = "Name", width = 0.30 },
    { key = "info", title = "", width = 0.22 },
    { key = "need", title = "Need", width = 0.07, descFirst = true },
    { key = "price", title = "Price", width = 0.14 },
    { key = "cost", title = "Cost", width = 0.14, sortName = "cost for what you need" },
    { key = "listed", title = "Listed", width = 0.12, descFirst = true },
}
-- Writs: no Need (always one), and reputation per gold.
local WRIT_COLUMNS = {
    { key = "name", title = "Name", width = 0.28 },
    { key = "info", title = "Turn-in", width = 0.19 },
    { key = "price", title = "Price", width = 0.14 },
    { key = "cost", title = "Cost", width = 0.14, sortName = "cost" },
    { key = "rep", title = "Rep/|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", width = 0.11,
      sortName = "rep per gold", descFirst = true },
    { key = "listed", title = "Listed", width = 0.13, descFirst = true },
}
local INFO_TITLE = { writs = "Turn-in", items = "For", myitems = "For", crates = "Level", materials = "Fills",
                     mymaterials = "Fills" }

-- Crates: no Need (always one), and Merchant's Favor per gold.
local CRATE_COLUMNS = {
    { key = "name", title = "Name", width = 0.29 },
    { key = "info", title = "Level", width = 0.12 },
    { key = "price", title = "Price", width = 0.15 },
    { key = "cost", title = "Cost", width = 0.15, sortName = "cost" },
    { key = "rep", title = "Favor/|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", width = 0.13,
      sortName = "Favor per gold", descFirst = true },
    { key = "listed", title = "Listed", width = 0.15, descFirst = true },
}
local LIST_COLUMNS = { writs = WRIT_COLUMNS, crates = CRATE_COLUMNS }

-- Merchant's Favor per gold for a crate row's cost, less the silver paid at the hand-in, or nil.
local function CrateFavorPerGold(crateID, q)
    if not q.cost then return nil end
    local K = ns.CrateCalc
    local back = ns.Prices.CashbackOn() and K.Silver(crateID) or 0
    return ns.Prices.RepPerGold(K.Favor(crateID), q.cost - back)
end

-- Reputation per gold for a writ row's cost, less the coin pouch (as in Buy Writs), or nil.
local function WritRepPerGold(writID, q)
    if not q.cost then return nil end
    return ns.Prices.RepPerGold(ns.WritRep(writID), q.cost - ns.Prices.Cashback(writID))
end

local function K() return CH.UI.Kit end

local function AHOpen()
    return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

local function Settings()
    return CH.db.profile.ah
end

---------------------------------------------------------------------------
-- What each list holds: entries { id (item to search), name, info, need, writs = { writ IDs },
-- crate = crate ID (materials), sortInfo }
---------------------------------------------------------------------------

local function WritPasses(writID, keys, ah, forItems)
    local w = ns.Writs[writID]
    if not K().MatchesKeys(keys, ah.zone, ah.npc) then return false end
    if ah.level ~= "ALL" and w.tier ~= ah.level then return false end
    local s = CH.Tracker:GetState(writID)
    if forItems then return true end
    if ah.hideDone and s.status == STATUS.DONE then return false end
    if ah.hideOwned and (s.inLog or (s.writsInBags or 0) > 0) then return false end
    return true
end

local function CratePasses(crateID, ah)
    local c = ns.Crates[crateID]
    return (ah.crateLevel == "ALL" or ah.crateLevel == c.level)
        and (ah.crateKind == "ALL" or (ah.crateKind == "CRAFTED") == (c.crafted or false))
end

local function Entries(list, ah, keyOf)
    local out = {}
    if list == "writs" then
        for writID, w in pairs(ns.Writs) do
            if WritPasses(writID, keyOf[writID], ah) then
                table.insert(out, { id = writID, name = w.name, info = keyOf[writID].zone, need = 1,
                                    sortInfo = keyOf[writID].zone:lower(), writs = { writID },
                                    extra = { { { w.item, w.count, w.name } } } })
            end
        end
    elseif list == "items" or list == "myitems" then
        -- items: what every writ in the filters asks for. myitems: what the writs in your quest
        -- log and bags still need (less what you have).
        local byItem = {}
        for writID, w in pairs(ns.Writs) do
            local s = CH.Tracker:GetState(writID)
            local held = s.status == STATUS.ACTIVE or s.status == STATUS.INBAGS
            local want
            if list == "myitems" then
                want = held and s.have < s.need and K().MatchesKeys(keyOf[writID], ah.zone, ah.npc) and (s.need - s.have)
            else
                want = WritPasses(writID, keyOf[writID], ah, true) and w.count
            end
            if want and want > 0 then
                local e = byItem[w.item]
                if not e then
                    e = { id = w.item, name = w.name, need = 0, writs = {} }
                    byItem[w.item] = e
                    table.insert(out, e)
                end
                e.need = e.need + want
                table.insert(e.writs, writID)
            end
        end
        for _, e in ipairs(out) do
            e.info = #e.writs == 1 and keyOf[e.writs[1]].zone or (#e.writs .. " writs")
            e.sortInfo = e.info:lower()
        end
    elseif list == "crates" then
        for crateID, c in pairs(ns.Crates) do
            if CratePasses(crateID, ah) then
                local level = ns.CrateCalc.LEVEL_NAMES[c.level]
                table.insert(out, { id = crateID, name = "Waylaid Crate: " .. c.name, info = level, need = 1,
                                    sortInfo = string.format("%d%s", c.level, c.name:lower()), extra = { c.bundles } })
            end
        end
    elseif list == "materials" then
        for crateID, c in pairs(ns.Crates) do
            if CratePasses(crateID, ah) then
                for _, b in ipairs(c.bundles) do
                    table.insert(out, { id = b[1], name = b[3], info = c.name, need = b[2], crate = crateID,
                                        sortInfo = string.format("%d%s", c.level, c.name:lower()) })
                end
            end
        end
    elseif list == "mymaterials" then
        -- Every fill for the crates in your bags, enough for all of them.
        for crateID, c in pairs(ns.Crates) do
            local n = ns.CrateCalc.Owned(crateID).bags
            if n > 0 then
                for _, b in ipairs(c.bundles) do
                    table.insert(out, { id = b[1], name = b[3], info = n > 1 and string.format("%s x%d", c.name, n) or c.name,
                                        need = b[2] * n, crate = crateID, crates = n,
                                        sortInfo = string.format("%d%s", c.level, c.name:lower()) })
                end
            end
        end
    end
    return out
end

-- What `need` of an item cost: from the last search when there is one, else the price source's
-- estimate. Returns { price, cost, short = too few listed, listed, at = search time, estimated }.
local function QuoteItem(id, need)
    local Scan = CH.AHScan
    local r = Scan.Get(id)
    if r then
        local cost, got = Scan.CostFor(r, need)
        return { price = r.p, cost = r.p and cost, short = r.p and got < need, listed = r.q, at = r.t }
    end
    local p = ns.Prices.GetItemPrice(id)
    return { price = p, cost = p and p * need, estimated = true }
end

-- Whether a list's rows add what they need to their cost ("Include item cost" / "Include
-- materials cost").
local function AddsExtra(ah)
    return (ah.list == "writs" and ah.writItemCost) or (ah.list == "crates" and ah.crateMatCost)
end

-- A row's quote. With AddsExtra, its cost also covers e.extra: groups of { itemID, count, name }
-- options, of which the cheapest counts (a writ's item; a crate's bundles). parts = what was added,
-- and cost is nil when one of them has no price.
local function Quote(e, ah)
    local q = QuoteItem(e.id, e.need)
    if not (AddsExtra(ah) and e.extra) then return q end
    q.parts = {}
    for _, options in ipairs(e.extra) do
        local best
        for _, o in ipairs(options) do
            local x = QuoteItem(o[1], o[2])
            if x.cost and (not best or x.cost < best.q.cost) then best = { itemID = o[1], count = o[2], name = o[3], q = x } end
        end
        if not best then
            q.cost, q.missing = nil, true
            return q
        end
        table.insert(q.parts, best)
        if q.cost then q.cost = q.cost + best.q.cost end
        q.short = q.short or best.q.short
        q.estimated = q.estimated or best.q.estimated
    end
    return q
end

-- Item IDs to search for the rows: each row's item, and with AddsExtra what it needs.
local function SearchIDs(entries, ah)
    local ids = {}
    for _, e in ipairs(entries) do
        table.insert(ids, e.id)
        if AddsExtra(ah) then
            for _, options in ipairs(e.extra or {}) do
                for _, o in ipairs(options) do table.insert(ids, o[1]) end
            end
        end
    end
    return ids
end

local function Ago(t)
    local s = math.max(0, time() - t)
    if s < 3600 then return math.floor(s / 60) .. "m" end
    if s < 86400 then return math.floor(s / 3600) .. "h" end
    return math.floor(s / 86400) .. "d"
end

---------------------------------------------------------------------------
-- The Auction House's own Buy screen
---------------------------------------------------------------------------

-- Shows an item in the default Buy screen: its commodity or item listing when the game knows the
-- item, else a search for its name.
function Tab:ShowInBuyScreen(itemID)
    local AH = AuctionHouseFrame
    if not (AH and AH:IsShown()) then return end
    local buyTab = AH.BuyTab or _G.AuctionHouseFrameBuyTab
    if buyTab then buyTab:Click() end
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(key)
    local r = CH.AHScan.Get(itemID)
    if info and AH.SelectBrowseResult then
        local ok = pcall(AH.SelectBrowseResult, AH, { itemKey = key, minPrice = r and r.p or 0, totalQuantity = r and r.q or 0 })
        if ok then return end
    end
    local name = C_Item.GetItemNameByID(itemID)
    local bar = AH.SearchBar
    if name and bar and bar.SetSearchText and bar.StartSearch then
        bar:SetSearchText(name)
        bar:StartSearch()
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function ShowRowTooltip(frame, e, q)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    CH.Tooltips.suppress = true
    GameTooltip:SetItemByID(e.id)
    CH.Tooltips.suppress = false
    GameTooltip:AddLine(" ")
    local r = CH.AHScan.Get(e.id)
    if r then
        GameTooltip:AddLine(string.format("Searched %s ago: %d listed", Ago(r.t), r.q), 1, 0.82, 0)
        for i = 1, math.min(5, #r.l) do
            if r.w then
                GameTooltip:AddDoubleLine(r.l[i][2] > 1 and string.format("  Auction of %d", r.l[i][2]) or "  Auction",
                    ns.FormatMoneyIcons(r.l[i][1]), 1, 1, 1, 1, 1, 1)
            else
                GameTooltip:AddDoubleLine(string.format("  %d for", r.l[i][2]), ns.FormatMoneyIcons(r.l[i][1]) .. " each",
                    1, 1, 1, 1, 1, 1)
            end
        end
        if r.w then GameTooltip:AddLine("  Buyouts only; auctions are bought whole.", 0.6, 0.6, 0.6) end
        if q.cost and not q.parts then
            GameTooltip:AddDoubleLine(string.format("%d cost", e.need), ns.FormatMoneyIcons(q.cost) ..
                (q.short and " (not enough listed)" or ""), 1, 0.82, 0, 1, 1, 1)
        end
    elseif q.price then
        GameTooltip:AddLine("Not searched yet. Estimate from " .. (ns.Prices.SourceName() or "your price addon") .. ".", 1, 0.82, 0, true)
    else
        GameTooltip:AddLine("Not searched yet.", 1, 0.82, 0)
    end
    if q.parts then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("This", q.price and ns.FormatMoneyIcons(q.price) or "no price", 1, 0.82, 0, 1, 1, 1)
        for _, part in ipairs(q.parts) do
            GameTooltip:AddDoubleLine(string.format("+ %d %s", part.count, CH.UI.Kit.ItemName(part.itemID, part.name)),
                ns.FormatMoneyIcons(part.q.cost), 1, 0.82, 0, 1, 1, 1)
        end
        if q.cost then GameTooltip:AddDoubleLine("Cost", ns.FormatMoneyIcons(q.cost), 1, 0.82, 0, 1, 1, 1) end
    elseif q.missing then
        GameTooltip:AddLine("What it needs has no price yet, so there's no total.", 1, 0.63, 0.13, true)
    end
    if ns.Crates[e.id] then
        local per = CrateFavorPerGold(e.id, q)
        if per then
            GameTooltip:AddDoubleLine("Favor per gold", string.format("%s (%d Favor)", ns.FormatRepPerGold(per),
                ns.CrateCalc.Favor(e.id)), 1, 0.82, 0, 1, 1, 1)
            if not Settings().crateMatCost then
                GameTooltip:AddLine("Tick \"Include materials cost\" to count filling it.", 0.6, 0.6, 0.6, true)
            end
        end
    end
    if ns.Writs[e.id] then
        local rep = WritRepPerGold(e.id, q)
        if rep then
            local back = ns.Prices.Cashback(e.id)
            GameTooltip:AddDoubleLine("Rep per gold", string.format("%s (%d rep%s)", ns.FormatRepPerGold(rep),
                ns.WritRep(e.id), back > 0 and (", " .. ns.FormatMoneyIcons(back) .. " back from the pouch") or ""),
                1, 0.82, 0, 1, 1, 1)
        end
    end
    if e.crate then
        if (e.crates or 1) > 1 then
            GameTooltip:AddLine(string.format("%d fill your %d Waylaid Crates: %s.", e.need, e.crates, ns.Crates[e.crate].name),
                1, 1, 1, true)
        else
            GameTooltip:AddLine(string.format("%d fill a Waylaid Crate: %s.", e.need, ns.Crates[e.crate].name), 1, 1, 1, true)
        end
        local have = (C_Item.GetItemCount and C_Item.GetItemCount(e.id)) or 0
        if have > 0 then GameTooltip:AddLine(string.format("You have %d in your bags.", have), 0.13, 1, 0.13) end
    end
    if e.writs and #e.writs > 1 then
        GameTooltip:AddLine("Wanted by " .. #e.writs .. " writs.", 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to open it in the Auction House's Buy screen.", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift-click to link it.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Dropdown(parent, label, width, list, order, value, onChange)
    local d = AceGUI:Create("Dropdown")
    d:SetLabel(label)
    d:SetRelativeWidth(width)
    d:SetList(list, order)
    d:SetValue(value)
    d:SetCallback("OnValueChanged", function(_, _, v) onChange(v) end)
    parent:AddChild(d)
    return d
end

local function Row(parent)
    local g = AceGUI:Create("SimpleGroup")
    g:SetFullWidth(true)
    g:SetLayout("Flow")
    parent:AddChild(g)
    return g
end

function Tab:Build()
    local root, kit = self.root, K()
    if not (root and kit) then return end
    local C, COLOR = kit.C, kit.COLOR
    local ah = Settings()
    local function Refresh() self:Build() end
    root:SetWidth(self.holder:GetWidth())
    root:SetHeight(self.holder:GetHeight())
    root:ReleaseChildren()
    -- Parts of the tab the tutorial points at (Tours.lua).
    local marks = { rows = {}, buttons = {} }
    self.marks = marks

    -- Which list: writs on the first row, crates on the second.
    local lists
    for i, l in ipairs(LISTS) do
        if i % 3 == 1 then
            lists = Row(root)
            table.insert(marks.rows, lists.frame)
        end
        local b = AceGUI:Create("Button")
        b:SetText(l.key == ah.list and ("|cffffd100" .. l.text .. "|r") or l.text)
        b:SetRelativeWidth(0.32)
        b:SetCallback("OnClick", function()
            ah.list = l.key
            CH.UI.scrollStatus.ah = nil
            Refresh()
        end)
        lists:AddChild(b)
        marks.buttons[l.key] = b.frame
    end

    -- Filters
    local keyOf = {}
    for writID in pairs(ns.Writs) do keyOf[writID] = kit.PlaceKeys(writID) end
    local filters = Row(root)
    marks.filters = { filters.frame }
    local writLists = ah.list == "writs" or ah.list == "items" or ah.list == "myitems"
    if ah.list == "mymaterials" then
        kit.AddLabel(filters, kit.C(kit.COLOR.dim, "Every way to fill the Waylaid Crates in your bags; the cheapest " ..
            "for each crate is green."), GameFontHighlightSmall)
    elseif writLists then
        ah.zone, ah.npc = kit.AddPlaceFilters(filters, keyOf, ah.zone, ah.npc, function(z, n)
            ah.zone, ah.npc = z, n
            Refresh()
        end)
        local more = Row(root)
        table.insert(marks.filters, more.frame)
        local levels = { ALL = "All levels" }
        for _, t in ipairs(ns.TIERS) do levels[t] = ns.TIER_NAMES[t] end
        local levelOrder = { "ALL", "JOURNEYMAN", "EXPERT", "ARTISAN" }
        if ah.list == "myitems" then
            kit.AddLabel(more, kit.C(kit.COLOR.dim, "What the writs in your quest log and bags still need."),
                GameFontHighlightSmall)
        else
            Dropdown(more, "Level", 0.32, levels, levelOrder, ah.level, function(v) ah.level = v; Refresh() end)
        end
        if ah.list == "writs" then
            for _, box in ipairs({ { "hideDone", "Hide done today" }, { "hideOwned", "Hide writs I have" },
                                   { "writItemCost", "Include item cost" } }) do
                local cb = AceGUI:Create("CheckBox")
                cb:SetLabel(box[2])
                cb:SetRelativeWidth(0.32)
                cb:SetValue(ah[box[1]])
                cb:SetCallback("OnValueChanged", function(_, _, v) ah[box[1]] = v; Refresh() end)
                more:AddChild(cb)
                if box[1] == "writItemCost" then marks.itemCost = cb.frame end
            end
        end
    else
        local levels, levelOrder = { ALL = "All levels" }, { "ALL" }
        for i, name in ipairs(ns.CrateCalc.LEVEL_NAMES) do
            levels[i] = name
            table.insert(levelOrder, i)
        end
        Dropdown(filters, "Level", 0.49, levels, levelOrder, ah.crateLevel, function(v) ah.crateLevel = v; Refresh() end)
        Dropdown(filters, "Fill with", 0.49, { ALL = "Gathered and crafted", GATHERED = "Gathered (herbs, ore, cloth...)",
            CRAFTED = "Crafted (bars, bolts, parts)" }, { "ALL", "GATHERED", "CRAFTED" }, ah.crateKind,
            function(v) ah.crateKind = v; Refresh() end)
        if ah.list == "crates" then
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel("Include materials cost")
            cb:SetRelativeWidth(0.49)
            cb:SetValue(ah.crateMatCost)
            cb:SetCallback("OnValueChanged", function(_, _, v) ah.crateMatCost = v; Refresh() end)
            cb:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPLEFT")
                GameTooltip:SetText("Include materials cost", 1, 1, 1)
                GameTooltip:AddLine("Adds the cheapest way to fill each crate to its cost.", nil, nil, nil, true)
                GameTooltip:Show()
            end)
            cb:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            local row = Row(root)
            row:AddChild(cb)
            marks.crateCost = cb.frame
        end
    end

    -- Search
    local entries = Entries(ah.list, ah, keyOf)
    local ids = SearchIDs(entries, ah)
    local controls = Row(root)
    local Scan = CH.AHScan
    local search = AceGUI:Create("Button")
    search:SetRelativeWidth(0.3)
    if Scan:IsRunning() then
        search:SetText("Stop")
        search:SetCallback("OnClick", function() Scan:Stop() end)
    else
        local unique = {}
        for _, id in ipairs(ids) do unique[id] = true end
        local n = 0
        for _ in pairs(unique) do n = n + 1 end
        search:SetText(string.format("Search %d item%s", n, n == 1 and "" or "s"))
        search:SetDisabled(n == 0)
        search:SetCallback("OnClick", function() Scan:Start(ids) end)
    end
    controls:AddChild(search)
    local status = AceGUI:Create("Label")
    status:SetRelativeWidth(0.68)
    status:SetFontObject(GameFontHighlight)
    controls:AddChild(status)
    self.status = status
    self:UpdateStatus()
    marks.search = { search.frame, status.frame }

    -- The list
    local box = AceGUI:Create("InlineGroup")
    box:SetFullWidth(true)
    box:SetFullHeight(true)
    box:SetLayout("Fill")
    root:AddChild(box)
    marks.table = box.frame
    local scroll = kit.CreateScroll(box, "ah")
    if #entries == 0 then
        local empty = {
            myitems = "Every writ you hold has its item, or none match the filters.",
            mymaterials = "No Waylaid Crates in your bags.",
        }
        kit.AddLabel(scroll, empty[ah.list] or "Nothing matches the filters.",
            GameFontHighlight)
        root:DoLayout()
        return
    end

    -- The cheapest bundle of each crate (materials list).
    local cheapest = {}
    local quotes = {}
    for _, e in ipairs(entries) do
        local q = Quote(e, ah)
        quotes[e] = q
        if e.crate and q.cost and not q.short then
            local best = cheapest[e.crate]
            if not best or q.cost < quotes[best].cost then cheapest[e.crate] = e end
        end
    end

    COLUMNS[2].title = INFO_TITLE[ah.list]
    local columns = LIST_COLUMNS[ah.list] or COLUMNS
    local rows = {}
    for _, e in ipairs(entries) do
        local q = quotes[e]
        local name = kit.ItemName(e.id, e.name)
        if cheapest[e.crate] == e then name = C(COLOR.ready, name) end
        local function Money(v)
            if not v then return "" end
            local s = ns.FormatMoneyIcons(v)
            return q.estimated and C(COLOR.dim, "~" .. s) or s
        end
        local listed
        if q.at then
            listed = (q.listed > 0 and tostring(q.listed) or C(COLOR.inbags, "none")) .. C(COLOR.dim, " " .. Ago(q.at))
        else
            listed = C(COLOR.dim, "-")
        end
        -- The "per gold" column: reputation for writs, Favor for crates.
        local rep = (ah.list == "writs" and WritRepPerGold(e.id, q)) or (ah.list == "crates" and CrateFavorPerGold(e.id, q))
        local text = {
            name = name, info = e.info, need = tostring(e.need), price = Money(q.price),
            cost = Money(q.cost) .. (q.short and C(COLOR.inbags, "*") or ""), listed = listed,
            rep = rep and (q.estimated and C(COLOR.dim, "~" .. ns.FormatRepPerGold(rep)) or ns.FormatRepPerGold(rep)) or "",
        }
        local cells = {}
        for i, col in ipairs(columns) do cells[i] = text[col.key] end
        table.insert(rows, {
            cells = cells,
            sort = { name = name:lower(), info = e.sortInfo, need = e.need, price = q.price, cost = q.cost, rep = rep or nil,
                     listed = q.listed, tie = string.format("%s%08d", e.sortInfo or "", e.id) },
            onEnter = function(frame) ShowRowTooltip(frame, e, q) end,
            onClick = function()
                if IsModifiedClick("CHATLINK") then
                    local _, link = C_Item.GetItemInfo(e.id)
                    if link then kit.InsertLink(link) end
                else
                    self:ShowInBuyScreen(e.id)
                end
            end,
        })
    end
    local sortKey, sortDesc, sortBy = kit.TableSort(ah, "row", columns, "price", Refresh)
    kit.SortRows(rows, sortKey, sortDesc)
    kit.AddTable(scroll, LIST_COLUMNS[ah.list] and ("ah_" .. ah.list) or "ah", columns, rows, sortKey, sortDesc, sortBy)
    root:DoLayout()
end

function Tab:UpdateStatus()
    if not self.status then return end
    local kit = K()
    local Scan = CH.AHScan
    if Scan:IsRunning() then
        local done, total = Scan:Progress()
        self.status:SetText(string.format("Searching %d of %d...", done + 1, total))
    else
        self.status:SetText(kit.C(kit.COLOR.dim, "Click a row to buy it in the Auction House. ~ = estimate, " ..
            "* = not enough listed."))
    end
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function Lib()
    return LibStub("LibAHTab-1-0", true)
end

function Tab:CreateTab()
    local lib = Lib()
    if not (lib and AuctionHouseFrame) or lib:DoesIDExist(TAB_ID) then return end
    local holder = CreateFrame("Frame", nil, AuctionHouseFrame)
    holder:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 8, -28)
    holder:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 28)
    self.holder = holder

    local root = AceGUI:Create("SimpleGroup")
    root:SetLayout("Flow")
    root.noAutoHeight = true
    root.frame:SetParent(holder)
    root.frame:ClearAllPoints()
    root.frame:SetPoint("TOPLEFT", holder, "TOPLEFT")
    root.frame:Show()
    self.root = root

    holder:SetScript("OnShow", function()
        self:Build()
        if CH.Tours then CH.Tours:OfferAuctionHouse() end
    end)
    holder:SetScript("OnSizeChanged", function() if holder:IsShown() then self:Build() end end)
    lib:CreateTab(TAB_ID, holder, "Craftman's", "Craftman's Helper")
end

-- Opens the tab on a list (with settings to copy into its filters) and optionally searches it.
-- Returns false when the Auction House isn't open.
function Tab:Open(list, filters, searchNow)
    if not AHOpen() then return false end
    self:CreateTab()
    local ah = Settings()
    ah.list = list
    for k, v in pairs(filters or {}) do ah[k] = v end
    CH.UI.scrollStatus.ah = nil
    Lib():SetSelected(TAB_ID)
    self:Build()
    if searchNow then self:SearchShown() end
    return true
end

-- Searches every item in the list as it's shown now.
function Tab:SearchShown()
    local keyOf = {}
    for writID in pairs(ns.Writs) do keyOf[writID] = K().PlaceKeys(writID) end
    local ids = {}
    for _, id in ipairs(SearchIDs(Entries(Settings().list, Settings(), keyOf), Settings())) do table.insert(ids, id) end
    if #ids > 0 then CH.AHScan:Start(ids) end
end

function Tab:IsAuctionHouseOpen()
    return AHOpen()
end

function Tab:OnProgress(_, done, total, finished)
    if not (self.holder and self.holder:IsShown()) then return end
    if finished or (done > 0 and done % REFRESH_EVERY == 0) or done == 1 then
        self:Build()
    else
        self:UpdateStatus()
    end
end

function Tab:OnUpdated()
    if self.holder and self.holder:IsShown() and not CH.AHScan:IsRunning() then self:Build() end
end

function Tab:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(_, kind)
    if Enum and Enum.PlayerInteractionType and kind == Enum.PlayerInteractionType.Auctioneer then
        self:CreateTab()
    end
    if CH.UI.Redraw then CH.UI:Redraw() end -- the "Search at the Auction House" buttons
end

function Tab:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, kind)
    if Enum and Enum.PlayerInteractionType and kind == Enum.PlayerInteractionType.Auctioneer then
        if CH.UI.Redraw then CH.UI:Redraw() end
    end
end

function Tab:OnEnable()
    if not C_AuctionHouse then return end
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    self:RegisterMessage(CH.AHScan.MSG_PROGRESS, "OnProgress")
    self:RegisterMessage(ns.MSG_NAMES, "OnUpdated")
    self:RegisterMessage(ns.MSG_UPDATED, "OnUpdated")
end
