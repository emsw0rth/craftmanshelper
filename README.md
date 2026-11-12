# Craftman's Helper

A World of Warcraft: Forever addon for Craftsman's Writs: the daily crafting orders that give reputation with
**Azeroth Commerce Authority** (Alliance) / **Durotar Supply and Logistics** (Horde).

## Features (v1.1.0)

- **Route** tab: plans a delivery route over every writ you can hand in right now.
  - Writs delivered to the same NPC become one stop, and each continent is ordered separately, starting with the
    one you're on.
  - Navigation uses TomTom waypoints, or the game's map pin as a fallback, and moves to the next stop after each
    delivery.
- Click a writ, or a zone heading, to set waypoints to its turn-ins.

- **My Writs** tab: the writs in your quest log (and, optionally, unstarted writs in your bags), grouped by
  continent (Kalimdor, then Eastern Kingdoms) and then by zone, sorted A–Z. Each row shows whether it is ready to
  deliver, how many of the required item you have, and who to deliver it to.
- **All Writs** tab: all 150 writs, filterable by profession and level, showing which are already done today.
- Daily reset countdown in the window's status bar.
- Records the turn-in NPC and position every time you deliver a writ (`/writs learned`). This fills in the
  Expert/Artisan locations that aren't documented yet.

Commands: `/writs` (toggle window), `/writs route`, `/writs clear`, `/writs all`, `/writs status`,
`/writs learned`.

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
| `CraftmansHelper/Core.lua` | Addon object, saved variables, slash commands |
| `CraftmansHelper/Zones.lua` | uiMapID → zone/continent resolution (localized via `C_Map`, English fallback) |
| `CraftmansHelper/Tracker.lua` | Writ state (done today / in log / in bags / ready), daily reset, turn-in learning |
| `CraftmansHelper/Nav.lua` | Waypoints: TomTom, or the game's map pin as a fallback |
| `CraftmansHelper/Solver.lua` | Route ordering (pure Lua): exact for 10 stops or fewer, nearest-neighbour + 2-opt above that |
| `CraftmansHelper/Route.lua` | Builds stops from deliverable writs, splits by continent, follows the route |
| `CraftmansHelper/UI/MainFrame.lua` | AceGUI window |
| `tests/` | Lua 5.1 tests for the solver and route logic: `pip install lupa`, then `python tests/test_solver.py` and `python tests/test_route.py` |
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
2. Locations learned in-game on turn-in.
3. The quest's own map marker (`C_QuestLog.GetNextWaypoint`), for accepted writs.
4. The zone only, from `Data/TurnIns.lua`.

Current data: 76 of 150 writs have a turn-in NPC with coordinates (all 45 Journeyman writs and 31 of the 60 Expert
writs). Nothing is known yet for the Artisan writs.

## Roadmap

- ~~Phase 2: TomTom waypoints~~ and ~~Phase 3: route planner (straight-line)~~ shipped in 1.1.0.
- **Next:** smarter routes that account for flight paths, boats/zeppelins and hearthstone.
- **Phase 4:** complete the Expert/Artisan data (runtime lookup in QuestieDB when it's installed, plus importing
  locations learned in-game).
- **Phase 5:** item tooltips (writ status, and "needed for writ X" on crafted items), shopping list, minimap
  button, bank/alt tracking.

## Notes on the data

- *Silver Skeleton Key* is delivered to a "Battered Trunk" object in Duskwood, not an NPC.

## Credits and license

Copyright (C) 2026 Patrick Larsen. Released under the [GNU General Public License v3.0](LICENSE.md).

- Turn-in NPCs and coordinates come from [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0).
- The list of writs comes from [Wowhead's Craftsman's Writs guide](https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards).
- Embeds [Ace3](https://github.com/WoWUIDev/Ace3) (see `CraftmansHelper/Libs/Ace3-LICENSE.txt`).
