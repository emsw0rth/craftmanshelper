# Changelog

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
