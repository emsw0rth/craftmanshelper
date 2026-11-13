-- Auction House price estimates for writ items, from Auctionator (optional).
local ADDON_NAME, ns = ...

local Prices = {}
ns.Prices = Prices

-- Base reputation per writ tier (QuestieDB quest reputationReward), before rep bonuses.
ns.TIER_REP = { JOURNEYMAN = 75, EXPERT = 125, ARTISAN = 200 }

-- Prices older than this many days are flagged as stale.
Prices.STALE_DAYS = 3

local function Auctionator()
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then return api end
end

function Prices.IsAvailable()
    return Auctionator() ~= nil
end

-- Unit price in copper and age in days (nil when unknown) for an item, or nil.
function Prices.GetItemPrice(itemID)
    local api = Auctionator()
    if not api then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON_NAME, itemID)
    if not ok or type(price) ~= "number" or price <= 0 then return nil end
    local age
    if api.GetAuctionAgeByItemID then
        local okAge, a = pcall(api.GetAuctionAgeByItemID, ADDON_NAME, itemID)
        if okAge and type(a) == "number" then age = a end
    end
    return price, age
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
function Prices.GetBuyList(sortBy, filter)
    local list = {}
    for writID in pairs(ns.Writs) do
        if not filter or filter(writID) then
            local e = Prices.GetWritBuyEstimate(writID)
            if e then table.insert(list, e) end
        end
    end
    table.sort(list, function(a, b)
        if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
        if a.cost and b.cost then
            if sortBy == "rep" and a.repPerGold ~= b.repPerGold then return a.repPerGold > b.repPerGold end
            if a.cost ~= b.cost then return a.cost < b.cost end
        elseif a.writPrice ~= b.writPrice then
            return a.writPrice < b.writPrice
        end
        return a.writID < b.writID
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
