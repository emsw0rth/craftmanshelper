-- The "Craftman's" tab in the Auction House: lists of writs, the items writs ask for, Waylaid
-- Crates and crate materials, searched one item at a time (AHScan.lua). Clicking a row opens that
-- item in the Auction House's own Buy screen.
--
-- The tab button comes from LibAHTab (MIT), which adds Auction House tabs without tainting the
-- game's UI. TradeSkillMaster and auxForever hide the game's Auction House window behind their own;
-- a "Craftman's" button in their window switches to the game's window on this tab (see
-- "TradeSkillMaster and auxForever" below).
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

-- The lists are drawn into one frame (root), moved into whichever holder is showing: the
-- Auction House tab's, or the panel in auxForever's window.
function Tab:Use(holder)
    if not self.root then
        local root = AceGUI:Create("SimpleGroup")
        root:SetLayout("Flow")
        root.noAutoHeight = true
        self.root = root
    end
    self.holder = holder
    local f = self.root.frame
    f:SetParent(holder)
    f:SetFrameLevel(holder:GetFrameLevel() + 1)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", holder, "TOPLEFT")
    f:Show()
end

local function OnHolderShown(self, holder)
    self:Use(holder)
    self:Build()
    if CH.Tours then CH.Tours:OfferAuctionHouse() end
end

function Tab:CreateTab()
    local lib = Lib()
    if not (lib and AuctionHouseFrame) or lib:DoesIDExist(TAB_ID) then return end
    local holder = CreateFrame("Frame", nil, AuctionHouseFrame)
    holder:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 8, -28)
    holder:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 28)
    self.tabHolder = holder
    if not self.holder then self:Use(holder) end

    holder:SetScript("OnShow", function() OnHolderShown(self, holder) end)
    holder:SetScript("OnSizeChanged", function() if self.holder == holder and holder:IsShown() then self:Build() end end)
    lib:CreateTab(TAB_ID, holder, "Craftman's", "Craftman's Helper")

    -- TradeSkillMaster and auxForever shrink the game's window to almost nothing while their own
    -- is showing. The tab is sized to its text when it's made, and text measured that small comes
    -- out far too wide (the tab ran off the screen), so it's measured again at full size.
    local function FixWidth()
        local b = lib:GetButton(TAB_ID)
        if b and PanelTemplates_TabResize and AuctionHouseFrame:GetScale() >= 0.5 then
            PanelTemplates_TabResize(b, 20, nil, 70)
        end
    end
    hooksecurefunc(AuctionHouseFrame, "SetScale", function() C_Timer.After(0, FixWidth) end)
    AuctionHouseFrame:HookScript("OnShow", function() C_Timer.After(0, FixWidth) end)
    FixWidth()
end

---------------------------------------------------------------------------
-- TradeSkillMaster and auxForever
--
-- Both replace the Auction House window: they keep the game's window open but shrunk to almost
-- nothing behind their own, and the Craftman's tab with it. Each has a button that shows the
-- game's window again: TSM's "WoW UI", aux's "Blizzard UI". A "Craftman's" button next to it
-- clicks that button (so they switch the way they always do) and then opens this tab.
--
-- Neither has an API for this, so their windows are found by what they're made of:
-- aux: its window's global name (aux_frame); its "Blizzard UI" button is in its top bar.
-- TSM: TSM_API.IsUIVisible("AUCTION") says its window is open, and it's the largest shown TSM
--   window (those are in UISpecialFrames, with resizeBtn and resizeIcon fields). Its "WoW UI"
--   button (the same in every language) is found in it. TSM reuses its frames for its other
--   windows, so our button only sits in TSM's title bar while that window is open.
-- Every lookup is checked; when one fails, our button just doesn't appear.
---------------------------------------------------------------------------

local CHECK_EVERY = 0.2 -- seconds between checks for TSM's window while the Auction House is open

local function AuxFrame()
    local f = _G.aux_frame
    if type(f) == "table" and f.GetObjectType and f.body then return f end
end

local function PlainText(region)
    local t = region and region.GetText and region:GetText()
    return type(t) == "string" and (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or nil
end

-- A button directly in aux's window (its top bar), by its label.
local function AuxButton(f, text)
    for _, c in ipairs({ f:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "Button" and PlainText(c) == text then return c end
    end
end

local function TSMShown()
    local api = _G.TSM_API
    if not (type(api) == "table" and api.IsUIVisible) then return false end
    local ok, shown = pcall(api.IsUIVisible, "AUCTION")
    return ok and shown == true
end

local function TSMFrame()
    if not TSMShown() then return nil end
    local best, bestArea
    for _, name in ipairs(UISpecialFrames) do
        local f = _G[name]
        if type(f) == "table" and f.resizeBtn and f.resizeIcon and f.IsVisible and f:IsVisible() and f:GetLeft() then
            local s = f:GetEffectiveScale()
            local area = f:GetWidth() * f:GetHeight() * s * s
            if not bestArea or area > bestArea then best, bestArea = f, area end
        end
    end
    return best
end

-- Whether TSM or aux keeps the game's Auction House window (and the tab) out of sight.
function Tab:GameWindowHidden()
    return AuctionHouseFrame ~= nil and (AuctionHouseFrame:GetAlpha() < 0.5 or AuctionHouseFrame:GetScale() < 0.5)
end

local function HasLabel(frame, text)
    if PlainText(frame) == text then return true end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and PlainText(r) == text then return true end
    end
end

local function FindButton(frame, text, depth)
    if depth > 8 then return nil end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "Button" and c:IsVisible() and HasLabel(c, text) then return c end
        local found = FindButton(c, text, depth + 1)
        if found then return found end
    end
end

-- TSM's "WoW UI" button, while TSM's Auction House window is showing.
function Tab:TSMSwitchButton()
    if not self:GameWindowHidden() then return nil end
    local f = TSMFrame()
    if not f then return nil end
    local b = self.tsmSwitch
    if not (b and b:IsVisible() and HasLabel(b, "WoW UI")) then
        -- TSM's window has many frames: when the button isn't there, look again only every 2 s.
        if (self.tsmSwitchRetry or 0) > GetTime() then return nil end
        b = FindButton(f, "WoW UI", 0)
        self.tsmSwitch = b
        self.tsmSwitchRetry = not b and GetTime() + 2 or nil
    end
    return b
end

-- aux's "Blizzard UI" button, while aux's window is showing and the game's is hidden.
function Tab:AuxSwitchButton()
    local f = AuxFrame()
    if not (f and f:IsVisible() and self:GameWindowHidden()) then return nil end
    return AuxButton(f, "Blizzard UI")
end

-- Switches from TSM's or aux's window to the game's, on this tab. false when neither is showing
-- (or its button isn't found).
function Tab:SwitchToTab()
    local b = self:TSMSwitchButton() or self:AuxSwitchButton()
    if not b then return false end
    b:Click()
    C_Timer.After(0, function()
        if AHOpen() and Lib() and Lib():DoesIDExist(TAB_ID) then Lib():SetSelected(TAB_ID) end
    end)
    return true
end

local function ShowButtonTooltip(btn, back)
    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Craftman's Helper")
    GameTooltip:AddLine("Switches to the WoW Auction House window on the Craftman's tab: writs, writ items, " ..
        "crates and crate materials, priced in one search. " .. back, 1, 1, 1, true)
    GameTooltip:Show()
end

-- The "Craftman's" button in aux's top bar, in aux's look (copied from its Full scan button).
function Tab:CreateAuxButton()
    local f = AuxFrame()
    if self.auxButton or not f then return end
    local ref = AuxButton(f, "Full scan")
    local b = CreateFrame("Button", nil, f, "BackdropTemplate")
    b:SetSize(ref and ref:GetWidth() or 80, ref and ref:GetHeight() or 26)
    if ref then
        -- Left of the last of aux's buttons lined up leftward from Full scan (its settings gear).
        local last = ref
        for _ = 1, 10 do
            local nextOne
            for _, c in ipairs({ f:GetChildren() }) do
                if c ~= b and c.GetPoint and c:GetNumPoints() > 0 then
                    local point, rel, relPoint = c:GetPoint(1)
                    if point == "RIGHT" and rel == last and relPoint == "LEFT" then nextOne = c; break end
                end
            end
            if not nextOne then break end
            last = nextOne
        end
        b:SetPoint("RIGHT", last, "LEFT", -4, 0)
    else
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -260, -7)
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetAllPoints()
    b:SetFontString(fs)
    local refFS = ref and ref.GetFontString and ref:GetFontString()
    local font, size, flags
    if refFS then font, size, flags = refFS:GetFont() end
    if font then fs:SetFont(font, size, flags) end
    b:SetText("Craftman's")
    if fs:GetStringWidth() + 16 > b:GetWidth() then b:SetWidth(fs:GetStringWidth() + 16) end
    local backdrop = ref and ref.GetBackdrop and ref:GetBackdrop()
    if backdrop then
        b:SetBackdrop(backdrop)
        b:SetBackdropColor(ref:GetBackdropColor())
        b:SetBackdropBorderColor(ref:GetBackdropBorderColor())
    else
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(0.12, 0.12, 0.12, 1)
        b:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
    end
    b:SetScript("OnClick", function()
        if not self:SwitchToTab() then
            CH:Print("Couldn't find auxForever's Blizzard UI button: click it, then the Craftman's tab.")
        end
    end)
    b:SetScript("OnEnter", function(btn) ShowButtonTooltip(btn, "Click aux to bring it back to the front.") end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.auxButton = b
end

-- The "Craftman's" button next to TSM's "WoW UI" button.
function Tab:CreateTSMButton()
    if self.tsmButton then return end
    local b = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    b:SetText("Craftman's")
    b:SetSize(b:GetFontString():GetStringWidth() + 24, 22)
    b:SetScript("OnClick", function() self:SwitchToTab() end)
    b:SetScript("OnEnter", function(btn) ShowButtonTooltip(btn, "Its TSM tab brings you back.") end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    self.tsmButton = b
end

local function ReleaseTSMButton(b)
    b:Hide()
    b:SetParent(UIParent)
    b.anchoredTo = nil
end

-- Shows the button in TSM's window while it's open.
function Tab:UpdateTSMButton()
    local switch = self:TSMSwitchButton()
    if switch then
        self:CreateTSMButton()
        local t = self.tsmButton
        -- In the same bar as the "WoW UI" button, so it's drawn with it (layer, scale, visibility).
        local bar = switch:GetParent() or UIParent
        if t:GetParent() ~= bar or t.anchoredTo ~= switch then
            t:SetParent(bar)
            t:SetScale(1)
            t:ClearAllPoints()
            t:SetPoint("RIGHT", switch, "LEFT", -6, 0)
            t.anchoredTo = switch
        end
        t:SetHeight(math.max(20, switch:GetHeight()))
        if t:GetFrameLevel() <= switch:GetFrameLevel() then t:SetFrameLevel(switch:GetFrameLevel() + 2) end
        t:Show()
    elseif self.tsmButton then
        ReleaseTSMButton(self.tsmButton)
    end
end

function Tab:StartButtons()
    self:CreateAuxButton()
    if not self.ticker then self.ticker = C_Timer.NewTicker(CHECK_EVERY, function() self:UpdateTSMButton() end) end
    self:UpdateTSMButton()
end

function Tab:StopButtons()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.tsmButton then ReleaseTSMButton(self.tsmButton) end
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
    if self:SwitchToTab() then
        -- the tab opens once TSM or aux has switched
    else
        Lib():SetSelected(TAB_ID)
    end
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
        self:StartButtons()
    end
    if CH.UI.Redraw then CH.UI:Redraw() end -- the "Search at the Auction House" buttons
end

function Tab:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, kind)
    if Enum and Enum.PlayerInteractionType and kind == Enum.PlayerInteractionType.Auctioneer then
        self:StopButtons()
        if CH.UI.Redraw then CH.UI:Redraw() end
    end
end

-- Also on the Auction House's own events, in case the interaction ones are missed.
function Tab:AUCTION_HOUSE_SHOW()
    C_Timer.After(0, function()
        if not AHOpen() then return end
        self:CreateTab()
        self:StartButtons()
    end)
end

function Tab:AUCTION_HOUSE_CLOSED()
    self:StopButtons()
end

-- /writs ahcheck: what was found of TradeSkillMaster's and auxForever's windows.
function Tab:Check()
    local function yes(v) return v and "|cff00ff00yes|r" or "|cffff4040no|r" end
    CH:Print("Auction House open: " .. yes(AHOpen()) .. ", game window hidden: " ..
        yes(AHOpen() and self:GameWindowHidden()))
    CH:Print("TSM window open: " .. yes(TSMShown()) .. ", found: " .. yes(TSMFrame()) ..
        ", its WoW UI button: " .. yes(self:TSMSwitchButton()) ..
        ", our button shown: " .. yes(self.tsmButton and self.tsmButton:IsShown()))
    local function where(f)
        if not f then return "none" end
        return string.format("visible %s, left %s, top %s, %sx%s, scale %.3f, alpha %.2f, %s level %d",
            tostring(f:IsVisible()), tostring(f:GetLeft() and math.floor(f:GetLeft())),
            tostring(f:GetTop() and math.floor(f:GetTop())), tostring(math.floor(f:GetWidth())),
            tostring(math.floor(f:GetHeight())), f:GetEffectiveScale(), f:GetEffectiveAlpha(), f:GetFrameStrata(),
            f:GetFrameLevel())
    end
    CH:Print("WoW UI button: " .. where(self:TSMSwitchButton()))
    CH:Print("Our button: " .. where(self.tsmButton))
    CH:Print("TSM window: " .. where(TSMFrame()))
    CH:Print("aux window: " .. yes(AuxFrame() and AuxFrame():IsVisible()) .. ", its Blizzard UI button: " ..
        yes(self:AuxSwitchButton()) .. ", our button: " .. yes(self.auxButton and self.auxButton:IsVisible()) ..
        ", checking: " .. yes(self.ticker))
end

function Tab:OnEnable()
    if not C_AuctionHouse then return end
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterMessage(CH.AHScan.MSG_PROGRESS, "OnProgress")
    self:RegisterMessage(ns.MSG_NAMES, "OnUpdated")
    self:RegisterMessage(ns.MSG_UPDATED, "OnUpdated")
end
