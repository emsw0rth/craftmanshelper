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
        minimap = { hide = false }, -- LibDBIcon position/visibility
        tooltips = true,           -- add writ info to item tooltips
        includeWritPrice = false,  -- add the writ's own AH price to the estimate and rep per gold
        buySort = "price",         -- "Buy Writs" tab: "price" (cheapest first) or "rep" (rep per gold)
        buyTier = "ALL",
        buyHideDone = true,        -- "Buy Writs" tab: hide writs already done today
        buyZone = "ALL",           -- "Buy Writs" tab: turn-in zone filter
        buyNpc = "ALL",            -- "Buy Writs" tab: turn-in NPC filter ("name;zone")
        tracker = { shown = true, locked = false }, -- small "next steps" window while a route is active
        useHearth = true,          -- let the route planner use your Hearthstone once when it saves time
    },
    char = {
        -- [questID] = server time of the daily reset after which the completion expires.
        completed = {},
        -- Flight masters whose flight path this character knows: [npcID] = true (FlightPaths.lua).
        flightPaths = {},
        -- Where the Hearthstone takes you: { name = bind location, map, x, y } (Hearth.lua).
        hearth = nil,
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
    "/writs tracker - show / hide the small route tracker window",
    "/writs why - show the route planner's travel times to the current stop",
    "/writs status - print a summary in chat",
    "/writs shopping - open the shopping list",
    "/writs buy - writs that are cheapest to buy on the Auction House",
    "/writs settings - open the settings",
    "/writs minimap - show / hide the minimap button",
    "/writs tooltips - turn writ info in item tooltips on / off",
    "/writs export - share the turn-in locations you've recorded",
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
    elseif cmd == "shopping" then
        self.UI:Show("shopping")
    elseif cmd == "why" then
        self.Route:Explain()
    elseif cmd == "tracker" then
        local shown = not self.db.profile.tracker.shown
        self.RouteTracker:SetShown(shown)
        self:Print("Route tracker " .. (shown and "on" or "off") ..
            ((shown and not self.Route:IsActive()) and " (it appears once you plan a route)." or "."))
    elseif cmd == "buy" then
        self.UI:Show("buy")
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        self.UI:Show("settings")
    elseif cmd == "minimap" then
        self.Minimap:Toggle()
    elseif cmd == "tooltips" then
        self.db.profile.tooltips = not self.db.profile.tooltips
        self:Print("Item tooltips " .. (self.db.profile.tooltips and "on." or "off."))
    elseif cmd == "export" then
        self.UI:ShowExport()
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

-- Recorded turn-in locations the addon doesn't ship with yet, as shareable text.
-- Format v2 (one line per writ quest): quest;source;id;kind;name;map;x;y
-- No "|" anywhere: WoW treats it as an escape character in edit boxes
-- ("||" shows as "|", "|t" starts a texture), which mangled v1 exports.
function CH:BuildExport()
    local lines, n = {}, 0
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "?"
    table.insert(lines, "CraftmansHelper export v2 (addon " .. version .. ")")
    local quests = {}
    for questID in pairs(self.db.global.learned) do table.insert(quests, questID) end
    table.sort(quests)
    for _, questID in ipairs(quests) do
        local l = self.db.global.learned[questID]
        local writID = ns.WritByQuest[questID]
        local w = writID and ns.Writs[writID]
        local static = w and w.turnIn and ns.TurnIns[w.turnIn]
        if w and l.map and l.x and not (static and static.x) then
            local name = (l.name or ""):gsub("[|;]", "/")
            table.insert(lines, string.format("%d;%s;%s;%s;%s;%d;%.1f;%.1f", questID, l.source or "turnin",
                tostring(l.npcID or ""), l.kind or "", name, l.map, l.x, l.y))
            n = n + 1
        end
    end
    return table.concat(lines, "\n"), n
end

function ns.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end
