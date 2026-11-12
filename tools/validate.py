"""Sanity checks for the addon's data and file layout.

Run from the repo root:  python tools/validate.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "CraftmansHelper"
errors = []


def err(msg):
    errors.append(msg)


# --- TOC: every listed file exists -------------------------------------------
toc = ROOT / "CraftmansHelper.toc"
for line in toc.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        if not (ROOT / line.replace("\\", "/")).exists():
            err(f"TOC lists missing file: {line}")

for xml in ROOT.rglob("*.xml"):
    if "Libs" in xml.parts and xml.parent.parent.name != "Libs":
        continue
    for ref in re.findall(r'file="([^"]+)"', xml.read_text(encoding="utf-8")):
        if not (xml.parent / ref.replace("\\", "/")).exists():
            err(f"{xml.relative_to(ROOT)} references missing file: {ref}")

# --- Data ---------------------------------------------------------------------
writs_src = (ROOT / "Data" / "Writs.lua").read_text(encoding="utf-8")
turnins_src = (ROOT / "Data" / "TurnIns.lua").read_text(encoding="utf-8")

rows = re.findall(r"^\s*\[(\d+)\] = \{(.*)\},", writs_src, re.M)
turnin_keys = set(re.findall(r"^\s*\[(\d+)\]\s*=", turnins_src, re.M))
turnin_keys |= set(re.findall(r"^\s*([A-Z_]+)\s*=\s*\{", turnins_src, re.M))

PROFS = {"ALCHEMY", "BLACKSMITHING", "ENGINEERING", "LEATHERWORKING", "TAILORING"}
TIERS = {"JOURNEYMAN", "EXPERT", "ARTISAN"}

if len(rows) != 150:
    err(f"expected 150 writs, found {len(rows)}")

seen_writ, seen_quest, npc_only = set(), set(), set()
known = 0
for writ_id, body in rows:
    def field(name, pat=r"(\d+)"):
        m = re.search(rf"\b{name} = {pat}", body)
        return m.group(1) if m else None

    quest, tier, item, count = field("quest"), field("tier", r'"(\w+)"'), field("item"), field("count")
    profs = re.findall(r'"(\w+)"', (re.search(r"profs = \{([^}]*)\}", body) or [None, ""])[1])
    turn_in = field("turnIn", r'"?(\w+)"?')

    for name, val in (("quest", quest), ("tier", tier), ("item", item), ("count", count)):
        if val is None:
            err(f"writ {writ_id}: missing {name}")
    if writ_id in seen_writ:
        err(f"duplicate writ {writ_id}")
    if quest in seen_quest:
        err(f"duplicate quest {quest}")
    seen_writ.add(writ_id)
    seen_quest.add(quest)
    if tier not in TIERS:
        err(f"writ {writ_id}: bad tier {tier}")
    if not profs or not set(profs) <= PROFS:
        err(f"writ {writ_id}: bad profs {profs}")
    if turn_in:
        if turn_in not in turnin_keys:
            # NPC ID known from the quest page, but no name/zone yet: resolved in-game.
            npc_only.add(turn_in)
        else:
            known += 1

per_prof = {p: 0 for p in PROFS}
for _, body in rows:
    for p in re.findall(r'"(\w+)"', re.search(r"profs = \{([^}]*)\}", body).group(1)):
        per_prof[p] += 1

print(f"{len(rows)} writs, {known} with a known turn-in location (zone).")
if npc_only:
    print(f"warning: {len(npc_only)} turn-in NPC IDs have no TurnIns.lua entry yet: {', '.join(sorted(npc_only))}")
print("per profession:", ", ".join(f"{p.title()} {n}" for p, n in sorted(per_prof.items())))
if errors:
    print("\nFAILED:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("OK")
