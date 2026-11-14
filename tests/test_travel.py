"""Tests for Travel.lua (travel-time graph) and FlightPaths.Match, in Lua 5.1.

    pip install lupa
    python tests/test_travel.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = {}
-- Fake world: each map is a 1000-yard square at x = map * 1000; continents by instance.
-- 1437 Wetlands (EK), 1440/1441 Ashenvale/Thousand Needles, 1438 Teldrassil, 1439 Darkshore (Kalimdor).
local INST = { [1437] = 0, [1440] = 1, [1441] = 1, [1438] = 1, [1439] = 1 }
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {}
function C_Map.GetWorldPosFromMapPos(map, v)
    if INST[map] == nil then return nil end
    return INST[map], { GetXY = function() return map * 1000 + v.x * 1000, v.y * 1000 end }
end
function ns.ResolveZone(map) return map, "Zone" .. map, 0 end
ns.FlightMasters, ns.Transports = {}, {}
ns.TRANSPORT_SECONDS = { boat = 240 }
ns.TRANSPORT_NAMES = { boat = "boat" }
function UnitLevel() return 10 end
spells = {}
function IsPlayerSpell(id) return spells[id] == true end

CH = { NewModule = function() return { RegisterEvent = function() end } end, db = { char = { flightPaths = {} } } }
ns.CH = CH
function P(map, x, y, kind) return { kind = kind or "stop", map = map, x = x, y = y } end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
for f in ("Travel.lua", "FlightPaths.lua"):
    g._load((ADDON / f).read_text(encoding="utf-8"), f)
T = g.ns.Travel

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def kinds(steps):
    return [steps[i].kind for i in range(1, len(steps) + 1)]


# Ground speed from riding skills, then level.
check("speed: on foot at low level", T.GroundSpeed() == 7)
lua.execute("UnitLevel = function() return 45 end")
check("speed: level 40+ assumes a mount", T.GroundSpeed() == 11.2)
lua.execute("spells[33391] = true")
check("speed: journeyman riding", T.GroundSpeed() == 14)
lua.execute("spells = {}; UnitLevel = function() return 10 end")

# Walking time on one landmass: 500 yards * 1.3 detour / 7 yd/s.
graph = T.NewGraph(lua.eval("{ speed = 7 }"))
a, b = T.AddNode(graph, g.P(1440, 0, 0)), T.AddNode(graph, g.P(1440, 50, 0))
s = T.Search(graph, a)
check("walk time", abs(s.seconds[b.gi] - 500 * 1.3 / 7) < 1e-6, s.seconds[b.gi])
check("walk steps", kinds(T.Steps(s, b)) == ["walk"])
check("walking needs no directions", T.Describe(T.Steps(s, b)[1]) is None)
check("no world position -> no node", T.AddNode(graph, g.P(9999, 1, 1)) is None)

# Crossing a zone border costs more than riding inside one (same straight-line distance).
c = T.AddNode(graph, g.P(1441, 0, 0))   # Thousand Needles, next to Ashenvale in the fake world
s = T.Search(graph, b)
check("cross-zone ride uses the higher detour", abs(s.seconds[c.gi] - 500 * 1.6 / 7) < 1e-6, s.seconds[c.gi])
check("node index field doesn't clash with stop numbers", b.index is None and b.gi is not None)

# Teldrassil is an island: without a boat it's a fallback "travel", with one the boat.
graph = T.NewGraph(lua.eval("{ speed = 7 }"))
dark, teld = T.AddNode(graph, g.P(1439, 50, 50)), T.AddNode(graph, g.P(1438, 0, 50))
s = T.Search(graph, dark)
check("island not walkable", kinds(T.Steps(s, teld)) == ["travel"], kinds(T.Steps(s, teld)))
check("fallback directions", T.Describe(T.Steps(s, teld)[1]) == "Travel to Zone1438")
lua.execute("ns.Transports = { { kind = 'boat', a = { map = 1439, x = 60, y = 50 }, b = { map = 1438, x = 10, y = 50 } } }")
graph = T.NewGraph(lua.eval("{ speed = 7 }"))
dark, teld = T.AddNode(graph, g.P(1439, 50, 50)), T.AddNode(graph, g.P(1438, 0, 50))
s = T.Search(graph, dark)
check("island by boat", kinds(T.Steps(s, teld)) == ["walk", "boat", "walk"], kinds(T.Steps(s, teld)))
lua.execute("ns.Transports = {}")

# Flights: faction, known paths, same continent only.
lua.execute("""ns.FlightMasters = {
    [1] = { name = "A1", map = 1440, x = 0, y = 0, faction = "A" },
    [2] = { name = "A2", map = 1441, x = 90, y = 90, faction = "AH" },
    [3] = { name = "H1", map = 1440, x = 1, y = 1, faction = "H" },
    [4] = { name = "EK", map = 1437, x = 50, y = 50, faction = "AH" },
}""")
graph = T.NewGraph(lua.eval("{ speed = 7, faction = 'A' }"))
names = sorted(graph.nodes[i].name for i in range(1, len(graph.nodes) + 1))
check("flight masters filtered by faction", names == ["A1", "A2", "EK"], names)
start, far = T.AddNode(graph, g.P(1440, 0, 0)), T.AddNode(graph, g.P(1441, 90, 90))
s = T.Search(graph, start)
check("all flight paths known by default", "fly" in kinds(T.Steps(s, far)), kinds(T.Steps(s, far)))
graph = T.NewGraph(lua.eval("{ speed = 7, faction = 'A', knowsFlight = function(id) return id ~= 2 end }"))
start, far = T.AddNode(graph, g.P(1440, 0, 0)), T.AddNode(graph, g.P(1441, 90, 90))
s = T.Search(graph, start)
check("unknown flight path not flown to", "fly" not in kinds(T.Steps(s, far)), kinds(T.Steps(s, far)))
# Flights don't cross continents (EK flight master isn't reachable by air from Kalimdor).
graph = T.NewGraph(lua.eval("{ speed = 7, faction = 'A' }"))
start, ek = T.AddNode(graph, g.P(1440, 0, 0)), T.AddNode(graph, g.P(1437, 50, 50))
s = T.Search(graph, start)
check("no flights between continents", "fly" not in kinds(T.Steps(s, ek)), kinds(T.Steps(s, ek)))
lua.execute("ns.FlightMasters = {}")

# One-way links ({ from, to }): the boat back isn't assumed; shared docks are one node.
lua.execute("""ns.Transports = {
    { kind = 'boat', from = { map = 1439, x = 60, y = 50 }, to = { map = 1438, x = 10, y = 50 } },
    { kind = 'boat', from = { map = 1439, x = 60, y = 50 }, to = { map = 1438, x = 20, y = 50 } },
}""")
graph = T.NewGraph(lua.eval("{ speed = 7 }"))
docks = [graph.nodes[i] for i in range(1, len(graph.nodes) + 1) if graph.nodes[i].kind == "dock"]
check("shared dock is one node", len(docks) == 3, len(docks))
dark, teld = T.AddNode(graph, g.P(1439, 50, 50)), T.AddNode(graph, g.P(1438, 0, 50))
check("one-way boat: there", "boat" in kinds(T.Steps(T.Search(graph, dark), teld)))
check("one-way boat: not back", "boat" not in kinds(T.Steps(T.Search(graph, teld), dark)))
lua.execute("ns.Transports = {}")

# Measured flight lengths: only listed routes are flown, hops merge into one flight.
lua.execute("""
ns.FlightMasters = {
    [1] = { name = "F1", map = 1440, x = 0, y = 0, faction = "AH" },
    [2] = { name = "F2", map = 1440, x = 50, y = 50, faction = "AH" },
    [3] = { name = "F3", map = 1441, x = 90, y = 90, faction = "AH" },
    [4] = { name = "F4", map = 1441, x = 10, y = 90, faction = "AH" },   -- no taxi node: estimated
}
ns.TaxiNodeOfNpc = { [1] = 11, [2] = 12, [3] = 13 }
ns.FlightLengths = { [110012] = 3000, [120011] = 3000, [120013] = 4000, [130012] = 4000 }
ns.Travel.ResetFlightData()
""")
graph = T.NewGraph(lua.eval("{ speed = 7 }"))
by = {graph.nodes[i].name: graph.nodes[i] for i in range(1, len(graph.nodes) + 1)}
check("measured: listed route", abs(T.FlySeconds(by["F1"], by["F2"]) - (3000 / 30.4 + 8)) < 1e-6)
check("measured: unlisted pair isn't direct", T.FlySeconds(by["F1"], by["F3"]) is None)
check("no estimated hop into the measured network", T.FlySeconds(by["F1"], by["F4"]) is None)
lua.execute("ns.FlightMasters[5] = { name = 'F5', map = 1441, x = 20, y = 90, faction = 'AH' }")
g5 = T.NewGraph(lua.eval("{ speed = 7 }"))
b5 = {g5.nodes[i].name: g5.nodes[i] for i in range(1, len(g5.nodes) + 1)}
check("estimate between two unmatched flight masters", T.FlySeconds(b5["F4"], b5["F5"]) is not None)
lua.execute("ns.FlightMasters[5] = nil")
start = T.AddNode(graph, g.P(1440, 0, 1))
far = T.AddNode(graph, g.P(1441, 90, 91))
s = T.Search(graph, start)
steps = T.Steps(s, far)
fly = [steps[i] for i in range(1, len(steps) + 1) if steps[i].kind == "fly"]
check("hops merge into one flight", len(fly) == 1 and fly[0]["from"].name == "F1" and fly[0].to.name == "F3",
      [(f["from"].name, f.to.name) for f in fly])
check("merged flight time", abs(fly[0].seconds - (7000 / 30.4 + 16)) < 1e-6, fly[0].seconds)
lua.execute("ns.FlightMasters = {}; ns.TaxiNodeOfNpc = {}; ns.FlightLengths = nil; ns.Travel.ResetFlightData()")

# FlightPaths.Match: nearest flight master within 250 yards on the same continent.
lua.execute("ns.FlightMasters = { [7] = { name = 'X', map = 1440, x = 50, y = 50, faction = 'AH' } }")
FPm = g.CH.FlightPaths
check("match nearby node", FPm.Match(1, 1440 * 1000 + 600, 500) == 7)
check("no match far away", FPm.Match(1, 1440 * 1000 + 900, 500) is None)
check("no match on another continent", FPm.Match(0, 1440 * 1000 + 500, 500) is None)
lua.execute("ns.FlightMasters = {}")

# Hearth.lua: recorded spot trusted only while the bind name matches; cooldown; setting.
lua.execute("""
bind, count, cd = "Ironforge", 1, { 0, 0 }
function GetBindLocation() return bind end
function GetTime() return 1000 end
C_Item = { GetItemCount = function() return count end }
C_Container = { GetItemCooldown = function() return cd[1], cd[2] end }
CH.db.char.hearth = { name = "Ironforge", map = 1455, x = 20, y = 50 }
CH.db.profile = { useHearth = true }
""")
g._load((ADDON / "Hearth.lua").read_text(encoding="utf-8"), "Hearth.lua")
H = g.CH.Hearth
opt = H.GetOption(H)
check("hearth: option when known and ready", opt is not None and opt.name == "Ironforge" and opt.readyIn == 0)
lua.execute("cd = { 900, 1800 }")  # used at t=900, 30 min cooldown -> 1700 s left at t=1000
check("hearth: cooldown left", abs(H.ReadyIn(H) - 1700) < 1e-6, H.ReadyIn(H))
lua.execute("cd = { 999, 1.5 }")   # global cooldown only
check("hearth: global cooldown ignored", H.ReadyIn(H) == 0)
lua.execute('bind = "Booty Bay"')
check("hearth: new bind location forgets the old spot", H.GetSpot(H) is None and H.GetOption(H) is None)
lua.execute('bind = "Ironforge"; count = 0')
check("hearth: no Hearthstone in bags", H.GetOption(H) is None)
lua.execute("count = 1; CH.db.profile.useHearth = false")
check("hearth: setting off", H.GetOption(H) is None)

# Real data: every flight master and dock sits on a map with a known zone, sane coordinates.
lua.execute("ns2 = {}; function _load2(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns2) end")
for f in ("Data/FlightMasters.lua", "Data/Transports.lua", "Data/FlightLengths.lua"):
    g._load2((ADDON / f).read_text(encoding="utf-8"), f)
fms = g.ns2.FlightMasters
bad = [k for k, v in fms.items() if not (0 <= v.x <= 100 and 0 <= v.y <= 100 and v.faction in ("A", "H", "AH"))]
check("flight master data sane", len(list(fms.keys())) >= 60 and not bad, bad)
tr = g.ns2.Transports
bad = [i for i in range(1, len(tr) + 1)
       if tr[i].kind not in ("boat", "zeppelin", "tram", "skycutter", "portal")
       or not (0 <= tr[i]["from"].x <= 100 and 0 <= tr[i].to.y <= 100)]
check("transport data sane", len(tr) >= 20 and not bad, bad)
fl = g.ns2.FlightLengths
check("flight length data sane", len(list(fl.keys())) >= 300
      and all(k // 10000 > 0 and k % 10000 > 0 and 0 < v < 30000 for k, v in fl.items()))

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
