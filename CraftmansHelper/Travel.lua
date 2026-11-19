-- Travel-time model for the route planner: walking/riding, flight paths, boats,
-- zeppelins and the tram, as a graph searched with Dijkstra.
--
-- Nodes are places ({ map, x, y } plus world coordinates): flight masters the
-- player can use, both ends of every transport link, the crossings between zones
-- (Data/Crossings.lua; a crossing counts as part of both zones), and the points added by
-- the caller (the player's position and the turn-in stops). Edges, in seconds:
--   * ground: between two nodes in the same zone, distance / riding speed. Riding into
--     another zone goes through a crossing. (Zones without crossing data: any two nodes on
--     the same landmass.)
--   * flight: between any two usable flight masters on the same continent
--   * transport: between the two ends of a boat / zeppelin / tram link
--   * fallback: to places you can't ride to and have no known link to ("travel to ..."),
--     so a stop is never unreachable because data is missing.
-- Only C_Map (for world coordinates) touches the WoW API, so this runs in tests.
local _, ns = ...

local Travel = {}
ns.Travel = Travel

local sqrt, huge = math.sqrt, math.huge

Travel.SPEED = { foot = 7, mount60 = 11.2, mount100 = 14 } -- yards per second
Travel.FLIGHT_SPEED = 30.4      -- yards per second, fitted to measured Classic flight times
Travel.FLIGHT_DETOUR = 1.25     -- flight paths curve; flown length vs straight line
Travel.FLIGHT_OVERHEAD = 20     -- seconds: talk to the flight master, take off, land
Travel.FLIGHT_HOP_SECONDS = 8   -- per hop when flown lengths are known (a multi-hop flight is one trip)
Travel.GROUND_DETOUR = 1.3      -- roads and terrain vs straight line, within one zone
Travel.GROUND_DETOUR_ZONES = 1.6 -- between zones: borders are mostly mountains with a few passes
Travel.FALLBACK_SECONDS = 900   -- reaching another landmass with no known link

-- Maps that can't be reached on foot from the rest of their continent.
local ISLANDS = { [1438] = "teldrassil", [1457] = "teldrassil", [2548] = "riverglades", [2521] = "zephras" }

-- Flight master npcID -> the game's taxi node ID, filled in at login (FlightPaths.lua).
-- With it, flights use the measured lengths in Data/FlightLengths.lua.
ns.TaxiNodeOfNpc = ns.TaxiNodeOfNpc or {}

-- Taxi nodes that appear in Data/FlightLengths.lua; for those, only listed routes are flown.
local covered
local function Covered(node)
    if not covered then
        covered = {}
        for key in pairs(ns.FlightLengths or {}) do
            covered[math.floor(key / 10000)] = true
            covered[key % 10000] = true
        end
    end
    return covered[node]
end

-- For tests that swap ns.FlightLengths.
function Travel.ResetFlightData() covered = nil end

-- Whether the character carries an item (in the bags: a key has to be on you).
function Travel.HasItem(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count ~= nil and (count(itemID) or 0) > 0
end

-- The zones a node is in: a crossing is in both (all) of its zones, anything else in its own.
local function ZonesOf(node)
    return node.zones or { [node.zone] = true }
end

-- Whether two nodes are in a zone together (so you ride between them without a crossing).
function Travel.SharesZone(a, b)
    if a.zone == b.zone then return true end
    local za = ZonesOf(a)
    for z in pairs(ZonesOf(b)) do
        if za[z] then return true end
    end
    return false
end

-- Whether you can ride from node u to node v directly. Between zones with crossing data
-- (graph.crossed), only within a zone; otherwise anywhere on the same landmass.
function Travel.CanRide(graph, u, v)
    if u.instance ~= v.instance then return false end
    local crossed = graph.crossed
    if crossed and crossed[u.zone] and crossed[v.zone] then return Travel.SharesZone(u, v) end
    return u.land == v.land
end

-- The zone a step onto a crossing takes you into: the crossing's zone you weren't in yet.
function Travel.CrossInto(from, crossing)
    local was = ZonesOf(from)
    if crossing.into then
        for _, z in ipairs(crossing.into) do
            if not was[z] then return z end
        end
    end
    if not was[crossing.zone] then return crossing.zone end
end

function ns.WorldPos(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
    if not (ok and instance and pos) then return nil end
    local wx, wy = pos:GetXY()
    return instance, wx, wy
end

-- Riding speed from the riding skills the character knows (yards per second).
local RIDING_100 = { 33391, 34090, 34091, 90265 } -- Journeyman and up
local RIDING_60 = { 33388 }                        -- Apprentice
function Travel.GroundSpeed()
    local known = IsPlayerSpell or IsSpellKnown
    if known then
        for _, id in ipairs(RIDING_100) do if known(id) then return Travel.SPEED.mount100 end end
        for _, id in ipairs(RIDING_60) do if known(id) then return Travel.SPEED.mount60 end end
    end
    if UnitLevel and UnitLevel("player") >= 40 then return Travel.SPEED.mount60 end
    return Travel.SPEED.foot
end

local function yards(a, b)
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end

-- Fills in world position and landmass for a { map, x, y } place; false when it has none.
function Travel.Locate(place)
    local instance, wx, wy = ns.WorldPos(place.map, place.x, place.y)
    if not instance then return false end
    place.instance, place.wx, place.wy = instance, wx, wy
    place.land = ISLANDS[place.map] or ("i" .. tostring(instance))
    place.zone = ns.ResolveZone(place.map) or place.map
    return true
end

-- Riding time between two places on the same landmass (seconds).
function Travel.WalkSeconds(graph, a, b)
    local detour = Travel.SharesZone(a, b) and Travel.GROUND_DETOUR or Travel.GROUND_DETOUR_ZONES
    return yards(a, b) * detour / graph.speed
end

-- Flight time between two flight masters on the same continent (seconds), or nil
-- when there's no direct route between them (the measured data lists every direct
-- route, so others are flown as several hops).
function Travel.FlySeconds(a, b)
    local L = ns.FlightLengths
    local aKnown = L and a.taxi and Covered(a.taxi)
    local bKnown = L and b.taxi and Covered(b.taxi)
    if aKnown or bKnown then
        -- A measured flight master only flies its measured routes (never an estimated
        -- hop through one that wasn't matched to a taxi node).
        local flown = aKnown and bKnown and L[a.taxi * 10000 + b.taxi]
        if not flown then return nil end
        return flown / Travel.FLIGHT_SPEED + Travel.FLIGHT_HOP_SECONDS
    end
    return yards(a, b) * Travel.FLIGHT_DETOUR / Travel.FLIGHT_SPEED + Travel.FLIGHT_OVERHEAD
end

-- Straight-line yards between two located places (nil across continents).
function Travel.Yards(a, b)
    if not (a and b and a.instance and a.instance == b.instance) then return nil end
    return yards(a, b)
end

-- Adds a place to the graph; returns the node, or nil when it has no world position.
function Travel.AddNode(graph, node)
    if not Travel.Locate(node) then return nil end
    node.links = node.links or {}
    table.insert(graph.nodes, node)
    node.gi = #graph.nodes -- position in graph.nodes (stops use .index for their route number)
    return node
end

-- Whether a player of `faction` ("A" / "H") may use something limited to `required` ("A", "H",
-- "AH"; nil = everyone). With the faction unknown, only what's open to everyone counts, so a
-- route never puts you on the other faction's tram, boat or zeppelin.
local function FactionOK(faction, required)
    if not required or required == "AH" then return true end
    return faction ~= nil and required:find(faction, 1, true) ~= nil
end
Travel.FactionOK = FactionOK

-- opts: faction = "A" | "H" | nil, speed = yards/second,
--       knowsFlight = function(npcID, node) -> bool (nil: every flight master counts),
--       hasItem = function(itemID) -> bool for keys to gates (nil: the character's bags)
function Travel.NewGraph(opts)
    opts = opts or {}
    local graph = { nodes = {}, speed = opts.speed or Travel.SPEED.foot }

    -- Crossings between zones: the ones open to you (your faction's capitals, keys you carry).
    if ns.Crossings then
        local hasItem = opts.hasItem or Travel.HasItem
        graph.crossed = {}
        for zone, list in pairs(ns.Crossings) do
            graph.crossed[zone] = true
            for _, c in ipairs(list) do
                if FactionOK(opts.faction, c.faction) and not (c.item and not hasItem(c.item)) then
                    local into = type(c.to) == "table" and c.to or { c.to }
                    local node = Travel.AddNode(graph, { kind = "crossing", map = zone, x = c.x, y = c.y,
                                                         note = c.note, into = into })
                    if node then
                        node.zones = { [node.zone] = true }
                        for _, z in ipairs(into) do node.zones[z] = true end
                    end
                end
            end
        end
    end

    for npcID, fm in pairs(ns.FlightMasters or {}) do
        if FactionOK(opts.faction, fm.faction) then
            local node = { kind = "flight", id = npcID, name = fm.name, map = fm.map, x = fm.x, y = fm.y,
                           taxi = ns.TaxiNodeOfNpc[npcID] }
            if Travel.AddNode(graph, node) and opts.knowsFlight and not opts.knowsFlight(npcID, node) then
                node.kind = "flight-unknown" -- still a place, but you can't fly from it
            end
        end
    end

    -- Docks shared by several links are one node.
    local docks = {}
    local function Dock(p)
        local key = string.format("%d:%.1f:%.1f", p.map, p.x, p.y)
        if docks[key] == nil then
            docks[key] = Travel.AddNode(graph, { kind = "dock", map = p.map, x = p.x, y = p.y }) or false
        end
        return docks[key] or nil
    end
    for _, t in ipairs(ns.Transports or {}) do
        if FactionOK(opts.faction, t.faction) then
            local seconds = (ns.TRANSPORT_SECONDS or {})[t.kind] or 240
            -- { from, to } is one way; { a, b } goes both ways.
            local from, to = Dock(t.from or t.a), Dock(t.to or t.b)
            if from and to and from ~= to then
                table.insert(from.links, { to = to, seconds = seconds, kind = t.kind })
                if t.a then table.insert(to.links, { to = from, seconds = seconds, kind = t.kind }) end
            end
        end
    end
    return graph
end

-- Calls visit(v, seconds, kind) for every edge out of node u.
local function Edges(graph, u, visit)
    for _, v in ipairs(graph.nodes) do
        if v ~= u then
            if Travel.CanRide(graph, u, v) then
                visit(v, Travel.WalkSeconds(graph, u, v), v.kind == "crossing" and "cross" or "walk")
            else
                visit(v, Travel.FALLBACK_SECONDS, "travel")
            end
            if u.kind == "flight" and v.kind == "flight" and v.instance == u.instance then
                local s = Travel.FlySeconds(u, v)
                if s then visit(v, s, "fly") end
            end
        end
    end
    for _, link in ipairs(u.links) do visit(link.to, link.seconds, link.kind) end
end

-- Shortest travel times from `source` to every node: { seconds = {[index] = s}, via = {[index] = edge} }.
function Travel.Search(graph, source)
    local n = #graph.nodes
    local seconds, via, done = {}, {}, {}
    for i = 1, n do seconds[i] = huge end
    seconds[source.gi] = 0
    for _ = 1, n do
        local u, best = nil, huge
        for i = 1, n do
            if not done[i] and seconds[i] < best then u, best = i, seconds[i] end
        end
        if not u then break end
        done[u] = true
        local from = graph.nodes[u]
        Edges(graph, from, function(v, s, kind)
            local total = best + s
            if total < seconds[v.gi] - 1e-9 then
                seconds[v.gi] = total
                via[v.gi] = { from = from, kind = kind, seconds = s }
            end
        end)
    end
    return { seconds = seconds, via = via, source = source }
end

-- Steps from the search's source to `target`: { { kind, from, to, seconds }, ... }.
function Travel.Steps(search, target)
    local steps, node = {}, target
    while node ~= search.source do
        local edge = search.via[node.gi]
        if not edge then return nil end -- unreachable
        local nextStep = steps[1]
        if edge.kind == "fly" and nextStep and nextStep.kind == "fly" then
            -- Hops of one flight: you pick the final stop at the flight master.
            nextStep.from = edge.from
            nextStep.seconds = nextStep.seconds + edge.seconds
        else
            table.insert(steps, 1, { kind = edge.kind, from = edge.from, to = node, seconds = edge.seconds })
        end
        node = edge.from
    end
    return steps
end

local function PlaceName(node)
    local _, zone = ns.ResolveZone(node.map)
    return zone or "?"
end

-- One line of directions for a step, or nil for plain walking.
function Travel.Describe(step)
    if step.kind == "fly" then
        return string.format("Fly from %s (%s) to %s (%s)", step.from.name or "?", PlaceName(step.from),
            step.to.name or "?", PlaceName(step.to))
    elseif step.kind == "travel" then
        return "Travel to " .. PlaceName(step.to)
    elseif step.kind == "cross" then
        local into = Travel.CrossInto(step.from, step.to)
        local _, intoName = ns.ResolveZone(into or step.to.map)
        local where = string.format("%s %.1f, %.1f", PlaceName(step.to), step.to.x, step.to.y)
        if not into then return string.format("Ride to %s", where) end
        return string.format("Ride into %s%s (%s)", intoName or "?", step.to.note and (", " .. step.to.note) or "", where)
    elseif step.kind == "hearth" then
        return string.format("Use your Hearthstone (%s)", step.to.name or PlaceName(step.to))
    elseif step.kind ~= "walk" then
        local what = (ns.TRANSPORT_NAMES or {})[step.kind] or step.kind
        return string.format("Take the %s from %s to %s", what, PlaceName(step.from), PlaceName(step.to))
    end
end
