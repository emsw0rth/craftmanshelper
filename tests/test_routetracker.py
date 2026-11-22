"""Tests for UI/RouteTracker.lua's writ buttons (start a writ's quest from the tracker) with stubbed
frames, in Lua 5.1.

    pip install lupa
    python tests/test_routetracker.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = { STATUS = { READY = "ready", ACTIVE = "active", INBAGS = "inbags", AVAILABLE = "available", DONE = "done" },
       MSG_ROUTE = "route", MSG_UPDATED = "updated" }
ns.Writs = { [1] = { name = "Writ One" }, [2] = { name = "Writ Two" }, [3] = { name = "Writ Three" } }
states = {
    [1] = { status = "inbags", writsInBags = 1 },
    [2] = { status = "active", writsInBags = 0 },
    [3] = { status = "inbags", writsInBags = 1 },
}
printed = {}
ns.CH = { db = { profile = { tracker = { shown = true } } },
          Tracker = { GetState = function(_, id) return states[id] end } }
function ns.CH:Print(msg) table.insert(printed, msg) end
function ns.CH:NewModule()
    local m = { events = {} }
    function m:RegisterMessage(k, h) self.events[k] = h end
    function m:RegisterEvent(k, h) self.events[k] = h end
    return m
end
stop = { name = "Bera", writs = { 1, 2, 3 }, x = 1, y = 2, index = 1 }
ns.CH.Route = { route = { stops = { stop } } }
function ns.CH.Route:IsActive() return true end
function ns.CH.Route:GetCurrent() return stop end
function ns.CH.Route:GetUpcoming() return { { kind = "stop", stop = stop, text = "Bera" } } end

combat = false
function InCombatLockdown() return combat end
quests = 10
C_QuestLog = { GetNumQuestLogEntries = function() return quests + 3, quests end }
C_Item = { GetItemIconByID = function(id) return "icon" .. id end }
now = 0
function GetTime() return now end
UIParent = {}

-- Frames: any capitalised method not defined here does nothing.
local noop = function() end
local Frame = {}
Frame.__index = function(t, k) if Frame[k] then return Frame[k] end if k:match("^%u") then return noop end end
function Frame:SetAttribute(k, v) if combat and self.secure then error("blocked in combat") end self.attrs[k] = v end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:Show() if combat and self.secure then error("blocked in combat") end self.shown = true end
function Frame:Hide() if combat and self.secure then error("blocked in combat") end self.shown = false end
function Frame:SetShown(v) self.shown = v end
function Frame:SetHeight(h) self.height = h end
function Frame:SetEnabled(v) self.enabled = v end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn) self.hooks[k] = fn end
function Frame:CreateFontString() return setmetatable({ attrs = {}, scripts = {}, hooks = {}, region = true }, Frame) end
function Frame:CreateTexture()
    local t = setmetatable({ attrs = {}, scripts = {}, hooks = {}, region = true }, Frame)
    function t:SetTexture(x) self.file = x end
    function t:SetDesaturated(v) self.grey = v end
    return t
end
function Frame:SetText(t) self.text = t end
-- Like the game: a secure button can't be anchored to a font string or texture.
function Frame:SetPoint(point, rel, ...)
    if self.secure and type(rel) == "table" and rel.region then error("Cannot anchor protected frames to regions") end
    self.points = self.points or {}
    table.insert(self.points, { point, rel, ... })
end
function Frame:ClearAllPoints() self.points = {} end
frames = {}
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ attrs = {}, scripts = {}, hooks = {}, parent = parent, shown = true,
                             secure = template == "SecureActionButtonTemplate" }, Frame)
    if name then frames[name] = f end
    return f
end
GameTooltip = setmetatable({ lines = {} }, { __index = function(t, k) return noop end })
function GameTooltip:AddLine(l) table.insert(self.lines, l) end
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
g._load((ADDON / "UI" / "RouteTracker.lua").read_text(encoding="utf-8"), "RouteTracker.lua")
lua.execute("T = ns.CH.RouteTracker; T:OnEnable()")
T = g.T

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


def button(i):
    return g.frames[f"CraftmansHelperWritButton{i}"]


bind = g.frames["CraftmansHelperStartWrit"]
st = T.Startable(g.stop)
check("startable: unstarted writs in your bags, in stop order", list(st.values()) == [1, 3], list(st.values()))
check("binding names set", g.BINDING_HEADER_CRAFTMANSHELPER == "Craftman's Helper"
      and g["BINDING_NAME_CLICK CraftmansHelperStartWrit:LeftButton"] == "Start the next writ")

T.Refresh(T)
b1, b2 = button(1), button(2)
check("button per writ", b1.shown and b2.shown and not button(3).shown)
check("button uses the writ", b1.attrs["type"] == "item" and b1.attrs["item"] == "item:1"
      and b2.attrs["item"] == "item:3", (b1.attrs["item"], b2.attrs["item"]))
check("button shows the writ's icon", b1.icon.file == "icon1" and not b1.icon.grey)
check("first button placed on the tracker frame", lua.eval("function(b) return b.points[1][2] == T.frame end")(b1))
check("key binding starts the first writ", bind.attrs["item"] == "item:1")
h_with = T.frame.height

# Quest log full: greyed out, the binding does nothing.
lua.execute("quests = 40")
T.Refresh(T)
check("quest log full: buttons greyed out", b1.icon.grey and b1.enabled is False)
check("quest log full: binding does nothing", bind.attrs["type"] is None and bind.attrs["item"] is None)
lua.execute("GameTooltip.lines = {}")
b1.scripts["OnEnter"](b1)
check("quest log full: tooltip says so", "Quest log full (40/40)." in list(g.GameTooltip.lines.values()),
      list(g.GameTooltip.lines.values()))
bind.hooks["OnClick"](bind, "LeftButton", True)
check("binding with a full log: says so", g.printed[1] == "Your quest log is full (40/40).", g.printed[1])
lua.execute("quests = 10")

# A writ started: its button goes.
lua.execute("states[1].status = 'active'; states[1].writsInBags = 0")
T.Refresh(T)
check("started writ: button gone", b1.attrs["item"] == "item:3" and not b2.shown)
check("binding moves to the next writ", bind.attrs["item"] == "item:3")

# In combat nothing secure is touched; it catches up after.
lua.execute("combat = true; states[3].status = 'active'; states[3].writsInBags = 0")
ok = lua.eval("function() return pcall(function() T:Refresh() end) end")()
check("combat: no blocked actions", ok is True or (isinstance(ok, tuple) and ok[0] is True), ok)
check("combat: buttons left as they were", b1.attrs["item"] == "item:3" and T.pending)
lua.execute("combat = false")
T.OnCombatEnd(T)
check("after combat: caught up", not b1.shown and bind.attrs["item"] is None and not T.pending)
check("no writs to start: no button row", T.frame.height < h_with, (T.frame.height, h_with))

# The binding with nothing to start says why, once per press.
lua.execute("printed = {}; now = 100")
bind.hooks["OnClick"](bind, "LeftButton", True)
bind.hooks["OnClick"](bind, "LeftButton", False)
check("binding with nothing to start: says so once", len(g.printed) == 1
      and g.printed[1] == "No unstarted writs in your bags for the current stop.", list(g.printed.values()))

# Route over: buttons gone, binding cleared.
lua.execute("states[1].status = 'inbags'; states[1].writsInBags = 1")
T.Refresh(T)
check("writ back in bags: button again", b1.shown and bind.attrs["item"] == "item:1")
lua.execute("function ns.CH.Route:IsActive() return false end")
T.Refresh(T)
check("route over: tracker hidden, binding cleared", not T.frame.shown and bind.attrs["item"] is None)

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
