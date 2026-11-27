"""Tests for AHScan.lua (Auction House searches) and searched prices in Prices.lua, in Lua 5.1.

    pip install lupa
    python tests/test_ahscan.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
ns = {}
now = 1000000
function time() return now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Horde" end
sent, messages = {}, {}
CH = { db = { global = {}, profile = {} } }
function CH:NewModule(name) local m = {}; self[name] = m; return m end
function CH:SendMessage(msg, ...) table.insert(messages, { ... }) end
ns.CH = CH
ns.Writs = {}
auctionOpen, ready = true, true
AuctionHouseFrame = { IsShown = function() return auctionOpen end }
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function(key) table.insert(sent, key.itemID) end,
    IsThrottledMessageSystemReady = function() return ready end,
    GetNumCommoditySearchResults = function(id) return #(commodities[id] or {}) end,
    GetCommoditySearchResultInfo = function(id, i) return commodities[id][i] end,
    GetNumItemSearchResults = function(key) return #(items[key.itemID] or {}) end,
    GetItemSearchResultInfo = function(key, i) return items[key.itemID][i] end,
}
commodities, items = {}, {}
function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end
""")
g = lua.globals()
g._load((ADDON / "AHScan.lua").read_text(encoding="utf-8"), "AHScan.lua")
g._load((ADDON / "Prices.lua").read_text(encoding="utf-8"), "Prices.lua")
Scan, P = g.CH.AHScan, g.ns.Prices
# AceTimer and AceEvent stand-ins.
lua.execute("""
local S = CH.AHScan
function S:ScheduleTimer() return 1 end
function S:CancelTimer() end
function S:RegisterEvent() end
""")

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


# Summaries and costs
s = Scan.Summarize(lua.eval("{ { price = 300, count = 5 }, { price = 100, count = 2 }, { price = 300, count = 1 }, "
                            "{ price = 0, count = 9 }, { price = 200, count = 4 } }"))
check("lowest price", s.p == 100)
check("total listed (no zero prices)", s.q == 12)
check("levels merged and sorted", [tuple(l.values()) for l in s.l.values()] == [(100, 2), (200, 4), (300, 6)])
cost, got = Scan.CostFor(s, 5)
check("cost for 5 = 2x100 + 3x200", cost == 800 and got == 5, (cost, got))
cost, got = Scan.CostFor(s, 20)
check("too few listed", got == 12 and cost == 200 + 800 + 1800, (cost, got))
empty = Scan.Summarize(lua.eval("{}"))
check("nothing listed", empty.p is None and empty.q == 0)

# A search: commodity, then an item with no listings, then the AH closes.
lua.execute("""
commodities[10] = { { unitPrice = 150, quantity = 20 }, { unitPrice = 175, quantity = 5 } }
items[20] = {}
""")
Scan.Start(Scan, lua.eval("{ 10, 20, 10, 30 }"))
check("first search sent, duplicates dropped", list(g.sent.values()) == [10] and Scan.IsRunning(Scan))
Scan.ITEM_SEARCH_RESULTS_UPDATED(Scan, None, lua.eval("{ itemID = 99 }"))
check("other items' results are ignored", list(g.sent.values()) == [10])
Scan.COMMODITY_SEARCH_RESULTS_UPDATED(Scan, None, 10)
check("commodity stored", Scan.Get(10).p == 150 and Scan.Get(10).q == 25 and Scan.Get(10).t == 1000000)
check("next item searched", list(g.sent.values()) == [10, 20])
Scan.ITEM_SEARCH_RESULTS_UPDATED(Scan, None, lua.eval("{ itemID = 20 }"))
check("none listed is stored", Scan.Get(20).q == 0 and Scan.Get(20).p is None)
g.ready = False
Scan.Next(Scan)
check("waits while throttled", list(g.sent.values()) == [10, 20] or len(g.sent) == 3)
g.ready = True
Scan.AUCTION_HOUSE_THROTTLED_SYSTEM_READY(Scan)
check("continues when ready", list(g.sent.values()) == [10, 20, 30])
Scan.OnTimeout(Scan)
check("timeout moves on and finishes", not Scan.IsRunning(Scan) and Scan.Get(30) is None)
last = list(g.messages.values())[-1]
check("finished message", last[3] is True)

# Auctions are bought whole, buyouts only.
w = Scan.Summarize(lua.eval("{ { price = 6999, count = 7 }, { price = 6999, count = 1 }, { price = 7500, count = 1 }, "
                            "{ price = 3000, count = 4 } }"), True)
check("whole: cheapest buyout is the price", w.p == 3000 and w.w and w.q == 13)
check("whole: one auction each, cheapest first, bigger first on ties",
      [tuple(a.values()) for a in w.l.values()] == [(3000, 4), (6999, 7), (6999, 1), (7500, 1)])
cost, got = Scan.CostFor(w, 1)
check("whole: one costs the cheapest auction", cost == 3000 and got == 1)
cost, got = Scan.CostFor(w, 5)
check("whole: 5 = the 7-stack alone (cheaper than 4 + 1)", cost == 6999 and got == 5, (cost, got))
cost, got = Scan.CostFor(w, 8)
check("whole: 8 = cheapest combination (4 + 7)", cost == 3000 + 6999 and got == 8, (cost, got))
cost, got = Scan.CostFor(w, 20)
check("whole: too few listed buys them all", cost == 3000 + 6999 + 6999 + 7500 and got == 13, (cost, got))
lua.execute("""
items[60] = { { buyoutAmount = 6999, quantity = 7 }, { bidAmount = 100, quantity = 1 }, { buyoutAmount = 0, quantity = 1 } }
CH.db.global.scans["Realm - Horde"][70] = { p = 5, q = 1, l = { { 5, 1 } }, t = now }
""")
Scan.Start(Scan, lua.eval("{ 60 }"))
Scan.ITEM_SEARCH_RESULTS_UPDATED(Scan, None, lua.eval("{ itemID = 60 }"))
r = Scan.Get(60)
check("auction: whole buyout, not divided by the stack", r.p == 6999 and r.w)
check("auction: bid-only and no-buyout listings left out", r.q == 7)
check("old saved results are ignored", Scan.Get(70) is None)

# Searched prices as a price source
check("SCAN source available with data", P.ActiveSource() == "SCAN")
price, age = P.GetItemPrice(10)
check("searched price", price == 150 and age == 0)
check("none listed: no price", P.GetItemPrice(20) is None)
lua.execute("""
AuctionatorStub = { API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return ({ [10] = 999, [40] = 500 })[id] end,
    GetAuctionAgeByItemID = function(_, id) return ({ [10] = 2, [40] = 0 })[id] end,
} } }
Auctionator = AuctionatorStub
""")
check("Auctionator is the source", P.ActiveSource() == "AUCTIONATOR")
check("a newer search beats an older Auctionator price", P.GetItemPrice(10)[0] == 150)
check("Auctionator for items not searched", P.GetItemPrice(40)[0] == 500)
g.now = 1000000 + 3 * 86400
check("an older search loses", P.GetItemPrice(10)[0] == 999)
lua.execute("ns.CH.db.profile.priceSource = 'SCAN'")
check("only searches when chosen", P.GetItemPrice(40) is None and P.GetItemPrice(10)[0] == 150)

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
