-- Map helpers: resolve a uiMapID to its zone and continent, with localized names
-- from the game where possible and an English fallback table otherwise.
local _, ns = ...

local KALIMDOR, EASTERN_KINGDOMS = 1414, 1415
ns.UNKNOWN_CONTINENT = 0

-- Continents in display order (user preference: Kalimdor first), unknown last.
ns.CONTINENT_ORDER = { KALIMDOR, EASTERN_KINGDOMS, ns.UNKNOWN_CONTINENT }

-- Fallback data for classic uiMapIDs: [mapID] = { English name, continent }.
local FALLBACK = {
    [1414] = { "Kalimdor" }, [1415] = { "Eastern Kingdoms" },
    -- Eastern Kingdoms
    [1416] = { "Alterac Mountains", EASTERN_KINGDOMS }, [1417] = { "Arathi Highlands", EASTERN_KINGDOMS },
    [1418] = { "Badlands", EASTERN_KINGDOMS },          [1419] = { "Blasted Lands", EASTERN_KINGDOMS },
    [1420] = { "Tirisfal Glades", EASTERN_KINGDOMS },   [1421] = { "Silverpine Forest", EASTERN_KINGDOMS },
    [1422] = { "Western Plaguelands", EASTERN_KINGDOMS }, [1423] = { "Eastern Plaguelands", EASTERN_KINGDOMS },
    [1424] = { "Hillsbrad Foothills", EASTERN_KINGDOMS }, [1425] = { "The Hinterlands", EASTERN_KINGDOMS },
    [1426] = { "Dun Morogh", EASTERN_KINGDOMS },        [1427] = { "Searing Gorge", EASTERN_KINGDOMS },
    [1428] = { "Burning Steppes", EASTERN_KINGDOMS },   [1429] = { "Elwynn Forest", EASTERN_KINGDOMS },
    [1430] = { "Deadwind Pass", EASTERN_KINGDOMS },     [1431] = { "Duskwood", EASTERN_KINGDOMS },
    [1432] = { "Loch Modan", EASTERN_KINGDOMS },        [1433] = { "Redridge Mountains", EASTERN_KINGDOMS },
    [1434] = { "Stranglethorn Vale", EASTERN_KINGDOMS }, [1435] = { "Swamp of Sorrows", EASTERN_KINGDOMS },
    [1436] = { "Westfall", EASTERN_KINGDOMS },          [1437] = { "Wetlands", EASTERN_KINGDOMS },
    [1453] = { "Stormwind City", EASTERN_KINGDOMS },    [1455] = { "Ironforge", EASTERN_KINGDOMS },
    [1458] = { "Undercity", EASTERN_KINGDOMS },
    -- Kalimdor
    [1411] = { "Durotar", KALIMDOR },             [1412] = { "Mulgore", KALIMDOR },
    [1413] = { "The Barrens", KALIMDOR },         [1438] = { "Teldrassil", KALIMDOR },
    [1439] = { "Darkshore", KALIMDOR },           [1440] = { "Ashenvale", KALIMDOR },
    [1441] = { "Thousand Needles", KALIMDOR },    [1442] = { "Stonetalon Mountains", KALIMDOR },
    [1443] = { "Desolace", KALIMDOR },            [1444] = { "Feralas", KALIMDOR },
    [1445] = { "Dustwallow Marsh", KALIMDOR },    [1446] = { "Tanaris", KALIMDOR },
    [1447] = { "Azshara", KALIMDOR },             [1448] = { "Felwood", KALIMDOR },
    [1449] = { "Un'Goro Crater", KALIMDOR },      [1450] = { "Moonglade", KALIMDOR },
    [1451] = { "Silithus", KALIMDOR },            [1452] = { "Winterspring", KALIMDOR },
    [1454] = { "Orgrimmar", KALIMDOR },           [1456] = { "Thunder Bluff", KALIMDOR },
    [1457] = { "Darnassus", KALIMDOR },
}

local cache = {}

local function MapInfo(mapID)
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok then return info end
    end
end

-- Returns zoneMapID, zoneName, continentMapID, continentName for any uiMapID
-- (sub-zones and dungeon maps are walked up to their zone).
function ns.ResolveZone(mapID)
    if not mapID then return nil end
    local hit = cache[mapID]
    if hit then return hit[1], hit[2], hit[3], hit[4] end

    local zoneID, zoneName, contID, contName
    local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

    local info = MapInfo(mapID)
    local guard = 0
    while info and guard < 10 do
        guard = guard + 1
        if info.mapType == CONTINENT then
            contID, contName = info.mapID, info.name
            break
        elseif not zoneID and info.mapType <= ZONE then
            zoneID, zoneName = info.mapID, info.name
        end
        if not info.parentMapID or info.parentMapID == 0 then break end
        info = MapInfo(info.parentMapID)
    end

    local fb = FALLBACK[zoneID or mapID]
    zoneID = zoneID or mapID
    zoneName = zoneName or (fb and fb[1]) or ("Map " .. mapID)
    contID = contID or (fb and fb[2]) or ns.UNKNOWN_CONTINENT
    contName = contName or (FALLBACK[contID] and FALLBACK[contID][1]) or "Unknown location"

    cache[mapID] = { zoneID, zoneName, contID, contName }
    return zoneID, zoneName, contID, contName
end

function ns.ContinentName(contID)
    if contID == ns.UNKNOWN_CONTINENT then return "Unknown location" end
    local info = MapInfo(contID)
    return (info and info.name) or (FALLBACK[contID] and FALLBACK[contID][1]) or ("Map " .. contID)
end
