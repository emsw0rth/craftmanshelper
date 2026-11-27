-- The two guided tours (Tutorial.lua): the main window, started a few seconds after the first
-- login, and the Auction House's "Craftman's" tab, started the first time it's opened.
local _, ns = ...
local CH = ns.CH

local Tours = CH:NewModule("Tours", "AceEvent-3.0", "AceTimer-3.0")
CH.Tours = Tours

local START_DELAY = 6 -- seconds after login before the main tour starts

local UI = function() return CH.UI end

---------------------------------------------------------------------------
-- The main window
---------------------------------------------------------------------------

local function Window()
    local f = UI().frame
    return f and f.frame
end

-- The area under the tabs, where each tab shows its contents.
local function Content()
    local t = UI().tabs
    return t and t.border
end

local function TabButtons()
    local t = UI().tabs
    if not (t and t.tabs) then return nil end
    local list = {}
    for _, b in ipairs(t.tabs) do
        if b:IsShown() then table.insert(list, b) end
    end
    return list
end

local function ShowTab(tab)
    return function() UI():Show(tab) end
end

local function Mark(key)
    return function() return UI().marks[key] end
end

local function MinimapButton()
    local b = _G.LibDBIcon10_CraftmansHelper
    if b and b:IsVisible() then return b end
    return Window()
end

local MAIN = {
    key = "main",
    alive = function() return UI().frame ~= nil end,
    steps = {
        { title = "Welcome to Craftman's Helper",
          text = "It keeps track of your Craftsman's Writs, plans the trip to hand them in and works out what " ..
              "they cost.\n\nThis short tour shows each tab. Use Next and Back, or close it at any time. " ..
              "Type /writs tutorial to see it again.",
          show = ShowTab("mine"), target = Window },
        { title = "The tabs",
          text = "Your writs on the top row; buying, crates and settings on the bottom row.",
          target = TabButtons },
        { title = "My Writs",
          text = "Every writ in your quest log and bags: whether it's ready, how many of the item you have, " ..
              "reputation per gold and where it goes. Click a writ for a waypoint to its turn-in.\n\n" ..
              "Your other characters' writs are in sections below your own.",
          show = ShowTab("mine"), target = Content },
        { title = "Plan a route",
          text = "One click plans a route past everyone you can hand a writ to now, using your flight paths, " ..
              "boats, zeppelins and Hearthstone. An arrow leads the way, and a small tracker shows your next steps.",
          show = ShowTab("route"), target = Mark("routePlan") },
        { title = "One continent at a time",
          text = "Keep the route to Kalimdor or the Eastern Kingdoms, and leave the rest for later.",
          show = ShowTab("route"), target = Mark("routeContinent") },
        { title = "Shopping",
          text = "The crafted items your writs still need, including copies in your bank or on your alts. " ..
              "Filter by continent, zone or turn-in NPC to get ready for one trip.",
          show = ShowTab("shopping"), target = Content },
        { title = "Buy Writs",
          text = "Writs for sale on the Auction House, with what they cost (item included) and the reputation " ..
              "per gold. The line at the top picks the cheapest writs to your next standing.\n\n" ..
              "Prices come from Auctionator, TradeSkillMaster, SnapPrice or the addon's own Auction House tab.",
          show = ShowTab("buy"), target = Content },
        { title = "Waylaid Crates",
          text = "Fill a crate and hand it in for Merchant's Favor, which buys profession recipes. This tab shows " ..
              "the cheapest fill and the gold per Favor of every crate.\n\nFrom Friendly, 15 Favor buy a Forged " ..
              "Delivery Receipt: with an empty crate, it's 50 reputation.",
          show = ShowTab("crates"), target = Content },
        { title = "All Writs",
          text = "All 150 writs: filter by profession and level, and see which ones you've done today.",
          show = ShowTab("all"), target = Content },
        { title = "Settings",
          text = "Choose your price source, set your Diplomat rank, pick how routes use your Hearthstone, and more.",
          show = ShowTab("settings"), target = Content },
        { title = "See it again",
          text = "Reset tutorials shows both tours again: this one on your next login, and the Auction House one " ..
              "the next time you open its Craftman's tab.",
          show = ShowTab("settings"), target = Mark("settingsReset") },
        { title = "That's it!",
          text = "Open this window with the minimap button or /writs; right-click the button to plan a route.\n\n" ..
              "At the Auction House, the Craftman's tab searches writs, items and crates. It has a short tour of " ..
              "its own.",
          target = MinimapButton },
    },
}

function Tours:StartMain()
    if InCombatLockdown() then
        CH:Print("The tutorial can start once you're out of combat.")
        return
    end
    UI():Show("mine")
    CH.Tutorial:Start(MAIN)
end

---------------------------------------------------------------------------
-- The Auction House's "Craftman's" tab
---------------------------------------------------------------------------

local function Tab() return CH.AuctionTab end

local function AHMark(key, sub)
    return function()
        local m = Tab().marks
        local v = m and m[key]
        if sub then v = v and v[sub] end
        return v
    end
end

local function ShowList(list)
    return function()
        local ah = CH.db.profile.ah
        if ah.list ~= list then
            ah.list = list
            Tab():Build()
        end
    end
end

local savedList

local AH = {
    key = "ah",
    alive = function() return Tab().holder ~= nil and Tab().holder:IsShown() end,
    onStop = function()
        if savedList and CH.db.profile.ah.list ~= savedList then
            CH.db.profile.ah.list = savedList
            if Tab().holder:IsShown() then Tab():Build() end
        end
        savedList = nil
    end,
    steps = {
        { title = "The Craftman's tab",
          text = "Find the writs, items and crate materials you need on the Auction House, priced in one search.\n\n" ..
              "A few steps show how it works.",
          target = function() return Tab().holder end },
        { title = "Pick a list",
          text = "Writs, the items writs ask for and the items your own writs still need on the top row; " ..
              "crates and their materials on the bottom row.",
          show = ShowList("writs"), target = AHMark("rows") },
        { title = "Narrow it down",
          text = "Filter by continent, zone, turn-in NPC and level, and hide writs you've done today or already have.",
          show = ShowList("writs"), target = AHMark("filters") },
        { title = "Include item cost",
          text = "Adds the item a writ asks for to its cost, so you see what handing it in really costs.",
          show = ShowList("writs"), target = AHMark("itemCost") },
        { title = "Search",
          text = "Looks up every item in the list, one at a time, waiting whenever the Auction House is busy.\n\n" ..
              "The prices it finds are used everywhere in the addon: Buy Writs, Crates and the tooltips.",
          show = ShowList("writs"), target = AHMark("search") },
        { title = "Prices and costs",
          text = "Price is the cheapest buyout; auctions are bought whole and bids don't count. Cost is what you " ..
              "need, all in. Rep/gold is the reputation per gold.\n\n~ means an estimate from your price addon " ..
              "(not searched yet), * means too few are listed.",
          show = ShowList("writs"), target = AHMark("table") },
        { title = "Buy it",
          text = "Click a row to open it in the Auction House's Buy screen. Shift-click links it.",
          show = ShowList("writs"), target = AHMark("table") },
        { title = "What you already have",
          text = "Items for my writs: what the writs you hold still need.\nMaterials for my crates: every way to " ..
              "fill the crates in your bags, the cheapest in green.",
          target = function()
              local b = Tab().marks and Tab().marks.buttons
              return b and { b.myitems, b.mymaterials }
          end },
        { title = "Crates and Favor",
          text = "Favor/gold is the Merchant's Favor per gold. Tick Include materials cost to count filling the " ..
              "crate too.",
          show = ShowList("crates"), target = AHMark("table") },
    },
}

function Tours:OfferAuctionHouse()
    if CH.Tutorial:HasSeen("ah") or CH.Tutorial:IsRunning() or InCombatLockdown() then return end
    -- After the tab has been laid out.
    C_Timer.After(0.2, function()
        if not (Tab().holder and Tab().holder:IsShown()) then return end
        savedList = CH.db.profile.ah.list
        if not CH.Tutorial:Offer(AH) then savedList = nil end
    end)
end

---------------------------------------------------------------------------
-- First login
---------------------------------------------------------------------------

function Tours:TryMain()
    if CH.Tutorial:HasSeen("main") or CH.Tutorial:IsRunning() then return end
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:ScheduleTimer("TryMain", 2)
        end)
        return
    end
    UI():Show("mine")
    CH.Tutorial:Offer(MAIN)
end

function Tours:OnEnable()
    if not CH.Tutorial:HasSeen("main") then self:ScheduleTimer("TryMain", START_DELAY) end
end
