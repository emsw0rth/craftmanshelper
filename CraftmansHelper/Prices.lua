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

-- Estimate for a writ: { cost = copper for the full count, rep, repPerGold, age } or nil.
function Prices.GetWritEstimate(writID)
    local w = ns.Writs[writID]
    if not w then return nil end
    local unit, age = Prices.GetItemPrice(w.item)
    if not unit then return nil end
    local cost = unit * (w.count or 1)
    local rep = ns.TIER_REP[w.tier]
    return {
        cost = cost,
        rep = rep,
        repPerGold = rep and rep / (cost / 10000),
        age = age,
    }
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
