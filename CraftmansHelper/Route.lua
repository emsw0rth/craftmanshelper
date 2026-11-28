-- Delivery route: every writ you can hand in right now, grouped into stops
-- (one per turn-in spot) and ordered by ns.SolvePath on travel time (Travel.lua):
-- flight paths you know, boats and zeppelins included, across both continents.
local _, ns = ...
local CH = ns.CH
local STATUS = ns.STATUS

local Route = CH:NewModule("Route", "AceEvent-3.0", "AceTimer-3.0")
CH.Route = Route

ns.MSG_ROUTE = "CRAFTMANSHELPER_ROUTE"

local GROUP = "route"
local VIA_GROUP = "route-via"  -- the one waypoint for the next flight master / dock on the way
local ARRIVE_YARDS = 40        -- this close to a flight master or dock counts as "got there"
local TICK_SECONDS = 1
local RESTORE_DELAY = 5        -- seconds after login / reload before re-planning a saved route
local HEARTH_SECONDS = 30      -- 10 s cast plus the trip / loading screen
local PICKUP_MAX_SECONDS = 60  -- most extra riding for a flight path you don't know yet
local PICKUP_SKIP = { [11798] = true, [11800] = true } -- Moonglade's druid-only flight masters (not for druids)
local HEARTH_MIN_SAVING = 60   -- only hearth when it saves at least a minute
local HEARTH_ARRIVE_YARDS = 80 -- within this of the recorded inn = hearthed

-- Whether a route is active, remembered per character so it survives a /reload or relog.
local function SetSaved(active)
    if CH.db and CH.db.char then CH.db.char.routeActive = active or nil end
end

-- A writ belongs on the route when it can be delivered right now, or as soon
-- as it's started (writ in bags + item in hand).
local function IsDeliverable(s)
    if s.status == STATUS.READY then return true end
    return s.status == STATUS.INBAGS and s.have >= s.need
end

local function PlayerFactionLetter()
    local f = UnitFactionGroup("player")
    return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

local function PlayerPosition()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    local _, _, contID = ns.ResolveZone(map)
    return { kind = "start", name = "You", map = map, x = x * 100, y = y * 100, contID = contID }
end

-- Flight paths this character knows, recorded when a flight map is opened
-- (FlightPaths.lua). Continents never scanned count as "none known".
local function KnowsFlight(npcID)
    local fp = CH.db and CH.db.char and CH.db.char.flightPaths
    return fp ~= nil and fp[npcID] == true
end

-- The non-walking parts of the way to a stop, in order: crossings into another zone, flights,
-- boats, zeppelins, the tram and "travel to ..." fallbacks. `board` is where the arrow points
-- first (the crossing, flight master or dock); fallbacks have none.
local function BuildVia(steps)
    local via = {}
    for _, step in ipairs(steps or {}) do
        local text = ns.Travel.Describe(step)
        if text then
            -- Fallbacks, the Hearthstone and teleports have no place to walk to first.
            local board = (step.kind ~= "travel" and step.kind ~= "hearth" and step.kind ~= "teleport")
                and step.from or nil
            local into
            if step.kind == "pickup" then
                board = step.to
            elseif step.kind == "cross" then
                board, into = step.to, ns.Travel.CrossInto(step.from, step.to)
            end
            table.insert(via, { kind = step.kind, text = text, from = step.from, to = step.to, board = board,
                                into = into })
        end
    end
    return via
end

-- Flight paths to pick up: adds a "pickup" step to the step lists for every flight master you
-- don't know yet that's at most PICKUP_MAX_SECONDS of extra riding from a stretch you ride
-- anyway. Each is added once, where it's the shortest detour. Only on continents where you've
-- opened a flight map: elsewhere the addon can't tell what you know.
-- taken: { [npcID] = true } to leave out. Returns the extra seconds per list.
local function AddPickups(lists, graph, taken)
    local extra = {}
    for i = 1, #lists do extra[i] = 0 end
    if CH.db.profile and CH.db.profile.pickups == false then return extra end

    local druid = UnitClass and select(2, UnitClass("player")) == "DRUID"
    local learned = {} -- [continent] = any flight path known there
    local function Learned(contID)
        if learned[contID] == nil then learned[contID] = CH.FlightPaths:CountOn(contID) > 0 end
        return learned[contID]
    end
    local todo = {}
    for _, node in ipairs(graph.nodes) do
        if node.kind == "flight-unknown" and not taken[node.id] and not (PICKUP_SKIP[node.id] and not druid)
            and Learned(select(3, ns.ResolveZone(node.map))) then
            table.insert(todo, node)
        end
    end
    -- The shortest detour to a flight master over every stretch you ride.
    local T = ns.Travel
    local function Best(node)
        local best
        for l, steps in ipairs(lists) do
            for k, step in ipairs(steps) do
                if (step.kind == "walk" or step.kind == "cross") and T.CanRide(graph, step.from, node)
                    and T.CanRide(graph, node, step.to) then
                    local there = T.WalkSeconds(graph, step.from, node)
                    local on = T.WalkSeconds(graph, node, step.to)
                    local detour = there + on - T.WalkSeconds(graph, step.from, step.to)
                    if detour <= PICKUP_MAX_SECONDS and (not best or detour < best.detour - 1e-9) then
                        best = { detour = detour, list = l, index = k, there = there, on = on }
                    end
                end
            end
        end
        return best
    end
    -- One at a time, nearest first: each one splits a stretch, which the next are measured on.
    while #todo > 0 do
        local pick, at
        for i = #todo, 1, -1 do
            local b = Best(todo[i])
            if not b then
                table.remove(todo, i)
                if at then at = at - 1 end -- it was further down the list
            elseif not pick or b.detour < pick.detour then
                pick, at = b, i
            end
        end
        if not pick then break end
        local node = table.remove(todo, at)
        local steps = lists[pick.list]
        local step = steps[pick.index]
        steps[pick.index] = { kind = step.kind, from = node, to = step.to, seconds = pick.on }
        table.insert(steps, pick.index, { kind = "pickup", from = step.from, to = node, seconds = pick.there })
        extra[pick.list] = extra[pick.list] + pick.detour
    end
    return extra
end

-- Waypoint title: the NPC and the writs to deliver there, e.g.
-- "Kixxle: Draught of Water Breathing, Goblin Rocket Fuel" (at most 3 names, then "+N more").
local MAX_TITLE_WRITS = 3

local function StopTitle(stop)
    local names = {}
    for _, writID in ipairs(stop.writs) do
        local w = ns.Writs[writID]
        local name = w and ((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(w.item)) or w.name)
        if name then table.insert(names, name) end
    end
    table.sort(names)
    local shown = {}
    for i = 1, math.min(#names, MAX_TITLE_WRITS) do shown[i] = names[i] end
    local text = table.concat(shown, ", ")
    if #names > MAX_TITLE_WRITS then
        text = string.format("%s +%d more", text, #names - MAX_TITLE_WRITS)
    end
    local who = stop.name or "Turn-in"
    return text ~= "" and (who .. ": " .. text) or who
end
ns._StopTitle = StopTitle -- for tests

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------

-- noMage: leave the mage teleports out (the route needed more Runes of Teleportation than you carry).
function Route:Build(noMage)
    local faction = PlayerFactionLetter()
    local stopsByKey, unroutable, excluded, elsewhere = {}, {}, {}, {}
    -- The continent chosen for routes; nil means all of them.
    local only = CH.db.char.routeContinent

    for _, s in pairs(CH.Tracker:GetAllStates()) do
        if IsDeliverable(s) then
            local t = s.turnIn
            if t and t.faction and faction and not t.faction:find(faction, 1, true) then
                table.insert(excluded, s)
            elseif not (t and t.map and t.x and t.y) then
                table.insert(unroutable, s)
            elseif only and s.continentID ~= only then
                table.insert(elsewhere, s)
            else
                -- Same spot (to ~1% of the map) = same stop, whatever the data source.
                local key = string.format("%d:%d:%d", t.map, math.floor(t.x + 0.5), math.floor(t.y + 0.5))
                local stop = stopsByKey[key]
                if not stop then
                    stop = { kind = "stop", key = key, name = t.name, map = t.map, x = t.x, y = t.y,
                             zoneName = s.zoneName, contID = s.continentID, writs = {} }
                    stopsByKey[key] = stop
                end
                table.insert(stop.writs, s.id)
            end
        end
    end

    -- Travel graph: flight paths you know, boats, zeppelins, plus you and every stop.
    -- Teleports you can use from anywhere (mage teleports, Teleport: Moonglade).
    local teleports, runes
    if CH.Teleports then teleports, runes = CH.Teleports:Anywhere(not noMage) end
    local graph = ns.Travel.NewGraph({ faction = faction, speed = ns.Travel.GroundSpeed(), knowsFlight = KnowsFlight,
                                       teleports = teleports })
    local start = PlayerPosition()
    if start then start = ns.Travel.AddNode(graph, start) end

    local points = {}
    for _, stop in pairs(stopsByKey) do
        if ns.Travel.AddNode(graph, stop) then
            table.insert(points, stop)
        else
            for _, id in ipairs(stop.writs) do table.insert(unroutable, CH.Tracker:GetState(id)) end
        end
    end
    -- Stable input order (pairs() isn't), so equal-cost routes come out the same every time.
    table.sort(points, function(a, b) return a.key < b.key end)

    -- Travel times between every pair of route points.
    local searches = {}
    if start then searches[start] = ns.Travel.Search(graph, start) end
    for _, p in ipairs(points) do searches[p] = ns.Travel.Search(graph, p) end
    local function cost(a, b) return searches[a].seconds[b.gi] end

    local order, total = ns.SolvePath(points, start, cost)
    local seq = {}
    for k, i in ipairs(order) do seq[k] = points[i] end

    -- Once per route: the Hearthstone and the engineering transporters (long cooldowns). Try
    -- each before each stop in turn and re-plan the rest from where it lands. Keep the quickest,
    -- if it saves at least HEARTH_MIN_SAVING.
    local once = {}
    if #seq > 0 then
        local hearth = CH.Hearth and CH.Hearth:GetOption()
        if hearth then
            table.insert(once, { kind = "hearth", readyIn = hearth.readyIn,
                                 node = { kind = "inn", name = hearth.name, map = hearth.map, x = hearth.x, y = hearth.y } })
        end
        for _, t in ipairs(CH.Teleports and CH.Teleports:Once() or {}) do
            table.insert(once, { kind = "teleport", readyIn = t.readyIn,
                                 node = { kind = "arrival", name = t.name, map = t.map, x = t.x, y = t.y, teleport = t } })
        end
    end
    local used, usedAt
    local best, bestSeq = total - HEARTH_MIN_SAVING, nil
    for _, o in ipairs(once) do
        local node = ns.Travel.AddNode(graph, o.node)
        if node then
            searches[node] = ns.Travel.Search(graph, node)
            local elapsed, prev = 0, start
            for k = 1, #seq do
                -- Usable from where you are (or a stop), once the cooldown is over by then.
                if prev and o.readyIn <= elapsed then
                    local rest = {}
                    for j = k, #seq do rest[#rest + 1] = seq[j] end
                    local restOrder, restCost = ns.SolvePath(rest, node, cost)
                    local candidate = elapsed + HEARTH_SECONDS + restCost
                    if candidate < best then
                        best, used, usedAt = candidate, o, k
                        bestSeq = {}
                        for j = 1, k - 1 do bestSeq[j] = seq[j] end
                        for _, r in ipairs(restOrder) do bestSeq[#bestSeq + 1] = rest[r] end
                    end
                end
                elapsed = elapsed + (prev and cost(prev, seq[k]) or 0)
                prev = seq[k]
            end
        end
    end
    if bestSeq then seq, total = bestSeq, best end
    local hearthAt = used and used.kind == "hearth" and usedAt or nil
    local teleportAt = used and used.kind == "teleport" and usedAt or nil

    -- Directions to each stop from the one before it (or from you), and legs per continent.
    local legs, flat, prev = {}, {}, start
    for k, stop in ipairs(seq) do
        if k == usedAt then
            local node = used.node
            stop.steps = { { kind = used.kind, from = prev, to = node, seconds = HEARTH_SECONDS } }
            for _, step in ipairs(ns.Travel.Steps(searches[node], stop) or {}) do table.insert(stop.steps, step) end
            stop.seconds = HEARTH_SECONDS + cost(node, stop)
        elseif prev then
            stop.steps = ns.Travel.Steps(searches[prev], stop) or {}
            stop.seconds = cost(prev, stop)
        else
            stop.steps, stop.seconds = {}, 0
        end
        prev = stop
    end

    -- Flight paths to pick up on the way.
    local lists = {}
    for k, stop in ipairs(seq) do lists[k] = stop.steps end
    local extra = AddPickups(lists, graph, {})

    for k, stop in ipairs(seq) do
        stop.seconds, total = stop.seconds + extra[k], total + extra[k]
        stop.via = BuildVia(stop.steps)
        local leg = legs[#legs]
        if not leg or leg.contID ~= stop.contID then
            leg = { contID = stop.contID, stops = {}, length = 0, fromPlayer = (#legs == 0 and start ~= nil) }
            table.insert(legs, leg)
        end
        table.insert(leg.stops, stop)
        leg.length = leg.length + stop.seconds
        table.insert(flat, stop)
    end

    -- Each mage teleport takes a Rune of Teleportation: with too few for this route, plan without them.
    if not noMage and runes then
        local casts = 0
        for _, stop in ipairs(flat) do
            for _, step in ipairs(stop.steps or {}) do
                if step.kind == "teleport" and step.to.teleport and step.to.teleport.rune then casts = casts + 1 end
            end
        end
        if casts > runes then return self:Build(true) end
    end

    return { legs = legs, stops = flat, seconds = total, unroutable = unroutable, excluded = excluded,
             elsewhere = elsewhere, continent = only, fromPlayer = start ~= nil, graph = graph, hearthAt = hearthAt,
             teleportAt = teleportAt }
end

---------------------------------------------------------------------------
-- Following the route
---------------------------------------------------------------------------

local function StopPending(stop)
    for _, id in ipairs(stop.writs) do
        local s = CH.Tracker:GetState(id)
        if s.status ~= STATUS.DONE and s.status ~= STATUS.AVAILABLE then return true end
    end
    return false
end

-- restoring: re-planning a route that was active before a /reload or relog.
function Route:Plan(restoring)
    self:Clear(true)
    local route = self:Build()
    if #route.stops == 0 then
        self.route = route -- keep unroutable/excluded so the UI can explain
        if not restoring then
            CH:Print(route.continent and string.format("Nothing to deliver in %s right now.",
                ns.ContinentName(route.continent)) or "Nothing to deliver right now.")
        end
        self:SendMessage(ns.MSG_ROUTE)
        return route
    end

    for i, stop in ipairs(route.stops) do
        stop.index = i
        stop.handle = CH.Nav:Add(GROUP, { map = stop.map, x = stop.x, y = stop.y, title = StopTitle(stop) }, false)
    end
    self.route = route
    self:SetCurrent(1, true)
    if self.ScheduleRepeatingTimer then
        self.ticker = self:ScheduleRepeatingTimer("Tick", TICK_SECONDS)
    end

    local writs = 0
    for _, stop in ipairs(route.stops) do writs = writs + #stop.writs end
    SetSaved(true)
    CH:Print(string.format("Route %s: %d writ%s at %d stop%s%s, about %d min.%s", restoring and "restored" or "planned",
        writs, writs == 1 and "" or "s",
        #route.stops, #route.stops == 1 and "" or "s",
        route.continent and (" in " .. ns.ContinentName(route.continent)) or "", math.max(1, math.floor((route.seconds or 0) / 60 + 0.5)),
        CH.Nav:HasTomTom() and "" or " Install TomTom to see every stop on the map."))
    self:SendMessage(ns.MSG_ROUTE)
    return route
end

-- Where you are, as a located place (nil in instances / unknown positions).
local function PlayerPlace()
    local here = PlayerPosition()
    if here and ns.Travel.Locate(here) then return here end
end

-- Recomputes the way to `stop` from where you are now (after picking a stop by hand).
function Route:RerouteFromHere(stop)
    local graph = self.route and self.route.graph
    local here = graph and PlayerPosition()
    if not (here and ns.Travel.AddNode(graph, here)) then return end
    local steps = ns.Travel.Steps(ns.Travel.Search(graph, here), stop)
    table.remove(graph.nodes, here.gi) -- the temporary node is always the last one
    if steps then
        -- Pickups on the way to the other stops stay there.
        local taken = {}
        for _, other in ipairs(self.route.stops) do
            if other ~= stop and not other.done then
                for _, step in ipairs(other.steps or {}) do
                    if step.kind == "pickup" then taken[step.to.id] = true end
                end
            end
        end
        for _, node in ipairs(graph.nodes) do
            if node.kind == "flight-unknown" and KnowsFlight(node.id) then taken[node.id] = true end -- since learned
        end
        AddPickups({ steps }, graph, taken)
        stop.steps = steps
        stop.via = BuildVia(steps)
    end
end

-- Points the arrow at the next flight master / dock on the way, or at the stop itself.
function Route:PointArrow()
    CH.Nav:Clear(VIA_GROUP)
    local stop = self:GetCurrent()
    if not stop then return end
    for i = self.viaIndex or 1, #(stop.via or {}) do
        local e = stop.via[i]
        if e.board then
            local h = CH.Nav:Add(VIA_GROUP, { map = e.board.map, x = e.board.x, y = e.board.y, title = e.text }, true)
            if h then return end
        end
    end
    if stop.handle then
        CH.Nav:Arrow(stop.handle)
    else
        -- Without TomTom only the current target has a pin.
        stop.handle = CH.Nav:Add(GROUP, { map = stop.map, x = stop.x, y = stop.y, title = StopTitle(stop) }, true)
    end
end

-- manual: picked by hand, so the directions are worked out again from where you are.
function Route:SetCurrent(index, quiet, manual)
    local route = self.route
    local stop = route and route.stops[index]
    if not stop then return end
    self.current = index
    self.viaIndex = 1
    if manual then self:RerouteFromHere(stop) end
    self:PointArrow()
    if not quiet then self:SendMessage(ns.MSG_ROUTE) end
end

function Route:GetCurrent()
    return self.route and self.current and self.route.stops[self.current]
end

-- Whether a via step is behind you: you reached its flight master / dock, or you're
-- already on the far side of a crossing (boat, zeppelin, travel to another landmass).
local function Passed(e, here)
    -- A flight path counts once you have it; riding past its flight master isn't enough.
    if e.kind == "pickup" then return KnowsFlight(e.to.id) end
    if e.board then
        local d = ns.Travel.Yards(here, e.board)
        if d and d <= ARRIVE_YARDS then return true end
    end
    if e.kind == "hearth" then
        -- Done once you're at the inn.
        local d = ns.Travel.Yards(here, e.to)
        if d and d <= HEARTH_ARRIVE_YARDS then return true end
    end
    -- A teleport: done once you're in its zone (where exactly you land isn't known until it's recorded).
    if e.kind == "teleport" then return here.zone == e.to.zone end
    if e.kind == "cross" then return e.into ~= nil and here.zone == e.into end
    return e.from.land ~= e.to.land and here.land == e.to.land
end

-- Moves the arrow along the current stop's via steps as you travel.
-- `here` is for tests; in game it's your current position.
function Route:Tick(here)
    local stop = self:GetCurrent()
    local via = stop and stop.via
    local i = self.viaIndex or 1
    if not (via and i <= #via) then return end
    here = here or PlayerPlace()
    if not here then return end

    local nextIndex = i
    -- Latest step already behind you (so skipping one, e.g. by hearthing, still works).
    for j = #via, i, -1 do
        if Passed(via[j], here) then nextIndex = j + 1; break end
    end
    -- In the air on the flight you were sent to take.
    if nextIndex == i and via[i].kind == "fly" and UnitOnTaxi and UnitOnTaxi("player") then
        nextIndex = i + 1
    end
    -- Standing at the stop itself.
    local d = ns.Travel.Yards(here, stop)
    if d and d <= ARRIVE_YARDS then nextIndex = #via + 1 end

    if nextIndex ~= i then
        self.viaIndex = nextIndex
        self:PointArrow()
        self:SendMessage(ns.MSG_ROUTE)
    end
end

-- The next `max` things to do, starting at the current stop: travel directions
-- ({ kind = "step", text }) and stops ({ kind = "stop", text, stop }), in order.
-- Delivered stops and steps already behind you are skipped.
function Route:GetUpcoming(max)
    local out = {}
    local route = self.route
    if not (route and self.current) then return out end
    for i = self.current, #route.stops do
        local stop = route.stops[i]
        if not stop.done then
            local first = (i == self.current) and (self.viaIndex or 1) or 1
            for k = first, #(stop.via or {}) do
                if #out >= max then return out end
                table.insert(out, { kind = "step", text = stop.via[k].text, stop = stop })
            end
            if #out >= max then return out end
            local n = #stop.writs
            table.insert(out, { kind = "stop", stop = stop,
                text = string.format("%s, %s (%d writ%s)", stop.name or "?", stop.zoneName or "?", n, n == 1 and "" or "s") })
        end
    end
    return out
end

---------------------------------------------------------------------------
-- /writs why: the planner's numbers for the way to the current stop
---------------------------------------------------------------------------

local function Clock(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Route:Explain()
    local stop = self:GetCurrent()
    local graph = self.route and self.route.graph
    if not (stop and graph) then
        CH:Print("Plan a route first (/writs route).")
        return
    end
    local here = PlayerPosition()
    if not (here and ns.Travel.AddNode(graph, here)) then
        CH:Print("Can't tell where you are right now.")
        return
    end
    local T = ns.Travel
    local search = T.Search(graph, here)

    CH:Print(string.format("Way to %s (%s), riding at %.1f yd/s:", stop.name or "?", stop.zoneName or "?", graph.speed))
    if here.land == stop.land then
        CH:Print(string.format("  Riding straight there: %s (%d yards)", Clock(T.WalkSeconds(graph, here, stop)),
            math.floor(T.Yards(here, stop) or 0)))
    end
    local steps = T.Steps(search, stop) or {}
    local parts = {}
    for _, step in ipairs(steps) do table.insert(parts, T.Describe(step) or "ride") end
    CH:Print(string.format("  Planned: %s (%s)", Clock(search.seconds[stop.gi]), table.concat(parts, ", ")))

    -- Best flight from each flight master on your landmass, landing on the stop's.
    local options, known, total = {}, 0, 0
    for _, a in ipairs(graph.nodes) do
        if (a.kind == "flight" or a.kind == "flight-unknown") and a.instance == here.instance then
            total = total + 1
            if a.kind == "flight" then known = known + 1 end
        end
        if a.kind == "flight" and a.land == here.land then
            -- Ride to this flight master, then the quickest way on from there.
            local fromA = T.Search(graph, a)
            local steps = T.Steps(fromA, stop) or {}
            if steps[1] and steps[1].kind == "fly" then
                table.insert(options, { a = a, b = steps[1].to,
                    total = T.WalkSeconds(graph, here, a) + fromA.seconds[stop.gi] })
            end
        end
    end
    table.sort(options, function(x, y) return x.total < y.total end)
    for i = 1, math.min(3, #options) do
        local o = options[i]
        CH:Print(string.format("  Via %s -> %s: %s", T.FlightPoint(o.a), T.FlightPoint(o.b), Clock(o.total)))
    end
    local measured = 0
    for _ in pairs(ns.TaxiNodeOfNpc) do measured = measured + 1 end
    CH:Print(string.format("  Flight masters matched to measured flight routes: %d.", measured))
    CH:Print(string.format("  Flight paths known on this continent: %d of %d for your faction.", known, total))
    table.remove(graph.nodes, here.gi) -- the temporary node is always the last one
end

function Route:IsActive()
    return self.route ~= nil and #self.route.stops > 0
end

-- Called whenever writ state changes: tick off delivered stops and move on.
function Route:OnWritsUpdated()
    local route = self.route
    if not (route and #route.stops > 0) then return end

    local changed = false
    for _, stop in ipairs(route.stops) do
        if not stop.done and not StopPending(stop) then
            stop.done = true
            CH.Nav:Remove(GROUP, stop.handle)
            stop.handle = nil
            changed = true
        end
    end
    if not changed then return end

    local current = self:GetCurrent()
    if current and current.done then
        local nextIndex
        for i = self.current + 1, #route.stops do
            if not route.stops[i].done then nextIndex = i; break end
        end
        if not nextIndex then
            for i = 1, #route.stops do
                if not route.stops[i].done then nextIndex = i; break end
            end
        end
        if nextIndex then
            self:SetCurrent(nextIndex, true)
            local stop = route.stops[nextIndex]
            CH:Print(string.format("Next stop: %s in %s.", stop.name or "?", stop.zoneName or "?"))
            for _, e in ipairs(stop.via or {}) do CH:Print("  " .. e.text .. ".") end
        else
            CH:Print("Route complete. All writs delivered!")
            self:Clear(true)
        end
    end
    self:SendMessage(ns.MSG_ROUTE)
end

function Route:Clear(quiet)
    CH.Nav:Clear(VIA_GROUP)
    CH.Nav:Clear(GROUP)
    if self.ticker and self.CancelTimer then self:CancelTimer(self.ticker) end
    self.route, self.current, self.viaIndex, self.ticker = nil, nil, nil, nil
    SetSaved(false)
    if not quiet then self:SendMessage(ns.MSG_ROUTE) end
end

-- After a /reload or relog the route is gone from memory; plan it again from
-- where you are, once writ data and turn-in sources have had time to load.
function Route:OnEnteringWorld()
    local saved = CH.db and CH.db.char.routeActive
    if saved and not self.route and not self.restoreTimer and self.ScheduleTimer then
        self.restoreTimer = self:ScheduleTimer(function()
            self.restoreTimer = nil
            if not self.route and CH.db.char.routeActive then self:Plan(true) end
        end, RESTORE_DELAY)
    end
end

function Route:OnEnable()
    self:RegisterMessage(ns.MSG_UPDATED, "OnWritsUpdated")
    if self.RegisterEvent then self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld") end
end
