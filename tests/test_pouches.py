"""Tests for Pouches.lua (learning coin pouch gold from loot events), in Lua 5.1.

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
now, money, bags, loot = 100, 50000, { [284584] = 2, [284585] = 1, [284586] = 0 }, {}
function GetTime() return now end
function GetMoney() return money end
C_Item = { GetItemCount = function(id) return bags[id] or 0 end }
function GetNumLootItems() return #loot end
function GetLootSourceInfo(slot) return loot[slot] end

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


def open_pouch(item, copper, source="Item-1-0-ABC", drop_first=False):
    """Right-click a pouch: loot window, gold in, pouch gone, window closed."""
    lua.execute(f"loot = {{ '{source}' }}" if source else "loot = {}")
    if drop_first:
        lua.execute(f"bags[{item}] = bags[{item}] - 1"); g.Fire("BAG_UPDATE_DELAYED")
    g.Fire("LOOT_OPENED")
    lua.execute(f"money = money + {copper}"); g.Fire("PLAYER_MONEY")
    if not drop_first:
        lua.execute(f"bags[{item}] = bags[{item}] - 1"); g.Fire("BAG_UPDATE_DELAYED")
    g.Fire("LOOT_CLOSED")
    lua.execute("now = now + 3")
    g.RunTimers()


open_pouch(284584, 3612)
check("pouch opened: gold recorded", log(284584) == (1, 3612, 3612, 3612), log(284584))
check("pouch opened: window told to redraw", g.messages == 1)

open_pouch(284584, 2950, drop_first=True)
check("pouch gone before the loot window opened still counts", log(284584) == (2, 6562, 2950, 3612), log(284584))

# A creature's loot: not a pouch, even if a pouch leaves the bags at the same time.
open_pouch(284585, 7000, source="Creature-0-1-2-3-4-5")
check("creature loot: nothing recorded", log(284585) is None, log(284585))

# An item's loot (a clam, a lockbox) with no pouch leaving the bags.
lua.execute("loot = { 'Item-1-0-XYZ' }")
g.Fire("LOOT_OPENED")
lua.execute("money = money + 500"); g.Fire("PLAYER_MONEY")
g.Fire("LOOT_CLOSED"); lua.execute("now = now + 3"); g.RunTimers()
check("other container: nothing recorded", log(284584)[0] == 2 and log(284585) is None)

# Gold while the loot window is open at a vendor (selling) doesn't count.
g.Fire("MERCHANT_SHOW")
open_pouch(284586 if False else 284585, 7400)
g.Fire("MERCHANT_CLOSED")
check("at a vendor: nothing recorded", log(284585) is None, log(284585))

# A pouch window with no gold (empty pouch, or the money came later than we wait).
lua.execute("loot = { 'Item-1-0-ABC' }; bags[284585] = bags[284585] + 1"); g.Fire("BAG_UPDATE_DELAYED")
g.Fire("LOOT_OPENED")
lua.execute("bags[284585] = bags[284585] - 1"); g.Fire("BAG_UPDATE_DELAYED")
g.Fire("LOOT_CLOSED"); lua.execute("now = now + 3"); g.RunTimers()
check("no gold: nothing recorded", log(284585) is None)

# Expert pouch, game not saying where the loot is from.
lua.execute("bags[284585] = 1"); g.Fire("BAG_UPDATE_DELAYED")
lua.execute("now = now + 60")  # the earlier unclaimed drop is old by now
open_pouch(284585, 7700, source=None)
check("loot source unknown: still counts with a pouch gone", log(284585) == (1, 7700, 7700, 7700), log(284585))

# Two pouches gone at once: can't tell which gave what.
lua.execute("bags[284584] = 5; bags[284586] = 3"); g.Fire("BAG_UPDATE_DELAYED")
lua.execute("now = now + 60; loot = { 'Item-1-0-ABC' }")
g.Fire("LOOT_OPENED")
lua.execute("money = money + 9000"); g.Fire("PLAYER_MONEY")
lua.execute("bags[284584] = 4; bags[284586] = 2"); g.Fire("BAG_UPDATE_DELAYED")
g.Fire("LOOT_CLOSED"); lua.execute("now = now + 3"); g.RunTimers()
check("two pouches gone at once: nothing recorded", log(284584)[0] == 2 and log(284586) is None)

# Opening pouches one after another, each window before the last one settled.
lua.execute("now = now + 60; bags[284584] = 10"); g.Fire("BAG_UPDATE_DELAYED")
lua.execute("now = now + 60")
for i, (copper, first) in enumerate([(3000, False), (3100, True), (3200, False), (3300, True)]):
    lua.execute("loot = { 'Item-1-0-ABC' }")
    if first:  # this pouch leaves the bags in the same moment its window opens
        lua.execute("bags[284584] = bags[284584] - 1"); g.Fire("BAG_UPDATE_DELAYED")
    g.Fire("LOOT_OPENED")
    lua.execute(f"money = money + {copper}"); g.Fire("PLAYER_MONEY")
    if not first:
        lua.execute("bags[284584] = bags[284584] - 1"); g.Fire("BAG_UPDATE_DELAYED")
    g.Fire("LOOT_CLOSED")
    lua.execute("now = now + 0.5")
lua.execute("now = now + 3")
g.RunTimers()
check("quick openings: every pouch recorded", log(284584) == (6, 6562 + 12600, 2950, 3612), log(284584))

g.ns.CH.Pouches.PrintStats(g.ns.CH.Pouches)
check("stats printed", len(g.printed) == 5 and "Journeyman pouch" in g.printed[1] and "6 opened" in g.printed[1],
      list(g.printed.values()))
check("stats: total from every pouch", "7 pouches opened" in g.printed[4] and "in all" in g.printed[4],
      g.printed[4])
t = g.ns.Prices.PouchTotals()
check("pouch totals", t.opened == 7 and t.total == 26862, (t.opened, t.total))

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
