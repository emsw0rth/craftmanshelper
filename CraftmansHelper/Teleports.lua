-- Teleports for the route planner: mage city teleports, the druids' Teleport: Moonglade and the
-- engineers' transporters.
--
-- Two kinds:
-- * repeatable (no cooldown): mage teleports (each takes a Rune of Teleportation) and Teleport:
--   Moonglade. The planner can use them from any point of the route, as often as they help
--   (Travel.lua: an edge from every place to the arrival spot).
-- * once (a long cooldown): the engineering transporters. The planner tries them once per
--   route, like the Hearthstone (Route.lua). They can misfire, so they're off by default.
--
-- Where each one lands starts out as a spot in the destination town, and is recorded the first
-- time you use it (account-wide: it's the same for everyone), but only when you land in the
-- expected zone, so a misfire doesn't move it.
local _, ns = ...
local CH = ns.CH

local Teleports = CH:NewModule("Teleports", "AceEvent-3.0")
CH.Teleports = Teleports

local RUNE = 17031           -- Rune of Teleportation, used by every mage teleport
local RECORD_DELAY = 3       -- seconds after the cast before your position is the arrival
local RECORD_TRIES = 15      -- then tried every 2 s (a loading screen can take a while)

-- key = { spell or item, name (destination), map, x, y, kind = "mage" | "druid" | "device",
--         fallback name of the spell or item }
Teleports.LIST = {
    { key = "STORMWIND", spell = 3561, kind = "mage", name = "Stormwind", map = 1453, x = 71.3, y = 72.2,
      title = "Teleport: Stormwind" },
    { key = "IRONFORGE", spell = 3562, kind = "mage", name = "Ironforge", map = 1455, x = 55.5, y = 47.7,
      title = "Teleport: Ironforge" },
    { key = "DARNASSUS", spell = 3565, kind = "mage", name = "Darnassus", map = 1457, x = 40.0, y = 82.0,
      title = "Teleport: Darnassus" },
    { key = "ORGRIMMAR", spell = 3567, kind = "mage", name = "Orgrimmar", map = 1454, x = 45.1, y = 63.9,
      title = "Teleport: Orgrimmar" },
    { key = "UNDERCITY", spell = 3563, kind = "mage", name = "Undercity", map = 1458, x = 63.2, y = 48.6,
      title = "Teleport: Undercity" },
    { key = "THUNDERBLUFF", spell = 3566, kind = "mage", name = "Thunder Bluff", map = 1456, x = 47.0, y = 49.8,
      title = "Teleport: Thunder Bluff" },
    { key = "MOONGLADE", spell = 18960, kind = "druid", name = "Moonglade", map = 1450, x = 44.3, y = 45.9,
      title = "Teleport: Moonglade" },
    { key = "GADGETZAN", item = 18986, kind = "device", name = "Gadgetzan", map = 1446, x = 51.0, y = 28.0,
      title = "Ultrasafe Transporter: Gadgetzan" },
    { key = "EVERLOOK", item = 18984, kind = "device", name = "Everlook", map = 1452, x = 61.4, y = 37.0,
      title = "Dimensional Ripper - Everlook" },
}

local function Profile() return CH.db.profile end

local function Known(spellID)
    local known = IsPlayerSpell or IsSpellKnown
    return known ~= nil and known(spellID) and true or false
end

local function ItemCount(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and (count(itemID) or 0) or 0
end

-- Seconds left of a cooldown that started at `start` and lasts `duration` (0 when ready).
local function Left(start, duration)
    if not (start and duration) or start == 0 or duration <= 1.5 then return 0 end -- 1.5: global cooldown
    return math.max(0, start + duration - GetTime())
end

local function SpellReadyIn(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if type(info) == "table" then return Left(info.startTime, info.duration) end
    end
    if GetSpellCooldown then return Left(GetSpellCooldown(spellID)) end
    return 0
end

local function ItemReadyIn(itemID)
    local getCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getCooldown then return 0 end
    return Left(getCooldown(itemID))
end

-- The spell or item's name in the game's language.
local function Title(t)
    local name
    if t.spell then
        name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(t.spell))
            or (GetSpellInfo and GetSpellInfo(t.spell))
    else
        name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(t.item)
    end
    return name or t.title
end

-- Where a teleport lands: the recorded spot, else the one in LIST.
function Teleports:Spot(t)
    local spots = CH.db.global.teleportSpots
    local s = spots and spots[t.key]
    if s and s.map == t.map then return s.map, s.x, s.y end
    return t.map, t.x, t.y
end

local function Option(self, t, readyIn)
    local map, x, y = self:Spot(t)
    local title = Title(t)
    local text
    if t.kind == "device" then
        text = string.format("Use your %s", title)
    elseif t.kind == "mage" then
        text = string.format("Teleport to %s", t.name)
    else
        text = string.format("Cast %s", title)
    end
    return { key = t.key, kind = t.kind, name = t.name, map = map, x = x, y = y, text = text,
             rune = t.kind == "mage" or nil, readyIn = readyIn or 0 }
end

-- The teleports the route can use from anywhere, as often as it likes: a list of options
-- { key, kind, name, map, x, y, text, rune }, and how many Runes of Teleportation you carry.
-- mage = false leaves the mage teleports out (not enough runes for the route).
function Teleports:Anywhere(mage)
    local list, runes = {}, ItemCount(RUNE)
    local p = Profile()
    for _, t in ipairs(self.LIST) do
        if t.kind == "mage" then
            if mage ~= false and p.useTeleports ~= false and runes > 0 and Known(t.spell) then
                table.insert(list, Option(self, t))
            end
        elseif t.kind == "druid" then
            if p.useMoonglade ~= false and Known(t.spell) and SpellReadyIn(t.spell) == 0 then
                table.insert(list, Option(self, t))
            end
        end
    end
    return list, runes
end

-- The teleports the route can use once (the engineering transporters, when turned on): options
-- with readyIn = seconds until they're off cooldown.
function Teleports:Once()
    local list = {}
    if not Profile().useEngineering then return list end
    for _, t in ipairs(self.LIST) do
        if t.kind == "device" and ItemCount(t.item) > 0 then
            table.insert(list, Option(self, t, ItemReadyIn(t.item)))
        end
    end
    return list
end

-- Whether the character has any teleport the planner knows (for the Settings tab).
function Teleports:Has(kind)
    for _, t in ipairs(self.LIST) do
        if t.kind == kind and ((t.spell and Known(t.spell)) or (t.item and ItemCount(t.item) > 0)) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Recording where you land
---------------------------------------------------------------------------

local function PlayerSpot()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return map, x * 100, y * 100
end

function Teleports:Record(t, tries)
    local map, x, y = PlayerSpot()
    if map == t.map then
        CH.db.global.teleportSpots = CH.db.global.teleportSpots or {}
        CH.db.global.teleportSpots[t.key] = { map = map, x = x, y = y }
        return
    end
    -- Elsewhere: still loading, or a misfire (then nothing is recorded).
    if tries > 0 then C_Timer.After(2, function() self:Record(t, tries - 1) end) end
end

-- spellID -> teleport, including the spells the transporters cast.
local bySpell
local function BySpell()
    if not bySpell then
        bySpell = {}
        for _, t in ipairs(Teleports.LIST) do
            if t.spell then
                bySpell[t.spell] = t
            elseif C_Item and C_Item.GetItemSpell then
                local _, spellID = C_Item.GetItemSpell(t.item)
                if spellID then bySpell[spellID] = t end
            end
        end
    end
    return bySpell
end

function Teleports:OnSpellcast(_, unit, _, spellID)
    if unit ~= "player" then return end
    local t = BySpell()[spellID]
    if t then C_Timer.After(RECORD_DELAY, function() self:Record(t, RECORD_TRIES) end) end
end

function Teleports:OnEnable()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcast")
end
