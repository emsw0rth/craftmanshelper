# Craftman's Helper

A World of Warcraft: Forever addon for Craftsman's Writs: the daily crafting orders that give reputation with
**Azeroth Commerce Authority** (Alliance) / **Durotar Supply and Logistics** (Horde).

**▶ [Watch the showcase video](https://youtu.be/eb8AAkmVXmM)** (November 2026, v1.10.2)

Download: [CurseForge](https://www.curseforge.com/wow/addons/craftmans-writ-helper) ·
[Wago](https://addons.wago.io/addons/craftmans-writ-helper)

## Features (v2.2.0)

- **Route** tab: plans a delivery route over every writ you can hand in right now.
  - Writs delivered to the same NPC become one stop.
  - Stops are ordered by travel time across both continents, using the flight paths the character knows, boats,
    zeppelins, the Deeprun Tram, teleports (mage city teleports and Teleport: Moonglade, as often as they help;
    the engineering transporters once, when turned on) and, once, the Hearthstone when it saves time. A continent where the character
    knows no flight paths yet gets a reminder to open a flight master's map there.
  - Can stick to one continent (dropdown in the Route tab, per character).
  - Goes past flight masters the character doesn't know yet when they're at most a minute off the route ("Pick up the
    flight path at Booty Bay (Stranglethorn Vale)"). Can be turned off in Settings.
  - Each stop comes with directions ("Fly from Ratchet (The Barrens) to Gadgetzan (Tanaris), about 3 min", "Take the boat from … to …"). The arrow (TomTom, or the
    game's map pin) points at the flight master or dock first, then at the NPC, and moves on as you travel and
    deliver.
  - A small **route tracker** window shows the next 5 steps while a route is active. Show or hide it with the
    button in the Route tab.
  - Under the steps, a button for each writ at the current stop that's still unstarted in your bags: click it to
    start the writ's quest. Or bind a key to **Start the next writ** (Key Bindings → Craftman's Helper).
  - `/writs why` prints the planner's travel times for the current leg.
  - An active route is planned again after a `/reload` or relog.
  - Shows the route's reputation, and how much is still to go as you deliver.
  - Uses only your faction's boats, zeppelins and tram.
- Click a writ, or a zone heading, to set waypoints to its turn-ins.
- Writ tooltips show an estimated Auction House price and the reputation per gold spent, using prices from
  Auctionator, TradeSkillMaster (any TSM custom price string), auxForever (its Value) or SnapPrice (lowest buyout from its last full scan). Optionally includes the writ's own price.
- **Coin pouch cashback:** the Coin Pouch each turn-in gives is counted as money back in rep per gold and the
  cheapest way to your next standing ("profit" when it pays more than the writ costs). Starts from Wowhead's
  average per writ level and learns from the pouches you open (`/writs pouches`). The route shows about how much its
  pouches will give, and `/writs pouches` and Settings show what your pouches have given you so far.
- **Buy Writs** tab: a table of the writs on the Auction House (name, level, price of writ + required items,
  rep per gold, where you already have it), 20 per page. Click a column title to sort by it. Filter by turn-in
  continent, zone and NPC, and hide writs you carry or have done today. Shows when Auctionator or SnapPrice last did a full scan.
  - Picks the cheapest writs to buy to reach your next standing today, counting the writs you already have.
- **Craftman's tab in the Auction House:** lists of writs, writ items, Waylaid Crates and crate materials, with the
  same filters as the addon's own tabs, plus **Items for my writs** (what the writs you hold still need) and
  **Materials for my crates** (every fill for the crates in your bags). **Search** looks each item up in turn and shows the
  lowest price, how many are listed and what the amount you need costs. Click a row to open it in the Auction House's
  own Buy screen. The searches are also a price source: newer than your price addon's price, or the only one without a
  price addon. Buy Writs, Shopping and Crates get a "Search at the Auction House" button while it's open.
- **TradeSkillMaster and auxForever:** both hide the game's Auction House window behind their own. A **Craftman's**
  button in their window (next to TSM's "WoW UI", or in aux's top bar) switches to the game's window on the
  Craftman's tab. `/writs ahcheck` shows what the addon found of their windows, if the button doesn't appear.
- **Tutorials:** a guided tour of the window on your first login, and one of the Auction House's Craftman's tab
  the first time you open it. Everything but the part being explained is dimmed, with Back, Next and Close tutorial
  buttons. Settings → Reset tutorials (or `/writs tutorial`) shows them again.
- **Crates** tab: every Waylaid Crate with its cheapest fill, the cost (empty crate + fill, less the silver paid at the
  hand-in), the Merchant's Favor it gives and the gold per Favor. Hover for every fill option and where to hand it in;
  filter by level, gathered or crafted, and crates you have. Shows your Favor, and what 50 reputation costs through a
  Forged Delivery Receipt (15 Favor + an empty crate) next to the best writ to buy. Crate tooltips show the cheapest fill.
- **Alts and bank:** remembers the writs and writ items in each character's bags and bank. Writ tooltips, crafted
  item tooltips, the Shopping tab and Buy Writs show copies in your bank and on alts (same realm and faction).
- **Settings** tab: item tooltips, price source, writ price in estimates, your Diplomat rank (Legacy perk, +2%
  reputation per rank, per character), Hearthstone and teleport use, route tracker, minimap button, and the list of remembered
  characters.
- **Recipe markers:** recipes at the trainer and in your profession window that craft an item a writ asks for
  get a small icon; hover it to see which writs. The trainer's recipe tooltips list them too.
- Minimap button (left-click: window, right-click: plan a route), item tooltips on writs and wanted crafts, and a
  **Shopping** tab of missing crafted items, which you can filter by turn-in continent, zone and NPC.
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
`/writs shopping`, `/writs all`, `/writs buy`, `/writs crates`, `/writs settings`, `/writs tutorial`, `/writs ahcheck`, `/writs status`, `/writs learned`, `/writs pouches`, `/writs pouches debug`, `/writs export`, `/writs minimap`, `/writs tooltips`, `/writs resetpos`.

## Install (development)

The addon folder is `CraftmansHelper/`. Copy it, or link it, into your Forever AddOns folder, for example
`C:\Games\World of Warcraft\_forever_\Interface\AddOns\CraftmansHelper`, then `/reload` in game.

The interface version in the TOC is `16001` (WoW: Forever 1.60.1). Check it in-game with
`/dump select(4, GetBuildInfo())` if the addon shows as out of date.

## Layout

| Path | What |
|---|---|
| `CraftmansHelper/CraftmansHelper.toc` | Addon manifest |
| `CraftmansHelper/Libs/` | Embedded Ace3 (LibStub, CallbackHandler, AceAddon/Event/Timer/Bucket/DB/Console/GUI), LibDataBroker, LibDBIcon, LibAHTab |
| `CraftmansHelper/Data/Writs.lua` | All 150 writs: writ item ID → quest, tier, professions, required item, count, turn-in key |
| `CraftmansHelper/Data/TurnIns.lua` | Turn-in NPCs → zone (uiMapID) and coordinates where known |
| `CraftmansHelper/Data/FlightMasters.lua` | Flight masters with position and faction (generated from QuestieDB) |
| `CraftmansHelper/Data/Crossings.lua` | Where you ride from one zone into the next: roads, passes, tunnels, gates (collected in-game) |
| `CraftmansHelper/Data/Transports.lua` | Boats, zeppelins, skycutters and the tram: one-way links between docks (Glyalith's data) |
| `CraftmansHelper/Data/FlightLengths.lua` | Flown length of every direct flight route, by taxi node (Glyalith's data) |
| `CraftmansHelper/Core.lua` | Addon object, saved variables, slash commands |
| `CraftmansHelper/Zones.lua` | uiMapID → zone/continent resolution (localized via `C_Map`, English fallback) |
| `CraftmansHelper/Tracker.lua` | Writ state (done today / in log / in bags / ready), daily reset, turn-in learning |
| `CraftmansHelper/Alts.lua` | Writs and writ items on each character's bags and bank (account-wide) |
| `CraftmansHelper/Questie.lua` | Optional runtime turn-in lookup in QuestieDB (`_G.LibQuestieDB`) |
| `CraftmansHelper/Prices.lua` | Optional Auction House price estimates via Auctionator's, TSM's or auxForever's API, or SnapPrice's saved scan; reputation per tier; coin pouch averages |
| `CraftmansHelper/AHScan.lua` | Searches the Auction House one item at a time and keeps the results (a price source) |
| `CraftmansHelper/UI/AuctionTab.lua` | The "Craftman's" tab in the Auction House (tab button from LibAHTab, MIT), and its buttons in TradeSkillMaster's and auxForever's windows |
| `CraftmansHelper/Tutorial.lua` | Guided tours: dims the screen around the part being explained, step card with Back / Next / Close |
| `CraftmansHelper/UI/Tours.lua` | The two tours (main window, Auction House tab) and when they start |
| `CraftmansHelper/Crates.lua` | Waylaid Crate costs per Merchant's Favor, and reputation through Forged Delivery Receipts (bundles in `Data/Crates.lua`) |
| `CraftmansHelper/Pouches.lua` | Learns how much gold each coin pouch gives when it's opened |
| `CraftmansHelper/Tooltips.lua` | Writ info in item tooltips |
| `CraftmansHelper/RecipeMarks.lua` | Writ icons on trainer and profession recipes |
| `CraftmansHelper/Minimap.lua` | Minimap button (LibDataBroker + LibDBIcon) |
| `CraftmansHelper/Nav.lua` | Waypoints: TomTom, or the game's map pin as a fallback |
| `CraftmansHelper/Solver.lua` | Route ordering on any cost (pure Lua): exact for 10 stops or fewer, nearest-neighbour + 2-opt above that |
| `CraftmansHelper/Travel.lua` | Travel-time graph (riding, flights, boats, zeppelins, tram) and shortest paths |
| `CraftmansHelper/FlightPaths.lua` | Learns the character's known flight paths when a flight map is opened |
| `CraftmansHelper/Hearth.lua` | Learns where the Hearthstone takes you; cooldown |
| `CraftmansHelper/Teleports.lua` | Mage, druid and engineering teleports the route may use; where they land |
| `CraftmansHelper/Route.lua` | Builds stops from deliverable writs, orders them by travel time, directions, follows the route |
| `CraftmansHelper/UI/MainFrame.lua` | AceGUI window |
| `CraftmansHelper/UI/RouteTracker.lua` | Small movable "next steps" window, with buttons to start the current stop's writs |
| `CraftmansHelper/Bindings.xml` | The "Start the next writ" key binding |
| `CraftmansHelper/Media/` | Textures (the dotted line between table rows) |
| `tests/` | Lua 5.1 tests (`pip install lupa`): `test_solver.py`, `test_route.py`, `test_travel.py`, `test_sources.py`, `test_prices.py`, `test_alts.py`, `test_reputation.py`, `test_pouches.py`, `test_recipemarks.py`, `test_routetracker.py`, `test_zones.py`, `test_crates.py`, `test_ahscan.py` |
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
- Teleports (`Teleports.lua`): 30 s each. Mage teleports (while you carry Runes of Teleportation; a route that
  would need more casts than you have runes is planned without them) and Teleport: Moonglade can be cast from any
  point of the route. The engineering transporters (Ultrasafe Transporter: Gadgetzan, Dimensional Ripper -
  Everlook) are tried once per route like the Hearthstone, and only when turned on in Settings: they can misfire.
  Where each one lands is recorded the first time you use it (only when you land in the expected zone).
- Riding into another zone goes through a crossing: a road, pass, tunnel or gate (`Data/Crossings.lua`, collected
  in-game). Each one is a direction ("Ride into Tanaris (Thousand Needles 74.9, 93.3)") with the arrow on it. From
  Thousand Needles, Un'Goro Crater is reached through Tanaris. Capital gates are for their own faction, and the
  Searing Gorge gate only counts with the Key to Searing Gorge.
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
- The list of writs, and some Expert and Artisan turn-in NPCs, come from [Wowhead's Craftsman's Writs guide](https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards) and its quest and NPC pages.
- Embeds [Ace3](https://github.com/WoWUIDev/Ace3) (see `CraftmansHelper/Libs/Ace3-LICENSE.txt`),
  [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1), LibDBIcon-1.0 and
  [LibAHTab](https://github.com/TheMouseNest/LibAHTab) by plusmouse (MIT, see `CraftmansHelper/Libs/LibAHTab/LICENSE`).
