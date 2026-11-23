"""Tests for Pouches.lua (learning coin pouch gold: pouch gone + gold in at once), in Lua 5.1.

    pip install lupa
    python tests/test_pouches.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = { Writs = {}, TIERS = { "JOURNEYMAN", "EXPERT", "ARTISAN" },
       TIER_NAMES = { JOURNEYMAN = "Journeyman", EXPERT = "Expert", ARTISAN = "Artisan" } }
messages, printed = 0, {}
ns.CH = { db = { profile = {}, global = {} } }
function ns.CH:Print(s) table.insert(printed, s) end
function ns.CH:NewModule(name)
    local m = { timers = {} }
    function m:RegisterEvent(event, fn) self.events = self.events or {}; self.events[event] = fn or event end
    function m:SendMessage() messages = messages + 1 end
    function m:ScheduleTimer(method, delay) local t = { method = method }; table.insert(self.timers, t); return t end
    function m:CancelTimer(t) t.cancelled = true end
    return m
end
now, money, bags = 100, 50000, { [284584] = 2, [284585] = 1, [284586] = 0 }
function GetTime() return now end
function GetMoney() return money end
C_Item = { GetItemCount = function(id) return bags[id] or 0 end }

-- Fires an event at the module (method name or the registered function).
function Fire(event)
    local h = P.events[event]
    if type(h) == "function" then h() else P[h](P) end
end
-- Runs the timers that are due (all of them: tests move time on themselves).
function RunTimers()
    local list = P.timers
    P.timers = {}
    for _, t in ipairs(list) do if not t.cancelled then P[t.method](P) end end
end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
g._load((ADDON / "Prices.lua").read_text(encoding="utf-8"), "Prices.lua")
g._load((ADDON / "Pouches.lua").read_text(encoding="utf-8"), "Pouches.lua")
lua.execute("P = ns.CH.Pouches; P:OnEnable()")

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def log(item):
    r = g.ns.CH.db["global"].pouches
    r = r and r[item]
    return (r.n, r.total, r.min, r.max) if r else None


def gold(copper):
    lua.execute(f"money = money + {copper}"); g.Fire("PLAYER_MONEY")


def bag(item, change=-1):
    lua.execute(f"bags[{item}] = bags[{item}] + {change}"); g.Fire("BAG_UPDATE_DELAYED")


def settle():
    lua.execute("now = now + 2")
    g.RunTimers()


def open_pouch(item, copper, bag_first=False):
    """Right-click a pouch: as seen in-game, no loot window; the gold and the bag change come at once."""
    if bag_first:
        bag(item); gold(copper)
    else:
        gold(copper); bag(item)
    settle()


open_pouch(284584, 3612)
check("pouch opened: gold recorded", log(284584) == (1, 3612, 3612, 3612), log(284584))
check("pouch opened: window told to redraw", g.messages == 1)

open_pouch(284584, 2950, bag_first=True)
check("bag change before the gold: still counts", log(284584) == (2, 6562, 2950, 3612), log(284584))

gold(500); settle()
check("gold with no pouch gone (looting, a quest): nothing recorded", log(284584)[0] == 2 and log(284585) is None)

bag(284585); settle()
check("pouch gone with no gold (deleted, mailed): nothing recorded", log(284585) is None)
bag(284585, 1)

g.Fire("MERCHANT_SHOW")
open_pouch(284585, 7400)
g.Fire("MERCHANT_CLOSED")
bag(284585, 1); settle()
check("pouch sold at a merchant: nothing recorded", log(284585) is None, log(284585))

# Gold a moment after the pouch still pairs; much later it doesn't.
bag(284585); lua.execute("now = now + 0.3"); gold(7700); settle()
check("gold just after the pouch: counts", log(284585) == (1, 7700, 7700, 7700), log(284585))
lua.execute("bags[284585] = 1"); g.Fire("BAG_UPDATE_DELAYED"); settle()
bag(284585); lua.execute("now = now + 0.8"); gold(7000); settle()
check("gold long after the pouch: not that pouch's", log(284585)[0] == 1, log(284585))

# Two kinds of pouch gone at once: can't tell which gave what.
lua.execute("bags[284584] = 5; bags[284586] = 3"); g.Fire("BAG_UPDATE_DELAYED"); settle()
gold(9000)
lua.execute("bags[284584] = 4; bags[284586] = 2"); g.Fire("BAG_UPDATE_DELAYED")
settle()
check("two kinds gone at once: nothing recorded", log(284584)[0] == 2 and log(284586) is None)

# Too much gold for a pouch: something else paid out at the same moment.
bag(284586); gold(15179 * 30); settle()
check("far too much gold: not recorded", log(284586) is None)

# Opening pouches one after another, quicker than the pairing waits.
lua.execute("bags[284584] = 10"); g.Fire("BAG_UPDATE_DELAYED"); settle()
for copper, first in [(3000, False), (3100, True), (3200, False), (3300, True)]:
    if first:
        bag(284584); gold(copper)
    else:
        gold(copper); bag(284584)
    lua.execute("now = now + 0.4")
settle()
check("quick openings: every pouch with its own gold", log(284584) == (6, 6562 + 12600, 2950, 3612), log(284584))

g.ns.CH.Pouches.PrintStats(g.ns.CH.Pouches)
check("stats printed", len(g.printed) == 5 and "Journeyman pouch" in g.printed[1] and "6 opened" in g.printed[1],
      list(g.printed.values()))
check("stats: total from every pouch", "7 pouches opened" in g.printed[4] and "in all" in g.printed[4],
      g.printed[4])
t = g.ns.Prices.PouchTotals()
check("pouch totals", t.opened == 7 and t.total == 26862, (t.opened, t.total))

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
