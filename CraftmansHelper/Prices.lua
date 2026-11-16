-- Auction House price estimates for writ items, from Auctionator or TradeSkillMaster
-- (both optional; "AUTO" uses whichever is installed, Auctionator first).
local ADDON_NAME, ns = ...

local Prices = {}
ns.Prices = Prices

-- Base reputation per writ tier (QuestieDB quest reputationReward), before rep bonuses.
ns.TIER_REP = { JOURNEYMAN = 75, EXPERT = 125, ARTISAN = 200 }

-- Prices older than this many days are flagged as stale.
Prices.STALE_DAYS = 3

-- TSM custom price used when no other is set: latest scan's lowest buyout, else market value.
Prices.DEFAULT_TSM_PRICE = "first(DBMinBuyout, DBMarket)"

Prices.SOURCES = { "AUCTIONATOR", "TSM" } -- order tried by "AUTO"
Prices.SOURCE_NAMES = { AUCTIONATOR = "Auctionator", TSM = "TradeSkillMaster" }

local function Profile()
    local db = ns.CH and ns.CH.db
    return db and db.profile or {}
end

local function AuctionatorAPI()
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then return api end
end

local function TSMAPI()
    local api = _G.TSM_API
    if type(api) == "table" and api.GetCustomPriceValue then return api end
end

local function TSMPriceString()
    local s = Profile().tsmPrice
    if type(s) ~= "string" or s:match("^%s*$") then return Prices.DEFAULT_TSM_PRICE end
    return s
end

-- Each source: available() and get(itemID) -> copper, age in days (or nil).
local SOURCES = {
    AUCTIONATOR = {
        available = function() return AuctionatorAPI() ~= nil end,
        get = function(itemID)
            local api = AuctionatorAPI()
            local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON_NAME, itemID)
            if not ok or type(price) ~= "number" or price <= 0 then return nil end
            local age
            if api.GetAuctionAgeByItemID then
                local okAge, a = pcall(api.GetAuctionAgeByItemID, ADDON_NAME, itemID)
                if okAge and type(a) == "number" then age = a end
            end
            return price, age
        end,
    },
    TSM = {
        available = function() return TSMAPI() ~= nil end,
        get = function(itemID)
            local ok, price = pcall(TSMAPI().GetCustomPriceValue, TSMPriceString(), "i:" .. itemID)
            if not ok or type(price) ~= "number" or price <= 0 then return nil end
            return price, nil -- TSM doesn't say how old a price is
        end,
    },
}

-- The source in use: the one chosen in Settings if it's installed, or with "AUTO"
-- the first installed one. nil when there's none.
function Prices.ActiveSource()
    local pref = Profile().priceSource or "AUTO"
    if pref ~= "AUTO" then
        return (SOURCES[pref] and SOURCES[pref].available()) and pref or nil
    end
    for _, key in ipairs(Prices.SOURCES) do
        if SOURCES[key].available() then return key end
    end
end

function Prices.IsAvailable()
    return Prices.ActiveSource() ~= nil
end

function Prices.IsInstalled(key)
    return SOURCES[key] ~= nil and SOURCES[key].available()
end

function Prices.SourceName()
    local key = Prices.ActiveSource()
    return key and Prices.SOURCE_NAMES[key]
end

-- Whether a TSM custom price string is valid: true, or false and TSM's reason.
function Prices.CheckTSMPrice(s)
    local api = TSMAPI()
    if not (api and api.IsCustomPriceValid) then return true end
    local ok, valid, err = pcall(api.IsCustomPriceValid, s)
    if not ok then return false, tostring(valid) end
    return valid and true or false, err
end

-- Unix time of Auctionator's last full scan of the Auction House, or nil. Not part of
-- Auctionator's public API, so read defensively; it's account-wide, not per realm.
-- Auctionator's default scan is the incremental "browse" scan (TimeOfLastBrowseScan);
-- the replicate / GetAll scans are options, so the latest of the three counts.
local SCAN_FIELDS = { "TimeOfLastBrowseScan", "TimeOfLastReplicateScan", "TimeOfLastGetAllScan" }
function Prices.LastFullScan()
    if Prices.ActiveSource() ~= "AUCTIONATOR" then return nil end
    local state = (_G.Auctionator and _G.Auctionator.SavedState) or _G.AUCTIONATOR_SAVEDVARS
    if type(state) ~= "table" then return nil end
    local latest
    for _, field in ipairs(SCAN_FIELDS) do
        local t = state[field]
        if type(t) == "number" and (not latest or t > latest) then latest = t end
    end
    return latest
end

-- Unit price in copper and age in days (nil when unknown) for an item, or nil.
function Prices.GetItemPrice(itemID)
    local key = Prices.ActiveSource()
    if not key then return nil end
    return SOURCES[key].get(itemID)
end

-- Estimate for a writ, or nil when the required item has no price:
--   { cost = copper, rep, repPerGold, age = days (oldest price used),
--     writIncluded = true when the writ's own price is part of cost,
--     writMissing = true when it was asked for but the writ has no price }
-- includeWrit adds the price of the writ item itself (for players who buy writs).
function Prices.GetWritEstimate(writID, includeWrit)
    local w = ns.Writs[writID]
    if not w then return nil end
    local unit, age = Prices.GetItemPrice(w.item)
    if not unit then return nil end
    local cost = unit * (w.count or 1)
    local est = { age = age }
    if includeWrit then
        local writPrice, writAge = Prices.GetItemPrice(writID)
        if writPrice then
            cost = cost + writPrice
            est.writIncluded = true
            if writAge and (not age or writAge > age) then est.age = writAge end
        else
            est.writMissing = true
        end
    end
    est.cost = cost
    est.rep = ns.TIER_REP[w.tier]
    est.repPerGold = est.rep and est.rep / (cost / 10000)
    return est
end

-- Cost of buying a writ and its item off the AH, or nil when the writ itself has no price:
--   { writID, writPrice, itemCost (nil when unknown), cost = writ + items (nil when the item
--     price is unknown), rep, repPerGold (nil without cost), age = oldest price in days }
function Prices.GetWritBuyEstimate(writID)
    local w = ns.Writs[writID]
    if not w then return nil end
    local writPrice, writAge = Prices.GetItemPrice(writID)
    if not writPrice then return nil end
    local e = { writID = writID, writPrice = writPrice, rep = ns.TIER_REP[w.tier], age = writAge }
    local unit, itemAge = Prices.GetItemPrice(w.item)
    if unit then
        e.itemCost = unit * (w.count or 1)
        e.cost = writPrice + e.itemCost
        e.repPerGold = e.rep and e.rep / (e.cost / 10000)
        if itemAge and (not e.age or itemAge > e.age) then e.age = itemAge end
    end
    return e
end

-- Every writ that can be bought, sorted. sortBy: "price" (cheapest first) or "rep" (most rep per
-- gold first). Writs whose item has no price go last, by writ price. filter(writID) -> bool is optional.
-- Writs for sale, sorted. sortBy:
--   "price"  total cost, low to high      "rep"  rep per gold, low to high
--   anything else: by valueOf(entry) (a string or number), low to high
-- desc reverses the order. For price and rep, writs whose item has no price are
-- always listed last. Ties go to the cheaper writ.
function Prices.GetBuyList(sortBy, filter, desc, valueOf)
    local list = {}
    for writID in pairs(ns.Writs) do
        if not filter or filter(writID) then
            local e = Prices.GetWritBuyEstimate(writID)
            if e then table.insert(list, e) end
        end
    end
    local function Cheaper(a, b)
        if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
        local ca, cb = a.cost or a.writPrice, b.cost or b.writPrice
        if ca ~= cb then return ca < cb end
        return a.writID < b.writID
    end
    local values = {}
    if valueOf and sortBy ~= "price" and sortBy ~= "rep" then
        for _, e in ipairs(list) do values[e] = valueOf(e) end
    end
    table.sort(list, function(a, b)
        if sortBy == "price" or sortBy == "rep" then
            if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
            if a.cost and b.cost then
                local va, vb = a.cost, b.cost
                if sortBy == "rep" then va, vb = a.repPerGold, b.repPerGold end
                if va ~= vb then
                    if desc then return va > vb end
                    return va < vb
                end
            elseif a.writPrice ~= b.writPrice then
                if desc then return a.writPrice > b.writPrice end
                return a.writPrice < b.writPrice
            end
            return Cheaper(a, b)
        end
        local va, vb = values[a], values[b]
        if va ~= vb and va ~= nil and vb ~= nil then
            if desc then return va > vb end
            return va < vb
        end
        return Cheaper(a, b)
    end)
    return list
end

-- Money with the game's gold/silver/copper coin icons, like the "Auction" tooltip line.
-- Falls back to plain text (FormatMoney) outside the client.
function ns.FormatMoneyIcons(copper)
    copper = math.floor((copper or 0) + 0.5)
    if GetMoneyString then return GetMoneyString(copper, true) end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    return ns.FormatMoney(copper)
end

-- 14239 -> "1g 42s 39c"; leading zero units are dropped ("42s 39c", "5c").
function ns.FormatMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end
