-- Route ordering. Pure Lua (no WoW API), so it can be unit-tested outside the game.
--
-- ns.SolvePath(points, start) orders `points` ({ wx, wy } in world yards) into the
-- shortest open path, beginning at `start` (or anywhere, if start is nil).
-- Returns an array of indices into `points` and the path length in yards.
local _, ns = ...

local sqrt, floor, huge = math.sqrt, math.floor, math.huge

local EXACT_LIMIT = 10 -- Held-Karp up to this many stops; heuristic above

local function dist(a, b)
    if not (a and b) then return 0 end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end

local function pathLength(points, order, start)
    local total, prev = 0, start
    for _, i in ipairs(order) do
        total = total + dist(prev, points[i])
        prev = points[i]
    end
    return total
end

-- Exact dynamic programming over subsets. Lua 5.1 has no bit operators, so
-- subset masks use arithmetic (bit j set <=> floor(mask / 2^j) % 2 == 1).
local function heldKarp(points, start)
    local n = #points
    local pow = {}
    for j = 0, n do pow[j] = 2 ^ j end
    local full = pow[n] - 1

    local function has(mask, j) return floor(mask / pow[j]) % 2 == 1 end

    local cost, parent = {}, {}
    for j = 0, n - 1 do
        local m = pow[j]
        cost[m] = cost[m] or {}
        parent[m] = parent[m] or {}
        cost[m][j] = start and dist(start, points[j + 1]) or 0
    end

    for mask = 1, full do
        local row = cost[mask]
        if row then
            for j = 0, n - 1 do
                local c = row[j]
                if c then
                    for k = 0, n - 1 do
                        if not has(mask, k) then
                            local nm = mask + pow[k]
                            local nc = c + dist(points[j + 1], points[k + 1])
                            cost[nm] = cost[nm] or {}
                            parent[nm] = parent[nm] or {}
                            if not cost[nm][k] or nc < cost[nm][k] then
                                cost[nm][k] = nc
                                parent[nm][k] = j
                            end
                        end
                    end
                end
            end
        end
    end

    local best, last = huge, nil
    for j = 0, n - 1 do
        local c = cost[full][j]
        if c and c < best then best, last = c, j end
    end

    local order, mask = {}, full
    while last do
        table.insert(order, 1, last + 1)
        local prev = parent[mask] and parent[mask][last]
        mask = mask - pow[last]
        last = prev
    end
    return order, best
end

local function nearestNeighbour(points, start, first)
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
                local d = dist(current, points[i])
                if d < best then best, bi = d, i end
            end
        end
        used[bi] = true
        order[#order + 1] = bi
        current = points[bi]
    end
    return order
end

-- 2-opt for an open path with an optional fixed start: reverse order[i..k]
-- whenever that shortens the path, until no reversal helps.
local function twoOpt(points, order, start)
    local n = #order
    local improved = true
    while improved do
        improved = false
        for i = 1, n - 1 do
            for k = i + 1, n do
                local a = (i > 1) and points[order[i - 1]] or start
                local b = points[order[i]]
                local c = points[order[k]]
                local d = (k < n) and points[order[k + 1]] or nil
                local delta = dist(a, c) + dist(b, d) - dist(a, b) - dist(c, d)
                if delta < -1e-6 then
                    local lo, hi = i, k
                    while lo < hi do
                        order[lo], order[hi] = order[hi], order[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    improved = true
                end
            end
        end
    end
    return order
end

local function heuristic(points, start)
    if start then
        local order = twoOpt(points, nearestNeighbour(points, start), start)
        return order, pathLength(points, order, start)
    end
    -- No fixed start: try every point as the first stop and keep the best.
    local bestOrder, best = nil, huge
    for first = 1, #points do
        local order = twoOpt(points, nearestNeighbour(points, nil, first), nil)
        local len = pathLength(points, order, nil)
        if len < best then bestOrder, best = order, len end
    end
    return bestOrder, best
end

function ns.SolvePath(points, start)
    local n = #points
    if n == 0 then return {}, 0 end
    if n == 1 then return { 1 }, dist(start, points[1]) end
    if n <= EXACT_LIMIT then return heldKarp(points, start) end
    return heuristic(points, start)
end

-- Exposed for tests.
ns._SolverInternals = { heldKarp = heldKarp, heuristic = heuristic, pathLength = pathLength }
