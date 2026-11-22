-- Learns how much gold the Coin Pouches from writ turn-ins hold. Opening one opens a loot
-- window with its gold; when that window came from an item, a pouch left the bags and money
-- came in, the amount is recorded for that pouch (Prices.RecordPouch, account-wide).
local _, ns = ...
local CH = ns.CH

local Pouches = CH:NewModule("Pouches", "AceEvent-3.0", "AceTimer-3.0")
CH.Pouches = Pouches

-- Seconds after the loot window closes for the last gold and bag change to come in.
local SETTLE = 2
-- A pouch leaving the bags this many seconds before the loot window opened still counts.
local EARLY = 2

local function Count(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and f(id) or 0
end

local function CountAll()
    local t = {}
    for _, id in pairs(ns.POUCHES) do t[id] = Count(id) end
    return t
end

-- Whether the open loot window is an item's contents (not a creature or chest). When the game
-- doesn't say where the loot comes from, it counts: a pouch still has to leave the bags.
local function FromItem()
    if not (GetNumLootItems and GetLootSourceInfo) then return true end
    local any = false
    for slot = 1, GetNumLootItems() do
        local guid = GetLootSourceInfo(slot)
        if type(guid) == "string" then
            any = true
            if guid:find("^Item%-") then return true end
        end
    end
    return not any
end

function Pouches:OnEnable()
    self.counts = CountAll()
    self.money = GetMoney()
    self.drops = {} -- { id, t } pouches that left the bags lately
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("PLAYER_MONEY")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("MERCHANT_SHOW", function() self.merchant = true end)
    self:RegisterEvent("MERCHANT_CLOSED", function() self.merchant = false end)
end

function Pouches:LOOT_OPENED()
    -- Opening pouches one after another: settle the last one now, with only what left the
    -- bags before this window (a pouch that goes as its window opens is this one).
    if self.finishTimer then
        self:CancelTimer(self.finishTimer)
        self:Finish(GetTime())
    end
    self.session = FromItem() and { opened = GetTime(), gain = 0 } or nil
end

function Pouches:LOOT_CLOSED()
    if self.session and not self.finishTimer then
        self.finishTimer = self:ScheduleTimer("Finish", SETTLE)
    end
end

function Pouches:PLAYER_MONEY()
    local now = GetMoney()
    local delta = now - (self.money or now)
    self.money = now
    -- Selling or buying at a vendor moves money too (and a pouch can be sold).
    if self.session and delta > 0 and not self.merchant then
        self.session.gain = self.session.gain + delta
    end
end

function Pouches:BAG_UPDATE_DELAYED()
    local counts, now = CountAll(), GetTime()
    for id, n in pairs(counts) do
        for _ = 1, (self.counts[id] or 0) - n do table.insert(self.drops, { id = id, t = now }) end
    end
    self.counts = counts
    -- Forget drops no loot window could still claim.
    for i = #self.drops, 1, -1 do
        if now - self.drops[i].t > 30 then table.remove(self.drops, i) end
    end
end

-- Records the closed loot window's pouch. before: only pouches that left the bags earlier count.
function Pouches:Finish(before)
    self.finishTimer = nil
    local session = self.session
    self.session = nil
    if not session or session.gain <= 0 then return end
    local claimed
    for i = #self.drops, 1, -1 do
        local t = self.drops[i].t
        if t >= session.opened - EARLY and not (before and t >= before) then
            if claimed then return end -- two pouches at once: can't tell them apart
            claimed = i
        end
    end
    if not claimed then return end
    local id = table.remove(self.drops, claimed).id
    if ns.Prices.RecordPouch(id, session.gain) then
        self:SendMessage(ns.MSG_UPDATED)
    end
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
