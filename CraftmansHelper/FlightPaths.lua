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

-- The place in a taxi node's name: "Gadgetzan, Tanaris" -> "Gadgetzan" (nil when it has none).
function FlightPaths.PlaceOf(name)
    if type(name) ~= "string" then return nil end
    local cut = name:find(",", 1, true) or name:find("\239\188\140", 1, true) -- the second: a full-width comma
    local place = strtrim(cut and name:sub(1, cut - 1) or name)
    return place ~= "" and place or nil
end

-- Names every flight master near a taxi node after it (the nearest node's name wins). Kept apart
-- from Match: both factions' flight masters in a town are named, whichever the node belongs to.
local nameYards = {}
local function NameFlightMasters(name, instance, wx, wy)
    local place = FlightPaths.PlaceOf(name)
    if not place then return end
    for npcID, fm in pairs(ns.FlightMasters) do
        local inst, fx, fy = ns.WorldPos(fm.map, fm.x, fm.y)
        if inst == instance then
            local d = math.sqrt((fx - wx) ^ 2 + (fy - wy) ^ 2)
            if d < (nameYards[npcID] or MATCH_YARDS) then
                nameYards[npcID] = d
                ns.FlightPlaceOfNpc[npcID] = place
            end
        end
    end
end

-- Taxi node ID and place name of every flight master, so routes can use the measured flight
-- lengths (Data/FlightLengths.lua) and say where you fly. The game lists taxi nodes per map,
-- with positions and names (in the game's language), without a flight map open.
function FlightPaths:MapTaxiNodes()
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return 0 end
    local maps, seen = { 1414, 1415 }, { [1414] = true, [1415] = true }
    for _, fm in pairs(ns.FlightMasters) do
        if not seen[fm.map] then seen[fm.map] = true; table.insert(maps, fm.map) end
    end
    local n = 0
    for _, mapID in ipairs(maps) do
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        for _, node in ipairs(ok and nodes or {}) do
            local pos = node.position
            if pos and node.nodeID then
                local x, y = pos.x, pos.y
                if pos.GetXY then x, y = pos:GetXY() end
                local instance, wx, wy = ns.WorldPos(mapID, x * 100, y * 100)
                local npcID = instance and FlightPaths.Match(instance, wx, wy)
                if instance then NameFlightMasters(node.name, instance, wx, wy) end
                if npcID and not ns.TaxiNodeOfNpc[npcID] then
                    ns.TaxiNodeOfNpc[npcID] = node.nodeID
                    n = n + 1
                end
            end
        end
    end
    return n
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
            if instance then NameFlightMasters(node.name, instance, wx, wy) end
            if npcID and node.nodeID then ns.TaxiNodeOfNpc[npcID] = node.nodeID end
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

-- Flight paths you know on a continent (its map ID, as ns.ResolveZone gives it).
function FlightPaths:CountOn(contID)
    local n = 0
    for npcID in pairs(CH.db.char.flightPaths) do
        local fm = ns.FlightMasters[npcID]
        if fm and select(3, ns.ResolveZone(fm.map)) == contID then n = n + 1 end
    end
    return n
end

function FlightPaths:OnEnable()
    self:RegisterEvent("TAXIMAP_OPENED", "OnTaxiMapOpened")
    -- Map data is ready once you're in the world.
    if C_Timer then C_Timer.After(2, function() self:MapTaxiNodes() end) end
end
