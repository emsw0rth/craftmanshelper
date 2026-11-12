# Changelog

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
