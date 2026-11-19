# Changelog

## 1.10.2

- **27 more turn-in locations:** 107 of the 150 writs now have a known turn-in, up from 80.
  - 10 recorded by players with `/writs export`, including Artisan turn-ins at Hastings (Deadwind Pass) and
    Kum'isha the Collector (Blasted Lands). Thank you!
  - 17 from Wowhead, among them Durganon (Searing Gorge), Taronn Redfeather and Eridan Bluewind (Felwood),
    Mylentha Riverbend (Moonglade), Bor'dorc (Winterspring), Calliard (Deadwind Pass) and Hermit Ortell (Silithus).
- These writs now get waypoints and a place in your route.

## 1.10.1

- **Fixed:** shift-clicking an item or writ in the addon now searches for it in Auctionator's Shopping tab, like
  shift-clicking an item in your bags. This works in My Writs, All Writs, Buy Writs and the Shopping list.
- **New command:** `/writs resetpos` moves the window back to the middle of the screen at its default size, and the
  route tracker back to its default spot, for when one ends up off-screen.

## 1.10.0

- **Cheapest way to your next standing:** Buy Writs picks the cheapest writs to buy to reach your next standing
  today, for example "Honored is 1,475 reputation away. Cheapest way there: 4 writs for 23g 10s".
  - Writs you already have (quest log, bags or bank) count toward it. Writs you've done today aren't suggested.
  - Click the line to show only those writs, and click again to show every writ. Hover it for the list.
- **Diplomat:** set your rank of the Legacy perk Diplomat (+2% reputation per rank) in **Settings → Reputation**.
  It's saved per character, and every reputation amount and rep per gold includes it.
- **Your other characters in My Writs:** below your own writs, a section for each of your characters on the same
  realm and faction, with the writs in their quest log, bags and bank.
  - Each heading shows their number of writs, the reputation they're worth and how many are ready. Click it to
    unfold their table, which also shows their standing.
  - It's as of when you last played them. Log in on each character once to fill it in.
  - Turn it off with **Show my other characters**.
- **My Writs** has a Rep/gold column.
- Hovering a writ in **My Writs** or **All Writs** shows the writ's own tooltip, and shift-click links the writ.

## 1.9.0

- **Fixed:** routes no longer use the other faction's transport. Horde routes skip the Alliance boats (Menethil,
  Auberdine, Theramore, Southshore, Rut'theran, Feathermoon, Stormwind), the Deeprun Tram and the Dalaran
  skycutter. Alliance routes skip every zeppelin, including Grom'gol to Tirisfal. Ratchet to Booty Bay and Tanaris
  to the Riverglades stay open to both.
- **Reputation totals:**
  - **My Writs** shows how much reputation the writs in your quest log and bags are worth, how much of it is
    ready to turn in now, and what's in your bank.
  - **Route** shows the route's reputation and, as you deliver, how much is still to go.
  - Both say what it does for your standing, such as "Friendly 5,600 / 6,000 now: enough to reach Honored".
  - Each writ counts once, since writs are daily. Amounts are base reputation, before bonuses.
- **My Writs and All Writs are now tables**, like Buy Writs: click a column title to sort, click again to reverse.
- **All Writs** is split into pages and has a Rep/gold column.

## 1.8.1

- **Fixed:** lists jumped back to the top after a few moments while you scrolled and hovered writs. The window
  now keeps its scroll position when it updates, on every tab.
- The window updates less often: only when a writ, item count or turn-in actually changes, not every time the
  game reports quest log or bag activity, or loads an item you hovered.

## 1.8.0

- **Alts and bank:** the addon now remembers which writs and writ items each of your characters has in their
  bags and bank.
  - **Buy Writs** shows where you already have a writ: your quest log, bags, bank, or an alt.
  - **Writ and crafted item tooltips** get an "Also have" line listing copies in your bank and on your alts.
  - The **Shopping** tab shows when a missing item is in your bank or on an alt.
  - Alts count when they're on your realm and faction, since they can mail you what they hold. Characters show
    by their full name, first name and surname.
  - Log in on each character once to add it, and open its bank once to include the bank.
  - **Settings → Characters** lists every remembered character, with a **Forget** button.
- **Buy Writs is now a table:** Name, Level, Price, Rep/gold and Have.
  - Click a column title to sort by it, and click again to reverse the order. The sort covers every page.
  - Fixed rows and columns with borders, a boxed header, and dotted lines between rows.
  - The Sort by and Level dropdowns are gone: sort with the column titles instead.
  - **Hide writs I have** now hides only writs in your quest log or bags. Writs in your bank or on an alt stay
    in the list, with where they are in the Have column.
- Writ names no longer show "x1". The one writ that asks for more, Crafted Solid Shot, still shows "x200".

## 1.7.1

- **Buy Writs:**
  - New **Hide writs I have** option, on by default. It hides writs that are already in your quest log, bags
    or bank.
  - The sort, filter and page controls are laid out in fixed rows, so they no longer jumble together,
    whatever the window size.
- **Fixed:** the Buy Writs tab said there had been no Auction House scan yet after Auctionator's normal scan.
  It now shows the time of your last scan.

## 1.7.0

- **Every Forever boat and zeppelin route:** routes now know all 27 boat, zeppelin, skycutter and tram
  connections, including Forever's new ones:
  - Southshore, and Stormwind ↔ Auberdine
  - Steamwheedle Port ↔ the Riverglades
  - Mulgore ↔ Zephras Isle, and the Dalaran skycutter
  - the Feathermoon ferry

  The dock positions are exact now, and the loop that some boats sail is followed correctly.
- **Measured flight times:** flights use the real flown length of every flight route, instead of a straight-line
  estimate. Only routes that exist are flown, and a trip that takes several hops shows as one flight in the
  directions.
- `/writs why` also shows how many flight masters were matched to measured flight routes.
- **Credits** section at the bottom of the Settings tab.
- The travel data was collected by **Glyalith** for EllesmereUI Forever Essentials and is used with their kind
  permission. Thank you!

## 1.6.0

- **TradeSkillMaster as a price source:**
  - Writ tooltips and the Buy Writs tab can now use TSM prices as well as Auctionator's.
  - **Settings → Price source:** Automatic (the default) uses Auctionator, or TSM if Auctionator isn't installed.
    You can also pick one.
  - TSM uses any custom price string you enter. The default is `first(DBMinBuyout, DBMarket)`.
- **Last scan time:** the Buy Writs tab and Settings show when Auctionator last did a full scan of the Auction
  House.
- **Your route survives a /reload or relog:** an active route is planned again from where you are a few seconds
  after logging in.

## 1.5.0

- **Smarter routes:** the route is now planned by travel time across both continents, instead of straight-line
  distance with each continent planned on its own.
  - **Flight paths:** used wherever flying is quicker. The addon learns which flight paths a character knows when
    you open a flight master's map, so open it once on each continent.
  - **Boats, zeppelins and the Deeprun Tram** connect the continents and islands.
  - **Hearthstone:** used once when it's off cooldown and saves at least a minute. The addon learns where it takes
    you when you use it or set it at an innkeeper. You can turn this off in Settings.
  - Riding speed follows your riding skill.
- **Directions for every stop**, for example "Fly from Bragok (The Barrens) to Bera Stonehammer (Tanaris)" or
  "Take the boat from Stranglethorn Vale to The Barrens", in the Route tab and in chat.
- **The arrow leads the way:** it points at the flight master or dock first, then at the turn-in NPC, and moves
  on by itself as you travel.
- **Route tracker** (`/writs tracker`): a small movable window with the next 5 steps of your route, so the main
  window can stay closed. Click a stop to head there instead. Its show and lock options are in Settings.
- **Buy Writs:**
  - Filter by turn-in zone and NPC.
  - Each writ shows how many of its item you need, and the tooltip shows where it's delivered.
- `/writs why` prints the route planner's travel times for the current leg, to help report a route that looks
  wrong.

Known gaps: Forever's new boat routes (Southshore, Stormwind, Steamwheedle Port, Zephras Isle) aren't included
yet, and some dock positions are estimates.

## 1.4.1

- **Route waypoints name the writs:** each TomTom waypoint now shows the turn-in NPC and the writs to deliver
  there, for example "Kixxle: Draught of Water Breathing, Goblin Rocket Fuel". After three writs it adds "+N more".
- The **Buy Writs** tab now comes before **All Writs**.

## 1.4.0

- **Buy Writs tab** (or `/writs buy`, requires Auctionator): the writs for sale on the Auction House, with what
  each one costs to complete. That's the writ plus the items it asks for.
  - Sort by price (cheapest first) or by rep per gold.
  - Filter by level, and hide writs you've already done today (on by default).
  - 20 writs per page. Hover a writ for the price breakdown, and shift-click to link it, for example into the
    Auction House search.
  - Writs whose item has no price yet are listed last.
- **Settings tab** (or `/writs settings`):
  - Turn writ info in item tooltips on or off.
  - Show or hide the minimap button.
  - **New option, off by default:** include the writ's own Auction House price in the tooltip's estimated price
    and rep per gold. Use it if you buy your writs rather than loot them.

## 1.3.0

- **Price estimates in writ tooltips** (requires [Auctionator](https://www.curseforge.com/wow/addons/auctionator)):
  - **Estimated price:** the Auction House price of the items the writ asks for, shown with coin icons. Prices
    more than 3 days old are marked with their age.
  - **Rep per gold:** how much reputation the writ gives for each gold spent. Base reputation is 75 for
    Journeyman, 125 for Expert and 200 for Artisan writs, before any reputation bonuses.
  - Prices come from your latest Auctionator scan. Both lines are left out when Auctionator isn't installed or
    has no price for the item.

## 1.2.0

- **Minimap button:**
  - Left-click opens the window; right-click plans a route.
  - The tooltip shows what's ready, what's in progress, the next route stop, and the time until the daily reset.
  - `/writs minimap` hides or shows the button. It's also available in the addon compartment.
- **Item tooltips:**
  - On a writ: whether it's done today, the item it needs (with how many you have), and where to deliver it.
  - On a crafted item that a writ asks for: which writs want it, and their status.
  - `/writs tooltips` turns them off or on.
- **Shopping tab** (or `/writs shopping`): the crafted items you're still missing for the writs you hold, with how
  many you need and where each writ goes. Shift-click an item to link it, for example into the Auction House
  search.
- **More turn-in locations:**
  - The delivery spot an accepted writ marks on your map is now remembered, so it stays known after the writ
    leaves your quest log, and shows up in routes from then on.
  - If Questie is installed, turn-ins it knows about are used automatically.
- **Share your locations:** `/writs export` shows the turn-in spots you've recorded that the addon doesn't ship
  with yet. Paste them into an issue at github.com/emsw0rth/craftmanshelper/issues to add them for everyone.
- **4 new turn-in locations** from players, including the first Artisan one (Gift of Arthas, Adon in Eastern
  Plaguelands). The addon now knows 80 of the 150 turn-ins.

## 1.1.0

- **Route planner:** the new **Route** tab (or `/writs route`) plans a delivery route for every writ you can hand
  in right now. That includes writs in your bags that you already have the item for.
  - Writs delivered to the same NPC are combined into one stop.
  - Each continent is planned separately, starting with the one you're on, and stops are ordered by the shortest
    path from where you're standing.
  - The waypoint arrow moves on to the next stop each time you deliver, and you can click any stop to go there
    instead.
  - Turn-in NPCs that won't deal with your faction are left out, and writs whose turn-in location isn't known yet
    are listed separately.
- **Waypoints:** click a writ to set a waypoint to its turn-in, or click a zone heading in My Writs for waypoints to
  every writ in that zone.
  - Uses TomTom when it's installed. Otherwise it falls back to the game's own map pin, which shows one stop at a
    time.
- New slash commands: `/writs route` and `/writs clear`.

## 1.0.0 (2026-11-12)

First release.

- **My Writs:** the writs in your quest log, grouped by continent (Kalimdor, then Eastern Kingdoms) and then by
  zone, A–Z. Each row shows whether it is ready to deliver, how many of the item you have, and the turn-in NPC.
- Optionally lists writs in your bags that haven't been started yet.
- **All Writs:** all 150 Craftsman's Writs, filterable by profession and level, showing which you've done today.
- Daily reset countdown.
- Tooltips with the turn-in NPC, zone and coordinates, the item you need, and any spare writs in your bank.
- Turn-in locations with coordinates for all 45 Journeyman writs and 31 of the 60 Expert writs (data from
  QuestieDB).
- Unknown turn-in locations are taken from the quest's map marker, and recorded every time you deliver a writ
  (`/writs learned`).
- Slash commands: `/writs`, `/writs all`, `/writs status`, `/writs learned`.
