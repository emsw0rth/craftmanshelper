-- Travel-time model for the route planner: walking/riding, flight paths, boats,
-- zeppelins and the tram, as a graph searched with Dijkstra.
--
-- Nodes are places ({ map, x, y } plus world coordinates): flight masters the
-- player can use, both ends of every transport link, and the points added by the
-- caller (the player's position and the turn-in stops). Edges, in seconds:
--   * ground: between any two nodes on the same landmass, distance / riding speed
--   * flight: between any two usable flight masters on the same continent
--   * transport: between the two ends of a boat / zeppelin / tram link
--   * fallback: between landmasses with no known link ("travel to ..."), so a
--     stop is never unreachable just because a dock is missing from the data.
-- Only C_Map (for world coordinates) touches the WoW API, so this runs in tests.
local _, ns = ...

local Travel = {}
ns.Travel = Travel

local sqrt, huge = math.sqrt, math.huge

Travel.SPEED = { foot = 7, mount60 = 11.2, mount100 = 14 } -- yards per second
Travel.FLIGHT_SPEED = 30.4      -- yards per second, fitted to measured Classic flight times
Travel.FLIGHT_DETOUR = 1.25     -- flight paths curve; flown length vs straight line
Travel.FLIGHT_OVERHEAD = 20     -- seconds: talk to the flight master, take off, land
Travel.GROUND_DETOUR = 1.3      -- roads and terrain vs straight line, within one zone
Travel.GROUND_DETOUR_ZONES = 1.6 -- between zones: borders are mostly mountains with a few passes
Travel.FALLBACK_SECONDS = 900   -- reaching another landmass with no known link

-- Maps that can't be reached on foot from the rest of their continent.
local ISLANDS = { [1438] = "teldrassil", [1457] = "teldrassil", [2548] = "riverglades" }

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
    local detour = (a.zone == b.zone) and Travel.GROUND_DETOUR or Travel.GROUND_DETOUR_ZONES
    return yards(a, b) * detour / graph.speed
end

-- Flight time between two flight masters on the same continent (seconds).
function Travel.FlySeconds(a, b)
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

local function FactionOK(faction, required)
    return not (faction and required) or required:find(faction, 1, true) ~= nil
end

-- opts: faction = "A" | "H" | nil, speed = yards/second,
--       knowsFlight = function(npcID, node) -> bool (nil: every flight master counts)
function Travel.NewGraph(opts)
    opts = opts or {}
    local graph = { nodes = {}, speed = opts.speed or Travel.SPEED.foot }

    for npcID, fm in pairs(ns.FlightMasters or {}) do
        if FactionOK(opts.faction, fm.faction) then
            local node = { kind = "flight", id = npcID, name = fm.name, map = fm.map, x = fm.x, y = fm.y }
            if Travel.AddNode(graph, node) and opts.knowsFlight and not opts.knowsFlight(npcID, node) then
                node.kind = "flight-unknown" -- still a place, but you can't fly from it
            end
        end
    end

    for _, t in ipairs(ns.Transports or {}) do
        if FactionOK(opts.faction, t.faction) then
            local a = Travel.AddNode(graph, { kind = "dock", map = t.a.map, x = t.a.x, y = t.a.y })
            local b = Travel.AddNode(graph, { kind = "dock", map = t.b.map, x = t.b.x, y = t.b.y })
            if a and b then
                local seconds = (ns.TRANSPORT_SECONDS or {})[t.kind] or 240
                table.insert(a.links, { to = b, seconds = seconds, kind = t.kind })
                table.insert(b.links, { to = a, seconds = seconds, kind = t.kind })
            end
        end
    end
    return graph
end

-- Calls visit(v, seconds, kind) for every edge out of node u.
local function Edges(graph, u, visit)
    for _, v in ipairs(graph.nodes) do
        if v ~= u then
            if v.land == u.land then
                visit(v, Travel.WalkSeconds(graph, u, v), "walk")
            else
                visit(v, Travel.FALLBACK_SECONDS, "travel")
            end
            if u.kind == "flight" and v.kind == "flight" and v.instance == u.instance then
                visit(v, Travel.FlySeconds(u, v), "fly")
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
        table.insert(steps, 1, { kind = edge.kind, from = edge.from, to = node, seconds = edge.seconds })
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
    elseif step.kind == "hearth" then
        return string.format("Use your Hearthstone (%s)", step.to.name or PlaceName(step.to))
    elseif step.kind ~= "walk" then
        local what = (ns.TRANSPORT_NAMES or {})[step.kind] or step.kind
        return string.format("Take the %s from %s to %s", what, PlaceName(step.from), PlaceName(step.to))
    end
end
