# Changelog

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
