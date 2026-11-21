-- Mage teleports for the route planner: Teleport: Stormwind, Ironforge, Darnassus,
-- Orgrimmar, Undercity and Thunder Bluff.
--
-- They have no cooldown, so a route may use them as often as it saves time; each cast
-- takes a Rune of Teleportation. Where each one lands starts as a spot by the city's
-- portal trainer and is replaced by where you actually arrive the first time you cast it
-- (shared by all characters: the arrival point is the same for everyone).
local _, ns = ...
local CH = ns.CH

local Teleports = CH:NewModule("Teleports", "AceEvent-3.0")
CH.Teleports = Teleports

Teleports.RUNE_ITEM = 17031       -- Rune of Teleportation
Teleports.NO_REAGENT_SPELL = 1225503 -- Legacy perk Reagent Economy: no reagents needed

local ARRIVAL_DELAY = 3 -- seconds after the cast before checking where you are
local ARRIVAL_TRIES = 5 -- loading screens can take a while

-- spellID -> where it takes you ({ map = uiMapID, x, y } in 0-100).
Teleports.DESTINATIONS = {
    [3561] = { name = "Stormwind", map = 1453, x = 38.6, y = 80.5 },
    [3562] = { name = "Ironforge", map = 1455, x = 25.5, y = 8.4 },
    [3565] = { name = "Darnassus", map = 1457, x = 43.5, y = 78.7 },
    [3567] = { name = "Orgrimmar", map = 1454, x = 38.6, y = 85.6 },
    [3563] = { name = "Undercity", map = 1458, x = 84.6, y = 16.3 },
    [3566] = { name = "Thunder Bluff", map = 1456, x = 22.4, y = 16.8 },
}

local function Known(spellID)
    local known = IsPlayerSpell or IsSpellKnown
    return known ~= nil and known(spellID) == true
end

local function Learned()
    local global = CH.db and CH.db.global
    if not global then return {} end
    global.teleports = global.teleports or {}
    return global.teleports
end

-- How many teleports you can cast right now: your Runes of Teleportation, or math.huge
-- when you need none.
function Teleports:Runes()
    if Known(self.NO_REAGENT_SPELL) then return math.huge end
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and (count(self.RUNE_ITEM) or 0) or 0
end

-- The teleports this character knows: { { spell, name, map, x, y }, ... }, sorted by spell ID.
function Teleports:GetKnown()
    local out, learned = {}, Learned()
    for spellID, d in pairs(self.DESTINATIONS) do
        if Known(spellID) then
            local spot = learned[spellID] or d
            table.insert(out, { spell = spellID, name = d.name, map = spot.map, x = spot.x, y = spot.y })
        end
    end
    table.sort(out, function(a, b) return a.spell < b.spell end)
    return out
end

-- What the route planner needs: the known teleports, or nil when they can't be used
-- (turned off, none known, or no Rune of Teleportation in your bags).
function Teleports:GetOptions()
    if not CH.db.profile.useTeleports then return nil end
    local known = self:GetKnown()
    if #known == 0 or self:Runes() == 0 then return nil end
    return known
end

-- Records where a teleport landed, once you're in its city.
function Teleports:Record(spellID, tries)
    local d = self.DESTINATIONS[spellID]
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos and ns.ResolveZone(map) == ns.ResolveZone(d.map) then
        local x, y = pos:GetXY()
        Learned()[spellID] = { map = map, x = x * 100, y = y * 100 }
    elseif tries > 1 then
        C_Timer.After(ARRIVAL_DELAY, function() self:Record(spellID, tries - 1) end)
    end
end

function Teleports:OnSpellcast(_, unit, _, spellID)
    if unit == "player" and self.DESTINATIONS[spellID] then
        C_Timer.After(ARRIVAL_DELAY, function() self:Record(spellID, ARRIVAL_TRIES) end)
    end
end

function Teleports:OnEnable()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcast")
end
