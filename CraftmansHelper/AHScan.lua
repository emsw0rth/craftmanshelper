-- Searches the Auction House for a list of items, one at a time, and remembers what's listed:
-- the lowest price and how many are for sale at each price. The prices are a price source of
-- their own (Prices.lua, "SCAN"), so the addon has prices without a price addon.
--
-- Uses the game's own search (C_AuctionHouse.SendSearchQuery), waits whenever the Auction House
-- says it's busy, and moves on after a few seconds when an answer doesn't come.
local _, ns = ...
local CH = ns.CH

local Scan = CH:NewModule("AHScan", "AceEvent-3.0", "AceTimer-3.0")
CH.AHScan = Scan

Scan.TIMEOUT = 5          -- seconds to wait for one item's results
Scan.MAX_LEVELS = 20      -- commodity price levels remembered per item (cheapest first)
Scan.MAX_AUCTIONS = 30    -- auctions remembered per item (cheapest buyout first)
Scan.VERSION = 2          -- saved results from older versions (per-unit auction prices) are ignored
Scan.MSG_PROGRESS = "CRAFTMANSHELPER_AHSCAN" -- fired with (done, total, finished)

---------------------------------------------------------------------------
-- Results (pure functions, also used by the tests)
---------------------------------------------------------------------------

-- Listings -> { p, q = total listed, l, w }.
-- Commodities (whole = false): listings { { price = copper per unit, count } }; you can buy any
-- number of units, so l = { { unit price, count } } merged by price, cheapest first, and p is the
-- lowest unit price.
-- Auctions (whole = true): listings { { price = the auction's buyout, count } }; an auction is
-- bought whole, so l = { { buyout, count } } one per auction, cheapest buyout first, and p is the
-- cheapest buyout: what getting one costs. Only listings with a buyout belong here.
function Scan.Summarize(listings, whole)
    if whole then
        local auctions, total = {}, 0
        for _, x in ipairs(listings) do
            if x.price and x.price > 0 and x.count and x.count > 0 then
                table.insert(auctions, { x.price, x.count })
                total = total + x.count
            end
        end
        table.sort(auctions, function(a, b)
            if a[1] ~= b[1] then return a[1] < b[1] end
            return a[2] > b[2]
        end)
        local kept = {}
        for i = 1, math.min(#auctions, Scan.MAX_AUCTIONS) do kept[i] = auctions[i] end
        return { p = kept[1] and kept[1][1], q = total, l = kept, w = true }
    end
    local byPrice, prices, total = {}, {}, 0
    for _, x in ipairs(listings) do
        if x.price and x.price > 0 and x.count and x.count > 0 then
            if not byPrice[x.price] then
                byPrice[x.price] = 0
                table.insert(prices, x.price)
            end
            byPrice[x.price] = byPrice[x.price] + x.count
            total = total + x.count
        end
    end
    table.sort(prices)
    local levels = {}
    for i = 1, math.min(#prices, Scan.MAX_LEVELS) do
        table.insert(levels, { prices[i], byPrice[prices[i]] })
    end
    return { p = prices[1], q = total, l = levels }
end

-- What getting `need` units costs: copper, and how many you'd get (less than need when too few are
-- listed). Commodities: the cheapest units first. Auctions: the cheapest set of whole auctions
-- with at least `need` in them (which may come with more than needed), or all of them when
-- they hold too few.
function Scan.CostFor(summary, need)
    if summary and summary.w then
        local INF = math.huge
        local best = { [0] = 0 }
        for k = 1, need do best[k] = INF end
        local all, total = 0, 0
        for _, a in ipairs(summary.l) do
            all, total = all + a[1], total + a[2]
            for k = need, 0, -1 do
                if best[k] < INF then
                    local nk = math.min(need, k + a[2])
                    if best[k] + a[1] < best[nk] then best[nk] = best[k] + a[1] end
                end
            end
        end
        if best[need] < INF then return best[need], need end
        return all, total
    end
    local cost, got = 0, 0
    for _, level in ipairs(summary and summary.l or {}) do
        if got >= need then break end
        local take = math.min(level[2], need - got)
        cost, got = cost + take * level[1], got + take
    end
    return cost, got
end

---------------------------------------------------------------------------
-- Saved results: CH.db.global.scans["Realm - Faction"][itemID] = { p, q, l, t = time }
---------------------------------------------------------------------------

local function RealmKey()
    return (GetRealmName and GetRealmName() or "?") .. " - " .. (UnitFactionGroup and UnitFactionGroup("player") or "?")
end

local function Saved(create)
    local g = CH.db and CH.db.global
    if not g then return nil end
    if create then g.scans = g.scans or {} end
    local all = g.scans
    if not all then return nil end
    local key = RealmKey()
    if create then all[key] = all[key] or {} end
    return all[key]
end

-- What the last search found for an item ({ p, q, l, w, t }), or nil when it was never searched.
function Scan.Get(itemID)
    local s = Saved(false)
    local r = s and s[itemID]
    if r and r.v == Scan.VERSION then return r end
end

-- Lowest price and its age in days, for Prices.lua; nil when nothing is listed or never searched.
function Scan.Price(itemID)
    local r = Scan.Get(itemID)
    if not (r and r.p) then return nil end
    return r.p, math.max(0, (time() - (r.t or 0)) / 86400)
end

function Scan.HasData()
    local s = Saved(false)
    if not s then return false end
    for _, r in pairs(s) do
        if r.v == Scan.VERSION then return true end
    end
    return false
end

local function Store(itemID, listings, whole)
    local r = Scan.Summarize(listings, whole)
    r.t, r.v = time(), Scan.VERSION
    Saved(true)[itemID] = r
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

local queue, total, current, timer = {}, 0, nil, nil

function Scan:IsRunning()
    return current ~= nil or #queue > 0
end

function Scan:Progress()
    return total - #queue - (current and 1 or 0), total
end

local function AHOpen()
    return AuctionHouseFrame and AuctionHouseFrame:IsShown()
end

local function Fire(finished)
    local done = total - #queue - (current and 1 or 0)
    CH:SendMessage(Scan.MSG_PROGRESS, done, total, finished)
end

-- Searches the Auction House for each item ID in turn. Replaces a search in progress.
function Scan:Start(itemIDs)
    self:Stop(true)
    local seen = {}
    for _, id in ipairs(itemIDs) do
        if not seen[id] then
            seen[id] = true
            table.insert(queue, id)
        end
    end
    total = #queue
    Fire(false)
    self:Next()
end

-- Stops searching; what was found so far is kept.
function Scan:Stop(quiet)
    local was = self:IsRunning()
    wipe(queue)
    current = nil
    if timer then self:CancelTimer(timer); timer = nil end
    if was and not quiet then Fire(true) end
end

local function SearchSorts()
    local order = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = order and order.Price or 0, reverseSort = false } }
end

function Scan:Next()
    if current then return end
    if not AHOpen() then self:Stop(); return end
    if #queue == 0 then
        total = 0
        Fire(true)
        return
    end
    local AH = C_AuctionHouse
    if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
        return -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY calls back
    end
    current = table.remove(queue, 1)
    local key = AH.MakeItemKey(current)
    AH.SendSearchQuery(key, SearchSorts(), true)
    timer = self:ScheduleTimer("OnTimeout", Scan.TIMEOUT)
end

local function Finish(self, itemID, listings, whole)
    if itemID ~= current then return end
    if timer then self:CancelTimer(timer); timer = nil end
    if listings then Store(itemID, listings, whole) end
    current = nil
    Fire(false)
    self:Next()
end

function Scan:OnTimeout()
    timer = nil
    if current then Finish(self, current, nil) end
end

function Scan:COMMODITY_SEARCH_RESULTS_UPDATED(_, itemID)
    if itemID ~= current then return end
    local AH, listings = C_AuctionHouse, {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r then table.insert(listings, { price = r.unitPrice, count = r.quantity }) end
    end
    Finish(self, itemID, listings)
end

function Scan:ITEM_SEARCH_RESULTS_UPDATED(_, itemKey)
    if not (itemKey and itemKey.itemID == current) then return end
    local AH, listings = C_AuctionHouse, {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        -- Only auctions you can buy out: bid-only ones have no buyout.
        if r and (r.buyoutAmount or 0) > 0 and (r.quantity or 0) > 0 then
            table.insert(listings, { price = r.buyoutAmount, count = r.quantity })
        end
    end
    Finish(self, itemKey.itemID, listings, true)
end

function Scan:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
    if not current and #queue > 0 then self:Next() end
end

function Scan:AUCTION_HOUSE_CLOSED()
    self:Stop()
end

function Scan:OnEnable()
    if not C_AuctionHouse then return end
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
end
