-- Small movable window with the next few route steps, shown while a route is
-- active, so the main window can stay closed while you travel. Below the steps: a button
-- for each writ at the current stop that's still unstarted in your bags; clicking one uses
-- the writ, which opens its quest. Using an item takes a secure button, which the game
-- won't let addons change in combat, so the buttons (and the frame holding them) are only
-- laid out out of combat; the step texts still update.
local _, ns = ...
local CH = ns.CH

local Tracker = CH:NewModule("RouteTracker", "AceEvent-3.0")
CH.RouteTracker = Tracker

local MAX_LINES = 5
local WIDTH = 300
local LINE_HEIGHT = 16
local PAD = 8

local COLOR_STEP = { 1, 0.63, 0.13 }
local COLOR_CURRENT = { 0.13, 1, 0.13 }
local COLOR_STOP = { 1, 1, 1 }

local MAX_WRIT_BUTTONS = 8
local BUTTON_SIZE = 22
local LABEL_WIDTH = 40 -- room for "Start:" left of the buttons
ns.QUEST_LOG_MAX = 40 -- WoW: Forever's quest log

-- The key binding (Bindings.xml) clicks this button: it starts the next writ.
BINDING_HEADER_CRAFTMANSHELPER = "Craftman's Helper"
_G["BINDING_NAME_CLICK CraftmansHelperStartWrit:LeftButton"] = "Start the next writ"

local function Settings() return CH.db.profile.tracker end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- Writs to deliver at a stop that are in your bags with their quest not started yet.
function Tracker.Startable(stop)
    local out = {}
    for _, id in ipairs(stop and not stop.done and stop.writs or {}) do
        local st = CH.Tracker:GetState(id)
        if st and st.status == ns.STATUS.INBAGS and (st.writsInBags or 0) > 0 then table.insert(out, id) end
    end
    return out
end

-- Quests in your log and the most it holds; quests is nil when the game doesn't say.
function Tracker.QuestLog()
    local quests
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        quests = select(2, C_QuestLog.GetNumQuestLogEntries())
    elseif GetNumQuestLogEntries then
        quests = select(2, GetNumQuestLogEntries())
    end
    return quests, ns.QUEST_LOG_MAX
end

function Tracker.QuestLogFull()
    local quests, max = Tracker.QuestLog()
    return quests ~= nil and quests >= max, quests, max
end

local function ItemName(id)
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or
        (ns.Writs[id] and ns.Writs[id].name) or ("writ " .. id)
end

local function ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or
        (GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function WritOnEnter(btn)
    if not btn.writID then return end
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(btn.writID) else GameTooltip:AddLine(ItemName(btn.writID)) end
    local full, quests, max = Tracker.QuestLogFull()
    if full then
        GameTooltip:AddLine(string.format("Quest log full (%d/%d).", quests, max), 1, 0.3, 0.3)
    else
        GameTooltip:AddLine("Click to start this writ's quest.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Points a secure button at writ `id` (nil: it does nothing). Out of combat only.
local function SetWrit(btn, id)
    btn.writID = id
    btn:SetAttribute("type", id and "item" or nil)
    btn:SetAttribute("item", id and ("item:" .. id) or nil)
end

local function SecureButton(name, parent)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    -- Both, so it works whichever the "cast on key down" setting is (the game uses the one that matches).
    b:RegisterForClicks("AnyUp", "AnyDown")
    return b
end

function Tracker:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    Settings().pos = { point, relPoint, x, y }
end

-- Back to its default spot, e.g. after it ended up off-screen.
function Tracker:ResetPosition()
    Settings().pos = nil
    if self.frame then self:RestorePosition() end
end

function Tracker:RestorePosition()
    local f, pos = self.frame, Settings().pos
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    end
end

local function LineOnEnter(btn)
    local item = btn.item
    if not item then return end
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    if item.kind == "stop" then
        local stop = item.stop
        GameTooltip:AddLine(stop.name or "?")
        GameTooltip:AddLine(string.format("%s (%.1f, %.1f)", stop.zoneName or "?", stop.x, stop.y), 1, 1, 1)
        for _, id in ipairs(stop.writs) do
            local w = ns.Writs[id]
            if w then
                local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(w.item)) or w.name
                GameTooltip:AddLine("  " .. name, 0.8, 0.8, 0.8)
            end
        end
        GameTooltip:AddLine("Click to point the arrow here.", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(item.text, 1, 1, 1, true)
        GameTooltip:AddLine("On the way to " .. (item.stop.name or "?") .. ".", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function LineOnClick(btn)
    local item = btn.item
    if item and item.stop and item.stop.index and not item.stop.done then
        CH.Route:SetCurrent(item.stop.index, nil, true)
    end
end

function Tracker:Create()
    local f = CreateFrame("Frame", "CraftmansHelperRouteTracker", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not Settings().locked and not InCombat() then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0, 0, 0, 0.65)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    end

    -- Title: click to open the Route tab.
    local title = CreateFrame("Button", nil, f)
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetPoint("TOPRIGHT", -PAD - 18, -PAD)
    title:SetHeight(LINE_HEIGHT)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
    title:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
    title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title.text:SetAllPoints()
    title.text:SetJustifyH("LEFT")
    title:SetScript("OnClick", function() CH.UI:Show("route") end)
    title:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:AddLine("Craftman's Helper route")
        GameTooltip:AddLine("Click to open the Route tab.", 0.6, 0.6, 0.6)
        if not Settings().locked then GameTooltip:AddLine("Drag to move.", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    title:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        Settings().shown = false
        self:Refresh()
        CH:Print("Route tracker hidden. Turn it back on in the Settings tab or with /writs tracker.")
    end)

    f.lines = {}
    for i = 1, MAX_LINES do
        local line = CreateFrame("Button", nil, f)
        line:SetHeight(LINE_HEIGHT)
        line:SetPoint("TOPLEFT", PAD, -PAD - i * LINE_HEIGHT - 2)
        line:SetPoint("TOPRIGHT", -PAD, -PAD - i * LINE_HEIGHT - 2)
        line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.text:SetAllPoints()
        line.text:SetJustifyH("LEFT")
        line.text:SetWordWrap(false)
        line:SetScript("OnEnter", LineOnEnter)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line:SetScript("OnClick", LineOnClick)
        line:RegisterForDrag("LeftButton")
        line:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
        line:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
        f.lines[i] = line
    end

    -- Writ buttons for the current stop.
    f.writLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.writLabel:SetText("Start:")
    f.writs = {}
    for i = 1, MAX_WRIT_BUTTONS do
        local b = SecureButton("CraftmansHelperWritButton" .. i, f)
        b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", WritOnEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Secure buttons can't be anchored to text, so the first is placed on the frame
        -- (in LayoutWrits) and the label hangs off it.
        if i > 1 then b:SetPoint("LEFT", f.writs[i - 1], "RIGHT", 3, 0) end
        b:Hide()
        f.writs[i] = b
    end

    self.frame = f
    self:RestorePosition()
end

-- Points the writ buttons and the key binding's button at the current stop's unstarted
-- writs, with the row's top at `top`. Out of combat only. Returns how many buttons show.
function Tracker:LayoutWrits(top)
    local f = self.frame
    local route = CH.Route
    local startable = Tracker.Startable(route:IsActive() and route:GetCurrent() or nil)
    local full = Tracker.QuestLogFull()
    if self.bindButton then SetWrit(self.bindButton, (not full) and startable[1] or nil) end
    if not f then return 0 end
    local shown = math.min(#startable, MAX_WRIT_BUTTONS)
    local first = f.writs[1]
    first:ClearAllPoints()
    first:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LABEL_WIDTH, top - 2)
    f.writLabel:ClearAllPoints()
    f.writLabel:SetPoint("RIGHT", first, "LEFT", -6, 0)
    f.writLabel:SetShown(shown > 0)
    for i, b in ipairs(f.writs) do
        local id = i <= shown and startable[i] or nil
        SetWrit(b, id)
        if id then
            b.icon:SetTexture(ItemIcon(id))
            b.icon:SetDesaturated(full)
            b:SetEnabled(not full)
            b:Show()
        else
            b:Hide()
        end
    end
    return shown
end

function Tracker:Refresh()
    local route = CH.Route
    local combat = InCombat()
    self.pending = combat or nil
    local show = Settings().shown and route:IsActive()
    if not show then
        if not combat then
            if self.frame then self.frame:Hide() end
            self:LayoutWrits(0)
        end
        return
    end
    if not self.frame then
        if combat then return end
        self:Create()
    end
    local f = self.frame

    local items = route:GetUpcoming(MAX_LINES)
    local remaining, delivered = 0, 0
    for _, stop in ipairs(route.route.stops) do
        if stop.done then delivered = delivered + 1 else remaining = remaining + 1 end
    end
    f.title.text:SetText(string.format("Route: %d stop%s left", remaining, remaining == 1 and "" or "s"))

    local current = route:GetCurrent()
    local number = 0
    for i, line in ipairs(f.lines) do
        local item = items[i]
        line.item = item
        if item then
            local color
            if item.kind == "stop" then
                number = number + 1
                color = (item.stop == current) and COLOR_CURRENT or COLOR_STOP
                line.text:SetText(string.format("%d. %s", item.stop.index or number, item.text))
            else
                color = COLOR_STEP
                line.text:SetText("    " .. item.text)
            end
            line.text:SetTextColor(color[1], color[2], color[3])
            line:Show()
        else
            line:Hide()
        end
    end
    -- The frame holds secure buttons: its size and the buttons wait until after combat.
    if combat then return end
    local height = PAD * 2 + LINE_HEIGHT * (1 + math.max(1, #items)) + 4
    if self:LayoutWrits(-height + PAD) > 0 then height = height + BUTTON_SIZE + 4 end
    f:SetHeight(height)
    f:Show()
end

function Tracker:OnCombatEnd()
    if self.pending then self:Refresh() end
end

function Tracker:SetShown(shown)
    Settings().shown = shown
    self:Refresh()
end

function Tracker:SetLocked(locked)
    Settings().locked = locked
end

function Tracker:OnEnable()
    -- The key binding's button: starts the first unstarted writ at the current stop.
    local b = SecureButton("CraftmansHelperStartWrit", UIParent)
    b:HookScript("OnClick", function(btn, _, down)
        if btn.writID then return end
        local now = GetTime and GetTime() or 0
        if self.saidNothing and now - self.saidNothing < 2 then return end -- once per press, not on key up too
        self.saidNothing = now
        local full, quests, max = Tracker.QuestLogFull()
        if full then
            CH:Print(string.format("Your quest log is full (%d/%d).", quests, max))
        else
            CH:Print("No unstarted writs in your bags for the current stop.")
        end
    end)
    self.bindButton = b

    self:RegisterMessage(ns.MSG_ROUTE, "Refresh")
    self:RegisterMessage(ns.MSG_UPDATED, "Refresh")
    self:RegisterEvent("QUEST_ACCEPTED", "Refresh")
    self:RegisterEvent("QUEST_REMOVED", "Refresh")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
end
