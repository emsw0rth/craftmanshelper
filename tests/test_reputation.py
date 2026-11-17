"""Tests for Reputation.lua (reputation for the writs you hold or have on a route), in Lua 5.1.

    pip install lupa
    python tests/test_reputation.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = {}
ns.STATUS = { READY = "ready", ACTIVE = "active", INBAGS = "inbags", AVAILABLE = "available", DONE = "done" }
ns.TIER_REP = { JOURNEYMAN = 75, EXPERT = 125, ARTISAN = 200 }
ns.Writs = {
    [1] = { tier = "JOURNEYMAN" }, [2] = { tier = "EXPERT" }, [3] = { tier = "ARTISAN" },
    [4] = { tier = "EXPERT" }, [5] = { tier = "ARTISAN" }, [6] = { tier = "JOURNEYMAN" },
}
states = {
    [1] = { status = "ready", inLog = true, writsInBags = 0, writsTotal = 0 },
    [2] = { status = "active", inLog = true, writsInBags = 0, writsTotal = 0 },
    [3] = { status = "inbags", inLog = false, writsInBags = 2, writsTotal = 2 }, -- two copies: once a day
    [4] = { status = "available", inLog = false, writsInBags = 0, writsTotal = 1 }, -- bank only
    [5] = { status = "done", inLog = false, writsInBags = 1, writsTotal = 1 },      -- done today
    [6] = { status = "available", inLog = false, writsInBags = 0, writsTotal = 0 },
}
ns.CH = { Tracker = {
    GetAllStates = function() return states end,
    GetState = function(_, id) return states[id] end,
} }
faction = "Alliance"
function UnitFactionGroup() return faction end
FACTION_STANDING_LABEL4 = "Neutral"
FACTION_STANDING_LABEL5 = "Friendly"
FACTION_STANDING_LABEL6 = "Honored"
standing = { name = "Azeroth Commerce Authority", factionID = 9001, reaction = 5,
             currentStanding = 3000 + 5600, currentReactionThreshold = 3000, nextReactionThreshold = 9000 }
C_Reputation = {
    GetNumFactions = function() return 2 end,
    GetFactionDataByIndex = function(i)
        if i == 1 then return { name = "Stormwind", factionID = 72 } end
        return standing
    end,
    GetFactionDataByID = function(id) if id == 9001 then return standing end end,
}
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
g._load((ADDON / "Reputation.lua").read_text(encoding="utf-8"), "Reputation.lua")
R = g.ns.Rep

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


h = R.Held()
check("held: quest log and bags, each writ once", h.count == 3 and h.rep == 75 + 125 + 200, (h.count, h.rep))
check("held: ready now", h.ready.count == 1 and h.ready.rep == 75, (h.ready.count, h.ready.rep))
check("held: bank only counted apart", h.bank.count == 1 and h.bank.rep == 125, (h.bank.count, h.bank.rep))
check("faction name follows your faction", R.FactionName() == "Azeroth Commerce Authority")
lua.execute("faction = 'Horde'")
check("Horde faction name", R.FactionName() == "Durotar Supply and Logistics")
lua.execute("faction = 'Alliance'")

route = lua.eval("{ stops = { { writs = { 1, 2 } }, { writs = { 5 } } } }")
r = R.OfRoute(route)
check("route total", r.count == 3 and r.rep == 75 + 125 + 200, (r.count, r.rep))
check("route left: delivered writs drop out", r.left.count == 2 and r.left.rep == 200, (r.left.count, r.left.rep))

st = R.Standing()
check("standing found by name", st is not None and st.standing == "Friendly" and st.value == 5600 and st.max == 6000,
      st and (st.standing, st.value, st.max))
o = R.Outlook(100)
check("outlook below the next standing", o == "Friendly 5600 / 6000 now, 5700 / 6000 after.", o)
o = R.Outlook(400)
check("outlook reaching the next standing", o == "Friendly 5600 / 6000 now: enough to reach Honored.", o)
check("no outlook for nothing", R.Outlook(0) is None)
lua.execute("standing.nextReactionThreshold = standing.currentReactionThreshold")
check("no outlook at the top standing", R.Outlook(100) is None)

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
