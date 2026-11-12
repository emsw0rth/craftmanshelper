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

-- Returns { name, map, x, y, source } or nil. x/y are 0-100 and may be nil.
function Tracker:GetTurnIn(writID, inLog)
    local w = ns.Writs[writID]
    local static = w.turnIn and ns.TurnIns[w.turnIn]
    local learned = CH.db.global.learned[w.quest]

    if static and static.x then
        return { name = static.name, map = static.map, x = static.x, y = static.y, source = "data" }
    end
    if learned and learned.map then
        return { name = learned.name or (static and static.name), map = learned.map,
                 x = learned.x, y = learned.y, source = "learned" }
    end
    -- An accepted writ marks its delivery spot on the map; ask the game for it.
    if inLog and C_QuestLog.GetNextWaypoint then
        local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, w.quest)
        if ok and mapID and mapID > 0 then
            return { name = static and static.name, map = mapID,
                     x = x and x * 100, y = y and y * 100, source = "quest" }
        end
    end
    if static then
        return { name = static.name, map = static.map, source = "data" }
    end
    if inLog and GetQuestUiMapID then
        local ok, mapID = pcall(GetQuestUiMapID, w.quest)
        if ok and mapID and mapID > 0 then
            return { map = mapID, source = "quest" }
        end
    end
    return nil
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
    for writID in pairs(ns.Writs) do
        self:BuildState(writID)
    end
    self:SendMessage(ns.MSG_UPDATED)
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
            npcID = p.npcID, kind = p.kind, name = p.name,
            map = p.map, x = p.x, y = p.y, when = GetServerTime(),
        }
    end
    self.pendingTurnIn = nil
    self:ScheduleTimer("Refresh", 0.5) -- let the quest log and bags settle
end

function Tracker:OnItemDataLoaded()
    self:SendMessage(ns.MSG_UPDATED) -- names/icons became available; redraw
end

function Tracker:OnEnable()
    self:PruneCompleted()
    self:RegisterBucketEvent({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED" },
        0.3, "Refresh")
    self:RegisterBucketEvent({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }, 0.5, "OnItemDataLoaded")
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
