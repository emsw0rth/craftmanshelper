-- Reputation sums for the writs you hold or have on a route, and what they'd do for
-- your standing with the writ faction (Azeroth Commerce Authority / Durotar Supply and
-- Logistics). Amounts include the Legacy perk Diplomat (ns.WritRep, Prices.lua).
local _, ns = ...
local CH = ns.CH
local STATUS = ns.STATUS

local Rep = {}
ns.Rep = Rep

Rep.FACTION_NAMES = { Alliance = "Azeroth Commerce Authority", Horde = "Durotar Supply and Logistics" }

function Rep.FactionName()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return Rep.FACTION_NAMES[faction or ""]
end

-- Reputation for one writ, with Diplomat.
function Rep.OfWrit(writID)
    return ns.WritRep(writID) or 0
end

-- The writs you have and can still turn in today: in your quest log or bags, and their
-- reputation; plus writs only in your bank. Each writ counts once (once a day).
-- Returns { count, rep, ready = { count, rep }, bank = { count, rep } }.
function Rep.Held()
    local out = { count = 0, rep = 0, ready = { count = 0, rep = 0 }, bank = { count = 0, rep = 0 } }
    for writID, s in pairs(CH.Tracker:GetAllStates()) do
        if s.status ~= STATUS.DONE then
            local r = Rep.OfWrit(writID)
            if s.inLog or (s.writsInBags or 0) > 0 then
                out.count, out.rep = out.count + 1, out.rep + r
                if s.status == STATUS.READY then
                    out.ready.count, out.ready.rep = out.ready.count + 1, out.ready.rep + r
                end
            elseif (s.writsTotal or 0) > 0 then
                out.bank.count, out.bank.rep = out.bank.count + 1, out.bank.rep + r
            end
        end
    end
    return out
end

-- A route's writs: { count, rep, left = { count, rep } } where left is what isn't delivered yet.
function Rep.OfRoute(route)
    local out = { count = 0, rep = 0, gold = 0, left = { count = 0, rep = 0, gold = 0 } }
    local Pouch = ns.Prices and ns.Prices.PouchGold or function() return 0 end
    for _, stop in ipairs(route and route.stops or {}) do
        for _, writID in ipairs(stop.writs) do
            local r, g = Rep.OfWrit(writID), Pouch(writID)
            out.count, out.rep, out.gold = out.count + 1, out.rep + r, out.gold + g
            if CH.Tracker:GetState(writID).status ~= STATUS.DONE then
                local left = out.left
                left.count, left.rep, left.gold = left.count + 1, left.rep + r, left.gold + g
            end
        end
    end
    return out
end

-- Your standing with the writ faction, or nil when the game doesn't list it (yet):
-- { name, standing = "Friendly", value, max (within the standing), nextName = "Honored" }.
local factionID
function Rep.Standing()
    local CR = C_Reputation
    if not (CR and CR.GetFactionDataByID) then return nil end
    local name = Rep.FactionName()
    if not name then return nil end
    if not factionID and CR.GetNumFactions and CR.GetFactionDataByIndex then
        for i = 1, CR.GetNumFactions() do
            local d = CR.GetFactionDataByIndex(i)
            if d and d.name == name then factionID = d.factionID; break end
        end
    end
    local d = factionID and CR.GetFactionDataByID(factionID)
    if not (d and d.reaction and d.currentStanding and d.nextReactionThreshold) then return nil end
    local function Label(reaction)
        return _G["FACTION_STANDING_LABEL" .. reaction]
    end
    local low = d.currentReactionThreshold or 0
    if d.nextReactionThreshold <= low then return nil end -- the top standing
    return {
        name = d.name,
        standing = Label(d.reaction),
        value = d.currentStanding - low,
        max = d.nextReactionThreshold - low,
        nextName = Label(d.reaction + 1),
    }
end

-- The cheapest writs worth at least `need` reputation together. entries: { writID, cost, rep }.
-- Every writ of a level gives the same reputation, so the answer is the cheapest few of each
-- level: try every count of the first two levels and work out the third.
-- Returns { writs = { entries }, cost, rep }, or nil when all of them together fall short.
function Rep.Cheapest(entries, need)
    if need <= 0 then return { writs = {}, cost = 0, rep = 0 } end
    local groups, byRep = {}, {}
    for _, e in ipairs(entries) do
        local g = byRep[e.rep]
        if not g then
            g = { rep = e.rep, list = {} }
            byRep[e.rep] = g
            table.insert(groups, g)
        end
        table.insert(g.list, e)
    end
    if #groups > 3 then return nil end -- writs come in three levels
    while #groups < 3 do table.insert(groups, { rep = 1, list = {} }) end
    for _, g in ipairs(groups) do
        table.sort(g.list, function(a, b)
            if a.cost ~= b.cost then return a.cost < b.cost end
            return a.writID < b.writID
        end)
        g.sum = { [0] = 0 } -- g.sum[n]: cost of the n cheapest
        for i, e in ipairs(g.list) do g.sum[i] = g.sum[i - 1] + e.cost end
    end
    local g1, g2, g3 = groups[1], groups[2], groups[3]
    local best
    for a = 0, #g1.list do
        for b = 0, #g2.list do
            local left = need - a * g1.rep - b * g2.rep
            local c = left > 0 and math.ceil(left / g3.rep) or 0
            if c <= #g3.list then
                local cost = g1.sum[a] + g2.sum[b] + g3.sum[c]
                local n = a + b + c
                if not best or cost < best.cost or (cost == best.cost and n < best.n) then
                    best = { cost = cost, n = n, a = a, b = b, c = c }
                end
            end
            if left <= 0 then break end -- more of the second level only costs more
        end
    end
    if not best then return nil end
    local out = { writs = {}, cost = best.cost, rep = 0 }
    for i, g in ipairs(groups) do
        for k = 1, best[({ "a", "b", "c" })[i]] do
            table.insert(out.writs, g.list[k])
            out.rep = out.rep + g.rep
        end
    end
    return out
end

-- How to reach your next standing today, or nil (standing unknown, or at the top):
--   { nextName, toGo = rep to the next standing, have = rep from the writs you have
--     (quest log, bags and bank), need = toGo - have,
--     writs, cost, rep = the cheapest writs to buy for the rest (when need > 0 and it can be done),
--     net = cost minus their coin pouches (picked on that),
--     forSale = how many writs you could buy (when it can't) }
-- Writs you have or have done today aren't bought again: each can be turned in once a day.
function Rep.NextStandingPlan()
    local st = Rep.Standing()
    if not (st and st.nextName) then return nil end
    local held = Rep.Held()
    local out = { nextName = st.nextName, toGo = st.max - st.value, have = held.rep + held.bank.rep }
    out.need = out.toGo - out.have
    if out.need <= 0 then return out end
    local entries = {}
    for writID in pairs(ns.Writs) do
        local s = CH.Tracker:GetState(writID)
        local owned = s.inLog or (s.writsInBags or 0) > 0 or (s.writsTotal or 0) > 0
        if s.status ~= STATUS.DONE and not owned then
            local e = ns.Prices.GetWritBuyEstimate(writID)
            if e and e.cost and e.rep then
                -- Picked on the cost after the coin pouch; one that pays for itself counts as free.
                table.insert(entries, { writID = writID, cost = math.max(0, e.net or e.cost), rep = e.rep, e = e })
            end
        end
    end
    local pick = Rep.Cheapest(entries, out.need)
    if pick then
        out.writs, out.rep, out.cost, out.net = {}, pick.rep, 0, 0
        for _, p in ipairs(pick.writs) do
            table.insert(out.writs, p.e)
            out.cost = out.cost + p.e.cost
            out.net = out.net + (p.e.net or p.e.cost)
        end
    else
        out.forSale = #entries
    end
    return out
end

local function Number(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end
Rep.Number = Number

-- One line on what `amount` reputation would do for your standing (or `st`, a standing
-- saved for another character), or nil.
function Rep.Outlook(amount, st)
    st = st or Rep.Standing()
    if not (st and st.standing and amount and amount > 0) then return nil end
    local after = st.value + amount
    if st.nextName and after >= st.max then
        return string.format("%s %s / %s now: enough to reach %s.", st.standing, Number(st.value), Number(st.max),
            st.nextName)
    end
    return string.format("%s %s / %s now, %s / %s after.", st.standing, Number(st.value), Number(st.max),
        Number(math.min(after, st.max)), Number(st.max))
end
