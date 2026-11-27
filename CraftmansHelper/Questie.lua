-- Optional runtime lookup in QuestieDB (when the user has Questie installed), so
-- turn-ins that Questie learns about after our release still show up.
-- Public API: _G.LibQuestieDB.{Quest,Npc,Object}.Get(id, fieldName).
local _, ns = ...

local Q = {}
ns.Questie = Q

-- Zone-level Questie AreaIDs -> uiMapIDs (from QuestieDB's Forever zone data, GPL-3.0).
local AREA_TO_MAP = {
    [1] = 1426, [3] = 1418, [4] = 1419, [8] = 1435, [10] = 1431, [11] = 1437, [12] = 1429, [14] = 1411,
    [15] = 1445, [16] = 1447, [17] = 1413, [28] = 1422, [33] = 1434, [36] = 1416, [38] = 1432, [40] = 1436,
    [41] = 1430, [44] = 1433, [45] = 1417, [46] = 1428, [47] = 1425, [51] = 1427, [85] = 1420, [130] = 1421,
    [139] = 1423, [141] = 1438, [148] = 1439, [215] = 1412, [267] = 1424, [331] = 1440, [357] = 1444,
    [361] = 1448, [400] = 1441, [405] = 1443, [406] = 1442, [440] = 1446, [490] = 1449, [493] = 1450,
    [618] = 1452, [1377] = 1451, [1497] = 1458, [1519] = 1453, [1537] = 1455, [1637] = 1454, [1638] = 1456,
    [1657] = 1457, [16591] = 2548, [616] = 2482,
}

local function DB()
    local db = rawget(_G, "LibQuestieDB")
    if type(db) == "table" and type(db.Quest) == "table" and type(db.Npc) == "table" then return db end
end

function Q.IsAvailable()
    return DB() ~= nil
end

local function AreaToMap(area)
    local m = AREA_TO_MAP[area]
    if m then return m end
    -- Questie's own ZoneDB knows every sub-zone, when Questie (not just QuestieDB) is loaded.
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) == "table" and loader.ImportModule then
        local ok, zoneDB = pcall(loader.ImportModule, loader, "ZoneDB")
        if ok and type(zoneDB) == "table" and zoneDB.GetUiMapIdByAreaId then
            local ok2, mapID = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, area)
            if ok2 and mapID and mapID > 0 then return mapID end
        end
    end
end

local function Get(entity, id, key)
    local ok, value = pcall(entity.Get, id, key)
    if ok then return value end
end

local function FirstSpawn(spawns)
    if type(spawns) ~= "table" then return nil end
    for area, points in pairs(spawns) do
        local p = type(points) == "table" and points[1]
        if p and p[1] and p[1] >= 0 and p[2] then
            local map = AreaToMap(area)
            if map then return map, p[1], p[2] end
        end
    end
end

local cache = {}

-- Returns { name, map, x, y, faction, npcID | objectID } or nil.
function Q.GetTurnIn(questID)
    local cached = cache[questID]
    if cached ~= nil then return cached or nil end
    local db = DB()
    if not db then return nil end -- not cached: QuestieDB may still be loading

    local result = false
    local finishedBy = Get(db.Quest, questID, "finishedBy")
    if type(finishedBy) == "table" then
        for _, id in ipairs(finishedBy[1] or {}) do
            local map, x, y = FirstSpawn(Get(db.Npc, id, "spawns"))
            if map then
                result = { npcID = id, name = Get(db.Npc, id, "name"), map = map, x = x, y = y,
                           faction = Get(db.Npc, id, "friendlyToFaction") }
                break
            end
        end
        if not result and db.Object then
            for _, id in ipairs(finishedBy[2] or {}) do
                local map, x, y = FirstSpawn(Get(db.Object, id, "spawns"))
                if map then
                    result = { objectID = id, name = Get(db.Object, id, "name"), map = map, x = x, y = y }
                    break
                end
            end
        end
    end
    cache[questID] = result
    return result or nil
end
