-- Where you cross from one zone into another on foot, collected in-game by Emsworth (2026-11-19).
-- [zone] = { { to = zone or { zones }, x, y (in this zone), note, item, faction }, ... }
--   item: you must carry it (a key to a gate). faction: only "A" or "H" may pass (capital gates).
-- Riding from one listed zone into another goes through one of these. A zone listed with no
-- crossings can't be reached on foot.
local _, ns = ...

ns.Crossings = {
    [1411] = { -- Durotar
        { to = 1413, x = 35.1, y = 42.4 },
        { to = 1454, x = 45.5, y = 12.3, faction = "H" },
    },
    [1412] = { -- Mulgore
        { to = 1413, x = 64.9, y = 64.0 },
        { to = 1456, x = 38.4, y = 40.8, note = "south lift", faction = "H" },
        { to = 1456, x = 35.5, y = 36.0, note = "south lift", faction = "H" },
        { to = 1456, x = 39.5, y = 29.4, note = "north lift", faction = "H" },
        { to = 1456, x = 42.3, y = 29.8, note = "north lift", faction = "H" },
    },
    [1413] = { -- The Barrens
        { to = 1412, x = 41.2, y = 58.6 },
        { to = 1445, x = 49.8, y = 78.4 },
        { to = 1441, x = 44.1, y = 91.5, note = "the Great Lift" },
        { to = 1442, x = 36.3, y = 27.5 },
        { to = 1440, x = 48.8, y = 7.1 },
        { to = 1411, x = 62.6, y = 19.2 },
    },
    [1416] = { -- Alterac Mountains
        { to = 1422, x = 80.7, y = 34.2 },
        { to = 1424, x = 51.8, y = 68.8 },
        { to = 1424, x = 81.7, y = 77.5, note = "Ravenholdt Manor" },
    },
    [1417] = { -- Arathi Highlands
        { to = 1437, x = 45.4, y = 88.9, note = "Thandol Span" },
        { to = 1424, x = 20.9, y = 30.6 },
    },
    [1418] = { -- Badlands
        { to = 1432, x = 51.1, y = 14.8 },
        { to = 1427, x = 5.3, y = 61.1 },
        { to = 2548, x = 54.8, y = 92.5, note = "Twilight's Shroud" },
    },
    [1419] = { -- Blasted Lands
        { to = 1435, x = 52.2, y = 10.7 },
    },
    [1420] = { -- Tirisfal Glades
        { to = 1422, x = 83.4, y = 70.6, note = "the Bulwark" },
        { to = 1458, x = 61.9, y = 65.0, faction = "H" },
        { to = 1421, x = 54.9, y = 72.7 },
    },
    [1421] = { -- Silverpine Forest
        { to = 1424, x = 66.3, y = 79.8 },
        { to = 1420, x = 67.7, y = 5.0 },
    },
    [1422] = { -- Western Plaguelands
        { to = 1416, x = 44.1, y = 87.1 },
        { to = 1420, x = 28.6, y = 57.5, note = "the Bulwark" },
        { to = 1423, x = 69.7, y = 50.3 },
        { to = 1425, x = 65.3, y = 86.4 },
    },
    [1423] = { -- Eastern Plaguelands
        { to = 1422, x = 11.8, y = 61.5 },
    },
    [1424] = { -- Hillsbrad Foothills
        { to = 1425, x = 84.6, y = 31.8 },
        { to = 1416, x = 54.8, y = 11.3 },
        { to = 1416, x = 75.5, y = 24.6, note = "Ravenholdt Manor" },
        { to = 1421, x = 13.7, y = 46.2 },
        { to = 1417, x = 81.0, y = 56.1 },
    },
    [1425] = { -- The Hinterlands
        { to = 1422, x = 24.1, y = 30.4 },
        { to = 1424, x = 6.4, y = 61.5 },
    },
    [1426] = { -- Dun Morogh (the jump down into the Wetlands at 30.5, 34.5 kills you: left out)
        { to = 1432, x = 84.3, y = 31.1, note = "North Gate Pass" },
        { to = 1432, x = 82.2, y = 53.5, note = "South Gate Pass" },
        { to = 1455, x = 53.3, y = 35.1, faction = "A" },
    },
    [1427] = { -- Searing Gorge
        { to = 1432, x = 78.5, y = 17.4, note = "the gate", item = 5396 },
        { to = 1428, x = 33.6, y = 79.0, note = "Blackrock Mountain" },
        { to = 1418, x = 68.8, y = 53.9 },
    },
    [1428] = { -- Burning Steppes
        { to = 1433, x = 78.3, y = 77.8 },
        { to = 1427, x = 31.9, y = 50.4, note = "Blackrock Mountain" },
    },
    [1429] = { -- Elwynn Forest
        { to = 1436, x = 21.0, y = 79.6 },
        { to = 1433, x = 93.2, y = 72.3 },
        { to = 1453, x = 32.2, y = 49.7, faction = "A" },
    },
    [1430] = { -- Deadwind Pass
        { to = 1431, x = 32.0, y = 35.3 },
        { to = 1435, x = 58.8, y = 42.2 },
    },
    [1431] = { -- Duskwood
        { to = 1436, x = 7.9, y = 63.8 },
        { to = 1434, x = 44.6, y = 87.9 },
        { to = 1433, x = 94.2, y = 10.3 },
        { to = 1430, x = 88.4, y = 40.9 },
    },
    [1432] = { -- Loch Modan
        { to = 1427, x = 18.4, y = 83.0, note = "the gate", item = 5396 },
        { to = 1426, x = 20.4, y = 17.4, note = "North Gate Pass" },
        { to = 1426, x = 21.5, y = 66.2, note = "South Gate Pass" },
        { to = 1418, x = 46.8, y = 76.9 },
        { to = 1437, x = 25.4, y = 10.9, note = "Dun Algaz" },
    },
    [1433] = { -- Redridge Mountains
        { to = 1431, x = 2.2, y = 90.6, note = "towards Darkshire" },
        { to = 1429, x = 3.0, y = 72.3, note = "Eastvale Logging Camp" },
        { to = 1428, x = 41.7, y = 7.1, note = "Blackrock Pass" },
        { to = 2548, x = 44.8, y = 9.8, note = "Blackrock Pass" },
        { to = 2548, x = 66.4, y = 18.6, note = "Redridge Pass" },
        { to = 1435, x = 96.5, y = 70.1, note = "Redridge Pass" },
    },
    [1434] = { -- Stranglethorn Vale
        { to = 1431, x = 39.2, y = 6.5 },
    },
    [1435] = { -- Swamp of Sorrows
        { to = 1430, x = 3.7, y = 61.1 },
        { to = 1419, x = 33.4, y = 74.8 },
    },
    [1436] = { -- Westfall
        { to = 1429, x = 62.0, y = 17.9 },
        { to = 1431, x = 67.9, y = 62.8 },
    },
    [1437] = { -- Wetlands
        { to = 1417, x = 51.3, y = 10.3, note = "Thandol Span" },
        { to = 1432, x = 56.0, y = 70.3, note = "Dun Algaz" },
    },
    [1438] = { -- Teldrassil
        { to = 1457, x = 55.9, y = 89.7, faction = "A" },
        { to = 1457, x = 36.2, y = 54.4, faction = "A" },
    },
    [1439] = { -- Darkshore
        { to = 1440, x = 43.3, y = 94.0 },
        { to = 1440, x = 37.5, y = 94.8 },
        { to = 1440, x = 27.7, y = 92.9, note = "the Zoram Strand" },
    },
    [1440] = { -- Ashenvale
        { to = 1439, x = 29.1, y = 14.8 },
        { to = 1439, x = 20.6, y = 16.1 },
        { to = 1439, x = 9.5, y = 10.7, note = "Twilight Shore" },
        { to = 1442, x = 42.3, y = 71.1, note = "the Talondeep Path" },
        { to = 1448, x = 55.8, y = 30.2 },
        { to = 1447, x = 94.2, y = 47.3 },
        { to = 1413, x = 68.6, y = 86.8 },
    },
    [1441] = { -- Thousand Needles
        { to = 1446, x = 74.9, y = 93.3 },
        { to = 1444, x = 8.3, y = 11.9 },
        { to = 1413, x = 32.2, y = 23.9, note = "the Great Lift" },
    },
    [1442] = { -- Stonetalon Mountains
        { to = 1413, x = 80.2, y = 92.4 },
        { to = 1443, x = 30.4, y = 75.4 },
        { to = 1440, x = 78.2, y = 42.8, note = "the Talondeep Path" },
    },
    [1443] = { -- Desolace
        { to = 1442, x = 53.4, y = 5.9 },
        { to = 1444, x = 41.6, y = 94.4 },
    },
    [1444] = { -- Feralas
        { to = 1443, x = 44.9, y = 7.7 },
        { to = 1441, x = 88.7, y = 41.1 },
    },
    [1445] = { -- Dustwallow Marsh
        { to = 1413, x = 30.0, y = 47.1 },
    },
    [1446] = { -- Tanaris
        { to = 1441, x = 50.6, y = 24.4 },
        { to = 1449, x = 27.1, y = 57.7 },
    },
    [1447] = { -- Azshara
        { to = 1440, x = 10.6, y = 75.3 },
    },
    [1448] = { -- Felwood
        { to = 1452, x = 65.0, y = 8.3, note = "Timbermaw Hold" },
        { to = 1440, x = 54.5, y = 89.2 },
    },
    [1449] = { -- Un'Goro Crater
        { to = 1446, x = 70.5, y = 78.6 },
        { to = 1451, x = 29.4, y = 22.3 },
    },
    [1450] = { -- Moonglade: the Timbermaw Hold tunnel leads to Felwood and Winterspring
        { to = { 1448, 1452 }, x = 35.7, y = 72.4, note = "Timbermaw Hold" },
    },
    [1451] = { -- Silithus
        { to = 1449, x = 82.4, y = 16.0 },
    },
    [1452] = { -- Winterspring
        { to = 1448, x = 27.9, y = 34.5, note = "Timbermaw Hold" },
    },
    [1453] = { -- Stormwind City
        { to = 1429, x = 74.5, y = 92.3, faction = "A" },
    },
    [1454] = { -- Orgrimmar
        { to = 1411, x = 52.4, y = 83.7, faction = "H" },
        { to = 1413, x = 18.1, y = 60.6, note = "the west gate", faction = "H" },
    },
    [1455] = { -- Ironforge
        { to = 1426, x = 21.9, y = 77.5, faction = "A" },
    },
    [1456] = { -- Thunder Bluff
        { to = 1412, x = 35.7, y = 62.8, note = "south lift", faction = "H" },
        { to = 1412, x = 51.3, y = 31.3, note = "north lift", faction = "H" },
    },
    [1457] = { -- Darnassus
        { to = 1438, x = 30.3, y = 41.4, note = "portal to Rut'theran Village", faction = "A" },
        { to = 1438, x = 86.9, y = 35.8, faction = "A" },
    },
    [1458] = { -- Undercity
        { to = 1420, x = 66.2, y = 5.2, faction = "H" },
    },
    [2482] = {}, -- Mount Hyjal
    [2521] = {}, -- Zephras Isle
    [2548] = { -- Riverglades
        { to = 1418, x = 32.0, y = 30.2, note = "north of Twilight's Shroud" },
        { to = 1433, x = 16.3, y = 69.0, note = "Blackrock Pass" },
        { to = 1433, x = 25.3, y = 72.8, note = "Redridge Pass" },
    },
    [2652] = {}, -- Shen'dralas
}
