# Craftman's Helper

A World of Warcraft: Forever addon for Craftsman's Writs: the daily crafting orders that give reputation with
**Azeroth Commerce Authority** (Alliance) / **Durotar Supply and Logistics** (Horde).

## Status: Phase 1 (tracking)

- **My Writs** tab: the writs in your quest log (and, optionally, unstarted writs in your bags), grouped by
  continent (Kalimdor, then Eastern Kingdoms) and then by zone, sorted A–Z. Each row shows whether it is ready to
  deliver, how many of the required item you have, and who to deliver it to.
- **All Writs** tab: all 150 writs, filterable by profession and level, showing which are already done today.
- Daily reset countdown in the window's status bar.
- Records the turn-in NPC and position every time you deliver a writ (`/writs learned`). This fills in the
  Expert/Artisan locations that Wowhead doesn't have yet.

Commands: `/writs` (toggle window), `/writs all`, `/writs status`, `/writs learned`.

## Install (development)

The addon folder is `CraftmansHelper/`. Forever shares the retail `Interface\AddOns` folder. Link it in, rather than
copying it, so that edits show up after a `/reload`. In PowerShell (adjust the WoW path if yours differs):

```powershell
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CraftmansHelper" -Target "C:\dev\projects\craftmans-helper\CraftmansHelper"
```

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
| `CraftmansHelper/UI/MainFrame.lua` | AceGUI window |
| `tools/validate.py` | Data and TOC sanity checks: `python tools/validate.py` |

## How turn-in locations are resolved

Sources, in order of priority:

1. Coordinates in `Data/TurnIns.lua`.
2. Locations learned in-game on turn-in.
3. The quest's own map marker (`C_QuestLog.GetNextWaypoint`), for accepted writs.
4. The zone only, from `Data/TurnIns.lua`.

Current data: 47 of 150 writs have a known zone (all 45 Journeyman writs, plus 2 Expert writs). 33 Expert writs have
a known NPC ID but no zone yet, and nothing is known for the Artisan writs.

## Roadmap

- **Phase 2:** TomTom waypoints (click a row or zone), with the built-in map pin as a fallback when TomTom isn't
  installed.
- **Phase 3:** route planner, per continent, over unique turn-in stops. Version 1 uses straight-line distance;
  version 2 adds flight paths, boats/zeppelins and hearthstone.
- **Phase 4:** complete the Expert/Artisan data (throttled Wowhead scraper, plus importing locations learned
  in-game).
- **Phase 5:** item tooltips (writ status, and "needed for writ X" on crafted items), shopping list, minimap
  button, bank/alt tracking.

## Unverified data

- *Shadow Protection Potion*: the quest page also lists item 284583. It is counted as an alternative.
- *Silver Skeleton Key*: delivered to a "Battered Trunk" object in Duskwood, not an NPC.
