-- Reputation sums for the writs you hold or have on a route, and what they'd do for
-- your standing with the writ faction (Azeroth Commerce Authority / Durotar Supply and
-- Logistics). Amounts are the writs' base reputation, before any bonuses.
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

-- Base reputation of one writ.
function Rep.OfWrit(writID)
    local w = ns.Writs[writID]
    return w and ns.TIER_REP[w.tier] or 0
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
    local out = { count = 0, rep = 0, left = { count = 0, rep = 0 } }
    for _, stop in ipairs(route and route.stops or {}) do
        for _, writID in ipairs(stop.writs) do
            local r = Rep.OfWrit(writID)
            out.count, out.rep = out.count + 1, out.rep + r
            if CH.Tracker:GetState(writID).status ~= STATUS.DONE then
                out.left.count, out.left.rep = out.left.count + 1, out.left.rep + r
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

local function Number(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end
Rep.Number = Number

-- One line on what `amount` reputation would do for your standing, or nil.
function Rep.Outlook(amount)
    local st = Rep.Standing()
    if not (st and st.standing and amount and amount > 0) then return nil end
    local after = st.value + amount
    if st.nextName and after >= st.max then
        return string.format("%s %s / %s now: enough to reach %s.", st.standing, Number(st.value), Number(st.max),
            st.nextName)
    end
    return string.format("%s %s / %s now, %s / %s after.", st.standing, Number(st.value), Number(st.max),
        Number(math.min(after, st.max)), Number(st.max))
end
