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
g._load((ADDON / "Prices.lua").read_text(encoding="utf-8"), "Prices.lua")
lua.execute("ns.CH.db = { char = { diplomat = 0 } }")
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

# Diplomat: +2% a rank, rounded down.
check("no Diplomat: base rep", R.OfWrit(1) == 75 and R.OfWrit(3) == 200)
lua.execute("ns.CH.db.char.diplomat = 5")
check("Diplomat 5: +10%", (R.OfWrit(1), R.OfWrit(2), R.OfWrit(3)) == (82, 137, 220),
      (R.OfWrit(1), R.OfWrit(2), R.OfWrit(3)))
lua.execute("ns.CH.db.char.diplomat = 3")
check("Diplomat 3: +6%", (R.OfWrit(1), R.OfWrit(3)) == (79, 212), (R.OfWrit(1), R.OfWrit(3)))
lua.execute("ns.CH.db.char.diplomat = 9")
check("Diplomat rank capped at 5", R.OfWrit(1) == 82)
lua.execute("ns.CH.db.char.diplomat = 0")


# Cheapest: the cheapest few of each level.
def entries(spec):
    return lua.eval("{" + ",".join(f"{{ writID = {i}, cost = {c}, rep = {r} }}" for i, (c, r) in enumerate(spec, 1)) + "}")


def pick(spec, need):
    p = R.Cheapest(entries(spec), need)
    if p is None:
        return None
    return (sorted(e.writID for e in p.writs.values()), p.cost, p.rep)


spec = [(100, 75), (300, 75), (500, 125), (900, 200), (2000, 200)]
check("cheapest: one writ is enough", pick(spec, 70) == ([1], 100, 75), pick(spec, 70))
check("cheapest: two cheap beat one dear", pick(spec, 150) == ([1, 2], 400, 150), pick(spec, 150))
check("cheapest: mixed levels", pick(spec, 200) == ([1, 3], 600, 200), pick(spec, 200))
alt = [(800, 75), (900, 75), (1000, 200)]
check("cheapest: an artisan when cheaper", pick(alt, 150) == ([3], 1000, 200), pick(alt, 150))
check("cheapest: everything", pick(spec, 675) == ([1, 2, 3, 4, 5], 3800, 675), pick(spec, 675))
check("cheapest: not enough for sale", pick(spec, 676) is None)
check("cheapest: nothing needed", pick(spec, 0) == ([], 0, 0))
check("cheapest: one level only", pick([(10, 200), (20, 200)], 300) == ([1, 2], 30, 400))

# Next standing plan. The writs you have (1, 2, 3 in log/bags and 4 in the bank) are worth 525.
lua.execute("standing.nextReactionThreshold = 9000")
plan = R.NextStandingPlan()
check("plan: writs you have are enough", plan.need == 400 - 525 and plan.writs is None, (plan.need, plan.writs))
lua.execute("standing.currentStanding = 3000 + 4000")
lua.execute("""ns.Prices.GetWritBuyEstimate = function(id)
    local cost = ({ [5] = 5000, [6] = 700 })[id]
    return { writID = id, cost = cost, rep = ns.WritRep(id) } end""")
plan = R.NextStandingPlan()
check("plan: needs more than you have", (plan.toGo, plan.have, plan.need) == (2000, 525, 1475),
      (plan.toGo, plan.have, plan.need))
check("plan: too much for one day (5 is done, only 6 for sale)", plan.writs is None and plan.forSale == 1, plan.forSale)
lua.execute("standing.currentStanding = 3000 + 5440")
plan = R.NextStandingPlan()
check("plan: buys the one writ for sale",
      plan.need == 35 and [e.writID for e in plan.writs.values()] == [6] and plan.cost == 700, (plan.need, plan.cost))
check("plan: no pouch data, net is the cost", plan.net == 700, plan.net)
lua.execute("""ns.Prices.GetWritBuyEstimate = function(id)
    local cost = ({ [5] = 5000, [6] = 700 })[id]
    return { writID = id, cost = cost, net = cost - 900, rep = ns.WritRep(id) } end""")
plan = R.NextStandingPlan()
check("plan: coin pouch paying it all back", plan.cost == 700 and plan.net == -200
      and [e.writID for e in plan.writs.values()] == [6], (plan.cost, plan.net))

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
