local ADDON_NAME, ns = ...

local CH = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.CH = CH
_G.CraftmansHelper = CH -- handy for /dump while developing

-- Message fired (via AceEvent) whenever writ state may have changed.
ns.MSG_UPDATED = "CRAFTMANSHELPER_UPDATED"

ns.PROFESSIONS = { "ALCHEMY", "BLACKSMITHING", "ENGINEERING", "LEATHERWORKING", "TAILORING" }
ns.PROFESSION_NAMES = {
    ALCHEMY = "Alchemy",
    BLACKSMITHING = "Blacksmithing",
    ENGINEERING = "Engineering",
    LEATHERWORKING = "Leatherworking",
    TAILORING = "Tailoring",
}
ns.TIERS = { "JOURNEYMAN", "EXPERT", "ARTISAN" }
ns.TIER_NAMES = { JOURNEYMAN = "Journeyman", EXPERT = "Expert", ARTISAN = "Artisan" }

-- Reverse lookup: quest ID -> writ item ID.
ns.WritByQuest = {}
for writID, w in pairs(ns.Writs) do
    ns.WritByQuest[w.quest] = writID
end

local defaults = {
    profile = {
        showUnstarted = true,      -- include writs sitting in bags (not yet accepted) in "My Writs"
        hideCompleted = false,     -- "All Writs": hide writs already done today
        professionFilter = "ALL",
        tierFilter = "ALL",
    },
    char = {
        -- [questID] = server time of the daily reset after which the completion expires.
        completed = {},
    },
    global = {
        -- Turn-in locations recorded in-game: [questID] = { npcID, name, map, x, y }
        learned = {},
    },
}

function CH:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("CraftmansHelperDB", defaults, true)
    self:RegisterChatCommand("writs", "SlashCommand")
    self:RegisterChatCommand("craftmanshelper", "SlashCommand")
end

function CH:Print(...)
    -- AceConsole's Print with our own coloured prefix.
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4a017Craftman's Helper|r: " .. strjoin(" ", tostringall(...)))
end

local HELP = {
    "/writs - toggle the window",
    "/writs all - open the All Writs tab",
    "/writs route - plan a delivery route and start the waypoints",
    "/writs clear - clear the route and any waypoints set by this addon",
    "/writs status - print a summary in chat",
    "/writs learned - list turn-in locations recorded in-game",
}

function CH:SlashCommand(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "" then
        self.UI:Toggle()
    elseif cmd == "all" then
        self.UI:Show("all")
    elseif cmd == "route" then
        self.Route:Plan()
        self.UI:Show("route")
    elseif cmd == "clear" then
        self.Route:Clear()
        self.Nav:Clear("manual")
        self:Print("Waypoints cleared.")
    elseif cmd == "status" then
        self:PrintStatus()
    elseif cmd == "learned" then
        self:PrintLearned()
    else
        for _, line in ipairs(HELP) do self:Print(line) end
    end
end

function CH:PrintStatus()
    local counts = self.Tracker:GetCounts()
    self:Print(string.format("%d ready, %d in progress, %d not started (in bags), %d done today, %d available today.",
        counts.ready, counts.active, counts.inbags, counts.done, counts.notDone))
    self:Print("Daily reset in " .. ns.FormatDuration(self.Tracker:SecondsUntilReset()) .. ".")
end

function CH:PrintLearned()
    local n = 0
    for questID, l in pairs(self.db.global.learned) do
        local writID = ns.WritByQuest[questID]
        local w = writID and ns.Writs[writID]
        self:Print(string.format("%s -> %s (map %s, %.1f, %.1f)", w and w.name or questID,
            l.name or "?", tostring(l.map), l.x or 0, l.y or 0))
        n = n + 1
    end
    if n == 0 then self:Print("No turn-in locations recorded yet.") end
end

function ns.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end
