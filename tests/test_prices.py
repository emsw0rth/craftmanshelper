"""Tests for Prices.lua (Auctionator price estimates) against a stubbed Auctionator API, in Lua 5.1.

    pip install lupa
    python tests/test_prices.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = {}
ns.Writs = {
    [100] = { quest = 1000, tier = "JOURNEYMAN", item = 1, count = 1 },
    [200] = { quest = 2000, tier = "ARTISAN", item = 2, count = 4 },
    [300] = { quest = 3000, tier = "EXPERT", item = 3, count = 1 }, -- never seen on the AH
}
prices = { [1] = 14239, [2] = 2500 }
ages = { [1] = 0, [2] = 5 }
calls = {}
AuctionatorStub = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, id) table.insert(calls, caller); return prices[id] end,
    GetAuctionAgeByItemID = function(caller, id) return ages[id] end,
} } }
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
g._load((ADDON / "Prices.lua").read_text(encoding="utf-8"), "Prices.lua")
P = g.ns.Prices
fmt = g.ns.FormatMoney

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


# Money formatting
for copper, want in [(14239, "1g 42s 39c"), (4239, "42s 39c"), (5, "5c"), (0, "0c"),
                     (10000, "1g 0s 0c"), (100, "1s 0c"), (1234567, "123g 45s 67c"), (99.6, "1s 0c")]:
    got = fmt(copper)
    check(f"FormatMoney({copper})", got == want, f"got {got!r}")

# Without Auctionator
check("no Auctionator: unavailable", not P.IsAvailable())
check("no Auctionator: no estimate", P.GetWritEstimate(100) is None)

g.Auctionator = g.AuctionatorStub
check("Auctionator: available", P.IsAvailable())

e = P.GetWritEstimate(100)
check("journeyman cost", e.cost == 14239, e.cost)
check("journeyman rep", e.rep == 75, e.rep)
check("journeyman rep per gold", abs(e.repPerGold - 75 / 1.4239) < 1e-9, e.repPerGold)
check("fresh price age", e.age == 0, e.age)
check("callerID is the addon name", g.calls[1] == "CraftmansHelper", g.calls[1])

e = P.GetWritEstimate(200)
check("count multiplies cost", e.cost == 10000, e.cost)
check("artisan rep per gold", e.repPerGold == 200, e.repPerGold)
check("stale age reported", e.age == 5 and e.age > P.STALE_DAYS, e.age)

check("writ price off by default", not e.writIncluded and not e.writMissing)

# Including the writ's own price (writ 100 is on the AH, writ 200 isn't).
lua.execute("prices[100] = 5761; ages[100] = 7")
e = P.GetWritEstimate(100, True)
check("incl. writ: cost adds writ price", e.cost == 14239 + 5761, e.cost)
check("incl. writ: rep per gold uses total", e.repPerGold == 37.5, e.repPerGold)
check("incl. writ: flagged", e.writIncluded and not e.writMissing)
check("incl. writ: oldest age wins", e.age == 7, e.age)
e = P.GetWritEstimate(100, False)
check("excl. writ: cost unchanged", e.cost == 14239 and not e.writIncluded, e.cost)
e = P.GetWritEstimate(200, True)
check("writ without price: item cost only", e.cost == 10000, e.cost)
check("writ without price: flagged missing", e.writMissing and not e.writIncluded)
check("writ without price: item age kept", e.age == 5, e.age)

check("unknown item: no estimate", P.GetWritEstimate(300) is None)
check("unknown item, incl. writ: no estimate", P.GetWritEstimate(300, True) is None)
check("unknown writ: no estimate", P.GetWritEstimate(999) is None)

# Buy list: writ 100 (writ 5761 + item 14239 = 20000, 75 rep -> 37.5/g),
# writ 200 (writ 2000 + item 10000 = 12000, 200 rep -> 166.7/g), writ 300 (writ 1000, item unknown).
lua.execute("prices[100] = 5761; ages[100] = 7; prices[200] = 2000; prices[300] = 1000; prices[3] = nil")
e = P.GetWritBuyEstimate(300)
check("buy: item unknown keeps writ price", e.writPrice == 1000 and e.cost is None and e.repPerGold is None)
lua.execute("prices[400] = nil")
check("buy: writ without price is not buyable", P.GetWritBuyEstimate(100 + 900) is None)

ids = lambda lst: [lst[i].writID for i in range(1, len(lst) + 1)]
lst = P.GetBuyList("price")
check("buy list by price, unknown item last", ids(lst) == [200, 100, 300], ids(lst))
check("buy list total cost", lst[1].cost == 12000 and lst[2].cost == 20000, (lst[1].cost, lst[2].cost))
lua.execute("prices[200] = 12000")  # writ 200 now 22000 total, still best rep/g (90.9 vs 37.5)
lst = P.GetBuyList("price")
check("buy list re-sorts on new prices", ids(lst) == [100, 200, 300], ids(lst))
lst = P.GetBuyList("rep")
check("buy list by rep per gold", ids(lst) == [200, 100, 300], ids(lst))
lst = P.GetBuyList("price", lua.eval("function(id) return id ~= 100 end"))
check("buy list filter", ids(lst) == [200, 300], ids(lst))
lua.execute("prices[100] = nil; prices[200] = nil; prices[300] = nil")
check("buy list empty without writ prices", len(P.GetBuyList("price")) == 0)

# Auctionator erroring (e.g. database not ready) must not break the tooltip.
lua.execute("AuctionatorStub.API.v1.GetAuctionPriceByItemID = function() error('boom') end")
check("API error: no estimate", P.GetWritEstimate(100) is None)

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
