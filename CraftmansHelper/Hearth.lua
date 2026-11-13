-- Where your Hearthstone takes you, for the route planner.
--
-- The game only gives the bind location's name (GetBindLocation), not a position,
-- so the spot is recorded per character: where you stand when you bind
-- (HEARTHSTONE_BOUND, next to the innkeeper), and where you arrive after using the
-- Hearthstone. A recorded spot is only trusted while the bind name still matches.
local _, ns = ...
local CH = ns.CH

local Hearth = CH:NewModule("Hearth", "AceEvent-3.0")
CH.Hearth = Hearth

local HEARTHSTONE_ITEM = 6948
local HEARTHSTONE_SPELL = 8690
local ARRIVAL_DELAY = 3 -- seconds after the cast before your position is the inn

local function PlayerSpot()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return map, x * 100, y * 100
end

function Hearth:Record(why)
    local name = GetBindLocation and GetBindLocation()
    local map, x, y = PlayerSpot()
    if not (name and map) then return end
    local old = CH.db.char.hearth
    CH.db.char.hearth = { name = name, map = map, x = x, y = y }
    if not (old and old.name == name) then
        CH:Print(string.format("Hearthstone location learned (%s) for route planning.", name))
    end
end

-- The recorded inn if it still matches your bind location, else nil.
function Hearth:GetSpot()
    local h = CH.db.char.hearth
    local name = GetBindLocation and GetBindLocation()
    if h and h.map and name and h.name == name then return h end
end

-- Seconds until the Hearthstone can be used (0 when ready), or nil without one in your bags.
function Hearth:ReadyIn()
    local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE_ITEM) or 0
    if count == 0 then return nil end
    local getCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getCooldown then return 0 end
    local start, duration = getCooldown(HEARTHSTONE_ITEM)
    if not (start and duration) or start == 0 or duration <= 1.5 then return 0 end -- 1.5: global cooldown
    return math.max(0, start + duration - GetTime())
end

-- What the route planner needs: { name, map, x, y, readyIn } or nil when the
-- Hearthstone can't be used (not in bags, location unknown, or turned off).
function Hearth:GetOption()
    if not CH.db.profile.useHearth then return nil end
    local spot = self:GetSpot()
    local readyIn = self:ReadyIn()
    if not (spot and readyIn) then return nil end
    return { name = spot.name, map = spot.map, x = spot.x, y = spot.y, readyIn = readyIn }
end

function Hearth:OnSpellcast(_, unit, _, spellID)
    if unit == "player" and spellID == HEARTHSTONE_SPELL then
        C_Timer.After(ARRIVAL_DELAY, function() self:Record("arrived") end)
    end
end

function Hearth:OnEnable()
    self:RegisterEvent("HEARTHSTONE_BOUND", function() self:Record("bound") end)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcast")
end
