"""Tests for turn-in location sources (Tracker.lua + Questie.lua) against stubbed WoW APIs, in Lua 5.1.

    pip install lupa
    python tests/test_sources.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = { MSG_UPDATED = "UPDATED", UNKNOWN_CONTINENT = 0 }
function ns.ResolveZone(map) return map, "Zone" .. map, 1414 end

-- Two writs: 100 has shipped coordinates, 200 has none.
ns.Writs = {
    [100] = { quest = 1000, item = 1, count = 1, name = "Shipped", turnIn = 5 },
    [200] = { quest = 2000, item = 2, count = 1, name = "Unknown", turnIn = 6 },
}
ns.TurnIns = {
    [5] = { name = "Static NPC", map = 1437, x = 10, y = 20, faction = "AH" },
    [6] = { name = "Zone-only NPC", map = 1446 },
}
ns.WritByQuest = { [1000] = 100, [2000] = 200 }

CH = { db = { global = { learned = {} }, char = { completed = {} } } }
function CH:NewModule(name)
    return { SendMessage = function() end, RegisterMessage = function() end }
end
ns.CH = CH

C_Item = { GetItemCount = function() return 0 end }
inLog = {}
markers = { poi = {}, waypoint = {}, questMap = {} }
C_QuestLog = {
    IsQuestFlaggedCompleted = function(q) return flagged and flagged[q] or false end,
    GetLogIndexForQuestID = function(q) return inLog[q] end,
    GetQuestsOnMap = function(map)
        local out = {}
        for q, p in pairs(markers.poi) do if p.map == map then table.insert(out, { questID = q, x = p.x, y = p.y }) end end
        return out
    end,
    GetNextWaypoint = function(q) local w = markers.waypoint[q]; if w then return w.map, w.x, w.y end end,
}
function GetQuestUiMapID(q) return markers.questMap[q] or 0 end
function GetServerTime() return 1000 end

-- QuestieDB stub: quest 2000 is finished by NPC 77 in Tanaris (AreaID 440).
questie = false
LibQuestieDB_impl = {
    Quest = { Get = function(id, key) if key == "finishedBy" and id == 2000 then return { { 77 } } end end },
    Npc = { Get = function(id, key)
        if id ~= 77 then return nil end
        if key == "spawns" then return { [440] = { { 52.5, 27.5 } } } end
        if key == "name" then return "Questie NPC" end
        if key == "friendlyToFaction" then return "AH" end
    end },
}
function setQuestie(on) LibQuestieDB = on and LibQuestieDB_impl or nil end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
for f in ("Questie.lua", "Tracker.lua"):
    g._load((ADDON / f).read_text(encoding="utf-8"), f)
T = g.CH.Tracker

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def turnin(writ, in_log=False):
    t = T.GetTurnIn(T, writ, in_log)
    return None if t is None else dict(t)


def reset():
    lua.execute("""CH.db.global.learned = {}; inLog = {}; markers = { poi = {}, waypoint = {}, questMap = {} }
                   setQuestie(false); package.loaded = package.loaded""")
    # Questie lookups are cached per quest; reload the module for a clean cache.
    g._load((ADDON / "Questie.lua").read_text(encoding="utf-8"), "Questie.lua")


# Shipped coordinates always win.
reset()
lua.execute('CH.db.global.learned[1000] = { source = "turnin", map = 1, x = 1, y = 1 }')
t = turnin(100)
check("shipped data wins", t["source"] == "data" and t["x"] == 10, t)

# No data anywhere -> static zone only.
reset()
t = turnin(200)
check("zone-only fallback", t["source"] == "data" and t["map"] == 1446 and t.get("x") is None, t)

# QuestieDB at runtime beats zone-only, with AreaID -> uiMapID and faction.
reset()
lua.execute("setQuestie(true)")
t = turnin(200)
check("questie runtime lookup", t["source"] == "questie" and t["map"] == 1446 and t["x"] == 52.5
      and t["faction"] == "AH" and t["name"] == "Questie NPC", t)

# A real turn-in recording beats Questie.
lua.execute('CH.db.global.learned[2000] = { source = "turnin", name = "Seen", map = 1446, x = 60, y = 30 }')
t = turnin(200)
check("learned turn-in beats questie", t["source"] == "learned" and t["x"] == 60, t)

# A marker recording loses to Questie but beats zone-only.
lua.execute('CH.db.global.learned[2000] = { source = "marker", map = 1446, x = 61, y = 31 }')
check("questie beats recorded marker", turnin(200)["source"] == "questie")
reset()
lua.execute('CH.db.global.learned[2000] = { source = "marker", map = 1446, x = 61, y = 31 }')
t = turnin(200)
check("recorded marker beats zone-only", t["source"] == "marker" and t["x"] == 61, t)

# Live marker while in the log: POI on the quest's own map.
reset()
lua.execute("inLog[2000] = 1; markers.questMap[2000] = 1446; markers.poi[2000] = { map = 1446, x = 0.5, y = 0.25 }")
t = turnin(200, True)
check("live POI marker", t["source"] == "marker" and t["map"] == 1446 and abs(t["x"] - 50) < 1e-9 and abs(t["y"] - 25) < 1e-9, t)

# GetNextWaypoint on a *different* map (e.g. a portal) is ignored.
reset()
lua.execute("inLog[2000] = 1; markers.questMap[2000] = 1446; markers.waypoint[2000] = { map = 1453, x = 0.4, y = 0.4 }")
t = turnin(200, True)
check("intermediate waypoint ignored", t["source"] == "data" and t.get("x") is None, t)
lua.execute("markers.waypoint[2000] = { map = 1446, x = 0.4, y = 0.6 }")
t = turnin(200, True)
check("same-map waypoint accepted", t["source"] == "marker" and abs(t["x"] - 40) < 1e-9, t)

# RecordMarker: records once, never over a turn-in, never for shipped writs.
reset()
lua.execute("inLog[2000] = 1; markers.questMap[2000] = 1446; markers.poi[2000] = { map = 1446, x = 0.5, y = 0.5 }")
check("record marker", T.RecordMarker(T, 2000) and g.CH.db["global"].learned[2000].source == "marker")
lua.execute('CH.db.global.learned[2000] = { source = "turnin", map = 1446, x = 1, y = 1 }')
check("marker never overwrites turn-in", not T.RecordMarker(T, 2000) and g.CH.db["global"].learned[2000].x == 1)
lua.execute("inLog[1000] = 1; markers.questMap[1000] = 1437; markers.poi[1000] = { map = 1437, x = 0.1, y = 0.1 }")
check("no marker for shipped writs", not T.RecordMarker(T, 1000) and g.CH.db["global"].learned[1000] is None)

# Refresh records markers for writs in the log.
reset()
lua.execute("inLog[2000] = 1; markers.questMap[2000] = 1446; markers.poi[2000] = { map = 1446, x = 0.3, y = 0.7 }")
T.Refresh(T)
rec = g.CH.db["global"].learned[2000]
check("refresh records marker", rec is not None and rec.source == "marker" and abs(rec.x - 30) < 1e-9)

# Refresh saves what the server says is done today, until the reset; a current entry is kept.
lua.execute("CH.db.char.completed = { [2000] = 5000 }; flagged = { [1000] = true, [2000] = true }")
T.Refresh(T)
done = g.CH.db.char.completed
check("refresh saves server completions", done[1000] == 1000 + 86400 and done[2000] == 5000, (done[1000], done[2000]))
lua.execute("CH.db.char.completed = {}; flagged = nil")

print()
if failures:
    print(f"{failures} test(s) failed")
    sys.exit(1)
print("all tests passed")
