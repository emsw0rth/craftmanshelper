-- Main window: "My Writs" (grouped by continent, then zone A-Z) and "All Writs".
local _, ns = ...
local CH = ns.CH
local AceGUI = LibStub("AceGUI-3.0")
local STATUS = ns.STATUS

local UI = CH:NewModule("UI", "AceEvent-3.0")
CH.UI = UI

local FRAME_GLOBAL = "CraftmansHelperFrame"
local DEFAULT_ICON = 134939 -- INV_Misc_Note_01

local COLOR = {
    ready = "ff20ff20", active = "ffff5050", inbags = "ffffa020",
    available = "ffffffff", done = "ff808080", dim = "ff999999",
}

local function C(color, text) return "|c" .. color .. text .. "|r" end

local function ItemName(id, fallback)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return name or fallback
end

local function ItemIcon(id)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon or DEFAULT_ICON
end

local function SortName(a, b)
    if strcmputf8i then return strcmputf8i(a, b) < 0 end
    return a:lower() < b:lower()
end

local STATUS_ORDER = { ready = 1, active = 2, inbags = 3, available = 4, done = 5 }

local function StatusText(s)
    if s.status == STATUS.READY then
        return C(COLOR.ready, "Ready to deliver")
    elseif s.status == STATUS.ACTIVE then
        return C(COLOR.active, string.format("%d/%d", math.min(s.have, s.need), s.need))
    elseif s.status == STATUS.INBAGS then
        return C(COLOR.inbags, "Not started (use the writ)")
    elseif s.status == STATUS.DONE then
        return C(COLOR.done, "Done today")
    end
    return C(COLOR.available, "Available")
end

local function InsertLink(link)
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function ShowTooltip(widget, s)
    local w = s.writ
    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(w.item)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Writ", ItemName(s.id, "Craftsman's Writ: " .. w.name), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Status", StatusText(s), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Have / need", string.format("%d / %d", s.have, s.need), 1, 0.82, 0, 1, 1, 1)
    local t = s.turnIn
    local where = s.zoneName or "Unknown"
    if t and t.x then where = string.format("%s (%.1f, %.1f)", where, t.x, t.y) end
    GameTooltip:AddDoubleLine("Deliver to", (t and t.name or "?") .. " - " .. where, 1, 0.82, 0, 1, 1, 1)
    if s.writsTotal > s.writsInBags then
        GameTooltip:AddDoubleLine("Writs in bank", tostring(s.writsTotal - s.writsInBags), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link the required item.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function AddRow(parent, s, extra)
    local row = AceGUI:Create("InteractiveLabel")
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlight)
    row:SetImage(ItemIcon(s.writ.item))
    row:SetImageSize(16, 16)
    local text = "  " .. ItemName(s.writ.item, s.writ.name)
    if s.writ.count > 1 then text = text .. " x" .. s.writ.count end
    text = text .. "   " .. StatusText(s)
    if extra then text = text .. "   " .. C(COLOR.dim, extra) end
    row:SetText(text)
    row:SetCallback("OnEnter", function(widget) ShowTooltip(widget, s) end)
    row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    row:SetCallback("OnClick", function()
        if IsModifiedClick("CHATLINK") then
            local _, link = C_Item.GetItemInfo(s.writ.item)
            if link then InsertLink(link) end
        end
        -- Phase 2: left-click will set a TomTom waypoint to the turn-in.
    end)
    parent:AddChild(row)
end

local function AddHeading(parent, text)
    local h = AceGUI:Create("Heading")
    h:SetFullWidth(true)
    h:SetText(text)
    parent:AddChild(h)
end

local function AddLabel(parent, text, font)
    local l = AceGUI:Create("Label")
    l:SetFullWidth(true)
    l:SetFontObject(font or GameFontNormal)
    l:SetText(text)
    parent:AddChild(l)
    return l
end

local function CreateScroll(container, key)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    UI.scrollStatus[key] = UI.scrollStatus[key] or {}
    scroll:SetStatusTable(UI.scrollStatus[key])
    container:AddChild(scroll)
    return scroll
end

---------------------------------------------------------------------------
-- Tab: My Writs
---------------------------------------------------------------------------

function UI:BuildMine(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    local toggle = AceGUI:Create("CheckBox")
    toggle:SetLabel("Include writs in bags that aren't started yet")
    toggle:SetWidth(360)
    toggle:SetValue(db.showUnstarted)
    toggle:SetCallback("OnValueChanged", function(_, _, value)
        db.showUnstarted = value
        self:Redraw()
    end)
    container:AddChild(toggle)

    local scroll = CreateScroll(container, "mine")

    -- continentID -> zoneName -> { states }
    local groups, any = {}, false
    for _, s in pairs(CH.Tracker:GetAllStates()) do
        local include = s.inLog or (db.showUnstarted and s.status == STATUS.INBAGS)
        if include then
            any = true
            local cont = groups[s.continentID] or {}
            groups[s.continentID] = cont
            local zone = cont[s.zoneName] or {}
            cont[s.zoneName] = zone
            table.insert(zone, s)
        end
    end

    if not any then
        AddLabel(scroll, "You have no Craftsman's Writs right now.\n\n" ..
            "Writs drop from creatures around the world (matching the zone's level) and can be " ..
            "bought on the Auction House. Each one can be completed once per day.", GameFontHighlight)
        return
    end

    for _, contID in ipairs(ns.CONTINENT_ORDER) do
        local cont = groups[contID]
        if cont then
            AddHeading(scroll, ns.ContinentName(contID))
            local zones = {}
            for zoneName in pairs(cont) do table.insert(zones, zoneName) end
            table.sort(zones, SortName)
            for _, zoneName in ipairs(zones) do
                AddLabel(scroll, zoneName, GameFontNormalLarge)
                local list = cont[zoneName]
                table.sort(list, function(a, b)
                    if a.status ~= b.status then return STATUS_ORDER[a.status] < STATUS_ORDER[b.status] end
                    return SortName(a.writ.name, b.writ.name)
                end)
                for _, s in ipairs(list) do
                    AddRow(scroll, s, s.turnIn and s.turnIn.name and ("-> " .. s.turnIn.name))
                end
            end
        end
    end
    -- Any continent not in CONTINENT_ORDER (shouldn't happen on Forever, but be safe).
    for contID, cont in pairs(groups) do
        if not tContains(ns.CONTINENT_ORDER, contID) then
            AddHeading(scroll, ns.ContinentName(contID))
            for _, list in pairs(cont) do
                for _, s in ipairs(list) do AddRow(scroll, s, s.zoneName) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tab: All Writs
---------------------------------------------------------------------------

function UI:BuildAll(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    local prof = AceGUI:Create("Dropdown")
    prof:SetLabel("Profession")
    prof:SetWidth(160)
    local profList, profOrder = { ALL = "All" }, { "ALL" }
    for _, p in ipairs(ns.PROFESSIONS) do profList[p] = ns.PROFESSION_NAMES[p]; table.insert(profOrder, p) end
    prof:SetList(profList, profOrder)
    prof:SetValue(db.professionFilter)
    prof:SetCallback("OnValueChanged", function(_, _, v) db.professionFilter = v; self:Redraw() end)
    container:AddChild(prof)

    local tier = AceGUI:Create("Dropdown")
    tier:SetLabel("Level")
    tier:SetWidth(140)
    local tierList, tierOrder = { ALL = "All" }, { "ALL" }
    for _, t in ipairs(ns.TIERS) do tierList[t] = ns.TIER_NAMES[t]; table.insert(tierOrder, t) end
    tier:SetList(tierList, tierOrder)
    tier:SetValue(db.tierFilter)
    tier:SetCallback("OnValueChanged", function(_, _, v) db.tierFilter = v; self:Redraw() end)
    container:AddChild(tier)

    local hide = AceGUI:Create("CheckBox")
    hide:SetLabel("Hide done today")
    hide:SetWidth(160)
    hide:SetValue(db.hideCompleted)
    hide:SetCallback("OnValueChanged", function(_, _, v) db.hideCompleted = v; self:Redraw() end)
    container:AddChild(hide)

    local scroll = CreateScroll(container, "all")
    local states = CH.Tracker:GetAllStates()

    for _, p in ipairs(ns.PROFESSIONS) do
        if db.professionFilter == "ALL" or db.professionFilter == p then
            local headingAdded = false
            for _, t in ipairs(ns.TIERS) do
                if db.tierFilter == "ALL" or db.tierFilter == t then
                    local list = {}
                    for _, s in pairs(states) do
                        if s.writ.tier == t and tContains(s.writ.profs, p)
                            and not (db.hideCompleted and s.status == STATUS.DONE) then
                            table.insert(list, s)
                        end
                    end
                    if #list > 0 then
                        if not headingAdded then AddHeading(scroll, ns.PROFESSION_NAMES[p]); headingAdded = true end
                        AddLabel(scroll, ns.TIER_NAMES[t], GameFontNormalLarge)
                        table.sort(list, function(a, b) return SortName(a.writ.name, b.writ.name) end)
                        for _, s in ipairs(list) do
                            AddRow(scroll, s, s.zoneName ~= "Unknown" and s.zoneName or "turn-in unknown")
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

function UI:UpdateStatusText()
    if not self.frame then return end
    local c = CH.Tracker:GetCounts()
    self.frame:SetStatusText(string.format("%d ready  -  %d in progress  -  %d done today  -  daily reset in %s",
        c.ready, c.active, c.done, ns.FormatDuration(CH.Tracker:SecondsUntilReset())))
end

function UI:Redraw()
    if not (self.frame and self.tabs) then return end
    self.tabs:SelectTab(self.currentTab or "mine")
end

function UI:Create()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Craftman's Helper")
    frame:SetLayout("Fill")
    CH.db.profile.window = CH.db.profile.window or {}
    frame:SetStatusTable(CH.db.profile.window)
    if not CH.db.profile.window.width then frame:SetWidth(560); frame:SetHeight(520) end
    frame:SetCallback("OnClose", function(widget)
        _G[FRAME_GLOBAL] = nil
        AceGUI:Release(widget)
        self.frame, self.tabs = nil, nil
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end)

    -- Close with Escape.
    _G[FRAME_GLOBAL] = frame.frame
    if not tContains(UISpecialFrames, FRAME_GLOBAL) then table.insert(UISpecialFrames, FRAME_GLOBAL) end

    local tabs = AceGUI:Create("TabGroup")
    tabs:SetTabs({ { text = "My Writs", value = "mine" }, { text = "All Writs", value = "all" } })
    tabs:SetCallback("OnGroupSelected", function(container, _, group)
        self.currentTab = group
        container:ReleaseChildren()
        if group == "all" then self:BuildAll(container) else self:BuildMine(container) end
        self:UpdateStatusText()
    end)
    frame:AddChild(tabs)

    self.frame, self.tabs = frame, tabs
    self.ticker = C_Timer.NewTicker(30, function() self:UpdateStatusText() end)
end

function UI:Show(tab)
    if tab then self.currentTab = tab end
    if not self.frame then self:Create() end
    self:Redraw()
end

function UI:Toggle()
    if self.frame then
        self.frame:Hide() -- fires OnClose -> release
    else
        self:Show()
    end
end

function UI:OnEnable()
    self.scrollStatus = {}
    self.currentTab = "mine"
    self:RegisterMessage(ns.MSG_UPDATED, "Redraw")
end
