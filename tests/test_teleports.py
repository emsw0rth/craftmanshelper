"""Tests for Teleports.lua (which teleports the route planner may use), in Lua 5.1.

    pip install lupa
    python tests/test_teleports.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
ns = {}
CH = { db = { global = {}, profile = { useTeleports = true, useMoonglade = true, useEngineering = false } } }
function CH:NewModule(name) local m = {}; self[name] = m; return m end
ns.CH = CH
known, items, cooldowns, itemCooldowns = {}, {}, {}, {}
now = 1000
function GetTime() return now end
function IsPlayerSpell(id) return known[id] == true end
C_Item = { GetItemCount = function(id) return items[id] or 0 end,
           GetItemNameByID = function(id) return nil end }
C_Spell = { GetSpellCooldown = function(id) local c = cooldowns[id] or { 0, 0 }
                                             return { startTime = c[1], duration = c[2] } end,
            GetSpellName = function(id) return nil end }
C_Container = { GetItemCooldown = function(id) local c = itemCooldowns[id] or { 0, 0 } return c[1], c[2] end }
timers = {}
C_Timer = { After = function(s, f) table.insert(timers, f) end }
function ns.ResolveZone(map) return map end
playerMap, playerX, playerY = 1, 0.5, 0.5
C_Map = { GetBestMapForUnit = function() return playerMap end,
          GetPlayerMapPosition = function() return { GetXY = function() return playerX, playerY end } end }
function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end
function keylist(list) local out = {} for _, o in ipairs(list) do table.insert(out, o.key) end return table.concat(out, ",") end
""")
g = lua.globals()
g._load((ADDON / "Teleports.lua").read_text(encoding="utf-8"), "Teleports.lua")
TP = g.CH.Teleports

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def anywhere(mage=None):
    lst, runes = TP.Anywhere(TP, mage) if mage is not None else TP.Anywhere(TP)
    return g.keylist(lst), runes


check("nothing known: none", anywhere() == ("", 0))

# A Horde mage: Orgrimmar and Undercity known.
lua.execute("known[3567] = true; known[3563] = true")
check("mage without runes: none", anywhere()[0] == "")
lua.execute("items[17031] = 4")
check("mage with runes: the known teleports", anywhere() == ("ORGRIMMAR,UNDERCITY", 4), anywhere())
lst, _ = TP.Anywhere(TP)
check("mage: directions and rune", lst[1].text == "Teleport to Orgrimmar" and lst[1].rune is True, lst[1].text)
check("mage: left out when asked", anywhere(False)[0] == "")
lua.execute("CH.db.profile.useTeleports = false")
check("mage: turned off", anywhere()[0] == "")
lua.execute("CH.db.profile.useTeleports = true; known = {}")

# A druid.
lua.execute("known[18960] = true")
lst, _ = TP.Anywhere(TP)
check("druid: Moonglade", g.keylist(lst) == "MOONGLADE" and lst[1].text == "Cast Teleport: Moonglade" and lst[1].rune is None,
      g.keylist(lst))
lua.execute("cooldowns[18960] = { 990, 300 }")
check("druid: not while on cooldown", anywhere()[0] == "")
lua.execute("cooldowns[18960] = { 999, 1.5 }")
check("druid: the global cooldown doesn't count", anywhere()[0] == "MOONGLADE")
lua.execute("CH.db.profile.useMoonglade = false")
check("druid: turned off", anywhere()[0] == "")
lua.execute("CH.db.profile.useMoonglade = true; known = {}")

# Engineering transporters: off by default.
lua.execute("items[18986] = 1")
check("transporter: off by default", g.keylist(TP.Once(TP)) == "")
check("transporter: Has device", TP.Has(TP, "device") is True and TP.Has(TP, "mage") is False)
lua.execute("CH.db.profile.useEngineering = true")
lst = TP.Once(TP)
check("transporter: on", g.keylist(lst) == "GADGETZAN" and lst[1].readyIn == 0 and lst[1].kind == "device",
      g.keylist(lst))
check("transporter: directions", lst[1].text == "Use your Ultrasafe Transporter: Gadgetzan", lst[1].text)
lua.execute("itemCooldowns[18986] = { 900, 14400 }")
check("transporter: cooldown left", abs(TP.Once(TP)[1].readyIn - (900 + 14400 - 1000)) < 1e-6, TP.Once(TP)[1].readyIn)
check("transporters aren't usable from anywhere", anywhere()[0] == "")

# Recording where you land: only on the destination's own map.
t = None
for i in range(1, len(TP.LIST) + 1):
    if TP.LIST[i].key == "ORGRIMMAR":
        t = TP.LIST[i]
check("default spot", tuple(TP.Spot(TP, t)) == (1454, 45.1, 63.9), tuple(TP.Spot(TP, t)))
lua.execute("playerMap, playerX, playerY = 1440, 0.1, 0.1")
TP.Record(TP, t, 0)
check("misfire elsewhere: not recorded", g.CH.db["global"].teleportSpots is None)
lua.execute("playerMap, playerX, playerY = 1454, 0.40, 0.70")
TP.Record(TP, t, 0)
m, x, y = TP.Spot(TP, t)
check("recorded on arrival", m == 1454 and abs(x - 40) < 1e-9 and abs(y - 70) < 1e-9, (m, x, y))

print()
print("All passed" if failures == 0 else f"{failures} test(s) failed")
sys.exit(1 if failures else 0)
