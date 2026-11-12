-- Where writs are delivered. Keyed by the `turnIn` value in Writs.lua.
-- map = uiMapID of the zone. x/y = 0-100 map coordinates, nil when not known yet
-- (coordinates are also learned in-game on turn-in, see Tracker.lua).
-- Sources: wowhead.com/forever writ guide (NPC + zone) and NPC pages (coordinates).
local _, ns = ...

ns.TurnIns = {
    -- Eastern Kingdoms
    [8305]   = { name = "Kixxle",                    map = 1437, x = 50.2, y = 37.8 }, -- Wetlands
    [257281] = { name = "Sos'mol",                   map = 1416 }, -- Alterac Mountains
    [257282] = { name = "Alan Sneeks",               map = 1416 }, -- Alterac Mountains
    [6176]   = { name = "Bath'rah the Windwatcher",  map = 1416 }, -- Alterac Mountains
    [257296] = { name = "Muggol Breezebeard",        map = 1417 }, -- Arathi Highlands
    [257304] = { name = "Alyce",                     map = 1417 }, -- Arathi Highlands
    [261928] = { name = "Webbed Mudsnout Gnoll",     map = 1424 }, -- Hillsbrad Foothills
    [261932] = { name = "Gorgrash",                  map = 1424 }, -- Hillsbrad Foothills
    [3536]   = { name = "Kris Legace",               map = 1424 }, -- Hillsbrad Foothills
    [3134]   = { name = "Kzixx",                     map = 1431 }, -- Duskwood
    BATTERED_TRUNK = { name = "Battered Trunk",      map = 1431 }, -- Duskwood (object)
    [14508]  = { name = "Short John Mithril",        map = 1434 }, -- Stranglethorn Vale
    [2501]   = { name = "\"Sea Wolf\" MacKinley",    map = 1434 }, -- Stranglethorn Vale
    [7853]   = { name = "Scooty",                    map = 1434 }, -- Stranglethorn Vale
    [2663]   = { name = "Narkk",                     map = 1434 }, -- Stranglethorn Vale
    [261961] = { name = "Hekshi",                    map = 1434 }, -- Stranglethorn Vale

    -- Kalimdor
    [257315] = { name = "Ash'alari",                 map = 1440 }, -- Ashenvale
    [257316] = { name = "Cowardly Peon",             map = 1440 }, -- Ashenvale
    [257317] = { name = "Grembly",                   map = 1440 }, -- Ashenvale
    [257322] = { name = "Murache",                   map = 1440 }, -- Ashenvale
    [4201]   = { name = "Ziz Fizziks",               map = 1442 }, -- Stonetalon Mountains
    [4720]   = { name = "Rizzle Brassbolts",         map = 1441 }, -- Thousand Needles
    [6626]   = { name = "\"Plucky\" Johnson",        map = 1441 }, -- Thousand Needles
    [4706]   = { name = "Razzeric",                  map = 1441 }, -- Thousand Needles
    [4496]   = { name = "Goblin Pit Boss",           map = 1441 }, -- Thousand Needles
    [6548]   = { name = "Magus Tirth",               map = 1441 }, -- Thousand Needles
    [262143] = { name = "Arch Druid Fandral Staghelm", map = 1457 }, -- Darnassus
}
