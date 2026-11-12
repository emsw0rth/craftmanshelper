"""Merge turn-in locations exported in-game (/writs export) into the addon data.

    python tools/import_locations.py export1.txt [export2.txt ...] [--dry-run]

Each export line is  quest;source;id;kind;name;map;x;y  (v2; v1 used "|", which WoW mangles in
edit boxes, but well-formed v1 lines are still accepted).  Locations recorded at an actual
turn-in ("turnin", with an NPC/object ID) win over map-marker ones ("marker"). Writs that
already have coordinates in Data/TurnIns.lua are left alone.
"""
import re
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "CraftmansHelper" / "Data"
WRITS = DATA / "Writs.lua"
TURNINS = DATA / "TurnIns.lua"
SECTION = "    -- Contributed: recorded in-game by players (/writs export)"


def parse_exports(paths):
    best = {}  # quest -> record
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            parts = line.split(";") if ";" in line else line.split("|")
            if len(parts) != 8 or not parts[0].isdigit():
                continue
            quest, source, eid, kind, name, map_id, x, y = parts
            rec = {"quest": int(quest), "source": source, "id": int(eid) if eid.isdigit() else None,
                   "kind": kind, "name": name or None, "map": int(map_id), "x": float(x), "y": float(y)}
            prev = best.get(rec["quest"])
            rank = lambda r: (r["source"] == "turnin", r["id"] is not None)
            if prev is None or rank(rec) > rank(prev):
                best[rec["quest"]] = rec
    return best


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if not args:
        print(__doc__)
        sys.exit(2)

    records = parse_exports(args)
    writs = WRITS.read_text(encoding="utf-8")
    turnins = TURNINS.read_text(encoding="utf-8")

    rows = {int(m[2]): (int(m[1]), m[0]) for m in re.finditer(
        r"^    \[(\d+)\] = \{ quest = (\d+),.*\},?.*$", writs, re.M)}  # quest -> (writID, line)
    keys_with_coords = set()
    for m in re.finditer(r"^\s*(\[(\d+)\]|([A-Z_0-9]+)) = \{([^\n]*)\},", turnins, re.M):
        if "x =" in m[4]:
            keys_with_coords.add(m[2] or m[3])

    new_entries, changed = [], 0
    for quest, rec in sorted(records.items()):
        if quest not in rows:
            print(f"skip quest {quest}: not a writ")
            continue
        writ_id, line = rows[quest]
        current = re.search(r'turnIn = "?(\w+)"?', line)
        if current and current[1] in keys_with_coords:
            print(f"skip quest {quest}: already has coordinates ({current[1]})")
            continue

        if rec["id"] and rec["kind"] == "GameObject":
            key, lua_key = f"OBJECT_{rec['id']}", f"OBJECT_{rec['id']}"
        elif rec["id"]:
            key, lua_key = str(rec["id"]), f"[{rec['id']}]"
        else:
            key, lua_key = f"QUEST_{quest}", f"QUEST_{quest}"

        if key not in keys_with_coords:
            name = rec["name"] or "Turn-in"
            obj = ", object = true" if rec["kind"] == "GameObject" else ""
            new_entries.append(f"    {lua_key} = {{ name = {lua_str(name)}, map = {rec['map']}, "
                               f"x = {rec['x']:.1f}, y = {rec['y']:.1f}{obj} }}, -- {rec['source']}")
            keys_with_coords.add(key)

        value = key if key.isdigit() else f'"{key}"'
        if current:
            new_line = re.sub(r'turnIn = "?\w+"?', f"turnIn = {value}", line)
        else:
            new_line = re.sub(r" \},", f", turnIn = {value} }},", line, count=1)
        writs = writs.replace(line, new_line)
        changed += 1
        print(f"quest {quest} (writ {writ_id}) -> {key} at map {rec['map']} ({rec['x']:.1f}, {rec['y']:.1f})")

    if not changed:
        print("Nothing to import.")
        return
    if new_entries:
        body = "\n".join(new_entries)
        if SECTION in turnins:
            turnins = turnins.replace(SECTION + "\n", SECTION + "\n" + body + "\n", 1)
        else:
            turnins = re.sub(r"\n\}\s*$", "\n" + SECTION + "\n" + body + "\n}\n", turnins)
    if dry:
        print(f"\n(dry run) would update {changed} writ(s), add {len(new_entries)} location(s)")
        return
    WRITS.write_text(writs, encoding="utf-8", newline="\n")
    TURNINS.write_text(turnins, encoding="utf-8", newline="\n")
    print(f"\nUpdated {changed} writ(s), added {len(new_entries)} location(s). Run tools/validate.py next.")


if __name__ == "__main__":
    main()
