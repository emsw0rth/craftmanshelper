-- Waypoints: TomTom when it's installed, otherwise the game's own map pin
-- (which only supports a single waypoint at a time).
local _, ns = ...
local CH = ns.CH

local Nav = CH:NewModule("Nav")
CH.Nav = Nav

local SOURCE = "Craftman's Helper"
local ARRIVAL_YARDS = 15

-- group name -> list of handles. Groups let the route and one-off clicks
-- clear their own waypoints without touching each other's (or the user's).
local groups = {}
local nativeHandle -- handle currently shown with the game's map pin

function Nav:HasTomTom()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

local function NativeSet(point)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(point.map) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(point.map, point.x / 100, point.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    return true
end

local function NativeClear()
    if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    nativeHandle = nil
end

-- point = { map = uiMapID, x = 0-100, y = 0-100, title = "..." }
-- Returns a handle, or nil if the point can't be shown.
function Nav:Add(group, point, withArrow)
    if not (point and point.map and point.x and point.y) then return nil end
    local handle = { point = point }

    if self:HasTomTom() then
        handle.uid = TomTom:AddWaypoint(point.map, point.x / 100, point.y / 100, {
            title = point.title,
            from = SOURCE,
            persistent = false,
            crazy = withArrow and true or false,
            silent = true,
            cleardistance = 0, -- keep it until the writ is delivered; we remove it ourselves
            arrivaldistance = ARRIVAL_YARDS,
        })
        if not handle.uid then return nil end
    elseif withArrow then
        if not NativeSet(point) then return nil end
        nativeHandle = handle
    end

    groups[group] = groups[group] or {}
    table.insert(groups[group], handle)
    return handle
end

-- Point the arrow (or the map pin) at an existing handle.
function Nav:Arrow(handle)
    if not handle then return end
    if handle.uid and self:HasTomTom() then
        TomTom:SetCrazyArrow(handle.uid, ARRIVAL_YARDS, handle.point.title)
    elseif not handle.uid then
        if NativeSet(handle.point) then nativeHandle = handle end
    end
end

function Nav:Remove(group, handle)
    if not handle then return end
    if handle.uid and self:HasTomTom() then
        TomTom:RemoveWaypoint(handle.uid)
    end
    if nativeHandle == handle then NativeClear() end
    local list = groups[group]
    if list then
        for i = #list, 1, -1 do
            if list[i] == handle then table.remove(list, i) end
        end
    end
end

function Nav:Clear(group)
    local list = groups[group]
    if not list then return end
    for i = #list, 1, -1 do
        self:Remove(group, list[i])
    end
    groups[group] = nil
end

-- One-off navigation (clicking a writ or zone): replaces the previous one-off waypoints.
function Nav:GoTo(points)
    self:Clear("manual")
    local first
    for i, point in ipairs(points) do
        local h = self:Add("manual", point, i == 1)
        first = first or h
    end
    if not first then
        CH:Print("No coordinates known for that turn-in yet.")
    elseif not self:HasTomTom() and #points > 1 then
        CH:Print("Install TomTom to see all waypoints at once; showing the first.")
    end
    return first
end
