-- Learns which flight paths this character knows, for the route planner.
--
-- The game only says which flight points you know while a flight map is open
-- (C_TaxiMap.GetAllTaxiNodes). Each node there is matched to the nearest flight
-- master in Data/FlightMasters.lua and remembered per character.
local _, ns = ...
local CH = ns.CH

local FlightPaths = CH:NewModule("FlightPaths", "AceEvent-3.0")
CH.FlightPaths = FlightPaths

local MATCH_YARDS = 250 -- a taxi node and its flight master stand close together

-- Enum.FlightPathState: Current = 0, Reachable = 1, Unreachable = 2 (unknown to you).
local function IsKnown(state)
    local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2
    return state ~= unreachable
end

-- Nearest flight master to a world position on the same continent, within MATCH_YARDS.
function FlightPaths.Match(instance, wx, wy)
    local best, bestID = MATCH_YARDS, nil
    for npcID, fm in pairs(ns.FlightMasters) do
        local inst, fx, fy = ns.WorldPos(fm.map, fm.x, fm.y)
        if inst == instance then
            local d = math.sqrt((fx - wx) ^ 2 + (fy - wy) ^ 2)
            if d < best then best, bestID = d, npcID end
        end
    end
    return bestID
end

function FlightPaths:OnTaxiMapOpened()
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(mapID)
    if type(nodes) ~= "table" then return end

    local known = CH.db.char.flightPaths
    local added = 0
    for _, node in ipairs(nodes) do
        local pos = node.position
        if pos and IsKnown(node.state) then
            local x, y = pos.x, pos.y
            if pos.GetXY then x, y = pos:GetXY() end
            local instance, wx, wy = ns.WorldPos(mapID, x * 100, y * 100)
            local npcID = instance and FlightPaths.Match(instance, wx, wy)
            if npcID and not known[npcID] then
                known[npcID] = true
                added = added + 1
            end
        end
    end
    -- The flight master you're talking to is known for sure.
    local guid = UnitGUID and UnitGUID("npc")
    local npcID = guid and tonumber(select(6, strsplit("-", guid)) or "")
    if npcID and ns.FlightMasters[npcID] and not known[npcID] then
        known[npcID] = true
        added = added + 1
    end
    if added > 0 then
        CH:Print(string.format("Learned %d flight path%s for route planning.", added, added == 1 and "" or "s"))
    end
end

function FlightPaths:Count()
    local n = 0
    for _ in pairs(CH.db.char.flightPaths) do n = n + 1 end
    return n
end

function FlightPaths:OnEnable()
    self:RegisterEvent("TAXIMAP_OPENED", "OnTaxiMapOpened")
end
