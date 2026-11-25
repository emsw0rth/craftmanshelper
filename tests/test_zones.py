"""Tests for Zones.lua's place filter (continent or zone), in Lua 5.1.

    pip install lupa
    python tests/test_zones.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("ns = {}; function _load(src) local f = assert(loadstring(src)); f('CraftmansHelper', ns) end")
g = lua.globals()
g._load((ADDON / "Zones.lua").read_text(encoding="utf-8"))
ns = g.ns

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


labels, order = ns.PlaceFilterList(lua.eval(
    "{ Wetlands = 1415, Ashenvale = 1414, Unknown = 0, Tanaris = 1414, ['Far Isle'] = 2999 }"))
order = list(order.values())
check("continents with their zones, Kalimdor first, unknown last",
      order == ["ALL", "CONT:1414", "Ashenvale", "Tanaris", "CONT:1415", "Wetlands", "CONT:2999", "Far Isle", "Unknown"],
      order)
check("labels", (labels["CONT:1414"], labels["CONT:1415"], labels["Tanaris"], labels["Unknown"])
      == ("Kalimdor", "Eastern Kingdoms", "    Tanaris", "Unknown"))
check("all", ns.MatchesPlace("ALL", "Tanaris", 1414) and ns.MatchesPlace("ALL", "Unknown", 0))
check("a continent takes all its zones", ns.MatchesPlace("CONT:1414", "Tanaris", 1414)
      and not ns.MatchesPlace("CONT:1414", "Wetlands", 1415) and not ns.MatchesPlace("CONT:1414", "Unknown", 0))
check("a zone takes only itself", ns.MatchesPlace("Tanaris", "Tanaris", 1414)
      and not ns.MatchesPlace("Tanaris", "Ashenvale", 1414))

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
