"""Tests for RecipeMarks.lua (writ icons on trainer and profession recipes) with stubbed frames, in Lua 5.1.

    pip install lupa
    python tests/test_recipemarks.py
"""
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parent.parent / "CraftmansHelper"

STUBS = r"""
ns = { Writs = {
    [264012] = { quest = 94212, tier = "JOURNEYMAN", item = 3383, count = 1, name = "Elixir of Wisdom" },
    [264037] = { quest = 94237, tier = "JOURNEYMAN", item = 8069, count = 200, name = "Crafted Solid Shot" },
} }
ns.WritsByItem = { [3383] = { 264012 }, [8069] = { 264037 } }
ns.CH = { db = { profile = {} } }
crafted = {}
ns.CH.Tooltips = { AddCraftLines = function(tt, itemID, fresh)
    if not ns.WritsByItem[itemID] then return false end
    table.insert(crafted, { tt = tt, item = itemID, fresh = fresh }); return true end }
function ns.CH:NewModule() return {} end

-- Frames: just enough to see what the marker does.
function CreateFrame(kind, name, parent)
    local f = { shown = true, points = {}, parent = parent, scripts = {} }
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level or 1 end
    function f:CreateTexture() local t = {}; function t:SetAllPoints() end; function t:SetTexture(x) self.file = x end; return t end
    function f:EnableMouse() end
    function f:SetPropagateMouseClicks(v) self.propagate = v end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) table.insert(self.points, { ... }) end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    return f
end
function Label(width, room)
    return { GetStringWidth = function() return width end, GetWidth = function() return room end }
end
function Row(id, label) local r = CreateFrame("Button"); r.name = label; r.Label = label; r.GetID = function() return id end; return r end

services = {
    [1] = { "Alchemy", "header" },
    [2] = { "Elixir of Wisdom", "available", "|cffffffff|Hitem:3383::::::::|h[Elixir of Wisdom]|h|r" },
    [3] = { "Minor Healing Potion", "available", "|cffffffff|Hitem:118::::::::|h[Minor Healing Potion]|h|r" },
    [4] = { "Crafted Solid Shot", "unavailable", nil },   -- no link: found by name
}
function GetTrainerServiceInfo(i) local s = services[i]; return s and s[1], s and s[2] end
function GetTrainerServiceItemLink(i) local s = services[i]; return s and s[3] end
schematics = { [101] = 3383, [102] = 118 }
C_TradeSkillUI = { GetRecipeSchematic = function(id) if schematics[id] then return { outputItemID = schematics[id] } end end }

-- Scroll boxes: remember the row callback so tests can run it.
rowCallbacks = {}
ScrollUtil = { AddInitializedFrameCallback = function(box, cb, owner, existing) rowCallbacks[box] = cb end }
loaded = {}
EventUtil = { ContinueOnAddOnLoaded = function(name, fn) loaded[name] = fn end }
hooks = {}
function hooksecurefunc(a, b, c) if type(a) == "table" then hooks[b] = c else hooks[a] = b end end
GameTooltip = { SetTrainerService = function() end, SetOwner = function() end, Hide = function() end,
                Show = function(self) self.shown = true end }
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
lua.execute("function _load(src, name) local f = assert(loadstring(src, name)); f('CraftmansHelper', ns) end")
g._load((ADDON / "RecipeMarks.lua").read_text(encoding="utf-8"), "RecipeMarks.lua")
M = g.ns.CH.RecipeMarks

failures = 0


def check(name, cond, detail=""):
    global failures
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    failures += 0 if cond else 1


check("trainer: recipe for a writ item", M.TrainerItem(2) == 3383)
check("trainer: recipe for another item", M.TrainerItem(3) is None)
check("trainer: no link, found by name", M.TrainerItem(4) == 8069)
check("recipe: schematic output is a writ item", M.RecipeItem(101) == 3383)
check("recipe: schematic output isn't", M.RecipeItem(102, "Elixir of Wisdom") is None)
check("recipe: no schematic, found by name", M.RecipeItem(999, "crafted solid shot") == 8069)

# Hooks wait for Blizzard's windows to load.
lua.execute("M = ns.CH.RecipeMarks; M:OnEnable()")
check("trainer tooltip hooked", g.hooks["SetTrainerService"] is not None)
lua.execute("""ClassTrainerFrame = { ScrollBox = {} }
ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = {} } } }
loaded.Blizzard_TrainerUI(); loaded.Blizzard_Professions()""")
check("trainer rows hooked", g.rowCallbacks[g.ClassTrainerFrame.ScrollBox] is not None and M.trainerHooked)
check("profession rows hooked", g.rowCallbacks[g.ProfessionsFrame.CraftingPage.RecipeList.ScrollBox] is not None
      and M.professionsHooked)

# Trainer rows, as the list fills them in.
lua.execute("""row = Row(0, Label(90, 200))
rowCallbacks[ClassTrainerFrame.ScrollBox](nil, row, { skillIndex = 2 })""")
m = g.row.craftmansHelperMark
check("trainer row: marker shown", m is not None and m.shown and m.itemID == 3383)
check("marker sits after the name", m.points[1][4] == 93, list(m.points[1].values()))
check("marker passes clicks to the row", m.propagate is True)
m.scripts.OnEnter(m)
check("marker tooltip: writ lines on a fresh tooltip", g.crafted[1].item == 3383 and g.crafted[1].fresh is True)
lua.execute("rowCallbacks[ClassTrainerFrame.ScrollBox](nil, row, { skillIndex = 3 })")
check("reused row for another recipe: marker hidden", not g.row.craftmansHelperMark.shown)
lua.execute("rowCallbacks[ClassTrainerFrame.ScrollBox](nil, row, { skillIndex = 1 })")
check("header row: no marker", not g.row.craftmansHelperMark.shown)
lua.execute("row2 = Row(4, Label(300, 200)); rowCallbacks[ClassTrainerFrame.ScrollBox](nil, row2, {})")
check("row index from GetID; long names capped at the label width",
      g.row2.craftmansHelperMark.shown and g.row2.craftmansHelperMark.points[1][4] == 203)

# Profession rows: tree nodes with recipe info (categories have none).
lua.execute("""prow = Row(0, Label(50, 150))
node = function(data) return { GetData = function() return data end } end
rowCallbacks[ProfessionsFrame.CraftingPage.RecipeList.ScrollBox](nil, prow, node({ recipeInfo = { recipeID = 101, name = "Elixir of Wisdom" } }))""")
check("profession row: marker shown", g.prow.craftmansHelperMark.shown and g.prow.craftmansHelperMark.itemID == 3383)
lua.execute("rowCallbacks[ProfessionsFrame.CraftingPage.RecipeList.ScrollBox](nil, prow, node({ categoryInfo = {} }))")
check("category row: marker hidden", not g.prow.craftmansHelperMark.shown)
lua.execute("""prow.Count = { IsShown = function() return true end, GetText = function() return " [3]" end,
                             GetStringWidth = function() return 20 end }
rowCallbacks[ProfessionsFrame.CraftingPage.RecipeList.ScrollBox](nil, prow, node({ recipeInfo = { recipeID = 101, name = "Elixir of Wisdom" } }))""")
pt = g.prow.craftmansHelperMark.points
last = pt[len(pt)]
check("craftable count shown: marker after the count", lua.eval("function(p) return p[2] == prow.Count end")(last) and last[4] == 23, (last[2], last[4]))
lua.execute("""prow.Count.GetText = function() return "" end
rowCallbacks[ProfessionsFrame.CraftingPage.RecipeList.ScrollBox](nil, prow, node({ recipeInfo = { recipeID = 101, name = "Elixir of Wisdom" } }))""")
pt = g.prow.craftmansHelperMark.points
last = pt[len(pt)]
check("no count: marker after the name", lua.eval("function(p) return p[2] == prow.Label end")(last) and last[4] == 53, (last[4],))

# Trainer tooltip lines.
lua.execute("crafted = {}; GameTooltip.shown = false; hooks.SetTrainerService(GameTooltip, 2)")
check("trainer tooltip: writ lines added", len(g.crafted) == 1 and g.crafted[1].fresh is None and g.GameTooltip.shown)
lua.execute("crafted = {}; hooks.SetTrainerService(GameTooltip, 3)")
check("trainer tooltip: nothing for other recipes", len(g.crafted) == 0)

# Setting off.
lua.execute("ns.CH.db.profile.markRecipes = false; crafted = {}")
lua.execute("rowCallbacks[ClassTrainerFrame.ScrollBox](nil, row, { skillIndex = 2 })")
check("setting off: no marker", not g.row.craftmansHelperMark.shown)
lua.execute("hooks.SetTrainerService(GameTooltip, 2)")
check("setting off: no trainer tooltip lines", len(g.crafted) == 0)
lua.execute("""ns.CH.db.profile.markRecipes = true
ClassTrainerFrame.ScrollBox.ForEachFrame = function(self, fn) fn(row, { skillIndex = 2 }) end
M:Refresh()""")
check("refresh after turning it back on", g.row.craftmansHelperMark.shown)

print(f"\n{'FAILED' if failures else 'All passed'} ({failures} failure(s))")
sys.exit(1 if failures else 0)
