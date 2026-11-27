-- Waylaid Crates: what filling one costs, and what that makes a Merchant's Favor cost.
--
-- A crate is filled with any one of its bundles (Data/Crates.lua) and handed in for Merchant's
-- Favor and a little silver. From Friendly, 15 Favor buy a Forged Delivery Receipt, which turns
-- one more (empty) crate into 50 reputation with the writ faction.
local _, ns = ...

local Crates = {}
ns.CrateCalc = Crates

Crates.LEVEL_NAMES = { "Apprentice", "Journeyman", "Expert", "Artisan" }
-- Favor for a filled crate by level; crafted crates (Fabrics, Ingots, Parts) give twice as much.
Crates.FAVOR = { 5, 10, 15, 20 }
-- Silver paid at the hand-in, in copper, by level; twice as much for crafted crates.
Crates.SILVER = { 250, 500, 750, 1000 }
Crates.FAVOR_CURRENCY = 3402
Crates.RECEIPT = { itemID = 262902, favor = 15, rep = 50, silver = 100 }
-- Who takes the crates: [faction] = { npcID, name, map, x, y }.
Crates.HAND_IN = {
    Horde = { npcID = 256386, name = "Dokimi", map = 1413, x = 50.1, y = 29.4, place = "the Crossroads, The Barrens" },
    Alliance = { npcID = 256390, name = "Marcy Baker", map = 1433, x = 9.7, y = 70.9, place = "Redridge Mountains" },
}

local function Price(itemID)
    local P = ns.Prices
    if not (P and P.GetItemPrice) then return nil end
    return P.GetItemPrice(itemID)
end

local function CashbackOn()
    return not (ns.Prices and ns.Prices.CashbackOn) or ns.Prices.CashbackOn()
end

function Crates.Favor(crateID)
    local c = ns.Crates[crateID]
    return c and Crates.FAVOR[c.level] * (c.crafted and 2 or 1)
end

function Crates.Silver(crateID)
    local c = ns.Crates[crateID]
    return c and Crates.SILVER[c.level] * (c.crafted and 2 or 1)
end

-- What filling and handing in a crate costs:
--   { crateID, name, level, crafted, favor, silver (0 with cashback off),
--     cratePrice (nil when the crate has no price), bundles = { { itemID, count, name, unit, cost } }
--     cheapest first (unpriced ones last), best = the cheapest priced bundle or nil,
--     cost = crate + best bundle (nil without a bundle price; without the crate's price when that's
--     missing, flagged crateMissing), net = cost - silver, perFavor = net / favor, age = oldest days }
function Crates.Estimate(crateID)
    local c = ns.Crates[crateID]
    if not c then return nil end
    local e = { crateID = crateID, name = c.name, level = c.level, crafted = c.crafted or false,
                favor = Crates.Favor(crateID), silver = CashbackOn() and Crates.Silver(crateID) or 0, bundles = {} }
    local function Older(age)
        if age and (not e.age or age > e.age) then e.age = age end
    end
    local unit, age = Price(crateID)
    e.cratePrice = unit
    if unit then Older(age) end
    for i, b in ipairs(c.bundles) do
        local p, a = Price(b[1])
        table.insert(e.bundles, { itemID = b[1], count = b[2], name = b[3], unit = p, cost = p and p * b[2], age = a, order = i })
    end
    table.sort(e.bundles, function(a, b)
        if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
        if a.cost and a.cost ~= b.cost then return a.cost < b.cost end
        return a.order < b.order
    end)
    local best = e.bundles[1]
    if best and best.cost then
        e.best = best
        Older(best.age)
        e.cost = best.cost + (e.cratePrice or 0)
        e.crateMissing = e.cratePrice == nil
        e.net = e.cost - e.silver
        e.perFavor = e.net / e.favor
    end
    return e
end

-- Every crate's estimate (filter(crateID) -> bool is optional), in crate order.
function Crates.List(filter)
    local ids = {}
    for id in pairs(ns.Crates) do
        if not filter or filter(id) then table.insert(ids, id) end
    end
    table.sort(ids)
    local list = {}
    for _, id in ipairs(ids) do table.insert(list, Crates.Estimate(id)) end
    return list
end

-- The cheapest way to earn Favor: the estimate with the lowest gold per Favor that includes the
-- crate's own price, or nil.
function Crates.BestPerFavor(list)
    local best
    for _, e in ipairs(list or Crates.List()) do
        if e.perFavor and not e.crateMissing and (not best or e.perFavor < best.perFavor) then best = e end
    end
    return best
end

-- The cheapest crate to buy empty, as { crateID, price } or nil.
function Crates.CheapestEmpty(list)
    local best
    for _, e in ipairs(list or Crates.List()) do
        if e.cratePrice and (not best or e.cratePrice < best.price) then best = { crateID = e.crateID, price = e.cratePrice } end
    end
    return best
end

-- Reputation for a Forged Delivery Receipt hand-in, with Diplomat (rounded down).
function Crates.ReceiptRep()
    local rank = ns.DiplomatRank and ns.DiplomatRank() or 0
    return math.floor(Crates.RECEIPT.rep * (1 + (ns.DIPLOMAT_STEP or 0.02) * rank) + 1e-6)
end

-- 50 reputation through a receipt: the Favor for it from the cheapest crates, plus an empty crate.
-- Returns { fill = the estimate Favor comes from, empty = CheapestEmpty, favorCost, cost, silver,
-- net, rep, repPerGold } or nil without prices.
function Crates.Receipt(list)
    list = list or Crates.List()
    local fill, empty = Crates.BestPerFavor(list), Crates.CheapestEmpty(list)
    if not (fill and empty) then return nil end
    local r = { fill = fill, empty = empty, rep = Crates.ReceiptRep() }
    r.favorCost = fill.perFavor * Crates.RECEIPT.favor
    r.cost = r.favorCost + empty.price
    r.silver = CashbackOn() and Crates.RECEIPT.silver or 0
    r.net = r.cost - r.silver
    r.repPerGold = ns.Prices and ns.Prices.RepPerGold and ns.Prices.RepPerGold(r.rep, r.net)
    return r
end

-- Your Merchant's Favor, or nil when the game doesn't say.
function Crates.FavorBalance()
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(Crates.FAVOR_CURRENCY)
    return info and info.quantity
end

local function Count(itemID, bank)
    local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    return GetCount and GetCount(itemID, bank) or 0
end

-- Crates of this kind you have: { bags, bank, fill = a bundle (from Data/Crates.lua) your bags
-- can fill it with now, or nil }.
function Crates.Owned(crateID)
    local c = ns.Crates[crateID]
    local bags = Count(crateID)
    local o = { bags = bags, bank = math.max(0, Count(crateID, true) - bags) }
    for _, b in ipairs(c and c.bundles or {}) do
        if Count(b[1]) >= b[2] then
            o.fill = { itemID = b[1], count = b[2], name = b[3] }
            break
        end
    end
    return o
end

-- Where your faction hands crates in.
function Crates.HandIn()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return Crates.HAND_IN[faction or ""]
end
