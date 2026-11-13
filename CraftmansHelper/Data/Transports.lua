-- Boats, zeppelins and the tram: fixed links between two docks, used by the route planner.
--
-- Each link: { kind, name, a = { map, x, y }, b = { map, x, y }, faction = optional "A" | "H" }
-- (uiMapID and 0-100 coordinates of where you board on each side).
-- Zeppelin and Booty Bay/Ratchet positions are the zeppelin masters and shipmasters in
-- QuestieDB (GPL-3.0); the rest are approximate and marked "verify" until checked in-game.
-- Forever's new routes (Southshore, Stormwind and Steamwheedle Port boats, Zephras Isle)
-- aren't listed yet.
local _, ns = ...

ns.Transports = {
    -- Zeppelins (Orgrimmar towers in Durotar, Undercity towers in Tirisfal Glades, Grom'gol).
    { kind = "zeppelin", a = { map = 1411, x = 50.8, y = 13.5 }, b = { map = 1420, x = 60.7, y = 58.9 } },
    { kind = "zeppelin", a = { map = 1411, x = 50.7, y = 12.9 }, b = { map = 1434, x = 31.5, y = 29.4 } },
    { kind = "zeppelin", a = { map = 1420, x = 61.8, y = 59.2 }, b = { map = 1434, x = 31.4, y = 29.9 } },

    -- Boats.
    { kind = "boat", a = { map = 1434, x = 26.1, y = 73.4 }, b = { map = 1413, x = 63.5, y = 38.6 } }, -- Booty Bay - Ratchet
    { kind = "boat", a = { map = 1437, x = 5.0, y = 63.5 }, b = { map = 1445, x = 71.6, y = 56.4 } },  -- Menethil - Theramore (verify)
    { kind = "boat", a = { map = 1437, x = 4.6, y = 57.1 }, b = { map = 1439, x = 32.4, y = 43.8 } },  -- Menethil - Auberdine (verify)
    { kind = "boat", a = { map = 1439, x = 33.2, y = 40.2 }, b = { map = 1438, x = 55.0, y = 95.0 } }, -- Auberdine - Rut'theran (verify)

    -- Deeprun Tram, Stormwind - Ironforge (verify).
    { kind = "tram", a = { map = 1453, x = 69.0, y = 31.0 }, b = { map = 1455, x = 76.5, y = 51.0 } },
}

-- Rough time per trip in seconds: average wait at the dock plus the ride itself.
ns.TRANSPORT_SECONDS = { boat = 240, zeppelin = 240, tram = 120 }

ns.TRANSPORT_NAMES = { boat = "boat", zeppelin = "zeppelin", tram = "Deeprun Tram" }
