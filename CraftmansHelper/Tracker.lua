-- Writ state tracking: what's done today, what's in the quest log or bags,
-- and what's ready to turn in. Also records turn-in locations as you play.
local _, ns = ...
local CH = ns.CH

local Tracker = CH:NewModule("Tracker", "AceEvent-3.0", "AceBucket-3.0", "AceTimer-3.0")
CH.Tracker = Tracker

local STATUS = {
    READY = "ready",         -- in quest log, objectives met: go deliver it
    ACTIVE = "active",       -- in quest log, still missing the item
    INBAGS = "inbags",       -- writ item in bags, quest not accepted yet
    AVAILABLE = "available", -- not done today, player doesn't hold the writ
    DONE = "done",           -- completed since the last daily reset
}
ns.STATUS = STATUS

local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local IsQuestFlaggedCompleted = C_QuestLog.IsQuestFlaggedCompleted

local states = {}  -- [writID] = state table, rebuilt by Refresh()

---------------------------------------------------------------------------
-- Daily reset
---------------------------------------------------------------------------

function Tracker:SecondsUntilReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local s = C_DateAndTime.GetSecondsUntilDailyReset()
        if s and s > 0 then return s end
    end
    if GetQuestResetTime then
        local s = GetQuestResetTime()
        if s and s > 0 then return s end
    end
    return 86400
end

function Tracker:NextResetTime()
    return GetServerTime() + self:SecondsUntilReset()
end

function Tracker:ScheduleResetRefresh()
    if self.resetTimer then self:CancelTimer(self.resetTimer) end
    self.resetTimer = self:ScheduleTimer(function()
        self:PruneCompleted()
        self:Refresh()
        self:ScheduleResetRefresh()
    end, self:SecondsUntilReset() + 5)
end

function Tracker:PruneCompleted()
    local now = GetServerTime()
    local completed = CH.db.char.completed
    for questID, expires in pairs(completed) do
        if expires <= now then completed[questID] = nil end
    end
end

-- Done today = server says so, or we saw the turn-in ourselves (covers the
-- short window before IsQuestFlaggedCompleted catches up).
local function IsDoneToday(questID)
    if IsQuestFlaggedCompleted(questID) then return true end
    local expires = CH.db.char.completed[questID]
    return expires ~= nil and expires > GetServerTime()
end

---------------------------------------------------------------------------
-- Turn-in location
---------------------------------------------------------------------------

-- The delivery spot an accepted writ marks on the world map.
-- Returns mapID, x, y (0-100); x/y may be nil if only the zone is known.
-- The quest's POI on its own map is preferred: GetNextWaypoint can point at an
-- intermediate step (a portal or flight master) when you're in another zone.
function ns.QuestMarker(questID)
    local questMap
    if GetQuestUiMapID then
        local ok, m = pcall(GetQuestUiMapID, questID)
        if ok and m and m > 0 then questMap = m end
    end
    if questMap and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, questMap)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                if info.questID == questID and info.x and info.y then
                    return questMap, info.x * 100, info.y * 100
                end
            end
        end
    end
    if C_QuestLog.GetNextWaypoint then
        local ok, m, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
        if ok and m and m > 0 and x and (not questMap or m == questMap) then
            return m, x * 100, y * 100
        end
    end
    return questMap
end

-- Turn-in sources, best first:
--   data      coordinates shipped with the addon (Data/TurnIns.lua)
--   learned   recorded in-game at a turn-in
--   questie   QuestieDB at runtime, if installed
--   marker    the quest's map marker, recorded when the writ was accepted, or live while it's in the log
-- Returns { name, map, x, y, faction, source } or nil. x/y are 0-100 and may be nil.
function Tracker:GetTurnIn(writID, inLog)
    local w = ns.Writs[writID]
    local static = w.turnIn and ns.TurnIns[w.turnIn]
    local learned = CH.db.global.learned[w.quest]
    local staticName = static and static.name

    if static and static.x then
        return { name = static.name, map = static.map, x = static.x, y = static.y,
                 faction = static.faction, source = "data" }
    end
    if learned and learned.map and learned.x and learned.source ~= "marker" then
        return { name = learned.name or staticName, map = learned.map, x = learned.x, y = learned.y,
                 source = "learned" }
    end
    local q = ns.Questie.GetTurnIn(w.quest)
    if q then
        return { name = q.name or staticName, map = q.map, x = q.x, y = q.y, faction = q.faction,
                 source = "questie" }
    end
    if learned and learned.map and learned.x then
        return { name = learned.name or staticName, map = learned.map, x = learned.x, y = learned.y,
                 source = "marker" }
    end
    if inLog then
        local map, x, y = ns.QuestMarker(w.quest)
        if map and x then
            return { name = staticName, map = map, x = x, y = y, source = "marker" }
        end
        if map and not static then
            return { map = map, source = "marker" }
        end
    end
    if static then
        return { name = static.name, map = static.map, faction = static.faction, source = "data" }
    end
    return nil
end

-- Remember the map marker of an accepted writ, so its turn-in stays known
-- after the quest leaves the log (and can be exported). Never overwrites a
-- location recorded at an actual turn-in.
function Tracker:RecordMarker(questID)
    local writID = ns.WritByQuest[questID]
    if not writID then return false end
    local w = ns.Writs[writID]
    local static = w.turnIn and ns.TurnIns[w.turnIn]
    if static and static.x then return false end -- already shipped with the addon
    local learned = CH.db.global.learned
    if learned[questID] and learned[questID].source ~= "marker" then return false end

    local map, x, y = ns.QuestMarker(questID)
    if not (map and x) then return false end
    learned[questID] = { source = "marker", name = static and static.name, map = map, x = x, y = y,
                         when = GetServerTime() }
    return true
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function CountItem(w)
    return GetItemCount(w.item) or 0
end

local function IsReady(questID, have, need, writsInBags)
    if C_QuestLog.ReadyForTurnIn then
        local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, questID)
        if ok and ready then return true end
    end
    if C_QuestLog.IsComplete then
        local ok, complete = pcall(C_QuestLog.IsComplete, questID)
        if ok and complete then return true end
    end
    -- Fallback if the quest has no trackable objectives: item + writ in bags.
    return have >= need and writsInBags > 0
end

function Tracker:BuildState(writID)
    local w = ns.Writs[writID]
    local s = states[writID] or {}
    states[writID] = s

    s.id = writID
    s.writ = w
    s.inLog = C_QuestLog.GetLogIndexForQuestID(w.quest) ~= nil
    s.writsInBags = GetItemCount(writID) or 0
    s.writsTotal = GetItemCount(writID, true) or s.writsInBags -- includes bank
    s.have = CountItem(w)
    s.need = w.count

    if s.inLog then
        s.status = IsReady(w.quest, s.have, s.need, s.writsInBags) and STATUS.READY or STATUS.ACTIVE
    elseif IsDoneToday(w.quest) then
        s.status = STATUS.DONE
    elseif s.writsInBags > 0 then
        s.status = STATUS.INBAGS
    else
        s.status = STATUS.AVAILABLE
    end

    s.turnIn = self:GetTurnIn(writID, s.inLog)
    if s.turnIn and s.turnIn.map then
        s.zoneID, s.zoneName, s.continentID = ns.ResolveZone(s.turnIn.map)
    else
        s.zoneID, s.zoneName, s.continentID = nil, "Unknown", ns.UNKNOWN_CONTINENT
    end
    return s
end

function Tracker:Refresh()
    local learned = CH.db.global.learned
    local completed, now = CH.db.char.completed, GetServerTime()
    for writID, w in pairs(ns.Writs) do
        -- Done today per the server, also when the addon didn't see the turn-in: saved so your
        -- other characters see it (Alts.lua).
        if IsQuestFlaggedCompleted(w.quest) and not ((completed[w.quest] or 0) > now) then
            completed[w.quest] = self:NextResetTime()
        end
        -- Writs in the log mark their turn-in on the map: record it (once) before building state.
        if not learned[w.quest] and C_QuestLog.GetLogIndexForQuestID(w.quest) then
            self:RecordMarker(w.quest)
        end
        self:BuildState(writID)
    end
    -- QUEST_LOG_UPDATE and BAG_UPDATE_DELAYED fire often; only announce real changes,
    -- since every announcement redraws the window.
    local sig = self:Signature()
    if sig ~= self.lastSignature then
        self.lastSignature = sig
        self:SendMessage(ns.MSG_UPDATED)
    end
end

-- Everything about the writs the window shows, as one string, to spot changes.
local sortedWrits
function Tracker:Signature()
    if not sortedWrits then
        sortedWrits = {}
        for writID in pairs(ns.Writs) do table.insert(sortedWrits, writID) end
        table.sort(sortedWrits)
    end
    local parts = {}
    for i, writID in ipairs(sortedWrits) do
        local s = states[writID]
        local t = s and s.turnIn
        parts[i] = s and table.concat({ s.status, s.have, s.writsInBags, s.writsTotal, tostring(s.inLog),
            t and tostring(t.map) or "", t and tostring(t.x) or "", t and tostring(t.y) or "", t and t.name or "" }, ",")
            or ""
    end
    return table.concat(parts, ";")
end

function Tracker:GetState(writID)
    return states[writID] or self:BuildState(writID)
end

function Tracker:GetAllStates()
    return states
end

function Tracker:GetCounts()
    local c = { ready = 0, active = 0, inbags = 0, available = 0, done = 0, notDone = 0 }
    for _, s in pairs(states) do
        c[s.status] = c[s.status] + 1
        if s.status ~= STATUS.DONE then c.notDone = c.notDone + 1 end
    end
    return c
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function NpcFromGUID(guid)
    if not guid or (issecretvalue and issecretvalue(guid)) then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "GameObject" then
        return tonumber(npcID), unitType
    end
end

-- QUEST_COMPLETE fires when the reward panel opens: the quest giver is the
-- "npc" unit and we're standing next to it, so remember who and where.
function Tracker:QUEST_COMPLETE()
    local questID = GetQuestID and GetQuestID()
    if not questID or not ns.WritByQuest[questID] then return end

    local pending = { questID = questID }
    local ok, guid = pcall(UnitGUID, "npc")
    if ok then pending.npcID, pending.kind = NpcFromGUID(guid) end
    local okName, name = pcall(UnitName, "npc")
    if okName and name and not (issecretvalue and issecretvalue(name)) then pending.name = name end

    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y = pos:GetXY()
            pending.map, pending.x, pending.y = mapID, x * 100, y * 100
        end
    end
    self.pendingTurnIn = pending
end

function Tracker:QUEST_TURNED_IN(_, questID)
    if not ns.WritByQuest[questID] then return end
    CH.db.char.completed[questID] = self:NextResetTime()

    local p = self.pendingTurnIn
    if p and p.questID == questID and p.map then
        CH.db.global.learned[questID] = {
            source = "turnin", npcID = p.npcID, kind = p.kind, name = p.name,
            map = p.map, x = p.x, y = p.y, when = GetServerTime(),
        }
    end
    self.pendingTurnIn = nil
    self:ScheduleTimer("Refresh", 0.5) -- let the quest log and bags settle
end

-- An item's data arrived. Hovering items loads their data too, so only redraw when
-- the window was waiting for this name (and then once for a burst of them).
function Tracker:OnItemDataLoaded(_, itemID)
    if not (itemID and ns.MissingNames[itemID]) then return end
    ns.MissingNames[itemID] = nil
    if self.namesTimer then return end
    self.namesTimer = self:ScheduleTimer(function()
        self.namesTimer = nil
        self:SendMessage(ns.MSG_NAMES)
    end, 0.5)
end

function Tracker:OnEnable()
    self:PruneCompleted()
    self:RegisterBucketEvent({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED" },
        0.3, "Refresh")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemDataLoaded")
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT", "OnItemDataLoaded")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    self:ScheduleResetRefresh()

    -- Warm the item cache so names and icons are ready when the window opens.
    if C_Item and C_Item.RequestLoadItemDataByID then
        for writID, w in pairs(ns.Writs) do
            C_Item.RequestLoadItemDataByID(w.item)
            C_Item.RequestLoadItemDataByID(writID)
        end
    end
    self:Refresh()
end
