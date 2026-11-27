"""Tests for Crates.lua (Waylaid Crate costs per Merchant's Favor) and Data/Crates.lua, in Lua 5.1.

    pip install lupa
    python tests/test_crates.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
ns = {}
prices, counts, bankCounts = {}, {}, {}
cashback, rank, faction = true, 0, "Horde"
ns.DIPLOMAT_STEP = 0.02
ns.DiplomatRank = function() return rank end
ns.Prices = {
    GetItemPrice = function(id) if prices[id] then return prices[id], 1 end end,
    CashbackOn = function() return cashback end,
    RepPerGold = function(rep, net) if net <= 0 then return math.huge end return rep / (net / 10000) end,
}
C_Item = { GetItemCount = function(id, bank) return (counts[id] or 0) + (bank and (bankCounts[id] or 0) or 0) end }
C_CurrencyInfo = { GetCurrencyInfo = function(id) if id == 3402 then return { quantity = 42 } end end }
UnitFactionGroup = function() return faction end
function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end
""")
g = lua.globals()
g._load((ADDON / "Data" / "Crates.lua").read_text(encoding="utf-8"), "Data/Crates.lua")
g._load((ADDON / "Crates.lua").read_text(encoding="utf-8"), "Crates.lua")
ns, K = g.ns, g.ns.CrateCalc

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


# Data
crates = {int(k): v for k, v in ns.Crates.items()}
check("30 crates", len(crates) == 30, len(crates))
check("every crate has bundles with item IDs and counts", all(
    len(c.bundles) >= 2 and all(b[1] > 0 and b[2] > 0 and b[3] for b in c.bundles.values()) for c in crates.values()))
check("levels 1-4", sorted({c.level for c in crates.values()}) == [1, 2, 3, 4])
crafted = sorted(c.name for c in crates.values() if c.crafted)
check("crafted = Fabrics, Ingots, Parts", all(any(k in n for k in ("Fabrics", "Ingots", "Parts")) for n in crafted)
      and len(crafted) == 12, crafted)

# Favor and silver
check("Favor: Apprentice Herbs 5, Artisan Parts 40", K.Favor(248682) == 5 and K.Favor(248713) == 40)
check("Favor: Expert Ore 15, Journeyman Ingots 20", K.Favor(248692) == 15 and K.Favor(248706) == 20)
check("silver: Apprentice Herbs 2.5s, Artisan Parts 20s", K.Silver(248682) == 250 and K.Silver(248713) == 2000)

# Expert Ore: 10 Gold Ore (2776) or 20 Mithril Ore (3858)
check("no prices: no cost", K.Estimate(248692).cost is None)
g.prices[2776] = 3000   # 10 gold ore = 3g
g.prices[3858] = 1000   # 20 mithril = 2g
e = K.Estimate(248692)
check("cheapest bundle first", e.best.itemID == 3858 and e.bundles[1].itemID == 3858 and e.bundles[2].itemID == 2776)
check("crate missing: cost is the fill only", e.cost == 20000 and e.crateMissing)
check("net and per Favor", e.net == 20000 - 750 and abs(e.perFavor - (19250 / 15)) < 1e-9, (e.net, e.perFavor))
g.prices[248692] = 5000
e = K.Estimate(248692)
check("with the crate's price", e.cost == 25000 and not e.crateMissing and abs(e.perFavor - 24250 / 15) < 1e-9)
g.cashback = False
e = K.Estimate(248692)
check("cashback off: no silver", e.silver == 0 and e.net == 25000)
g.cashback = True
check("an unpriced bundle goes last", K.Estimate(248682).best is None)

# Best per Favor ignores crates without their own price; the cheapest empty crate.
g.prices[248682] = 100          # Apprentice Herbs crate 1s
g.prices[2447] = 50             # 20 Peacebloom = 10s -> (100 + 1000 - 250) / 5 = 170 per Favor
g.prices[248706] = 2000         # Journeyman Ingots crate; no bar prices
lst = K.List()
best = K.BestPerFavor(lst)
check("best per Favor", best.crateID == 248682 and abs(best.perFavor - 170) < 1e-9, (best.crateID, best.perFavor))
empty = K.CheapestEmpty(lst)
check("cheapest empty crate", empty.crateID == 248682 and empty.price == 100)

# Receipt: 15 Favor at 170 + an empty crate of 100, less 1s silver, for 50 rep.
r = K.Receipt(lst)
check("receipt cost", abs(r.cost - (15 * 170 + 100)) < 1e-9 and abs(r.net - (2550 + 100 - 100)) < 1e-9, (r.cost, r.net))
check("receipt rep 50", r.rep == 50 and abs(r.repPerGold - 50 / (2550 / 10000)) < 1e-9)
g.rank = 5
check("receipt rep with Diplomat 5 = 55", K.Receipt(lst).rep == 55)

# Owned crates and fill
g.counts[248692] = 1
g.bankCounts[248692] = 2
o = K.Owned(248692)
check("bags and bank", o.bags == 1 and o.bank == 2 and o.fill is None)
g.counts[3858] = 25
o = K.Owned(248692)
check("can fill from bags", o.fill.itemID == 3858 and o.fill.count == 20)
check("Favor balance", K.FavorBalance() == 42)
check("hand-in by faction", K.HandIn().name == "Dokimi")
g.faction = "Alliance"
check("hand-in Alliance", K.HandIn().name == "Marcy Baker")

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
