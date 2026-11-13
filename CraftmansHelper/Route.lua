-- Delivery route: every writ you can hand in right now, grouped into stops
-- (one per turn-in spot), split by continent and ordered by ns.SolvePath.
local _, ns = ...
local CH = ns.CH
local STATUS = ns.STATUS

local Route = CH:NewModule("Route", "AceEvent-3.0")
CH.Route = Route

ns.MSG_ROUTE = "CRAFTMANSHELPER_ROUTE"

local GROUP = "route"

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

local function WorldPos(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
    if not (ok and pos) then return nil end
    local wx, wy = pos:GetXY()
    return instance, wx, wy
end

local function PlayerPosition()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    local _, _, contID = ns.ResolveZone(map)
    local instance, wx, wy = WorldPos(map, x * 100, y * 100)
    if not instance then return nil end
    return { contID = contID, instance = instance, wx = wx, wy = wy }
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

function Route:Build()
    local faction = PlayerFactionLetter()
    local stopsByKey, unroutable, excluded = {}, {}, {}

    for _, s in pairs(CH.Tracker:GetAllStates()) do
        if IsDeliverable(s) then
            local t = s.turnIn
            if t and t.faction and faction and not t.faction:find(faction, 1, true) then
                table.insert(excluded, s)
            elseif not (t and t.map and t.x and t.y) then
                table.insert(unroutable, s)
            else
                -- Same spot (to ~1% of the map) = same stop, whatever the data source.
                local key = string.format("%d:%d:%d", t.map, math.floor(t.x + 0.5), math.floor(t.y + 0.5))
                local stop = stopsByKey[key]
                if not stop then
                    local instance, wx, wy = WorldPos(t.map, t.x, t.y)
                    stop = { key = key, name = t.name, map = t.map, x = t.x, y = t.y,
                             zoneName = s.zoneName, contID = s.continentID,
                             instance = instance, wx = wx, wy = wy, writs = {} }
                    stopsByKey[key] = stop
                end
                table.insert(stop.writs, s.id)
            end
        end
    end

    -- Split by continent.
    local byCont = {}
    for _, stop in pairs(stopsByKey) do
        if stop.wx then
            byCont[stop.contID] = byCont[stop.contID] or {}
            table.insert(byCont[stop.contID], stop)
        else
            for _, id in ipairs(stop.writs) do table.insert(unroutable, CH.Tracker:GetState(id)) end
        end
    end

    -- Continent order: the one you're on first, then the usual display order.
    local player = PlayerPosition()
    local contOrder = {}
    if player and byCont[player.contID] then table.insert(contOrder, player.contID) end
    for _, c in ipairs(ns.CONTINENT_ORDER) do
        if byCont[c] and not tContains(contOrder, c) then table.insert(contOrder, c) end
    end
    for c in pairs(byCont) do
        if not tContains(contOrder, c) then table.insert(contOrder, c) end
    end

    local legs, flat = {}, {}
    for _, c in ipairs(contOrder) do
        local points = byCont[c]
        local start = (player and player.contID == c) and player or nil
        local order, length = ns.SolvePath(points, start)
        local leg = { contID = c, stops = {}, length = length, fromPlayer = start ~= nil }
        for _, i in ipairs(order) do
            table.insert(leg.stops, points[i])
            table.insert(flat, points[i])
        end
        table.insert(legs, leg)
    end

    return { legs = legs, stops = flat, unroutable = unroutable, excluded = excluded }
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

function Route:Plan()
    self:Clear(true)
    local route = self:Build()
    if #route.stops == 0 then
        self.route = route -- keep unroutable/excluded so the UI can explain
        CH:Print("Nothing to deliver right now.")
        self:SendMessage(ns.MSG_ROUTE)
        return route
    end

    for i, stop in ipairs(route.stops) do
        stop.index = i
        stop.handle = CH.Nav:Add(GROUP, { map = stop.map, x = stop.x, y = stop.y, title = StopTitle(stop) }, false)
    end
    self.route = route
    self:SetCurrent(1, true)

    local writs = 0
    for _, stop in ipairs(route.stops) do writs = writs + #stop.writs end
    CH:Print(string.format("Route planned: %d writ%s at %d stop%s.%s", writs, writs == 1 and "" or "s",
        #route.stops, #route.stops == 1 and "" or "s",
        CH.Nav:HasTomTom() and "" or " Install TomTom to see every stop on the map."))
    self:SendMessage(ns.MSG_ROUTE)
    return route
end

function Route:SetCurrent(index, quiet)
    local route = self.route
    local stop = route and route.stops[index]
    if not stop then return end
    self.current = index
    if stop.handle then
        CH.Nav:Arrow(stop.handle)
    else
        -- Without TomTom only the current stop has a pin.
        stop.handle = CH.Nav:Add(GROUP, { map = stop.map, x = stop.x, y = stop.y, title = StopTitle(stop) }, true)
    end
    if not quiet then self:SendMessage(ns.MSG_ROUTE) end
end

function Route:GetCurrent()
    return self.route and self.current and self.route.stops[self.current]
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
        else
            CH:Print("Route complete. All writs delivered!")
            self:Clear(true)
        end
    end
    self:SendMessage(ns.MSG_ROUTE)
end

function Route:Clear(quiet)
    CH.Nav:Clear(GROUP)
    self.route, self.current = nil, nil
    if not quiet then self:SendMessage(ns.MSG_ROUTE) end
end

function Route:OnEnable()
    self:RegisterMessage(ns.MSG_UPDATED, "OnWritsUpdated")
end
