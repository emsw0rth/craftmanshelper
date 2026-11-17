"""Tests for Alts.lua (writs and writ items on your bank and other characters), in Lua 5.1.

    pip install lupa
    python tests/test_alts.py
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = { MSG_UPDATED = "MSG" }
ns.Writs = {
    [100] = { quest = 1000, item = 1, count = 1 },
    [200] = { quest = 2000, item = 2, count = 4 },
}
sent = 0
local Module = {}
function Module:RegisterBucketEvent() end
function Module:RegisterEvent() end
function Module:RegisterMessage() end
function Module:SendMessage() sent = sent + 1 end
ns.CH = { db = { global = {}, char = { completed = {} } } }
ns.STATUS = { READY = "ready", ACTIVE = "active", INBAGS = "inbags", AVAILABLE = "available", DONE = "done" }
ns.WritByQuest = { [1000] = 100, [2000] = 200 }
ns.TIER_REP = { JOURNEYMAN = 75, EXPERT = 125, ARTISAN = 200 }
ns.Writs[100].tier, ns.Writs[200].tier = "JOURNEYMAN", "ARTISAN"
ns.Writs[300] = { quest = 3000, item = 3, count = 1, tier = "EXPERT" }
ns.WritByQuest[3000] = 300
ns.UNKNOWN_CONTINENT = 0
function ns.ResolveZone(map) return map, "Zone" .. map, 1 end
function ns.DiplomatRank() return diplomat or 0 end
function ns.WritRep(id, rank)
    return math.floor(ns.TIER_REP[ns.Writs[id].tier] * (1 + 0.02 * (rank or ns.DiplomatRank())) + 1e-6)
end
logstates = {}
ns.CH.Tracker = {
    GetAllStates = function() return logstates end,
    GetTurnIn = function(_, id) return { name = "NPC" .. id, map = 1400 + id } end,
}
function ns.CH:NewModule(name) local m = setmetatable({}, { __index = Module }); return m end

player = { name = "Main", realm = "Realm", faction = "Alliance", class = "WARRIOR" }
bags, bank = {}, {}
C_Item = { GetItemCount = function(id, includeBank)
    local n = bags[id] or 0
    if includeBank then n = n + (bank[id] or 0) end
    return n
end }
function UnitName() return player.name, player.surname end
function GetRealmName() return player.realm end
function UnitFactionGroup() return player.faction end
function UnitClass() return player.class, player.class end
now = 1000
function GetServerTime() return now end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
g._load((ADDON / "Alts.lua").read_text(encoding="utf-8"), "Alts.lua")
A = g.ns.CH.Alts
chars = lambda: g.ns.CH.db["global"].characters

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def as_list(t):
    return [t[i] for i in range(1, len(t) + 1)]


def login(name, realm="Realm", faction="Alliance", cls="MAGE"):
    lua.execute(f"player = {{ name = '{name}', realm = '{realm}', faction = '{faction}', class = '{cls}' }}")
    lua.execute("bags, bank = {}, {}")
    A.bankOpened = None


# Main: one writ 100 in bags, two in the bank, 3 of item 2 in bags.
login("Main", cls="WARRIOR")
lua.execute("bags = { [100] = 1, [2] = 3 }; bank = { [100] = 2 }")
A.Snapshot(A)
main = chars()["Realm-Main"]
check("snapshot saved under Realm-Name", main is not None)
check("writ bags and bank counted", main.writs[100].b == 1 and main.writs[100].k == 2)
check("writ item counted", main["items"][2].b == 3)
check("nothing stored for items you don't have", main.writs[200] is None and main["items"][1] is None)
check("class saved", main["class"] == "WARRIOR")
check("InBank reads the snapshot", A.InBank(A, 100, "writs") == 2)

# Next login the bank isn't known yet (reads as empty): keep last time's bank.
lua.execute("bags = { [100] = 1 }; bank = {}")
A.Snapshot(A)
main = chars()["Realm-Main"]
check("unknown bank keeps saved bank counts", main.writs[100].k == 2 and main.writs[100].b == 1)
check("bags still updated", main["items"][2] is None)

# Once the bank has been opened this session, an empty bank is really empty.
A.bankOpened = True
A.Snapshot(A)
check("opened bank: empty bank clears counts", chars()["Realm-Main"].writs[100].k == 0)

# Alts
login("Bankalt")
lua.execute("bags = { [100] = 1 }; bank = { [100] = 1, [1] = 5 }")
A.Snapshot(A)
login("Zed")
lua.execute("bags = { [100] = 1 }")
A.Snapshot(A)
login("Hordie", faction="Horde")
lua.execute("bags = { [100] = 4 }")
A.Snapshot(A)
login("Faraway", realm="Other")
lua.execute("bags = { [100] = 4 }")
A.Snapshot(A)

login("Main", cls="WARRIOR")
holders = as_list(A.Holders(A, 100, "writs"))
names = [(h.name, h.count) for h in holders]
check("holders: same realm and faction only, sorted, bags+bank", names == [("Bankalt", 2), ("Zed", 1)], names)
check("holders exclude yourself", all(h.name != "Main" for h in holders))
items = [(h.name, h.count) for h in as_list(A.Holders(A, 1, "items"))]
check("item holders include banked items", items == [("Bankalt", 5)], items)
check("no holders", len(as_list(A.Holders(A, 200, "writs"))) == 0)
check("summary", A.Summary(A.Holders(A, 100, "writs")) == "Bankalt x2, Zed")

lst = as_list(A.List(A))
check("list has every character", len(lst) == 5, len(lst))
check("list marks this character", [c.name for c in lst if c.me] == ["Main"])
check("list sorted by realm then name", [c.name for c in lst][:2] == ["Faraway", "Bankalt"] or
      [c.realm for c in lst] == sorted(c.realm for c in lst))
check("list counts writs (bags+bank)", [c.writs for c in lst if c.name == "Bankalt"] == [2])

before = g.sent
A.Forget(A, "Realm-Zed")
check("forget removes the character", chars()["Realm-Zed"] is None)
check("forget announces the change", g.sent == before + 1)
check("forgotten alt no longer a holder", A.Summary(A.Holders(A, 100, "writs")) == "Bankalt x2")

# WoW Forever surnames: UnitName's second value. Older entries (no surname) are replaced.
chars()["Realm-Main"].writs[100].b = 7
lua.execute("player = { name = 'Main', surname = 'Stormhammer', realm = 'Realm', faction = 'Alliance', class = 'WARRIOR' }")
lua.execute("bags, bank = { [100] = 1 }, {}")
A.Snapshot(A)
check("key includes the surname", chars()["Realm-Main Stormhammer"] is not None)
check("entry saved without the surname is replaced", chars()["Realm-Main"] is None)
check("surname saved", chars()["Realm-Main Stormhammer"].surname == "Stormhammer")
check("full name is First Last", A.FullName(chars()["Realm-Main Stormhammer"]) == "Main Stormhammer")
check("you are not your own alt after the rename",
      all(h.name != "Main" for h in as_list(A.Holders(A, 100, "writs"))))
lua.execute("player = { name = 'Alt', surname = 'Realm', realm = 'Realm', faction = 'Alliance' }")
check("a realm in the surname slot is ignored", A.Me()[0] == "Realm-Alt")
lua.execute("player = { name = 'Main', surname = 'Stormhammer', realm = 'Realm', faction = 'Alliance', class = 'WARRIOR' }")

# Update only announces a change when the counts changed (each announcement redraws the window).
lua.execute("bags, bank = { [100] = 2 }, {}")
before = g.sent
A.Update(A)
A.Update(A)
check("update announces a change once", g.sent == before + 1, g.sent - before)
lua.execute("bags = { [100] = 3 }")
A.Update(A)
check("update announces a new count", g.sent == before + 2, g.sent - before)

# Quest log, done today, Diplomat: saved for My Writs' character sections.
login("Logger", cls="PRIEST")
lua.execute("""
    bags = { [300] = 1, [3] = 1 }; bank = { [200] = 1 }
    logstates = { [100] = { inLog = true, status = "ready" }, [300] = { inLog = false, status = "inbags" } }
    ns.CH.db.char.completed = { [2000] = now + 500 }
    diplomat = 5
""")
A.Snapshot(A)
c = chars()["Realm-Logger"]
check("quest log saved with ready state", c.log[100] is True and c.log[300] is None, (c.log[100], c.log[300]))
check("done today saved by writ", c.done[200] == 1500, c.done[200])
check("Diplomat rank saved", c.diplomat == 5)
lua.execute("diplomat = 0")

st = A.WritStates(c, True)
by = {x.id: x for x in st.values()}
check("alt states: log, bags; done-today bank writ left out", sorted(by) == [100, 300], sorted(by))
check("alt state: ready from the log", by[100].status == "ready")
check("alt state: unstarted writ in bags", by[300].status == "inbags" and not by[300].bankOnly)
check("alt state: item counted from bags and bank", by[300].have == 1 and by[300].need == 1)
check("alt state: turn-in and zone", by[300].turnIn.name == "NPC300" and by[300].zoneName == "Zone1700")
check("alt states without unstarted: log only", [x.id for x in A.WritStates(c, False).values()] == [100])
r = A.Rep(c, st)
check("alt rep uses the alt's Diplomat", r.count == 2 and r.rep == 82 + 137 and r.ready.count == 1 and r.ready.rep == 82,
      (r.count, r.rep, r.ready.rep))

lua.execute("now = 2000")  # past the reset: the writ done yesterday counts again
by = {x.id: x for x in A.WritStates(c, True).values()}
check("after the reset: bank writ listed, marked bank only", 200 in by and by[200].bankOnly is True)

# Others: this realm and faction, not you.
login("Logger", cls="PRIEST")
names = [o.entry.name for o in A.Others(A).values()]
check("others: same realm and faction, not you", "Logger" not in names and "Main" in names, names)
check("others: no other realm or faction", all(chars()[o.key].realm == "Realm" and chars()[o.key].faction == "Alliance"
                                               for o in A.Others(A).values()))

print("All passed" if failures == 0 else f"{failures} failure(s)", f"({failures} failure(s))")
raise SystemExit(1 if failures else 0)
