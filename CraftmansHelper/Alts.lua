-- Remembers which writs and writ items each of your characters carries, so the
-- addon can tell you about writs in your bank or on your alts.
--
-- Saved account-wide in CH.db.global.characters["Realm-Name"]:
--   { name, realm, faction, class, updated = server time,
--     writs = { [writID] = { b = bags, k = bank } },
--     items = { [itemID] = { b = bags, k = bank } },   -- items that writs ask for
--     log = { [writID] = true when ready to deliver, false when not },  -- writs in the quest log
--     done = { [writID] = server time it expires (the daily reset) },   -- done today
--     standing = { standing, value, max, nextName } or nil,  -- with the writ faction
--     diplomat = Legacy perk rank }
-- Only non-zero counts are stored. Alts count when they share your realm and
-- faction, since only then can they mail you what they hold.
local _, ns = ...
local CH = ns.CH

local Alts = CH:NewModule("Alts", "AceEvent-3.0", "AceBucket-3.0")
CH.Alts = Alts

local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

-- Every item ID worth counting: writs and the items they ask for.
local WATCH = {}
for writID, w in pairs(ns.Writs) do
    WATCH[writID] = "writs"
    WATCH[w.item] = WATCH[w.item] or "items"
end

local function Characters()
    CH.db.global.characters = CH.db.global.characters or {}
    return CH.db.global.characters
end

-- WoW Forever characters have a surname, which UnitName returns as its second
-- value (retail returns the realm there, or nothing for your own character).
local SEPARATOR = (Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) or type(v) ~= "string" or v == "" then return nil end
    return v
end

function Alts.Key(name, realm, surname)
    return (realm or "?") .. "-" .. (name or "?") .. (surname and (SEPARATOR .. surname) or "")
end

-- This character's key, realm, faction, first name and surname.
function Alts.Me()
    local first, surname
    local nameFn = UnitNameUnmodified or UnitName
    if nameFn then first, surname = nameFn("player") end
    first, surname = Plain(first), Plain(surname)
    local realm = (GetRealmName and GetRealmName()) or "?"
    if surname == realm then surname = nil end -- retail-style realm, not a surname
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return Alts.Key(first, realm, surname), realm, faction, first, surname
end

-- Counts bags and bank for this character and saves them. The bank's contents are
-- only known once it has been opened (this session or an earlier one): until the
-- bank is opened this session, an all-zero bank read keeps the counts saved before.
function Alts:Snapshot()
    local key, realm, faction, name, surname = Alts.Me()
    if not name or name == UNKNOWNOBJECT then return end
    local chars = Characters()
    -- Saved before surnames were recorded (key without the surname): replace it.
    local oldKey = Alts.Key(name, realm)
    if oldKey ~= key and chars[oldKey] and not chars[oldKey].surname then
        chars[key] = chars[key] or chars[oldKey]
        chars[oldKey] = nil
    end
    local old = chars[key]
    local entry = { name = name, surname = surname, realm = realm, faction = faction,
                    updated = GetServerTime and GetServerTime(), writs = {}, items = {} }
    if UnitClass then entry.class = select(2, UnitClass("player")) end

    local bankSeen = false
    for id, kind in pairs(WATCH) do
        local bags = GetItemCount(id) or 0
        local total = GetItemCount(id, true) or bags
        local bank = math.max(0, total - bags)
        if bank > 0 then bankSeen = true end
        if bags > 0 or bank > 0 then entry[kind][id] = { b = bags, k = bank } end
    end

    if not bankSeen and not self.bankOpened and old then
        -- Bank contents unknown: carry over what was in the bank last time.
        for _, kind in ipairs({ "writs", "items" }) do
            for id, c in pairs(old[kind] or {}) do
                if (c.k or 0) > 0 then
                    local cur = entry[kind][id] or { b = 0, k = 0 }
                    cur.k = c.k
                    entry[kind][id] = cur
                end
            end
        end
    end
    -- Quest log, done today, standing and Diplomat: for My Writs' other-character sections.
    local STATUS = ns.STATUS
    entry.log, entry.done = {}, {}
    for writID, st in pairs(CH.Tracker:GetAllStates()) do
        if st.inLog then entry.log[writID] = st.status == STATUS.READY end
    end
    for questID, expires in pairs(CH.db.char.completed or {}) do
        local writID = ns.WritByQuest[questID]
        if writID then entry.done[writID] = expires end
    end
    local st = ns.Rep and ns.Rep.Standing()
    entry.standing = st and { standing = st.standing, value = st.value, max = st.max, nextName = st.nextName }
        or (old and old.standing)
    entry.diplomat = ns.DiplomatRank()
    chars[key] = entry
end

local function Count(c) return c and ((c.b or 0) + (c.k or 0)) or 0 end

-- Your other characters on this realm and faction holding `id`, as
-- { { name, class, count }, ... } sorted by name. kind: "writs" or "items".
function Alts:Holders(id, kind)
    local me, realm, faction = Alts.Me()
    local list = {}
    for key, c in pairs(Characters()) do
        if key ~= me and c.realm == realm and (not faction or not c.faction or c.faction == faction) then
            local n = Count(c[kind] and c[kind][id])
            if n > 0 then table.insert(list, { name = c.name, surname = c.surname, realm = c.realm, class = c.class, count = n }) end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- How many of `id` are in this character's bank (from the saved snapshot, so it
-- works while the bank is closed).
function Alts:InBank(id, kind)
    local me = Alts.Me()
    local c = Characters()[me]
    return c and c[kind] and c[kind][id] and (c[kind][id].k or 0) or 0
end

-- Your other characters on this realm and faction, as { { key, entry }, ... } by name.
function Alts:Others()
    local me, realm, faction = Alts.Me()
    local list = {}
    for key, c in pairs(Characters()) do
        if key ~= me and c.realm == realm and (not faction or not c.faction or c.faction == faction) then
            table.insert(list, { key = key, entry = c })
        end
    end
    table.sort(list, function(a, b) return Alts.FullName(a.entry) < Alts.FullName(b.entry) end)
    return list
end

-- The writs another character holds and can still turn in today, from its snapshot, as
-- writ states like Tracker's (status, have, need, turnIn, zone...), plus bankOnly for
-- writs only in its bank. unstarted: include writs in its bags and bank, not just its log.
function Alts.WritStates(c, unstarted)
    local STATUS = ns.STATUS
    local now = GetServerTime and GetServerTime() or 0
    local list = {}
    local ids = {}
    for writID in pairs(c.log or {}) do ids[writID] = true end
    if unstarted then for writID in pairs(c.writs or {}) do ids[writID] = true end end
    for writID in pairs(ids) do
        local w = ns.Writs[writID]
        local expires = c.done and c.done[writID]
        local doneToday = expires and expires > now
        local inLog = c.log and c.log[writID] ~= nil
        if w and (inLog or not doneToday) then
            local held = c.writs and c.writs[writID] or {}
            local item = c.items and c.items[w.item] or {}
            local s = { id = writID, writ = w, inLog = inLog, need = w.count,
                        writsInBags = held.b or 0, writsTotal = (held.b or 0) + (held.k or 0),
                        have = (item.b or 0) + (item.k or 0) }
            if inLog then
                s.status = c.log[writID] and STATUS.READY or STATUS.ACTIVE
            else
                s.status = STATUS.INBAGS
                s.bankOnly = s.writsInBags == 0
            end
            s.turnIn = CH.Tracker:GetTurnIn(writID, false)
            if s.turnIn and s.turnIn.map then
                s.zoneID, s.zoneName, s.continentID = ns.ResolveZone(s.turnIn.map)
            else
                s.zoneID, s.zoneName, s.continentID = nil, "Unknown", ns.UNKNOWN_CONTINENT
            end
            table.insert(list, s)
        end
    end
    return list
end

-- Reputation for a list of writ states of character c: { count, rep, ready = { count, rep } }.
function Alts.Rep(c, states)
    local out = { count = 0, rep = 0, ready = { count = 0, rep = 0 } }
    for _, s in ipairs(states) do
        local r = ns.WritRep(s.id, c.diplomat or 0) or 0
        out.count, out.rep = out.count + 1, out.rep + r
        if s.status == ns.STATUS.READY then out.ready.count, out.ready.rep = out.ready.count + 1, out.ready.rep + r end
    end
    return out
end

-- First name and surname ("Firstname Lastname"), or just the name without a surname.
function Alts.FullName(h)
    return h.surname and (h.name .. SEPARATOR .. h.surname) or h.name
end

-- Name coloured by class when the client knows the colour; full = with the surname.
function Alts.ColoredName(h, full)
    local colors = (C_ClassColor and h.class and C_ClassColor.GetClassColor(h.class))
        or (RAID_CLASS_COLORS and h.class and RAID_CLASS_COLORS[h.class])
    local name = full and Alts.FullName(h) or h.name
    if colors and colors.WrapTextInColorCode then return colors:WrapTextInColorCode(name) end
    if colors and colors.colorStr then return "|c" .. colors.colorStr .. name .. "|r" end
    return name
end

-- "Name x2, Other" style summary of holders (counts above 1 only).
function Alts.Summary(holders, colored)
    local parts = {}
    for _, h in ipairs(holders) do
        local n = colored and Alts.ColoredName(h) or h.name
        table.insert(parts, h.count > 1 and (n .. " x" .. h.count) or n)
    end
    return table.concat(parts, ", ")
end

-- Every saved character: { { key, name, realm, faction, class, updated, writs = n, me = bool }, ... }
function Alts:List()
    local me = Alts.Me()
    local list = {}
    for key, c in pairs(Characters()) do
        local n = 0
        for _, cnt in pairs(c.writs or {}) do n = n + Count(cnt) end
        table.insert(list, { key = key, name = c.name, surname = c.surname, realm = c.realm, faction = c.faction, class = c.class,
                             updated = c.updated, writs = n, me = key == me })
    end
    table.sort(list, function(a, b)
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return list
end

function Alts:Forget(key)
    Characters()[key] = nil
    self:SendMessage(ns.MSG_UPDATED)
end

-- Counts as one string, to spot changes.
local function Signature(entry)
    if not entry then return "" end
    local parts = {}
    for _, kind in ipairs({ "writs", "items" }) do
        local ids = {}
        for id in pairs(entry[kind] or {}) do table.insert(ids, id) end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local c = entry[kind][id]
            table.insert(parts, kind .. id .. ":" .. (c.b or 0) .. "/" .. (c.k or 0))
        end
    end
    local log = {}
    for id, ready in pairs(entry.log or {}) do table.insert(log, id .. (ready and "r" or "")) end
    table.sort(log)
    local done = {}
    for id in pairs(entry.done or {}) do table.insert(done, id) end
    table.sort(done)
    local st = entry.standing
    table.insert(parts, "log" .. table.concat(log, "/") .. "done" .. table.concat(done, "/") ..
        "st" .. (st and (tostring(st.standing) .. st.value .. "/" .. st.max) or "") .. "d" .. tostring(entry.diplomat))
    return table.concat(parts, ",")
end

-- Saves this character's counts; announces it only when something changed (every
-- announcement redraws the window).
function Alts:Update()
    self:Snapshot()
    local sig = Signature(Characters()[Alts.Me()])
    if sig ~= self.lastSignature then
        self.lastSignature = sig
        self:SendMessage(ns.MSG_UPDATED)
    end
end

function Alts:BANKFRAME_OPENED()
    self.bankOpened = true
    self:Update()
end

function Alts:OnEnable()
    self:RegisterBucketEvent({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED" }, 1, "Update")
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
    -- Quest log and reputation changes come through the tracker's update. Update only
    -- announces when something changed, so answering our own announcement stops there.
    self:RegisterMessage(ns.MSG_UPDATED, "Update")
    self:RegisterBucketEvent("UPDATE_FACTION", 2, "Update")
end
