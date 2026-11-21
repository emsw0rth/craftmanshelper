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

# Mage teleports in the graph: from anywhere to where they land, but not within that city.
TP = "{ speed = 7, teleports = { { spell = 1, name = 'Port', map = 1440, x = 50, y = 50 } } }"
graph = T.NewGraph(lua.eval(TP))
start, stop = T.AddNode(graph, g.P(1437, 50, 50)), T.AddNode(graph, g.P(1440, 55, 50))
s = T.Search(graph, start)
check("teleport: across continents", kinds(T.Steps(s, stop)) == ["teleport", "walk"], kinds(T.Steps(s, stop)))
check("teleport: time", abs(s.seconds[stop.gi] - (30 + 50 * 1.3 / 7)) < 1e-6, s.seconds[stop.gi])
check("teleport: directions", T.Describe(T.Steps(s, stop)[1]) == "Teleport to Port")
graph = T.NewGraph(lua.eval(TP))
start, stop = T.AddNode(graph, g.P(1441, 0, 50)), T.AddNode(graph, g.P(1440, 55, 50))
s = T.Search(graph, start)
check("teleport: quicker than riding there", kinds(T.Steps(s, stop))[0] == "teleport", kinds(T.Steps(s, stop)))
graph = T.NewGraph(lua.eval(TP))
start, stop = T.AddNode(graph, g.P(1440, 0, 0)), T.AddNode(graph, g.P(1440, 90, 50))
s = T.Search(graph, start)
check("teleport: not within its own city", kinds(T.Steps(s, stop)) == ["walk"], kinds(T.Steps(s, stop)))
graph = T.NewGraph(lua.eval("{ speed = 7 }"))
start, stop = T.AddNode(graph, g.P(1437, 50, 50)), T.AddNode(graph, g.P(1440, 55, 50))
check("teleport: none without the option", kinds(T.Steps(T.Search(graph, start), stop)) == ["travel"])

# Teleports.lua: known spells, runes, setting, learned arrival spot.
lua.execute("""
runes = 0
C_Item = { GetItemCount = function(id) return id == 17031 and runes or 0 end }
CH.db.global = {}
CH.db.profile.useTeleports = true
timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
""")
g._load((ADDON / "Teleports.lua").read_text(encoding="utf-8"), "Teleports.lua")
TPm = g.CH.Teleports
check("teleports: none known", len(TPm.GetKnown(TPm)) == 0 and TPm.GetOptions(TPm) is None)
lua.execute("spells[3567] = true; spells[3563] = true")
known = TPm.GetKnown(TPm)
check("teleports: known spells", [known[i].name for i in range(1, len(known) + 1)] == ["Undercity", "Orgrimmar"],
      [known[i].name for i in range(1, len(known) + 1)])
check("teleports: no rune, no teleports", TPm.GetOptions(TPm) is None)
lua.execute("runes = 3")
check("teleports: with runes", TPm.GetOptions(TPm) is not None and TPm.Runes(TPm) == 3)
lua.execute("runes = 0; spells[1225503] = true")
check("teleports: Reagent Economy needs no runes", TPm.GetOptions(TPm) is not None and TPm.Runes(TPm) == float("inf"))
lua.execute("CH.db.profile.useTeleports = false")
check("teleports: setting off", TPm.GetOptions(TPm) is None)
lua.execute("CH.db.profile.useTeleports = true")
# Arrival: recorded once you're in the city (a retry while the loading screen is still up).
lua.execute("""
here = { map = 1437, x = 0.5, y = 0.5 }
C_Map.GetBestMapForUnit = function() return here.map end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return here.x, here.y end } end
""")
TPm.OnSpellcast(TPm, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 3567)
lua.execute("local fn = table.remove(timers, 1); fn()")
check("teleports: not recorded outside the city", g.CH.db["global"].teleports[3567] is None)
lua.execute("here = { map = 1454, x = 0.47, y = 0.62 }; local fn = table.remove(timers, 1); fn()")
spot = g.CH.db["global"].teleports[3567]
check("teleports: arrival recorded", spot is not None and spot.map == 1454 and abs(spot.x - 47) < 1e-6)
org = [k for k in TPm.GetKnown(TPm).values() if k.spell == 3567][0]
check("teleports: learned spot used", abs(org.x - 47) < 1e-6 and abs(org.y - 62) < 1e-6, (org.x, org.y))
TPm.OnSpellcast(TPm, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 133)
check("teleports: other spells ignored", len(g.timers) == 0)
lua.execute("spells = {}; C_Item = nil")

# Faction links: a Horde player never boards an Alliance boat, and vice versa.
lua.execute("""ns.Transports = {
    { kind = 'boat', faction = 'A', from = { map = 1437, x = 5, y = 60 }, to = { map = 1438, x = 70, y = 55 } },
    { kind = 'zeppelin', faction = 'H', from = { map = 1440, x = 50, y = 14 }, to = { map = 1441, x = 31, y = 29 } },
    { kind = 'boat', from = { map = 1439, x = 63, y = 38 }, to = { map = 1437, x = 25, y = 73 } },
}""")
def link_kinds(opts):
    gr = T.NewGraph(lua.eval(opts))
    out = []
    for i in range(1, len(gr.nodes) + 1):
        for j in range(1, len(gr.nodes[i].links) + 1):
            out.append((gr.nodes[i].links[j].kind, gr.nodes[i].map))
    return sorted(out)
check("Horde: no Alliance boat", link_kinds("{ speed = 7, faction = 'H' }") == [("boat", 1439), ("zeppelin", 1440)],
      link_kinds("{ speed = 7, faction = 'H' }"))
check("Alliance: no zeppelin", link_kinds("{ speed = 7, faction = 'A' }") == [("boat", 1437), ("boat", 1439)],
      link_kinds("{ speed = 7, faction = 'A' }"))
check("faction unknown: only shared links", link_kinds("{ speed = 7 }") == [("boat", 1439)], link_kinds("{ speed = 7 }"))
lua.execute("ns.Transports = {}")

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
# Factions: zeppelins are Horde; Menethil, Auberdine, Theramore, Southshore and the tram are
# Alliance; Ratchet - Booty Bay and Tanaris - Riverglades are for everyone.
links = [tr[i] for i in range(1, len(tr) + 1)]
fac = lambda m, kind=None: {l.faction for l in links if (l["from"].map == m or l.to.map == m) and (kind is None or l.kind == kind)}
check("zeppelins are Horde", fac(1411) == {"H"} and fac(1420) == {"H"}, (fac(1411), fac(1420)))
check("Grom'gol (STV) zeppelin is Horde", fac(1434, "zeppelin") == {"H"}, fac(1434, "zeppelin"))
check("Menethil boats are Alliance", fac(1437) == {"A"}, fac(1437))
check("Theramore and Southshore boats are Alliance", fac(1445) == {"A"} and fac(1424) == {"A"})
check("Deeprun Tram is Alliance", fac(1455, "tram") == {"A"}, fac(1455, "tram"))
check("Ratchet - Booty Bay is neutral", fac(1413) == {None}, fac(1413))
check("Tanaris - Riverglades is neutral", fac(2548) == {None}, fac(2548))
check("Zephras Isle: Horde zeppelin, Alliance skycutter",
      fac(2521, "zeppelin") == {"H"} and fac(2521, "skycutter") == {"A"})
check("Auberdine and Rut'theran boats are Alliance", fac(1439) == {"A"} and fac(1438) == {"A"},
      (fac(1439), fac(1438)))
check("Stormwind boat is Alliance", fac(1453, "boat") == {"A"}, fac(1453, "boat"))


# The real links each faction may use (Travel.FactionOK is what NewGraph filters with).
def usable(faction):
    return [(l.kind, l["from"].map, l.to.map) for l in links if T.FactionOK(faction, l.faction)]


ALLIANCE_ONLY = {1437, 1438, 1439, 1453, 1455, 1424, 1445, 1444}  # Menethil, Darnassus, Auberdine, SW, IF...
horde = usable("H")
check("Horde network: no tram, no skycutter", not any(k in ("tram", "skycutter") for k, _, _ in horde),
      sorted({k for k, _, _ in horde}))
check("Horde network: no Alliance docks", not any(a in ALLIANCE_ONLY or b in ALLIANCE_ONLY for _, a, b in horde),
      [x for x in horde if x[1] in ALLIANCE_ONLY or x[2] in ALLIANCE_ONLY])
check("Horde network: zeppelins and shared boats",
      {k for k, _, _ in horde} == {"zeppelin", "boat"} and ("boat", 1413, 1434) in horde and ("boat", 1446, 2548) in horde,
      sorted(set(horde)))
alliance = usable("A")
check("Alliance network: no zeppelin", not any(k == "zeppelin" for k, _, _ in alliance))
check("Alliance network: tram and shared boats",
      ("tram", 1453, 1455) in alliance and ("boat", 1413, 1434) in alliance and ("boat", 1446, 2548) in alliance,
      sorted(set(alliance)))
unknown = usable(None)
check("unknown faction: shared boats only", sorted({k for k, _, _ in unknown}) == ["boat"]
      and all(a not in ALLIANCE_ONLY and b not in ALLIANCE_ONLY for _, a, b in unknown), unknown)

fl = g.ns2.FlightLengths
check("flight length data sane", len(list(fl.keys())) >= 300
      and all(k // 10000 > 0 and k % 10000 > 0 and 0 < v < 30000 for k, v in fl.items()))

# Crossings between zones. Fake world: Darkshore 1439 - Ashenvale 1440 - Thousand Needles 1441
# on one continent; crossings at x = 0 / 100 on each side of a border.
lua.execute("""ns.Transports, ns.FlightMasters = {}, {}
ns.Crossings = {
    [1439] = { { to = 1440, x = 99, y = 50 } },
    [1440] = { { to = 1439, x = 1, y = 50 }, { to = 1441, x = 99, y = 50, note = "the pass" } },
    [1441] = { { to = 1440, x = 1, y = 50 } },
}""")


def graph_with(opts="{ speed = 7 }"):
    return T.NewGraph(lua.eval(opts))


def crossings(gr):
    return [gr.nodes[i] for i in range(1, len(gr.nodes) + 1) if gr.nodes[i].kind == "crossing"]


graph = graph_with()
cs = crossings(graph)
check("crossings are nodes in both zones", len(cs) == 4 and all(len(list(c.zones.keys())) == 2 for c in cs))
a, b = T.AddNode(graph, g.P(1441, 50, 50)), T.AddNode(graph, g.P(1439, 50, 50))
s1 = T.Search(graph, a)
steps = T.Steps(s1, b)
check("rides through the crossings between", kinds(steps) == ["cross", "cross", "walk"], kinds(steps))
check("crossing directions", [T.Describe(steps[1]), T.Describe(steps[2])] ==
      ["Ride into Zone1440 (Zone1441 1.0, 50.0)", "Ride into Zone1439 (Zone1440 1.0, 50.0)"],
      [T.Describe(steps[1]), T.Describe(steps[2])])
check("crossing note in the directions",
      T.Describe(lua.eval("function(c, f) return { kind = 'cross', from = f, to = c } end")(
          [c for c in crossings(graph) if c.note][0], a)) == "Ride into Zone1440, the pass (Zone1440 99.0, 50.0)")
check("no straight ride across a zone you're not in", not T.CanRide(graph, a, b))
inside = T.AddNode(graph, g.P(1441, 10, 10))
check("ride within a zone", T.CanRide(graph, a, inside))
x441 = [c for c in cs if c.map == 1441][0]
check("crossing counts as both zones", T.CanRide(graph, x441, a) and T.CanRide(graph, x441, T.AddNode(graph, g.P(1440, 5, 5))))
x = [c for c in cs if c.map == 1440 and c.x == 99][0]
check("crossing leads into the zone you're not in", T.CrossInto(a, x) == 1440 and T.CrossInto(inside, x) == 1440)
y_ = T.AddNode(graph, g.P(1440, 50, 50))
check("from the other side it leads back", T.CrossInto(y_, x) == 1441)

# A zone listed without crossings can't be ridden into.
lua.execute("ns.Crossings[1441] = {}; ns.Crossings[1440][2] = nil")
graph = graph_with()
a, b = T.AddNode(graph, g.P(1441, 50, 50)), T.AddNode(graph, g.P(1440, 50, 50))
check("zone without crossings: travel fallback", kinds(T.Steps(T.Search(graph, a), b)) == ["travel"])

# Keys and capitals.
lua.execute("""ns.Crossings = {
    [1440] = { { to = 1441, x = 99, y = 50, item = 5396 }, { to = 1439, x = 1, y = 50, faction = "A" } },
    [1441] = {}, [1439] = {},
}""")
check("gate without the key: shut", len(crossings(graph_with("{ speed = 7, faction = 'A', hasItem = function() return false end }"))) == 1)
check("gate with the key: open", len(crossings(graph_with("{ speed = 7, faction = 'A', hasItem = function(id) return id == 5396 end }"))) == 2)
lua.execute("C_Item = { GetItemCount = function(id) return id == 5396 and 1 or 0 end }")
check("key found in the bags", T.HasItem(5396) and not T.HasItem(1) and len(crossings(graph_with("{ speed = 7, faction = 'A' }"))) == 2)
lua.execute("C_Item = nil")
check("capital gate: not for the other faction", len(crossings(graph_with("{ speed = 7, faction = 'H' }"))) == 0)
check("capital gate: not with the faction unknown", len(crossings(graph_with("{ speed = 7 }"))) == 0)

# Zones missing from the data: ridden into as before (same landmass).
lua.execute("ns.Crossings = { [1439] = {} }")
graph = graph_with()
a, b = T.AddNode(graph, g.P(1441, 50, 50)), T.AddNode(graph, g.P(1440, 50, 50))
check("zones without data: free riding", kinds(T.Steps(T.Search(graph, a), b)) == ["walk"])
lua.execute("ns.Crossings = nil")

# The real crossing data.
lua.execute("_cr = {}")
lua.eval("function(src) local f = assert(loadstring(src)); f('CraftmansHelper', _cr) end")(
    (ADDON / "Data" / "Crossings.lua").read_text(encoding="utf-8"))
CR = g._cr.Crossings
zones = {z: [CR[z][i] for i in range(1, len(CR[z]) + 1)] for z in CR.keys()}


def targets(c):
    return list(c.to.values()) if lua.eval("type")(c.to) == "table" else [c.to]


check("crossings: coordinates on the map", all(0 <= c.x <= 100 and 0 <= c.y <= 100 for l in zones.values() for c in l))
check("crossings: lead to listed zones", all(t in zones for l in zones.values() for c in l for t in targets(c)),
      [(z, t) for z, l in zones.items() for c in l for t in targets(c) if t not in zones])
# Every zone that has crossings is reachable on foot from the rest of its continent (ignoring keys and
# factions), apart from the island of Teldrassil.
links = {(z, t) for z, l in zones.items() for c in l if not c.item for t in targets(c)}


def reach(start):
    seen, todo = {start}, [start]
    while todo:
        z = todo.pop()
        for u, v in links:
            for p, q in ((u, v), (v, u)):
                if p == z and q not in seen:
                    seen.add(q); todo.append(q)
    return seen


KALIMDOR = {1411, 1412, 1413, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451,
            1452, 1454, 1456}
EK = {1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432,
      1433, 1434, 1435, 1436, 1437, 1453, 1455, 1458, 2548}
check("crossings: Kalimdor connected", reach(1413) == KALIMDOR, KALIMDOR ^ reach(1413))
check("crossings: Eastern Kingdoms connected", reach(1429) == EK, EK ^ reach(1429))
check("crossings: Teldrassil and Darnassus", reach(1438) == {1438, 1457})
tn = {t for c in zones[1441] for t in targets(c)}
check("Thousand Needles leads to Tanaris, Feralas and The Barrens, not Un'Goro", tn == {1446, 1444, 1413}, tn)
check("Searing Gorge gate needs its key",
      sorted((z, c.item) for z, l in zones.items() for c in l if c.item) == [(1427, 5396), (1432, 5396)])
CAPITALS = {1453: "A", 1455: "A", 1457: "A", 1454: "H", 1456: "H", 1458: "H"}
check("capital crossings carry their faction",
      all(c.faction == CAPITALS[z] for z in CAPITALS for c in zones[z])
      and all(c.faction == CAPITALS[t] for z, l in zones.items() for c in l for t in targets(c) if t in CAPITALS),
      [(z, c.x, c.faction) for z, l in zones.items() for c in l for t in targets(c) if t in CAPITALS and c.faction != CAPITALS[t]])

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
