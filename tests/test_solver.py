"""Unit tests for CraftmansHelper/Solver.lua, run in a real Lua 5.1 (via lupa).

    pip install lupa
    python tests/test_solver.py
"""
import itertools
import math
import random
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

SOLVER = Path(__file__).resolve().parent.parent / "CraftmansHelper" / "Solver.lua"

lua = LuaRuntime(unpack_returned_tuples=True)
ns = lua.table()
lua.execute("function _load(src, ns) local f = assert(loadstring(src, 'Solver.lua')); f('CraftmansHelper', ns) end")
lua.globals()._load(SOLVER.read_text(encoding="utf-8"), ns)


def to_lua_points(pts):
    t = lua.table()
    for i, (x, y) in enumerate(pts, 1):
        p = lua.table()
        p.wx, p.wy = x, y
        t[i] = p
    return t


def to_lua_start(start):
    if start is None:
        return None
    p = lua.table()
    p.wx, p.wy = start
    return p


def solve(pts, start=None, fn=None):
    f = fn or ns.SolvePath
    order, length = f(to_lua_points(pts), to_lua_start(start))
    return [order[i] for i in range(1, len(pts) + 1)], length


def path_len(pts, order, start):
    total, prev = 0.0, start
    for i in order:
        p = pts[i - 1]
        if prev is not None:
            total += math.dist(prev, p)
        prev = p
    return total


def brute(pts, start):
    return min(path_len(pts, perm, start) for perm in itertools.permutations(range(1, len(pts) + 1)))


failures = 0


def check(name, cond, detail=""):
    global failures
    if cond:
        print(f"ok   {name}")
    else:
        failures += 1
        print(f"FAIL {name} {detail}")


# Edge cases
order, length = solve([])
check("empty", order == [] and length == 0)
order, length = solve([(3, 4)], (0, 0))
check("single point", order == [1] and abs(length - 5) < 1e-9, (order, length))

# A line visited from one end must be walked in order.
line = [(30, 0), (10, 0), (40, 0), (20, 0)]
order, length = solve(line, (0, 0))
check("line from start", order == [2, 4, 1, 3] and abs(length - 40) < 1e-9, (order, length))
order, length = solve(line, None)
check("line, free start", abs(length - 30) < 1e-9, (order, length))

# Held-Karp is exact: compare against brute force on random sets.
rng = random.Random(42)
for trial in range(25):
    n = rng.randint(2, 8)
    pts = [(rng.uniform(0, 5000), rng.uniform(0, 5000)) for _ in range(n)]
    start = (rng.uniform(0, 5000), rng.uniform(0, 5000)) if trial % 2 == 0 else None
    order, length = solve(pts, start)
    best = brute(pts, start)
    ok = sorted(order) == list(range(1, n + 1)) and abs(length - best) < 1e-6 \
        and abs(path_len(pts, order, start) - length) < 1e-6
    check(f"exact n={n} start={'yes' if start else 'no'}", ok, (length, best))

# Heuristic (used above 10 stops): valid permutation, reported length matches,
# and within 10% of optimal on sets small enough to brute-force.
heur = ns._SolverInternals.heuristic
for trial in range(10):
    n = 8
    pts = [(rng.uniform(0, 5000), rng.uniform(0, 5000)) for _ in range(n)]
    start = (rng.uniform(0, 5000), rng.uniform(0, 5000)) if trial % 2 else None
    order, length = solve(pts, start, fn=heur)
    best = brute(pts, start)
    check(f"heuristic n={n} within 10%", sorted(order) == list(range(1, n + 1)) and length <= best * 1.10 + 1e-6,
          (length, best))

# Large set goes through the heuristic path and stays valid.
pts = [(rng.uniform(0, 8000), rng.uniform(0, 8000)) for _ in range(25)]
order, length = solve(pts, (0, 0))
check("n=25 valid permutation", sorted(order) == list(range(1, 26)))
check("n=25 length consistent", abs(path_len(pts, order, (0, 0)) - length) < 1e-6)

print()
if failures:
    print(f"{failures} test(s) failed")
    sys.exit(1)
print("all tests passed")
