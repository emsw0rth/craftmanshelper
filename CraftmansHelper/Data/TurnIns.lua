-- Where writs are delivered. Keyed by the `turnIn` value in Writs.lua.
-- map = uiMapID of the zone; x/y = 0-100 map coordinates.
-- faction = who the NPC is friendly to: "AH" both, "A" Alliance, "H" Horde, nil unknown.
-- Data: QuestieDB (https://github.com/Questie/Questie), GPL-3.0. Turn-ins missing here are
-- resolved in-game (quest map marker, or recorded on turn-in).
local _, ns = ...

ns.TurnIns = {
    -- Alterac Mountains
    [257282] = { name = "Alan Sneeks", map = 1416, x = 30.6, y = 61.0, faction = "AH" },
    [6176] = { name = "Bath'rah the Windwatcher", map = 1416, x = 80.5, y = 66.9, faction = "AH" },
    [257281] = { name = "Sos'mol", map = 1416, x = 38.4, y = 61.1, faction = "AH" },
    -- Arathi Highlands
    [257304] = { name = "Alyce", map = 1417, x = 34.0, y = 23.3, faction = "AH" },
    [257296] = { name = "Muggol Breezebeard", map = 1417, x = 48.7, y = 55.8, faction = "AH" },
    -- Ashenvale
    [257315] = { name = "Ash'alari", map = 1440, x = 60.2, y = 72.7, faction = "AH" },
    [257316] = { name = "Cowardly Peon", map = 1440, x = 78.5, y = 68.9, faction = "AH" },
    [257317] = { name = "Grembly", map = 1440, x = 82.1, y = 51.0, faction = "AH" },
    [257322] = { name = "Murache", map = 1440, x = 64.8, y = 80.2, faction = "AH" },
    -- Badlands
    [2888] = { name = "Garek", map = 1418, x = 61.9, y = 54.3, faction = "AH" },
    [2921] = { name = "Lotwil Veriatus", map = 1418, x = 25.9, y = 44.9, faction = "AH" },
    [2817] = { name = "Rigglefuzz", map = 1418, x = 42.4, y = 52.9, faction = "AH" },
    -- Desolace
    [11863] = { name = "Azore Aldamort", map = 1443, x = 38.9, y = 27.2, faction = "AH" },
    [11438] = { name = "Bibbly F'utzbuckle", map = 1443, x = 62.3, y = 39.0, faction = "AH" },
    [13717] = { name = "Centaur Pariah", map = 1443, x = 50.4, y = 86.7, faction = "AH" },
    -- Duskwood
    BATTERED_TRUNK = { name = "Battered Trunk", map = 1431, x = 26.3, y = 36.2, object = true },
    [3134] = { name = "Kzixx", map = 1431, x = 81.8, y = 19.8, faction = "AH" },
    -- Dustwallow Marsh
    [262072] = { name = "The Ravenous", map = 1445, x = 54, y = 56.5, faction = "AH" },
    -- Felwood
    [10922] = { name = "Greta Mosshoof", map = 1448, x = 51.2, y = 82.1, faction = "AH" },
    -- Feralas
    [262143] = { name = "Scout Raroul", map = 1444, x = 72.4, y = 52.5, faction = "AH" },
    -- Hillsbrad Foothills
    [261932] = { name = "Gorgrash", map = 1424, x = 80.0, y = 48.5, faction = "AH" },
    [3536] = { name = "Kris Legace", map = 1424, x = 80.1, y = 38.9, faction = "AH" },
    [261928] = { name = "Webbed Mudsnout Gnoll", map = 1424, x = 62.4, y = 69.2, faction = "AH" },
    -- Moonglade
    [11802] = { name = "Dendrite Starblaze", map = 1450, x = 56.2, y = 30.6, faction = "AH" },
    [12024] = { name = "Meliri", map = 1450, x = 51.2, y = 42.3, faction = "AH" },
    -- Riverglades
    [262284] = { name = "Spek", map = 2548, x = 76.9, y = 54.1, faction = "AH" },
    -- Searing Gorge
    [14628] = { name = "Evonice Sootsmoker", map = 1427, x = 38.4, y = 27.7, faction = "AH" },
    [14634] = { name = "Lookout Captain Lolo Longstriker", map = 1427, x = 37.7, y = 26.6, faction = "AH" },
    [14624] = { name = "Master Smith Burninate", map = 1427, x = 38.8, y = 28.5, faction = "AH" },
    -- Stonetalon Mountains
    [4201] = { name = "Ziz Fizziks", map = 1442, x = 59.0, y = 62.6, faction = "AH" },
    -- Stranglethorn Vale
    [2501] = { name = "\"Sea Wolf\" MacKinley", map = 1434, x = 27.8, y = 77.1, faction = "AH" },
    [261961] = { name = "Hekshi", map = 1434, x = 50.7, y = 19.3, faction = "AH" },
    [2663] = { name = "Narkk", map = 1434, x = 28.1, y = 74.4, faction = "AH" },
    [7853] = { name = "Scooty", map = 1434, x = 27.6, y = 77.5, faction = "AH" },
    [14508] = { name = "Short John Mithril", map = 1434, x = 29.6, y = 47.4, faction = "AH" },
    -- Swamp of Sorrows
    [262306] = { name = "Mukomonji", map = 1435, x = 62.4, y = 52.9 },
    -- Tanaris
    [5594] = { name = "Alchemist Pestlezugg", map = 1446, x = 50.9, y = 27.0, faction = "AH" },
    [14743] = { name = "Jhordy Lapforge", map = 1446, x = 52.3, y = 26.9, faction = "AH" },
    [6568] = { name = "Vizzklick", map = 1446, x = 51.0, y = 27.4, faction = "AH" },
    [8579] = { name = "Yeh'kinya", map = 1446, x = 67.0, y = 22.4, faction = "AH" },
    -- The Hinterlands
    [262388] = { name = "Juo", map = 1425, x = 80.1, y = 55.4 },
    -- Thousand Needles
    [6626] = { name = "\"Plucky\" Johnson", map = 1441, x = 79.6, y = 75.6, faction = "AH" },
    [4496] = { name = "Goblin Pit Boss", map = 1441, x = 79.9, y = 76.7, faction = "AH" },
    [6548] = { name = "Magus Tirth", map = 1441, x = 78.3, y = 75.7, faction = "AH" },
    [4706] = { name = "Razzeric", map = 1441, x = 80.3, y = 76.1, faction = "AH" },
    [4720] = { name = "Rizzle Brassbolts", map = 1441, x = 77.2, y = 77.4, faction = "AH" },
    -- Un'Goro Crater
    [9272] = { name = "Spark Nilminer", map = 1449, x = 43.5, y = 7.4, faction = "AH" },
    [9619] = { name = "Torwa Pathfinder", map = 1449, x = 71.6, y = 76.0, faction = "AH" },
    -- Wetlands
    [8305] = { name = "Kixxle", map = 1437, x = 50.2, y = 37.7, faction = "AH" },
    -- Contributed: recorded in-game by players (/writs export)
    [7408] = { name = "Spigot Operator Luglunket", map = 1446, x = 52.4, y = 28.4 }, -- turnin
    [11705] = { name = "Rayan Dawnrisen", map = 1447, x = 30.0, y = 40.2 }, -- turnin
    [14348] = { name = "Earthcaller Franzahl", map = 1452, x = 54.0, y = 90.4 }, -- turnin
    [14437] = { name = "Gorzeeki Wildeyes", map = 1428, x = 12.6, y = 31.4 }, -- turnin
    [257429] = { name = "Furious Shadowforge Digger", map = 1418, x = 44.4, y = 11.4 }, -- turnin
    [11019] = { name = "Jessir Moonbow", map = 1448, x = 51.3, y = 82.1 }, -- turnin
    [12029] = { name = "Narianna", map = 1450, x = 53.3, y = 42.7 }, -- turnin
    [262379] = { name = "Bullets Bigblast", map = 1435, x = 70.1, y = 41.7 }, -- turnin
    [5634] = { name = "Rhapsody Shindigger", map = 1425, x = 26.9, y = 48.5 }, -- turnin
    [8379] = { name = "Archmage Xylem", map = 1447, x = 29.5, y = 40.5 }, -- turnin
    [7363] = { name = "Kum'isha the Collector", map = 1419, x = 51.9, y = 35.5 }, -- turnin
    [257743] = { name = "Hastings", map = 1430, x = 47.0, y = 75.3 }, -- turnin
    [4503] = { name = "Mudcrush Durtfeet", map = 1445, x = 35.2, y = 38.2, faction = "AH" }, -- marker
    [10924] = { name = "Ivy Leafrunner", map = 1448, x = 50.9, y = 81.7 }, -- turnin
    [11706] = { name = "Adon", map = 1423, x = 50.9, y = 11.5, faction = "AH" }, -- marker

    -- From Wowhead (quest turn-in NPC and NPC page), 2026-11-19
    [262294] = { name = "Durganon", map = 1427, x = 41.0, y = 58.4 },
    [270919] = { name = "Ugbert", map = 1445, x = 40.8, y = 28.0, faction = "AH" },
    [10921] = { name = "Taronn Redfeather", map = 1448, x = 50.8, y = 81.6, faction = "AH" },
    [12959] = { name = "Nergal", map = 1449, x = 43.2, y = 7.8, faction = "AH" },
    [13656] = { name = "Willow", map = 1443, x = 62.0, y = 39.4, faction = "AH" },
    [6546] = { name = "Tabetha", map = 1445, x = 46.0, y = 57.0, faction = "AH" },
    [9116] = { name = "Eridan Bluewind", map = 1448, x = 51.2, y = 81.4, faction = "AH" },
    [14470] = { name = "Impsy", map = 1448, x = 41.4, y = 44.8, faction = "AH" },
    [11795] = { name = "Mylentha Riverbend", map = 1450, x = 51.8, y = 32.8, faction = "AH" },
    [9273] = { name = "Petra Grossen", map = 1449, x = 43.2, y = 7.3, faction = "AH" },
    [262041] = { name = "Bor'dorc", map = 1452, x = 64.8, y = 33.2, faction = "AH" },
    [257750] = { name = "Calliard", map = 1430, x = 48.0, y = 68.2 },
    [15194] = { name = "Hermit Ortell", map = 1451, x = 67.0, y = 69.6, faction = "AH" },
}
