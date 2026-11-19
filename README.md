# Craftman's Helper

A World of Warcraft: Forever addon for Craftsman's Writs: the daily crafting orders that give reputation with
**Azeroth Commerce Authority** (Alliance) / **Durotar Supply and Logistics** (Horde).

## Features (v1.10.1)

- **Route** tab: plans a delivery route over every writ you can hand in right now.
  - Writs delivered to the same NPC become one stop.
  - Stops are ordered by travel time across both continents, using the flight paths the character knows, boats,
    zeppelins, the Deeprun Tram and, once, the Hearthstone when it saves time.
  - Each stop comes with directions ("Fly from … to …", "Take the boat from … to …"). The arrow (TomTom, or the
    game's map pin) points at the flight master or dock first, then at the NPC, and moves on as you travel and
    deliver.
  - A small **route tracker** window shows the next 5 steps while a route is active.
  - `/writs why` prints the planner's travel times for the current leg.
  - An active route is planned again after a `/reload` or relog.
  - Shows the route's reputation, and how much is still to go as you deliver.
  - Uses only your faction's boats, zeppelins and tram.
- Click a writ, or a zone heading, to set waypoints to its turn-ins.
- Writ tooltips show an estimated Auction House price and the reputation per gold spent, using prices from
  Auctionator or TradeSkillMaster (any TSM custom price string). Optionally includes the writ's own price.
- **Buy Writs** tab: a table of the writs on the Auction House (name, level, price of writ + required items,
  rep per gold, where you already have it), 20 per page. Click a column title to sort by it. Filter by turn-in zone
  and NPC, and hide writs you carry or have done today. Shows when Auctionator last did a full scan.
  - Picks the cheapest writs to buy to reach your next standing today, counting the writs you already have.
- **Alts and bank:** remembers the writs and writ items in each character's bags and bank. Writ tooltips, crafted
  item tooltips, the Shopping tab and Buy Writs show copies in your bank and on alts (same realm and faction).
- **Settings** tab: item tooltips, price source, writ price in estimates, your Diplomat rank (Legacy perk, +2%
  reputation per rank, per character), Hearthstone use, route tracker, minimap button, and the list of remembered
  characters.
- Minimap button (left-click: window, right-click: plan a route), item tooltips on writs and wanted crafts, and a
  **Shopping** tab of missing crafted items.
- Turn-in spots are remembered from the quest map marker as soon as you accept a writ, and taken from QuestieDB
  at runtime when it's installed. `/writs export` shares what you've recorded.

- **My Writs** tab: a table of the writs in your quest log (and, optionally, unstarted writs in your bags) with
  status, how many of the required item you have, rep per gold, the turn-in NPC and zone. Click a column title to
  sort. Above it: the reputation your writs are worth and what it does for your standing.
  - Below it, a folding section for each of your other characters (same realm and faction) with their writs, as of
    when you last played them.
- **All Writs** tab: all 150 writs in a table, 20 per page, with profession, level, status, rep per gold and turn-in
  zone. Filter by profession and level, and hide writs done today.
- Daily reset countdown in the window's status bar.
- Records the turn-in NPC and position every time you deliver a writ (`/writs learned`). This fills in the
  Expert/Artisan locations that aren't documented yet.

Commands: `/writs` (toggle window), `/writs route`, `/writs clear`, `/writs tracker`, `/writs why`,
`/writs shopping`, `/writs all`, `/writs buy`, `/writs settings`, `/writs status`, `/writs learned`, `/writs export`, `/writs minimap`, `/writs tooltips`, `/writs resetpos`.

## Install (development)

The addon folder is `CraftmansHelper/`. Copy it, or link it, into your Forever AddOns folder, for example
`C:\Games\World of Warcraft\_forever_\Interface\AddOns\CraftmansHelper`, then `/reload` in game.

The interface version in the TOC is `16001` (WoW: Forever 1.60.1). Check it in-game with
`/dump select(4, GetBuildInfo())` if the addon shows as out of date.

## Layout

| Path | What |
|---|---|
| `CraftmansHelper/CraftmansHelper.toc` | Addon manifest |
| `CraftmansHelper/Libs/` | Embedded Ace3 (LibStub, CallbackHandler, AceAddon/Event/Timer/Bucket/DB/Console/GUI) |
| `CraftmansHelper/Data/Writs.lua` | All 150 writs: writ item ID → quest, tier, professions, required item, count, turn-in key |
| `CraftmansHelper/Data/TurnIns.lua` | Turn-in NPCs → zone (uiMapID) and coordinates where known |
| `CraftmansHelper/Data/FlightMasters.lua` | Flight masters with position and faction (generated from QuestieDB) |
| `CraftmansHelper/Data/Transports.lua` | Boats, zeppelins, skycutters and the tram: one-way links between docks (Glyalith's data) |
| `CraftmansHelper/Data/FlightLengths.lua` | Flown length of every direct flight route, by taxi node (Glyalith's data) |
| `CraftmansHelper/Core.lua` | Addon object, saved variables, slash commands |
| `CraftmansHelper/Zones.lua` | uiMapID → zone/continent resolution (localized via `C_Map`, English fallback) |
| `CraftmansHelper/Tracker.lua` | Writ state (done today / in log / in bags / ready), daily reset, turn-in learning |
| `CraftmansHelper/Alts.lua` | Writs and writ items on each character's bags and bank (account-wide) |
| `CraftmansHelper/Questie.lua` | Optional runtime turn-in lookup in QuestieDB (`_G.LibQuestieDB`) |
| `CraftmansHelper/Prices.lua` | Optional Auction House price estimates via Auctionator's or TSM's API; reputation per tier |
| `CraftmansHelper/Tooltips.lua` | Writ info in item tooltips |
| `CraftmansHelper/Minimap.lua` | Minimap button (LibDataBroker + LibDBIcon) |
| `CraftmansHelper/Nav.lua` | Waypoints: TomTom, or the game's map pin as a fallback |
| `CraftmansHelper/Solver.lua` | Route ordering on any cost (pure Lua): exact for 10 stops or fewer, nearest-neighbour + 2-opt above that |
| `CraftmansHelper/Travel.lua` | Travel-time graph (riding, flights, boats, zeppelins, tram) and shortest paths |
| `CraftmansHelper/FlightPaths.lua` | Learns the character's known flight paths when a flight map is opened |
| `CraftmansHelper/Hearth.lua` | Learns where the Hearthstone takes you; cooldown |
| `CraftmansHelper/Route.lua` | Builds stops from deliverable writs, orders them by travel time, directions, follows the route |
| `CraftmansHelper/UI/MainFrame.lua` | AceGUI window |
| `CraftmansHelper/UI/RouteTracker.lua` | Small movable "next steps" window |
| `CraftmansHelper/Media/` | Textures (the dotted line between table rows) |
| `tests/` | Lua 5.1 tests (`pip install lupa`): `test_solver.py`, `test_route.py`, `test_travel.py`, `test_sources.py`, `test_prices.py`, `test_alts.py` |
| `tools/gen_flightmasters.py` | Regenerates `Data/FlightMasters.lua` from a QuestieDB TOC |
| `tools/import_travel.py` | Regenerates `Data/Transports.lua` and `Data/FlightLengths.lua` from EllesmereUI Forever Essentials |
| `tools/import_locations.py` | Merges `/writs export` text from players into `Data/` (`--dry-run` to preview) |
| `tools/validate.py` | Data and TOC sanity checks: `python tools/validate.py` |
| `tools/package.ps1` | Builds the release zip in `.release/` for upload to CurseForge |

## Releasing

1. Bump `## Version` in the TOC and add an entry to `CHANGELOG.md`.
2. Run `python tools/validate.py`.
3. Run `powershell -ExecutionPolicy Bypass -File tools\package.ps1`. This writes
   `.release/CraftmansHelper-<version>.zip`, which contains the `CraftmansHelper/` folder.
4. Upload the zip to CurseForge (game version: WoW Forever), then tag the commit `v<version>`.

## How turn-in locations are resolved

Sources, in order of priority:

1. Coordinates in `Data/TurnIns.lua`.
2. Locations recorded in-game at a turn-in.
3. QuestieDB at runtime, if it's installed.
4. The quest's map marker: recorded when the writ is accepted, or read live while it's in the quest log.
5. The zone only, from `Data/TurnIns.lua`.

Players can share their recorded locations with `/writs export`. Merge them with
`python tools/import_locations.py <file>`.

Current data: 80 of 150 writs have a turn-in NPC with coordinates (all 45 Journeyman writs, 34 of the 60 Expert
writs and 1 of the 45 Artisan writs).

## How routes are timed

`Travel.lua` builds a graph of the flight masters the character knows, the docks of every boat / zeppelin /
skycutter / tram link, the player and the stops, and runs Dijkstra between them. Estimates:

- Riding: straight-line distance × 1.3 inside a zone, × 1.6 across zone borders, at the speed of the riding skill
  the character knows (on foot below level 40 without one).
- Flying: the measured length of each flight route at 30.4 yd/s, plus 8 s per hop. Only real routes are
  flown; longer flights chain hops. Flight masters are matched to the game's taxi nodes at login. Any that
  can't be matched fall back to straight line × 1.25, plus 20 s.
- Boats, zeppelins and skycutters: 4 minutes including the wait; the tram 2 minutes. Links are one-way
  (some boats sail a loop).
- Hearthstone: 30 s, used at most once, only where it's off cooldown and saves at least a minute.
- Teldrassil, the Riverglades and Zephras Isle count as islands. Landmasses with no known link get a 15-minute fallback.

Transport links and flight lengths are Glyalith's WoW Forever data. Re-import them with
`python tools/import_travel.py <EllesmereUIForeverEssentials folder>`. The Stormwind portal isn't used yet, because
its arrival point isn't in the data.

## Roadmap

- ~~TomTom waypoints, straight-line route planner~~ (1.1.0), ~~data sources, tooltips, shopping list, minimap
  button~~ (1.2.0), ~~smarter routes: flight paths, boats/zeppelins, hearthstone~~ (1.5.0).
- ~~Forever's boat routes and measured flight times~~ (Glyalith's data), ~~tracking writs across alts and the
  bank~~ (1.8.0).

## Notes on the data

- *Silver Skeleton Key* is delivered to a "Battered Trunk" object in Duskwood, not an NPC.

## Credits and license

Copyright (C) 2026 Emsworth. Released under the [GNU General Public License v3.0](LICENSE.md).

- Turn-in NPCs and coordinates, flight masters, and the zeppelin masters and shipmasters used as dock positions
  come from [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0).
- Boat, zeppelin, skycutter and tram connections and measured flight route lengths were collected by
  **Glyalith** for [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI) Forever Essentials, and are used
  with their kind permission. Thank you!
- The list of writs comes from [Wowhead's Craftsman's Writs guide](https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards).
- Embeds [Ace3](https://github.com/WoWUIDev/Ace3) (see `CraftmansHelper/Libs/Ace3-LICENSE.txt`),
  [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) and LibDBIcon-1.0.
