-- Small movable window with the next few route steps, shown while a route is
-- active, so the main window can stay closed while you travel.
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

local function Settings() return CH.db.profile.tracker end

function Tracker:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    Settings().pos = { point, relPoint, x, y }
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
        if not Settings().locked then frame:StartMoving() end
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

    self.frame = f
    self:RestorePosition()
end

function Tracker:Refresh()
    local route = CH.Route
    local show = Settings().shown and route:IsActive()
    if not show then
        if self.frame then self.frame:Hide() end
        return
    end
    if not self.frame then self:Create() end
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
    f:SetHeight(PAD * 2 + LINE_HEIGHT * (1 + math.max(1, #items)) + 4)
    f:Show()
end

function Tracker:SetShown(shown)
    Settings().shown = shown
    self:Refresh()
end

function Tracker:SetLocked(locked)
    Settings().locked = locked
end

function Tracker:OnEnable()
    self:RegisterMessage(ns.MSG_ROUTE, "Refresh")
    self:RegisterMessage(ns.MSG_UPDATED, "Refresh")
end
