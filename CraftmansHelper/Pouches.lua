-- Learns how much gold the Coin Pouches from writ turn-ins hold. Opening one opens no loot
-- window: the gold comes in and the pouch leaves the bags in the same moment. So each pouch
-- that leaves the bags is paired with gold that came in at about the same time (not at a
-- merchant, where selling a pouch looks the same), and the amount is recorded for that pouch
-- (Prices.RecordPouch, account-wide).
local _, ns = ...
local CH = ns.CH

local Pouches = CH:NewModule("Pouches", "AceEvent-3.0", "AceTimer-3.0")
CH.Pouches = Pouches

-- Most seconds between a pouch leaving the bags and its gold coming in.
Pouches.PAIR = 0.5
-- Seconds after the last gold or bag change before pairing them up.
Pouches.WAIT = 1

local function Count(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and f(id) or 0
end

local function CountAll()
    local t = {}
    for _, id in pairs(ns.POUCHES) do t[id] = Count(id) end
    return t
end

-- /writs pouches debug: say in chat what the detection sees (for this session only).
local function Debug(fmt, ...)
    if Pouches.debug then
        CH:Print(string.format("|cff999999[pouch %.2f]|r ", GetTime()) .. string.format(fmt, ...))
    end
end

function Pouches:ToggleDebug()
    self.debug = not self.debug
    CH:Print(self.debug and "Pouch debug on: open a coin pouch and the steps show here. " ..
        "/writs pouches debug again to stop." or "Pouch debug off.")
end

function Pouches:OnEnable()
    self.counts = CountAll()
    self.money = GetMoney()
    self.drops = {} -- { id, t }: pouches that left the bags, not paired yet
    self.gains = {} -- { copper, t }: gold that came in, not paired yet
    self:RegisterEvent("PLAYER_MONEY")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("MERCHANT_SHOW", function() self.merchant = true end)
    self:RegisterEvent("MERCHANT_CLOSED", function() self.merchant = false end)
end

-- Pairs up once nothing has changed for WAIT seconds.
function Pouches:Settle()
    if self.timer then self:CancelTimer(self.timer) end
    self.timer = self:ScheduleTimer("Pair", Pouches.WAIT)
end

function Pouches:PLAYER_MONEY()
    local now = GetMoney()
    local delta = now - (self.money or now)
    self.money = now
    Debug("gold %+d copper%s", delta, self.merchant and " (at a merchant: ignored)" or "")
    if delta > 0 and not self.merchant then
        table.insert(self.gains, { copper = delta, t = GetTime() })
        self:Settle()
    end
end

function Pouches:BAG_UPDATE_DELAYED()
    local counts, now = CountAll(), GetTime()
    for id, n in pairs(counts) do
        local was = self.counts[id] or 0
        if n ~= was then Debug("bags: pouch %d %d -> %d", id, was, n) end
        -- Pouches sold at a merchant aren't opened.
        if not self.merchant then
            for _ = 1, was - n do table.insert(self.drops, { id = id, t = now }) end
        end
    end
    self.counts = counts
    if #self.drops > 0 then self:Settle() end
end

-- Records each pouch that left the bags with the gold that came in nearest to it (within
-- PAIR seconds). Pouches of two kinds leaving at the same moment can't be told apart: skipped.
function Pouches:Pair()
    self.timer = nil
    local drops, gains = self.drops, self.gains
    self.drops, self.gains = {}, {}
    local used, recorded = {}, false
    for i, d in ipairs(drops) do
        local clash = false
        for j, other in ipairs(drops) do
            if j ~= i and other.id ~= d.id and math.abs(other.t - d.t) <= Pouches.PAIR then clash = true end
        end
        local best, bestDt
        for j, gain in ipairs(gains) do
            local dt = math.abs(gain.t - d.t)
            if not used[j] and dt <= Pouches.PAIR and (not bestDt or dt < bestDt) then best, bestDt = j, dt end
        end
        if clash then
            Debug("pouches of two kinds left the bags at once: skipped")
        elseif not best then
            Debug("pouch %d left the bags with no gold: not opened (deleted, mailed, traded?)", d.id)
        else
            used[best] = true
            local copper = gains[best].copper
            if ns.Prices.RecordPouch(d.id, copper) then
                Debug("recorded pouch %d with %d copper", d.id, copper)
                recorded = true
            else
                Debug("%d copper is too much for pouch %d: not recorded", copper, d.id)
            end
        end
    end
    if recorded then self:SendMessage(ns.MSG_UPDATED) end
end

-- Chat summary of what pouches pay (/writs pouches).
function Pouches:PrintStats()
    for _, tier in ipairs(ns.TIERS) do
        local st = ns.Prices.PouchStats(tier)
        local line = string.format("%s pouch: about %s", ns.TIER_NAMES[tier], ns.FormatMoney(st.average))
        if st.opened > 0 then
            line = line .. string.format(" (%d opened, %s to %s)", st.opened, ns.FormatMoney(st.min),
                ns.FormatMoney(st.max))
        else
            line = line .. " (Wowhead's average; none opened yet)"
        end
        CH:Print(line)
    end
    local totals = ns.Prices.PouchTotals()
    if totals.opened > 0 then
        CH:Print(string.format("All your characters: %d pouch%s opened, %s in all.", totals.opened,
            totals.opened == 1 and "" or "es", ns.FormatMoney(totals.total)))
    end
    CH:Print(ns.Prices.CashbackOn() and "Price estimates count the pouch as money back." or
        "Price estimates don't count the pouch (turned off in Settings).")
end
