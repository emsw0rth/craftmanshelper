"""Tests for CraftmansHelper/Route.lua against stubbed WoW APIs, in Lua 5.1 (via lupa).

    pip install lupa
    python tests/test_route.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = { STATUS = { READY = "ready", ACTIVE = "active", INBAGS = "inbags", AVAILABLE = "available", DONE = "done" },
       MSG_UPDATED = "UPDATED", UNKNOWN_CONTINENT = 0, CONTINENT_ORDER = { 1414, 1415, 0 } }
printed, sent = {}, {}

-- Zones: map -> continent (1440 Ashenvale/1441 Thousand Needles = Kalimdor; 1437 Wetlands/1431 Duskwood = EK)
local CONT = { [1440] = 1414, [1441] = 1414, [1437] = 1415, [1431] = 1415 }
function ns.ResolveZone(map) return map, "Zone" .. map, CONT[map] or 0 end
function ns.ContinentName(c) return "C" .. c end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

-- Fake world: each map is a 1000-yard square; Kalimdor maps on instance 1, EK on 0.
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {}
function C_Map.GetWorldPosFromMapPos(map, v)
    local inst = (CONT[map] == 1414) and 1 or 0
    return inst, { GetXY = function() return map * 1000 + v.x * 1000, v.y * 1000 end }
end
player = { map = 1437, x = 0.5, y = 0.5 }
function C_Map.GetBestMapForUnit() return player.map end
function C_Map.GetPlayerMapPosition() return { GetXY = function() return player.x, player.y end } end
faction = "Alliance"
function UnitFactionGroup() return faction end

-- Travel data: none by default (tests below add some).
ns.FlightMasters, ns.Transports = {}, {}
function UnitLevel() return 60 end

-- Addon object / modules
CH = { Print = function(self, msg) table.insert(printed, msg) end,
       db = { char = { flightPaths = {} } } }
function CH:NewModule(name)
    local m = { name = name }
    function m:SendMessage(msg) table.insert(sent, msg) end
    function m:RegisterMessage() end
    return m
end
ns.CH = CH

-- Nav stub: records waypoints and the arrow target.
nav = { added = 0, removed = 0, arrow = nil, tomtom = true }
CH.Nav = {
    HasTomTom = function() return nav.tomtom end,
    Add = function(self, group, point, arrow)
        if not nav.tomtom and not arrow then return nil end
        nav.added = nav.added + 1
        local h = { point = point }
        if arrow then nav.arrow = h end
        return h
    end,
    Arrow = function(self, h) nav.arrow = h end,
    Remove = function(self, group, h) if h then nav.removed = nav.removed + 1 end end,
    Clear = function(self, group) end,
}

-- Tracker stub
states = {}
CH.Tracker = {
    GetAllStates = function() return states end,
    GetState = function(self, id) return states[id] end,
}
function writ(id, status, map, x, y, name, fac, have)
    local turnIn = map and { map = map, x = x, y = y, name = name, faction = fac } or nil
    states[id] = { id = id, status = status, have = have or 1, need = 1, turnIn = turnIn,
                   zoneName = map and ("Zone" .. map) or "Unknown",
                   continentID = map and ns.ResolveZone(map) and select(3, ns.ResolveZone(map)) or 0,
                   writ = { name = "W" .. id, item = id } }
end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
for f in ("Solver.lua", "Travel.lua", "Route.lua", "FlightPaths.lua"):
    g._load((ADDON / f).read_text(encoding="utf-8"), f)
Route = g.CH.Route
same = lua.eval("rawequal")  # lupa wrappers don't compare Lua tables by identity

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def reset():
    lua.execute("states = {}; printed = {}; sent = {}; nav.added, nav.removed, nav.arrow = 0, 0, nil")


def stop_names(route):
    return [route.stops[i].name for i in range(1, len(route.stops) + 1)]


# --- Waypoint titles -----------------------------------------------------------
lua.execute("""ns.Writs = { [1] = { name = "Goblin Rocket Fuel", item = 1 }, [2] = { name = "Draught of Water Breathing", item = 2 },
    [3] = { name = "Iron Buckle", item = 3 }, [4] = { name = "Bolt of Silk Cloth", item = 4 } }""")
title = g.ns._StopTitle
check("title: one writ", title(lua.eval('{ name = "Kixxle", writs = { 1 } }')) == "Kixxle: Goblin Rocket Fuel")
check("title: names sorted", title(lua.eval('{ name = "Kixxle", writs = { 1, 2 } }'))
      == "Kixxle: Draught of Water Breathing, Goblin Rocket Fuel")
t = title(lua.eval('{ name = "Kixxle", writs = { 4, 3, 2, 1 } }'))
check("title: capped at 3 names", t == "Kixxle: Bolt of Silk Cloth, Draught of Water Breathing, Goblin Rocket Fuel +1 more", t)
check("title: unknown writ falls back to NPC", title(lua.eval('{ name = "Kixxle", writs = { 99 } }')) == "Kixxle")
check("title: no NPC name", title(lua.eval('{ writs = { 1 } }')) == "Turn-in: Goblin Rocket Fuel")
lua.execute("ns.Writs = {}")

# --- Grouping, filtering, ordering ------------------------------------------
reset()
lua.execute("""
writ(1, "ready",   1437, 50.2, 37.7, "Kixxle", "AH")      -- Wetlands
writ(2, "ready",   1437, 50.2, 37.7, "Kixxle", "AH")      -- same spot -> same stop
writ(3, "inbags",  1431, 81.8, 19.8, "Kzixx", "AH", 1)    -- in bags with item -> included
writ(4, "inbags",  1431, 81.8, 19.8, "Kzixx", "AH", 0)    -- in bags without item -> excluded
writ(5, "active",  1431, 10, 10, "Missing", "AH", 0)      -- still missing the item -> excluded
writ(6, "ready",   1440, 60.2, 72.7, "Ash'alari", "AH")   -- Kalimdor
writ(7, "ready",   1441, 77.2, 77.4, "Rizzle", "H")       -- Horde-only NPC -> excluded for Alliance
writ(8, "ready",   nil)                                   -- no location -> unroutable
writ(9, "done",    1440, 60, 60, "Done", "AH")            -- done today -> excluded
""")
route = Route.Build(Route)
names = stop_names(route)
check("stops are grouped by spot", names.count("Kixxle") == 1 and len(route.stops[1].writs) == 2, names)
check("unstarted writ with item included", "Kzixx" in names, names)
check("writs missing items / done are excluded", "Missing" not in names and "Done" not in names, names)
check("faction filter", len(route.excluded) == 1 and route.excluded[1].id == 7)
check("unroutable listed", len(route.unroutable) == 1 and route.unroutable[1].id == 8)
check("player's continent (EK) first", route.legs[1].contID == 1415 and route.legs[2].contID == 1414,
      [route.legs[i].contID for i in range(1, len(route.legs) + 1)])
check("EK leg starts from player", route.legs[1].fromPlayer and not route.legs[2].fromPlayer)
check("flat stop list = 3 stops", len(route.stops) == 3, names)

# Horde player sees the Horde-only NPC.
lua.execute('faction = "Horde"')
route = Route.Build(Route)
check("Horde player gets Horde NPC", "Rizzle" in stop_names(route) and len(route.excluded) == 0)
lua.execute('faction = "Alliance"')

# Player in Kalimdor -> Kalimdor first.
lua.execute("player.map = 1440")
route = Route.Build(Route)
check("Kalimdor first when standing there", route.legs[1].contID == 1414)
lua.execute("player.map = 1437")

# --- Travel across continents and by flight -----------------------------------
# EK stops in Wetlands (1437) and Kalimdor stops in Ashenvale (1440); a boat links the two.
reset()
lua.execute("""
writ(1, "ready", 1437, 50, 50, "EK", "AH")
writ(2, "ready", 1440, 50, 50, "Kal", "AH")
ns.Transports = { { kind = "boat", a = { map = 1437, x = 10, y = 10 }, b = { map = 1440, x = 10, y = 10 } } }
player.map, player.x, player.y = 1437, 0.5, 0.6
""")
route = Route.Build(Route)
check("one route across both continents", stop_names(route) == ["EK", "Kal"], stop_names(route))
kal = route.stops[2]
kinds = [kal.steps[i].kind for i in range(1, len(kal.steps) + 1)]
check("crosses by boat", kinds == ["walk", "boat", "walk"], kinds)
check("boat directions", g.ns.Travel.Describe(kal.steps[2]) == "Take the boat from Zone1437 to Zone1440",
      g.ns.Travel.Describe(kal.steps[2]))
check("legs follow continents", route.legs[1].contID == 1415 and route.legs[2].contID == 1414)
check("route time adds up", abs(route.seconds - (route.stops[1].seconds + kal.seconds)) < 1e-6)

# Upcoming steps for the route tracker: stop 1, the boat, stop 2.
Route.Plan(Route)
up = Route.GetUpcoming(Route, 5)
texts = [(up[i].kind, up[i].text) for i in range(1, len(up) + 1)]
check("upcoming: stops and directions in order",
      texts == [("stop", "EK, Zone1437 (1 writ)"), ("step", "Take the boat from Zone1437 to Zone1440"),
                ("stop", "Kal, Zone1440 (1 writ)")], texts)
check("upcoming: capped", len(Route.GetUpcoming(Route, 2)) == 2)
lua.eval("function() states[1].status = 'done' end")()
Route.OnWritsUpdated(Route)
up = Route.GetUpcoming(Route, 5)
check("upcoming: delivered stop dropped", [up[i].kind for i in range(1, len(up) + 1)] == ["step", "stop"])

# Arrow via the dock: after the first delivery the current stop is across the sea.
kal = Route.GetCurrent(Route)
check("via: arrow points at the dock first", g.nav.arrow.point.title == "Take the boat from Zone1437 to Zone1440"
      and g.nav.arrow.point.map == 1437, g.nav.arrow.point.title)
place = lua.eval("function(map, x, y) local p = { map = map, x = x, y = y }; ns.Travel.Locate(p); return p end")
Route.Tick(Route, place(1437, 50, 50))          # still far from the dock
check("via: nothing changes away from the dock", Route.viaIndex == 1)
Route.Tick(Route, place(1437, 11, 11))          # at the dock (within 40 yards)
check("via: reaching the dock moves the arrow to the stop", Route.viaIndex == 2 and same(g.nav.arrow, kal.handle))
up = Route.GetUpcoming(Route, 5)
check("via: passed step leaves the tracker", [up[i].kind for i in range(1, len(up) + 1)] == ["stop"])
Route.SetCurrent(Route, kal.index, True)        # back to the dock step
Route.Tick(Route, place(1440, 30, 30))          # already across (took another way)
check("via: being across the sea counts as passed", Route.viaIndex == 2)

# Picking a stop by hand re-plans the way from where you are: standing in Kalimdor, no boat.
lua.execute("player.map, player.x, player.y = 1440, 0.4, 0.4")
Route.SetCurrent(Route, kal.index, None, True)
check("manual pick: directions from here", len(kal.via) == 0 and len(Route.GetUpcoming(Route, 5)) == 1,
      [kal.via[i].text for i in range(1, len(kal.via) + 1)])
last = kal.steps[len(kal.steps)]
check("manual pick: directions end at the picked stop", same(last.to, kal), (last.to.name, kal.name))

# /writs why prints the planner's numbers without leaving a node behind.
n_before = len(Route.route.graph.nodes)
lua.execute("printed = {}")
Route.Explain(Route)
lines = [str(v) for v in g.printed.values()]
check("why: explains the way", any("Way to Kal" in l for l in lines) and any("Planned:" in l for l in lines), lines)
check("why: temporary node removed", len(Route.route.graph.nodes) == n_before)
lua.execute("player.map, player.x, player.y = 1437, 0.5, 0.6")

Route.Clear(Route)
check("upcoming: empty without a route", len(Route.GetUpcoming(Route, 5)) == 0)

# A known flight path is used for a long trip; an unknown one isn't.
reset()
lua.execute("""
ns.Transports = {}
writ(1, "ready", 1441, 90, 90, "Far", "AH")                 -- Thousand Needles, far from Ashenvale
ns.FlightMasters = {
    [10] = { name = "FM Ash", map = 1440, x = 50, y = 50, faction = "AH" },
    [11] = { name = "FM TN", map = 1441, x = 90, y = 88, faction = "AH" },
}
player.map, player.x, player.y = 1440, 0.5, 0.5
""")
route = Route.Build(Route)
kinds = [route.stops[1].steps[i].kind for i in range(1, len(route.stops[1].steps) + 1)]
check("unknown flight paths aren't used", kinds == ["walk"], kinds)
lua.execute("CH.db.char.flightPaths = { [10] = true, [11] = true }")
route = Route.Build(Route)
steps = route.stops[1].steps
kinds = [steps[i].kind for i in range(1, len(steps) + 1)]
check("known flight path is used", "fly" in kinds, kinds)
fly = [steps[i] for i in range(1, len(steps) + 1) if steps[i].kind == "fly"][0]
check("flight directions with the flight time",
      g.ns.Travel.Describe(fly) == "Fly from FM Ash (Zone1440) to FM TN (Zone1441), about "
      + g.ns.Travel.Minutes(fly.seconds), g.ns.Travel.Describe(fly))
lua.execute("""
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
FM = ns.FlightMasters
C_TaxiMap = { GetTaxiNodesForMap = function(map)
    if map ~= 1441 then return {} end
    local function P(x, y) return { x = x, y = y } end
    return { { nodeID = 2, name = "Near Miss, Needles", position = P(0.80, 0.88) },   -- 100 yards off
             { nodeID = 1, name = "Freewind Post, Needles", position = P(0.90, 0.88) }, -- on the spot
             { nodeID = 3, name = "Far Away, Needles", position = P(0.10, 0.10) } }
end }
FM[12] = { name = "Other Faction", map = 1441, x = 89, y = 88, faction = "H" }
CH.FlightPaths:MapTaxiNodes()
FM[12] = nil""")
check("flight point named after the nearest taxi node", g.ns.FlightPlaceOfNpc[11] == "Freewind Post",
      g.ns.FlightPlaceOfNpc[11])
check("both factions' flight masters in a town get its name", g.ns.FlightPlaceOfNpc[12] == "Freewind Post")
check("flight directions use the place, the NPC only without one",
      g.ns.Travel.Describe(fly).startswith("Fly from FM Ash (Zone1440) to Freewind Post (Zone1441), about "),
      g.ns.Travel.Describe(fly))
lua.execute("ns.FlightPlaceOfNpc[11] = 'Zone1441'")
check("place named like its zone: said once", " to Zone1441, about " in g.ns.Travel.Describe(fly), g.ns.Travel.Describe(fly))
lua.execute("ns.FlightPlaceOfNpc = {}; ns.TaxiNodeOfNpc = {}")
PlaceOf = g.CH.FlightPaths.PlaceOf
check("place of a node name", (PlaceOf("Gadgetzan, Tanaris"), PlaceOf("Moonglade"), PlaceOf(""), PlaceOf(None),
      PlaceOf("A\uff0cB")) == ("Gadgetzan", "Moonglade", None, None, "A"))
check("flight paths known per continent", g.CH.FlightPaths.CountOn(g.CH.FlightPaths, 1414) == 2
      and g.CH.FlightPaths.CountOn(g.CH.FlightPaths, 1415) == 0)
check("flight time formats", (g.ns.Travel.Minutes(20), g.ns.Travel.Minutes(150), g.ns.Travel.Minutes(3900))
      == ("under a minute", "3 min", "1h 5m"))

# --- Flight paths on the way -------------------------------------------------------
# Riding 400 yards east through Thousand Needles; only FM 20 known on Kalimdor.
reset()
lua.execute("""
CH.db.char.flightPaths = { [20] = true }
writ(1, "ready", 1441, 90, 50, "East", "AH")
player.map, player.x, player.y = 1441, 0.5, 0.5
ns.FlightMasters = {
    [20] = { name = "Known", map = 1440, x = 1, y = 1, faction = "AH" },
    [21] = { name = "Near", map = 1441, x = 70, y = 54, faction = "AH" },   -- just off the road
    [22] = { name = "Nearer", map = 1441, x = 60, y = 51, faction = "AH" },
    [23] = { name = "Far", map = 1441, x = 70, y = 5, faction = "AH" },     -- 450 yards off
    [24] = { name = "Enemy", map = 1441, x = 75, y = 50, faction = "H" },
    [11800] = { name = "Druids only", map = 1441, x = 80, y = 50, faction = "AH" },
}
""")


def via_texts(stop):
    return [stop.via[i].text for i in range(1, len(stop.via) + 1)]


NEAR, NEARER = "Pick up the flight path at Near (Zone1441)", "Pick up the flight path at Nearer (Zone1441)"
lua.execute("CH.db.profile = { pickups = false }")
plain = Route.Build(Route)
check("pickups: off in Settings", via_texts(plain.stops[1]) == [], via_texts(plain.stops[1]))
lua.execute("CH.db.profile = { pickups = true }")
route = Route.Build(Route)
check("pickups: in riding order, not the far, enemy or druid ones", via_texts(route.stops[1]) == [NEARER, NEAR],
      via_texts(route.stops[1]))
steps = route.stops[1].steps
kinds = [steps[i].kind for i in range(1, len(steps) + 1)]
check("pickups: ride on afterwards", kinds == ["pickup", "pickup", "walk"], kinds)
secs = sum(steps[i].seconds for i in range(1, len(steps) + 1))
check("pickups: detours in the route's time", abs(route.seconds - secs) < 1e-6 and route.seconds > plain.seconds
      and abs(route.stops[1].seconds - secs) < 1e-6 and abs(route.legs[1].length - secs) < 1e-6,
      (route.seconds, secs, plain.seconds))
lua.execute("CH.db.char.flightPaths = {}")
check("pickups: none where no flight map was opened", via_texts(Route.Build(Route).stops[1]) == [])
lua.execute("CH.db.char.flightPaths = { [20] = true }")

Route.Plan(Route)
check("pickups: arrow at the flight master", g.nav.arrow.point.title == NEARER and g.nav.arrow.point.x == 60)
Route.Tick(Route, place(1441, 60, 51))
check("pickups: standing there isn't enough", Route.viaIndex == 1, Route.viaIndex)
lua.execute("CH.db.char.flightPaths[22] = true")
Route.Tick(Route, place(1441, 60, 51))
check("pickups: done once learned", Route.viaIndex == 2 and g.nav.arrow.point.title == NEAR, Route.viaIndex)
Route.Tick(Route, place(1441, 90, 50))
check("pickups: skipped at the stop", Route.viaIndex == 3, Route.viaIndex)
Route.SetCurrent(Route, 1, True, True)
check("pickups: re-routed by hand, learned one gone", via_texts(Route.GetCurrent(Route)) == [NEAR],
      via_texts(Route.GetCurrent(Route)))
Route.Clear(Route)

# Two stops: each flight master is offered once, where it's the shortest detour.
lua.execute("""CH.db.char.flightPaths = { [20] = true, [22] = true }
writ(2, "ready", 1441, 70, 56, "AtNear", "AH")""")
route = Route.Build(Route)
alltexts = [t for i in range(1, len(route.stops) + 1) for t in via_texts(route.stops[i])]
check("pickups: once per route", alltexts == [NEAR], alltexts)

# Learning a flight path without the flight map opening.
lua.execute("""
function strsplit(sep, s) local out = {}; for p in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = p end; return unpack(out) end
ERR_NEWTAXIPATH = "New flight path discovered!"
function UnitGUID(u) if u == "target" then return "Creature-0-1-1-1-21-00001" end end
CH.FlightPaths:OnInfoMessage("UI_INFO_MESSAGE", 1, "Something else")
before = CH.db.char.flightPaths[21]
CH.FlightPaths:OnInfoMessage("UI_INFO_MESSAGE", 1, ERR_NEWTAXIPATH)""")
check("discovered flight path learned", g.before is None and g.CH.db.char.flightPaths[21] is True)

# --- One continent -------------------------------------------------------------------
reset()
lua.execute("""
ns.FlightMasters = {}
writ(1, "ready", 1441, 90, 50, "Kal", "AH")
writ(2, "ready", 1437, 50, 50, "East", "AH")
writ(3, "ready", nil)
CH.db.char.routeContinent = 1415""")
route = Route.Build(Route)
check("one continent: only its stops", stop_names(route) == ["East"] and len(route.elsewhere) == 1
      and route.elsewhere[1].id == 1 and len(route.unroutable) == 1, stop_names(route))
Route.Plan(Route)
check("one continent: said when planning", "1 stop in C1415, about" in g.printed[len(g.printed)], g.printed[len(g.printed)])
Route.Clear(Route)
lua.execute("states[2] = nil")
Route.Plan(Route)
check("one continent: nothing there", g.printed[len(g.printed)] == "Nothing to deliver in C1415 right now.",
      g.printed[len(g.printed)])
lua.execute("CH.db.char.routeContinent = nil")
check("all continents again", stop_names(Route.Build(Route)) == ["Kal"])
Route.Clear(Route)
lua.execute("""CH.db.char.flightPaths = {}; ns.FlightMasters = {}
player.map, player.x, player.y = 1437, 0.5, 0.5""")

# --- Hearthstone ------------------------------------------------------------------
# A stop next to you in the Wetlands, one in Ashenvale with no known way across
# (15-minute fallback), and a hearth bound in Ashenvale.
reset()
lua.execute("""
ns.Transports = {}
writ(1, "ready", 1437, 50, 55, "Near", "AH")
writ(2, "ready", 1440, 50, 50, "Over", "AH")
player.map, player.x, player.y = 1437, 0.5, 0.5
hearthOpt = { name = "Inn Town", map = 1440, x = 52, y = 50, readyIn = 0 }
CH.Hearth = { GetOption = function() return hearthOpt end }
""")
route = Route.Build(Route)
check("hearth: used after the nearby stop", stop_names(route) == ["Near", "Over"] and route.hearthAt == 2,
      (stop_names(route), route.hearthAt))
over = route.stops[2]
kinds = [over.steps[i].kind for i in range(1, len(over.steps) + 1)]
check("hearth: steps", kinds == ["hearth", "walk"], kinds)
check("hearth: directions", over.via[1].text == "Use your Hearthstone (Inn Town)", over.via[1].text)
check("hearth: route is quicker than the fallback", route.seconds < 900, route.seconds)

lua.execute("hearthOpt.readyIn = 100000")
route = Route.Build(Route)
check("hearth: not used while on cooldown", route.hearthAt is None and route.seconds >= 900, route.seconds)

lua.execute("hearthOpt.readyIn = 0; states = {}; writ(2, 'ready', 1440, 50, 50, 'Over', 'AH')")
route = Route.Build(Route)
check("hearth: can be the first move", route.hearthAt == 1, route.hearthAt)

lua.execute("states = {}; writ(1, 'ready', 1437, 50, 55, 'Near', 'AH'); writ(3, 'ready', 1437, 60, 60, 'Near2', 'AH')")
route = Route.Build(Route)
check("hearth: not used when it doesn't help", route.hearthAt is None)

# Following: the hearth step is passed once you're at the inn.
lua.execute("states = {}; writ(2, 'ready', 1440, 50, 50, 'Over', 'AH')")
Route.Plan(Route)
check("hearth: no waypoint for the hearth step itself", same(g.nav.arrow, Route.GetCurrent(Route).handle))
Route.Tick(Route, place(1440, 52, 50))
check("hearth: passed at the inn", Route.viaIndex == 2)
Route.Clear(Route)
lua.execute("CH.Hearth = nil")

# --- Teleports --------------------------------------------------------------------
# The same two stops; a mage teleport landing in Ashenvale, usable from anywhere.
reset()
lua.execute("""
ns.Transports = {}
writ(1, "ready", 1437, 50, 55, "Near", "AH")
writ(2, "ready", 1440, 50, 50, "Over", "AH")
player.map, player.x, player.y = 1437, 0.5, 0.5
runes = 5
tpOnce = {}
CH.Teleports = {
    Anywhere = function(self, mage)
        if mage == false then return {}, runes end
        return { { key = "TOWN", kind = "mage", name = "Town", map = 1440, x = 52, y = 50,
                   text = "Teleport to Town", rune = true } }, runes
    end,
    Once = function() return tpOnce end,
}
""")
route = Route.Build(Route)
over = route.stops[2]
kinds = [over.steps[i].kind for i in range(1, len(over.steps) + 1)]
check("teleport: used to reach the far stop", stop_names(route) == ["Near", "Over"] and kinds == ["teleport", "walk"],
      (stop_names(route), kinds))
check("teleport: directions", over.via[1].text == "Teleport to Town", over.via[1].text)
check("teleport: quicker than the fallback", route.seconds < 900, route.seconds)

lua.execute("runes = 0")
route = Route.Build(Route)
check("teleport: not without runes", route.seconds >= 900, route.seconds)

# Following: the teleport step is passed once you're in its zone.
lua.execute("runes = 5; states = {}; writ(2, 'ready', 1440, 50, 50, 'Over', 'AH')")
Route.Plan(Route)
Route.Tick(Route, place(1440, 10, 10))
check("teleport: passed in its zone", Route.viaIndex == 2, Route.viaIndex)
Route.Clear(Route)

# An engineering transporter: once per route, like the Hearthstone.
lua.execute("""
states = {}; writ(1, "ready", 1437, 50, 55, "Near", "AH"); writ(2, "ready", 1440, 50, 50, "Over", "AH")
CH.Teleports.Anywhere = function() return {}, 0 end
tpOnce = { { key = "GADGETZAN", kind = "device", name = "Gadgetzan", map = 1440, x = 52, y = 50,
             text = "Use your Transporter", readyIn = 0 } }
""")
route = Route.Build(Route)
over = route.stops[2]
check("transporter: used once", route.teleportAt == 2 and route.hearthAt is None, (route.teleportAt, route.hearthAt))
check("transporter: directions", over.via[1].text == "Use your Transporter", over.via[1].text)
lua.execute("tpOnce[1].readyIn = 100000")
route = Route.Build(Route)
check("transporter: not while on cooldown", route.teleportAt is None and route.seconds >= 900, route.seconds)
lua.execute("CH.Teleports = nil")

# Back to the three-stop set used below.
reset()
lua.execute("""
writ(1, "ready", 1437, 50.2, 37.7, "Kixxle", "AH"); writ(2, "ready", 1437, 50.2, 37.7, "Kixxle", "AH")
writ(3, "inbags", 1431, 81.8, 19.8, "Kzixx", "AH", 1); writ(6, "ready", 1440, 60.2, 72.7, "Ash'alari", "AH")
""")

# --- Following the route -------------------------------------------------------
route = Route.Plan(Route)
first = Route.GetCurrent(Route)
check("plan sets the first stop as current", first is not None and first.index == 1)
check("waypoint added per stop (TomTom)", g.nav.added == 3, g.nav.added)
check("arrow points at the first stop", same(g.nav.arrow, first.handle))

# Deliver everything at the first stop.
for wid in list(first.writs.values()):
    lua.eval(f"function() states[{wid}].status = 'done' end")()
Route.OnWritsUpdated(Route)
second = Route.GetCurrent(Route)
check("advances after delivery", first.done and second.index == 2, (first.done, second and second.index))
check("delivered stop's waypoint removed", g.nav.removed == 1)
check("arrow moved to the next stop", same(g.nav.arrow, second.handle))

# A partial delivery at a multi-writ stop doesn't advance.
lua.execute("""
states = {}
writ(1, "ready", 1437, 50, 50, "A", "AH"); writ(2, "ready", 1437, 50, 50, "A", "AH")
writ(3, "ready", 1437, 90, 90, "B", "AH")
player.x, player.y = 0.5, 0.5
""")
Route.Plan(Route)
cur = Route.GetCurrent(Route)
lua.execute("states[1].status = 'done'")
Route.OnWritsUpdated(Route)
check("partial delivery keeps the stop", same(Route.GetCurrent(Route), cur) and not cur.done)
lua.execute("states[2].status = 'done'; states[3].status = 'done'")
Route.OnWritsUpdated(Route)
check("route completes and clears", not Route.IsActive(Route) and any("complete" in str(p) for p in g.printed.values()))

# Without TomTom only the current stop gets a pin.
lua.execute("""
nav.tomtom = false; nav.added = 0; states = {}
writ(1, "ready", 1437, 10, 10, "A", "AH"); writ(2, "ready", 1437, 90, 90, "B", "AH")
""")
Route.Plan(Route)
check("map pin fallback: one pin", g.nav.added == 1, g.nav.added)
lua.execute("states[%d].status = 'done'" % Route.GetCurrent(Route).writs[1])
Route.OnWritsUpdated(Route)
check("map pin fallback: pin moves on", g.nav.added == 2 and same(g.nav.arrow, Route.GetCurrent(Route).handle))

# Surviving a /reload: the active route is remembered and planned again.
lua.execute("""
nav.tomtom = true; states = {}
writ(1, "ready", 1437, 10, 10, "A", "AH")
scheduled = nil
CH.Route.ScheduleTimer = function(self, fn, delay) scheduled = fn; return {} end
""")
Route.Plan(Route)
check("restore: active route remembered", g.CH.db.char.routeActive == True)
lua.execute("CH.Route.route, CH.Route.current = nil, nil")   # what a /reload leaves behind
Route.OnEnteringWorld(Route)
lua.execute("printed = {}; scheduled()")
check("restore: planned again after login", Route.IsActive(Route)
      and any("Route restored" in str(p) for p in g.printed.values()), list(g.printed.values()))
Route.Clear(Route)
check("restore: clearing forgets it", g.CH.db.char.routeActive is None)
lua.execute("scheduled = nil")
Route.OnEnteringWorld(Route)
check("restore: nothing to restore", g.scheduled is None)
lua.execute("CH.Route.ScheduleTimer = nil")

# Nothing to deliver.
lua.execute("nav.tomtom = true; states = {}")
route = Route.Plan(Route)
check("empty route handled", len(route.stops) == 0 and not Route.IsActive(Route))

print()
if failures:
    print(f"{failures} test(s) failed")
    sys.exit(1)
print("all tests passed")
