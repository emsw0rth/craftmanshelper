-- Route ordering. Pure Lua (no WoW API), so it can be unit-tested outside the game.
--
-- ns.SolvePath(points, start, cost) orders `points` into the cheapest open path,
-- beginning at `start` (or anywhere, if start is nil). Returns an array of indices
-- into `points` and the total cost. `cost(a, b)` defaults to the straight-line
-- distance between { wx, wy } points in world yards; the route planner passes
-- travel time in seconds instead, which need not be symmetric.
local _, ns = ...

local sqrt, floor, huge = math.sqrt, math.floor, math.huge

local EXACT_LIMIT = 10 -- Held-Karp up to this many stops; heuristic above

local function dist(a, b)
    if not (a and b) then return 0 end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end

local function pathLength(points, order, start, cost)
    cost = cost or dist
    local total, prev = 0, start
    for _, i in ipairs(order) do
        if prev then total = total + cost(prev, points[i]) end
        prev = points[i]
    end
    return total
end

-- Exact dynamic programming over subsets. Lua 5.1 has no bit operators, so
-- subset masks use arithmetic (bit j set <=> floor(mask / 2^j) % 2 == 1).
local function heldKarp(points, start, cost)
    cost = cost or dist
    local n = #points
    local pow = {}
    for j = 0, n do pow[j] = 2 ^ j end
    local full = pow[n] - 1

    local function has(mask, j) return floor(mask / pow[j]) % 2 == 1 end

    -- Pairwise costs once, up front.
    local c = {}
    for j = 1, n do
        c[j] = {}
        for k = 1, n do c[j][k] = (j ~= k) and cost(points[j], points[k]) or 0 end
    end

    local best, parent = {}, {}
    for j = 0, n - 1 do
        local m = pow[j]
        best[m] = best[m] or {}
        parent[m] = parent[m] or {}
        best[m][j] = start and cost(start, points[j + 1]) or 0
    end

    for mask = 1, full do
        local row = best[mask]
        if row then
            for j = 0, n - 1 do
                local cj = row[j]
                if cj then
                    for k = 0, n - 1 do
                        if not has(mask, k) then
                            local nm = mask + pow[k]
                            local nc = cj + c[j + 1][k + 1]
                            best[nm] = best[nm] or {}
                            parent[nm] = parent[nm] or {}
                            if not best[nm][k] or nc < best[nm][k] then
                                best[nm][k] = nc
                                parent[nm][k] = j
                            end
                        end
                    end
                end
            end
        end
    end

    local total, last = huge, nil
    for j = 0, n - 1 do
        local v = best[full][j]
        if v and v < total then total, last = v, j end
    end

    local order, mask = {}, full
    while last do
        table.insert(order, 1, last + 1)
        local prev = parent[mask] and parent[mask][last]
        mask = mask - pow[last]
        last = prev
    end
    return order, total
end

local function nearestNeighbour(points, start, first, cost)
    local n = #points
    local used, order = {}, {}
    local current = start
    if first then
        used[first] = true
        order[1] = first
        current = points[first]
    end
    while #order < n do
        local best, bi = huge, nil
        for i = 1, n do
            if not used[i] then
                local d = current and cost(current, points[i]) or 0
                if not bi or d < best then best, bi = d, i end
            end
        end
        used[bi] = true
        order[#order + 1] = bi
        current = points[bi]
    end
    return order
end

local function reverse(order, lo, hi)
    while lo < hi do
        order[lo], order[hi] = order[hi], order[lo]
        lo, hi = lo + 1, hi - 1
    end
end

-- 2-opt for an open path with an optional fixed start: reverse order[i..k]
-- whenever that makes the path cheaper, until no reversal helps. Costs may be
-- asymmetric (a reversed segment is travelled the other way), so each candidate
-- is priced in full rather than by the usual four-edge delta.
local function twoOpt(points, order, start, cost)
    local n = #order
    local current = pathLength(points, order, start, cost)
    local improved = true
    while improved do
        improved = false
        for i = 1, n - 1 do
            for k = i + 1, n do
                reverse(order, i, k)
                local candidate = pathLength(points, order, start, cost)
                if candidate < current - 1e-6 then
                    current = candidate
                    improved = true
                else
                    reverse(order, i, k) -- undo
                end
            end
        end
    end
    return order, current
end

local function heuristic(points, start, cost)
    cost = cost or dist
    if start then
        return twoOpt(points, nearestNeighbour(points, start, nil, cost), start, cost)
    end
    -- No fixed start: try every point as the first stop and keep the best.
    local bestOrder, best = nil, huge
    for first = 1, #points do
        local order, len = twoOpt(points, nearestNeighbour(points, nil, first, cost), nil, cost)
        if len < best then bestOrder, best = order, len end
    end
    return bestOrder, best
end

function ns.SolvePath(points, start, cost)
    cost = cost or dist
    local n = #points
    if n == 0 then return {}, 0 end
    if n == 1 then return { 1 }, start and cost(start, points[1]) or 0 end
    if n <= EXACT_LIMIT then return heldKarp(points, start, cost) end
    return heuristic(points, start, cost)
end

-- Exposed for tests.
ns._SolverInternals = { heldKarp = heldKarp, heuristic = heuristic, pathLength = pathLength, dist = dist }
