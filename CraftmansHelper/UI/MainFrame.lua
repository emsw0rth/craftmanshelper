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
    if not name then ns.MissingNames[id] = true end -- redraw once it loads (Tracker.lua)
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
        return C(COLOR.inbags, s.bankOnly and "In the bank" or "Not started (use the writ)")
    elseif s.status == STATUS.DONE then
        return C(COLOR.done, "Done today")
    end
    return C(COLOR.available, "Available")
end

-- Inserts an item link the way a shift-click on a bag item does: into chat, the Auction
-- House search, or Auctionator's Shopping search. The modern client's ChatFrameUtil.InsertLink
-- comes first: Auctionator hooks that one when it exists, not the older ChatEdit_InsertLink.
local function InsertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- showWrit: the tooltip is the writ's own (All Writs); otherwise the item it asks for.
local function ShowTooltip(widget, s, showWrit)
    local w = s.writ
    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
    -- Our own rows already show the writ details; skip the item-tooltip hook here.
    CH.Tooltips.suppress = true
    GameTooltip:SetItemByID(showWrit and s.id or w.item)
    CH.Tooltips.suppress = false
    GameTooltip:AddLine(" ")
    if showWrit then
        GameTooltip:AddDoubleLine("Needs", ItemName(w.item, w.name) .. (w.count > 1 and (" x" .. w.count) or ""),
            1, 0.82, 0, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Writ", ItemName(s.id, "Craftsman's Writ: " .. w.name), 1, 0.82, 0, 1, 1, 1)
    end
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
    if t and t.x then
        GameTooltip:AddLine("Click to set a waypoint to the turn-in.", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(showWrit and "Shift-click to link the writ." or "Shift-click to link the required item.",
        0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function PointFor(s)
    local t = s.turnIn
    if not (t and t.map and t.x and t.y) then return nil end
    local who = t.name or s.zoneName or "Turn-in"
    return { map = t.map, x = t.x, y = t.y, title = who .. ": " .. ItemName(s.writ.item, s.writ.name) }
end

-- Waypoints to the turn-ins of the given writ states (one per distinct spot).
local function NavigateTo(list)
    local points, seen = {}, {}
    for _, s in ipairs(list) do
        local p = PointFor(s)
        if p then
            local key = string.format("%d:%.0f:%.0f", p.map, p.x, p.y)
            if not seen[key] then
                seen[key] = true
                table.insert(points, p)
            end
        end
    end
    CH.Nav:GoTo(points)
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
        else
            NavigateTo({ s })
        end
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

-- Zone heading in "My Writs": click for waypoints to every writ listed under it.
local function AddZoneHeader(parent, zoneName, list)
    local l = AceGUI:Create("InteractiveLabel")
    l:SetFullWidth(true)
    l:SetFontObject(GameFontNormalLarge)
    l:SetText(zoneName)
    l:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(zoneName)
        GameTooltip:AddLine("Click to set waypoints to every writ in this zone.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    l:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    l:SetCallback("OnClick", function() NavigateTo(list) end)
    parent:AddChild(l)
end

local function AddButton(parent, text, width, onClick)
    local b = AceGUI:Create("Button")
    b:SetText(text)
    b:SetWidth(width)
    b:SetCallback("OnClick", onClick)
    parent:AddChild(b)
    return b
end

local function FormatMinutes(seconds)
    local m = math.floor((seconds or 0) / 60 + 0.5)
    if m < 1 then return "under a minute" end
    if m >= 60 then return string.format("%dh %dm", math.floor(m / 60), m % 60) end
    return m .. " min"
end

local function CreateScroll(container, key)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    local status = UI.scrollStatus[key] or {}
    UI.scrollStatus[key] = status
    -- AceGUI's scroll frame jumps back to the top while it's being filled (a short list
    -- hides the scrollbar, which resets the position), so remember where it was and
    -- put it back once the tab is built (RestoreScroll).
    UI.pendingScroll = { widget = scroll, offset = status.offset, value = status.scrollvalue }
    scroll:SetStatusTable(status)
    container:AddChild(scroll)
    return scroll
end

---------------------------------------------------------------------------
-- Tables (My Writs, All Writs, Buy Writs)
---------------------------------------------------------------------------
-- Plain frames, not AceGUI widgets: every row is the same height, every cell is one
-- line (cut off with "..." when it doesn't fit; the tooltip has it all) and text is
-- centred vertically. Each table (by id) makes its frames once and reuses them.
--
-- columns: { { key, title, width = share of the table's width (all just under 1),
--              sortName = "name" for the header tooltip, descFirst = true to sort
--              high-to-low on the first click } }
-- rows:    { { cells = { text per column }, onEnter = fn(frame), onClick = fn(frame) } }

local ROW_HEIGHT = 22
local HEADER_HEIGHT = 24
local CELL_PAD = 6
local LINE = { 0.55, 0.45, 0.2, 0.9 }      -- gold-brown, like the window border
local HEADER_BG = { 0.25, 0.2, 0.05, 0.5 }
local DOTS = "Interface\\AddOns\\CraftmansHelper\\Media\\DottedLine"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local SORT_ARROW = { [false] = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t",
                     [true] = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t" }

local tables = {}

local function SolidLine(parent, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(LINE[1], LINE[2], LINE[3], LINE[4])
    return t
end

local function NewCell(parent, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    return fs
end

local function LayoutTable(t, width)
    local x = 0
    for c, col in ipairs(t.columns) do
        local w = width * col.width / 0.99
        local hc = t.header.cells[c]
        hc:ClearAllPoints()
        hc:SetPoint("TOPLEFT", x, 0)
        hc:SetWidth(w)
        for _, row in ipairs(t.rows) do
            local cell = row.cells[c]
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", x + CELL_PAD, 0)
            cell:SetWidth(math.max(1, w - 2 * CELL_PAD))
        end
        x = x + w
    end
end

local function CreateTableFrame(columns)
    local t = CreateFrame("Frame")
    t.columns = columns
    t.rows = {}

    -- Header: a box with a light fill, a line between columns, clickable titles.
    local header = CreateFrame("Frame", nil, t)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(HEADER_BG[1], HEADER_BG[2], HEADER_BG[3], HEADER_BG[4])
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local l = SolidLine(header)
        l:SetHeight(1)
        l:SetPoint(side .. "LEFT")
        l:SetPoint(side .. "RIGHT")
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local l = SolidLine(header)
        l:SetWidth(1)
        l:SetPoint("TOP" .. side)
        l:SetPoint("BOTTOM" .. side)
    end
    header.cells = {}
    for c, col in ipairs(columns) do
        local b = CreateFrame("Button", nil, header)
        b:SetHeight(HEADER_HEIGHT)
        b.text = NewCell(b, "GameFontNormal")
        b.text:SetPoint("LEFT", CELL_PAD, 0)
        b.text:SetPoint("RIGHT", -CELL_PAD, 0)
        b:SetHighlightTexture(HIGHLIGHT, "ADD")
        if c > 1 then
            local divider = SolidLine(b)
            divider:SetWidth(1)
            divider:SetPoint("TOPLEFT", 0, -3)
            divider:SetPoint("BOTTOMLEFT", 0, 3)
        end
        b:SetScript("OnClick", function() if t.onSort then t.onSort(col.key) end end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Sort by " .. (col.sortName or col.title):lower(), 1, 1, 1)
            GameTooltip:AddLine("Click again to reverse the order.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        header.cells[c] = b
    end
    t.header = header

    -- Columns follow the table's width.
    t:SetScript("OnSizeChanged", function(self, width) LayoutTable(self, width) end)
    return t
end

-- Row i, made when first needed.
local function TableRowFrame(t, i)
    local row = t.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, t)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + (i - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -(HEADER_HEIGHT + (i - 1) * ROW_HEIGHT))
    row:SetHighlightTexture(HIGHLIGHT, "ADD")
    local dots = row:CreateTexture(nil, "BORDER")
    dots:SetTexture(DOTS, "REPEAT", "REPEAT")
    dots:SetHorizTile(true)
    dots:SetVertexColor(LINE[1], LINE[2], LINE[3], 0.6)
    dots:SetHeight(1)
    dots:SetPoint("BOTTOMLEFT")
    dots:SetPoint("BOTTOMRIGHT")
    row.cells = {}
    for c = 1, #t.columns do row.cells[c] = NewCell(row, "GameFontHighlight") end
    row:SetScript("OnEnter", function(self) if self.data and self.data.onEnter then self.data.onEnter(self) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self) if self.data and self.data.onClick then self.data.onClick(self) end end)
    t.rows[i] = row
    return row
end

-- Adds table `id` to `parent` (an AceGUI container), sorted by sortKey (desc: reversed).
local function AddTable(parent, id, columns, rows, sortKey, desc, onSort)
    local t = tables[id]
    if not t then
        t = CreateTableFrame(columns)
        tables[id] = t
    end
    t.onSort = onSort
    for c, col in ipairs(columns) do
        t.header.cells[c].text:SetText(col.title .. (col.key == sortKey and SORT_ARROW[desc and true or false] or ""))
    end
    for i, r in ipairs(rows) do
        local row = TableRowFrame(t, i)
        row.data = r
        for c = 1, #columns do row.cells[c]:SetText(r.cells[c] or "") end
        row:Show()
    end
    for i = #rows + 1, #t.rows do
        t.rows[i].data = nil
        t.rows[i]:Hide()
    end

    -- An AceGUI group of the table's height holds it; the table goes back to
    -- UIParent (hidden) when the group is released.
    local holder = AceGUI:Create("SimpleGroup")
    holder:SetFullWidth(true)
    holder.noAutoHeight = true
    holder:SetHeight(HEADER_HEIGHT + #rows * ROW_HEIGHT + 2)
    holder:SetCallback("OnRelease", function()
        t:Hide()
        t:ClearAllPoints()
        t:SetParent(UIParent)
    end)
    parent:AddChild(holder)
    t:SetParent(holder.frame)
    t:ClearAllPoints()
    t:SetAllPoints(holder.frame)
    t:Show()
    local w = holder.frame:GetWidth()
    if w and w > 0 then LayoutTable(t, w) end
end

-- A table's sort, kept in the profile as db[prefix .. "Sort"] (a column key) and
-- db[prefix .. "SortDesc"] (nil: the column's usual direction). Returns the key, whether
-- it's reversed, and the function to call with a clicked column's key.
local function TableSort(db, prefix, columns, default, refresh)
    local byKey = {}
    for _, col in ipairs(columns) do byKey[col.key] = col end
    local sortField, descField = prefix .. "Sort", prefix .. "SortDesc"
    if not byKey[db[sortField]] then db[sortField], db[descField] = default, nil end
    local function Desc()
        if db[descField] == nil then return byKey[db[sortField]].descFirst or false end
        return db[descField]
    end
    local function SortBy(key)
        if key == db[sortField] then
            db[descField] = not Desc()
        else
            db[sortField], db[descField] = key, nil
        end
        refresh()
    end
    return db[sortField], Desc(), SortBy
end

-- Sorts rows by row.sort[key] (a number or lower-case string), reversed when desc;
-- ties go by row.sort.tie.
-- Rows without a value (nil) always go last.
local function SortRows(rows, key, desc)
    table.sort(rows, function(a, b)
        local va, vb = a.sort[key], b.sort[key]
        if (va == nil) ~= (vb == nil) then return va ~= nil end
        if va ~= vb and va ~= nil then
            if desc then return va > vb end
            return va < vb
        end
        return (a.sort.tie or "") < (b.sort.tie or "")
    end)
end

-- Row text helpers shared by My Writs and All Writs.
local function WritName(s)
    local name = ItemName(s.writ.item, s.writ.name)
    if s.writ.count > 1 then name = name .. " " .. C(COLOR.ready, "x" .. s.writ.count) end
    return name
end

local function ShortStatus(s)
    if s.status == STATUS.READY then return C(COLOR.ready, "Ready to deliver") end
    if s.status == STATUS.ACTIVE then return C(COLOR.active, "Need the item") end
    if s.status == STATUS.INBAGS then return C(COLOR.inbags, s.bankOnly and "In bank" or "Not started") end
    if s.status == STATUS.DONE then return C(COLOR.done, "Done today") end
    return C(COLOR.available, "Available")
end

-- Zone sort value: continents in their usual order (Kalimdor first), then zone A-Z.
local function ZoneSortValue(s)
    local order = 99
    for i, id in ipairs(ns.CONTINENT_ORDER) do if id == s.continentID then order = i end end
    if not s.turnIn or s.zoneName == "Unknown" then order = 100 end
    return string.format("%03d%s", order, (s.zoneName or ""):lower())
end

-- A writ row for My Writs and All Writs: hover for details, click for a waypoint,
-- shift-click to link the item; zoneList (optional) is used for alt-click.
-- showWrit: hover shows the writ and shift-click links it, not the item it asks for.
local function WritRow(s, cells, zoneList, showWrit)
    return {
        cells = cells,
        onEnter = function(frame)
            ShowTooltip({ frame = frame }, s, showWrit)
            if zoneList then
                GameTooltip:AddLine("Alt-click for waypoints to every writ in " .. (s.zoneName or "this zone") .. ".",
                    0.6, 0.6, 0.6)
                GameTooltip:Show()
            end
        end,
        onClick = function()
            if IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(showWrit and s.id or s.writ.item)
                if link then InsertLink(link) end
            elseif zoneList and IsAltKeyDown() then
                NavigateTo(zoneList)
            else
                NavigateTo({ s })
            end
        end,
    }
end

-- What the reputation amounts include, e.g. "Includes Diplomat +6%."
local function RepBonusNote()
    local rank = ns.DiplomatRank()
    if rank == 0 then return "Without Diplomat (set your rank in Settings)." end
    return string.format("Includes Diplomat +%d%%.", math.floor(rank * ns.DIPLOMAT_STEP * 100 + 0.5))
end

---------------------------------------------------------------------------
-- Tab: My Writs
---------------------------------------------------------------------------

local MINE_COLUMNS = {
    { key = "name", title = "Name", width = 0.26 },
    { key = "status", title = "Status", width = 0.16 },
    { key = "have", title = "Have", width = 0.08, sortName = "items you have" },
    { key = "rep", title = "Rep/|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", width = 0.10, sortName = "rep per gold", descFirst = true },
    { key = "npc", title = "Turn-in", width = 0.20, sortName = "turn-in NPC" },
    { key = "zone", title = "Zone", width = 0.19 },
}

-- Table rows for writ states (yours, or another character's from its snapshot).
-- diplomat: that character's Diplomat rank for rep per gold (yours when nil).
local function MineRows(list, diplomat)
    local db = CH.db.profile
    local priced = ns.Prices.IsAvailable()
    local byZone = {}
    for _, s in ipairs(list) do
        byZone[s.zoneName] = byZone[s.zoneName] or {}
        table.insert(byZone[s.zoneName], s)
    end
    local rows = {}
    for _, s in ipairs(list) do
        local enough = s.have >= s.need
        local npc = s.turnIn and s.turnIn.name
        local est = priced and ns.Prices.GetWritEstimate(s.id, db.includeWritPrice)
        local repPerGold = est and ns.Prices.RepPerGold(ns.WritRep(s.id, diplomat) or 0, est.net)
        local cells = {
            WritName(s),
            ShortStatus(s),
            C(enough and COLOR.ready or COLOR.active, string.format("%d/%d", math.min(s.have, s.need), s.need)),
            repPerGold and C(COLOR.ready, ns.FormatRepPerGold(repPerGold)) or C(COLOR.dim, "-"),
            npc or C(COLOR.dim, "unknown yet"),
            s.zoneName ~= "Unknown" and s.zoneName or C(COLOR.dim, "unknown yet"),
        }
        local row = WritRow(s, cells, byZone[s.zoneName], true)
        local name = (ItemName(s.writ.item, s.writ.name) or ""):lower()
        row.sort = {
            name = name,
            status = STATUS_ORDER[s.status],
            have = s.need > 0 and s.have / s.need or 0,
            rep = repPerGold,
            npc = npc and npc:lower() or "~",
            zone = ZoneSortValue(s),
            tie = STATUS_ORDER[s.status] .. name,
        }
        table.insert(rows, row)
    end
    return rows
end

-- "3 hours ago", "yesterday", "4 days ago".
local function Ago(t)
    if not (t and GetServerTime) then return "a while ago" end
    local d = GetServerTime() - t
    if d < 3600 then return "less than an hour ago" end
    if d < 86400 then
        local h = math.floor(d / 3600)
        return h .. " hour" .. (h == 1 and "" or "s") .. " ago"
    end
    local days = math.floor(d / 86400)
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

local FOLD_ICON = { [true] = "Interface\\Buttons\\UI-MinusButton-Up", [false] = "Interface\\Buttons\\UI-PlusButton-Up" }

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

    -- Your other characters on this realm and faction that hold writs.
    local allOthers = CH.Alts:Others()
    if #allOthers > 0 then
        local altToggle = AceGUI:Create("CheckBox")
        altToggle:SetLabel("Show my other characters")
        altToggle:SetWidth(240)
        altToggle:SetValue(db.mineShowAlts)
        altToggle:SetCallback("OnValueChanged", function(_, _, value)
            db.mineShowAlts = value
            self:Redraw()
        end)
        container:AddChild(altToggle)
    end
    local others = {}
    if db.mineShowAlts then
        for _, o in ipairs(allOthers) do
            local states = CH.Alts.WritStates(o.entry, db.showUnstarted)
            if #states > 0 then
                o.states = states
                table.insert(others, o)
            end
        end
    end

    local box = AceGUI:Create("InlineGroup")
    box:SetFullWidth(true)
    box:SetFullHeight(true)
    box:SetLayout("Fill")
    container:AddChild(box)
    local scroll = CreateScroll(box, "mine")

    local list = {}
    for _, s in pairs(CH.Tracker:GetAllStates()) do
        if s.inLog or (db.showUnstarted and s.status == STATUS.INBAGS) then
            table.insert(list, s)
        end
    end
    -- One sort for every table on the tab.
    local sortKey, desc, sortBy = TableSort(db, "mine", MINE_COLUMNS, "zone", function() self:Redraw() end)

    if #others > 0 then
        local _, _, _, first, surname = CH.Alts.Me()
        local me = { name = first or UnitName("player"), surname = surname, class = select(2, UnitClass("player")) }
        AddHeading(scroll, CH.Alts.ColoredName(me, true) .. " (you)")
    end

    if #list == 0 then
        AddLabel(scroll, "You have no Craftsman's Writs right now.\n\n" ..
            "Writs drop from creatures around the world (matching the zone's level) and can be " ..
            "bought on the Auction House. Each one can be completed once per day.", GameFontHighlight)
    else
        -- Reputation for turning them all in.
        local held = ns.Rep.Held()
        local repText = string.format("Turning in your %d writ%s: %s reputation", held.count,
            held.count == 1 and "" or "s", C(COLOR.ready, ns.Rep.Number(held.rep)))
        if ns.Rep.FactionName() then repText = repText .. " with " .. ns.Rep.FactionName() end
        if held.ready.count > 0 and held.ready.count < held.count then
            repText = repText .. string.format(" (%s from the %d ready now)", ns.Rep.Number(held.ready.rep),
                held.ready.count)
        end
        repText = repText .. "."
        if held.bank.count > 0 then
            repText = repText .. C(COLOR.dim, string.format("  %d more in your bank: %s.", held.bank.count,
                ns.Rep.Number(held.bank.rep)))
        end
        AddLabel(scroll, repText, GameFontHighlight)
        local outlook = ns.Rep.Outlook(held.rep)
        AddLabel(scroll, C(COLOR.dim, (outlook and (outlook .. "  ") or "") .. RepBonusNote()),
            GameFontHighlightSmall)
        AddLabel(scroll, " ", GameFontHighlightSmall)

        local rows = MineRows(list)
        SortRows(rows, sortKey, desc)
        AddTable(scroll, "mine", MINE_COLUMNS, rows, sortKey, desc, sortBy)
    end

    if #others == 0 then return end

    -- Other characters: a heading each (click to fold or unfold), then their table.
    AddLabel(scroll, " ", GameFontHighlightSmall)
    AddHeading(scroll, "Your other characters")
    db.mineAltsOpen = db.mineAltsOpen or {}
    for _, o in ipairs(others) do
        local c, states = o.entry, o.states
        local open = db.mineAltsOpen[o.key] and true or false
        local rep = CH.Alts.Rep(c, states)
        local summary = string.format("%d writ%s, %s reputation", rep.count, rep.count == 1 and "" or "s",
            ns.Rep.Number(rep.rep))
        if rep.ready.count > 0 then summary = summary .. string.format(", %d ready", rep.ready.count) end

        local head = AceGUI:Create("InteractiveLabel")
        head:SetFullWidth(true)
        head:SetFontObject(GameFontHighlight)
        head:SetImage(FOLD_ICON[open])
        head:SetImageSize(16, 16)
        head:SetHighlight(HIGHLIGHT)
        head:SetText(" " .. CH.Alts.ColoredName(c, true) .. ": " .. summary ..
            C(COLOR.dim, "   (seen " .. Ago(c.updated) .. ")"))
        head:SetCallback("OnClick", function()
            db.mineAltsOpen[o.key] = not open or nil
            self:Redraw()
        end)
        head:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(CH.Alts.FullName(c), 1, 1, 1)
            GameTooltip:AddLine((open and "Click to hide" or "Click to show") .. " this character's writs.",
                0.6, 0.6, 0.6)
            GameTooltip:AddLine("As of when you last played them (" .. Ago(c.updated) .. "). Log in on them " ..
                "to bring it up to date.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        head:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        scroll:AddChild(head)

        if open then
            local rank = c.diplomat or 0
            local note = rank > 0 and string.format("Includes Diplomat +%d%%.",
                math.floor(rank * ns.DIPLOMAT_STEP * 100 + 0.5)) or "Without Diplomat."
            local outlook = ns.Rep.Outlook(rep.rep, c.standing)
            AddLabel(scroll, C(COLOR.dim, (outlook and (outlook .. "  ") or "") .. note), GameFontHighlightSmall)
            local rows = MineRows(states, c.diplomat or 0)
            SortRows(rows, sortKey, desc)
            AddTable(scroll, "mine:" .. o.key, MINE_COLUMNS, rows, sortKey, desc, sortBy)
            AddLabel(scroll, " ", GameFontHighlightSmall)
        end
    end
end

---------------------------------------------------------------------------
-- Tab: All Writs
---------------------------------------------------------------------------

local ALL_COLUMNS = {
    { key = "name", title = "Name", width = 0.26 },
    { key = "prof", title = "Profession", width = 0.15 },
    { key = "level", title = "Level", width = 0.12 },
    { key = "status", title = "Status", width = 0.15 },
    { key = "rep", title = "Rep/|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", width = 0.10,
      sortName = "rep per gold", descFirst = true },
    { key = "zone", title = "Turn-in zone", width = 0.21 },
}
local ALL_PAGE_SIZE = 20

function UI:BuildAll(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    -- Show another page, scrolled back to the top.
    local function GoToPage(n)
        self.allPage = n
        self.scrollStatus.all = nil
        self:Redraw()
    end
    local function Refilter() GoToPage(1) end

    local prof = AceGUI:Create("Dropdown")
    prof:SetLabel("Profession")
    prof:SetWidth(160)
    local profList, profOrder = { ALL = "All" }, { "ALL" }
    for _, p in ipairs(ns.PROFESSIONS) do profList[p] = ns.PROFESSION_NAMES[p]; table.insert(profOrder, p) end
    prof:SetList(profList, profOrder)
    prof:SetValue(db.professionFilter)
    prof:SetCallback("OnValueChanged", function(_, _, v) db.professionFilter = v; Refilter() end)
    container:AddChild(prof)

    local tier = AceGUI:Create("Dropdown")
    tier:SetLabel("Level")
    tier:SetWidth(140)
    local tierList, tierOrder = { ALL = "All" }, { "ALL" }
    for _, t in ipairs(ns.TIERS) do tierList[t] = ns.TIER_NAMES[t]; table.insert(tierOrder, t) end
    tier:SetList(tierList, tierOrder)
    tier:SetValue(db.tierFilter)
    tier:SetCallback("OnValueChanged", function(_, _, v) db.tierFilter = v; Refilter() end)
    container:AddChild(tier)

    local hide = AceGUI:Create("CheckBox")
    hide:SetLabel("Hide done today")
    hide:SetWidth(160)
    hide:SetValue(db.hideCompleted)
    hide:SetCallback("OnValueChanged", function(_, _, v) db.hideCompleted = v; Refilter() end)
    container:AddChild(hide)

    local sortKey, desc, sortBy = TableSort(db, "all", ALL_COLUMNS, "name", Refilter)
    local rows = {}
    for _, s in pairs(CH.Tracker:GetAllStates()) do
        local w = s.writ
        local profOK = db.professionFilter == "ALL" or tContains(w.profs, db.professionFilter)
        local tierOK = db.tierFilter == "ALL" or w.tier == db.tierFilter
        if profOK and tierOK and not (db.hideCompleted and s.status == STATUS.DONE) then
            local profNames = {}
            for _, p in ipairs(w.profs) do table.insert(profNames, ns.PROFESSION_NAMES[p] or p) end
            table.sort(profNames)
            local profText = table.concat(profNames, ", ")
            local known = s.turnIn and s.zoneName ~= "Unknown"
            -- Same estimate as the writ tooltip (with the writ's own price if that's turned on).
            local est = ns.Prices.IsAvailable() and ns.Prices.GetWritEstimate(s.id, db.includeWritPrice)
            local repPerGold = est and est.repPerGold
            local row = WritRow(s, {
                WritName(s),
                profText,
                C(COLOR.dim, ns.TIER_NAMES[w.tier]),
                ShortStatus(s),
                repPerGold and C(COLOR.ready, ns.FormatRepPerGold(repPerGold)) or C(COLOR.dim, "-"),
                known and s.zoneName or C(COLOR.dim, "unknown yet"),
            }, nil, true)
            local name = (ItemName(w.item, w.name) or ""):lower()
            row.sort = {
                name = name,
                prof = profText:lower(),
                level = ns.TIER_NAMES[w.tier],
                status = STATUS_ORDER[s.status],
                rep = repPerGold,
                zone = ZoneSortValue(s),
                tie = name,
            }
            table.insert(rows, row)
        end
    end
    SortRows(rows, sortKey, desc)

    -- Page buttons.
    local pages = math.max(1, math.ceil(#rows / ALL_PAGE_SIZE))
    local page = math.min(math.max(self.allPage or 1, 1), pages)
    self.allPage = page
    local rowPage = AceGUI:Create("SimpleGroup")
    rowPage:SetFullWidth(true)
    rowPage:SetLayout("Flow")
    container:AddChild(rowPage)
    local prev = AddButton(rowPage, "< Prev", 80, function() GoToPage(page - 1) end)
    prev:SetRelativeWidth(0.2)
    prev:SetDisabled(page <= 1)
    local info = AceGUI:Create("Label")
    info:SetRelativeWidth(0.58)
    info:SetJustifyH("CENTER")
    info:SetFontObject(GameFontHighlight)
    info:SetText(string.format("Page %d of %d  (%d writ%s)", page, pages, #rows, #rows == 1 and "" or "s"))
    rowPage:AddChild(info)
    local nextB = AddButton(rowPage, "Next >", 80, function() GoToPage(page + 1) end)
    nextB:SetRelativeWidth(0.2)
    nextB:SetDisabled(page >= pages)

    local box = AceGUI:Create("InlineGroup")
    box:SetFullWidth(true)
    box:SetFullHeight(true)
    box:SetLayout("Fill")
    container:AddChild(box)
    local scroll = CreateScroll(box, "all")
    if #rows == 0 then
        AddLabel(scroll, "No writs match these filters.", GameFontHighlight)
        return
    end
    local pageRows = {}
    for i = (page - 1) * ALL_PAGE_SIZE + 1, math.min(page * ALL_PAGE_SIZE, #rows) do
        table.insert(pageRows, rows[i])
    end
    AddTable(scroll, "all", ALL_COLUMNS, pageRows, sortKey, desc, sortBy)
end

---------------------------------------------------------------------------
-- Tab: Route
---------------------------------------------------------------------------

local function AddWritLines(parent, writs)
    for _, id in ipairs(writs) do
        local s = CH.Tracker:GetState(id)
        local text = "      " .. ItemName(s.writ.item, s.writ.name)
        if s.status == STATUS.INBAGS then
            text = text .. "  " .. C(COLOR.inbags, "(start the writ first)")
        elseif s.status == STATUS.DONE then
            text = text .. "  " .. C(COLOR.done, "delivered")
        end
        AddLabel(parent, text, GameFontHighlightSmall)
    end
end

local function AddStateList(parent, title, list, note)
    if #list == 0 then return end
    AddHeading(parent, title)
    if note then AddLabel(parent, C(COLOR.dim, note), GameFontHighlightSmall) end
    table.sort(list, function(a, b) return SortName(a.writ.name, b.writ.name) end)
    for _, s in ipairs(list) do
        AddRow(parent, s, s.zoneName ~= "Unknown" and s.zoneName or nil)
    end
end

function UI:BuildRoute(container)
    container:SetLayout("Flow")
    local Route = CH.Route

    AddButton(container, Route:IsActive() and "Re-plan route" or "Plan route", 150, function() Route:Plan() end)
    if Route:IsActive() then
        AddButton(container, "Clear route", 120, function() Route:Clear() end)
    end
    local hint = AceGUI:Create("Label")
    hint:SetWidth(240)
    hint:SetFontObject(GameFontHighlightSmall)
    hint:SetText(CH.Nav:HasTomTom() and C(COLOR.dim, "Waypoints via TomTom.")
        or C(COLOR.inbags, "TomTom not found: using the map pin (one stop at a time)."))
    container:AddChild(hint)

    local scroll = CreateScroll(container, "route")
    local route = Route.route

    if not route then
        AddLabel(scroll, "Plan a route to visit every turn-in for the writs you can deliver right now: writs " ..
            "that are ready, plus writs in your bags that you have the item for (start them before you arrive).\n\n" ..
            "Stops are ordered by the quickest way round from where you are, using the flight paths you know, " ..
            "boats and zeppelins, across both continents, your mage teleports and your Hearthstone when it " ..
            "saves time.\n\n" ..
            "The arrow moves on to the next stop each time you deliver.", GameFontHighlight)
        if CH.FlightPaths:Count() == 0 then
            AddLabel(scroll, "\n" .. C(COLOR.inbags, "Open a flight master's map once on each continent, so the " ..
                "addon learns which flight paths you know."), GameFontHighlight)
        end
        if CH.db.profile.useHearth and not CH.Hearth:GetSpot() then
            AddLabel(scroll, "\n" .. C(COLOR.inbags, "Use your Hearthstone once (or set it at an innkeeper), so the " ..
                "addon learns where it takes you."), GameFontHighlight)
        end
        return
    end

    if #route.stops == 0 then
        AddLabel(scroll, "Nothing to deliver right now.", GameFontHighlight)
    else
        -- Reputation for the whole route, and what's left of it.
        local r = ns.Rep.OfRoute(route)
        local text = string.format("This route: %d writ%s, %s reputation", r.count, r.count == 1 and "" or "s",
            C(COLOR.ready, ns.Rep.Number(r.rep)))
        if r.left.count < r.count then
            text = text .. string.format(". %d delivered, %s still to go", r.count - r.left.count,
                C(COLOR.ready, ns.Rep.Number(r.left.rep)))
        end
        AddLabel(scroll, text .. ".", GameFontHighlight)
        local outlook = ns.Rep.Outlook(r.left.rep)
        if outlook then AddLabel(scroll, C(COLOR.dim, outlook), GameFontHighlightSmall) end
    end

    local current = Route:GetCurrent()
    local n = 0
    for _, leg in ipairs(route.legs) do
        local pending = 0
        for _, stop in ipairs(leg.stops) do if not stop.done then pending = pending + 1 end end
        AddHeading(scroll, string.format("%s: %d stop%s, about %s", ns.ContinentName(leg.contID),
            #leg.stops, #leg.stops == 1 and "" or "s", FormatMinutes(leg.length)))
        for _, stop in ipairs(leg.stops) do
            n = n + 1
            local isCurrent = stop == current
            local label = string.format("%d. %s - %s (%.1f, %.1f)", n, stop.name or "?", stop.zoneName or "?", stop.x, stop.y)
            if stop.done then
                label = C(COLOR.done, label .. "  delivered")
            elseif isCurrent then
                label = C(COLOR.ready, label .. "  <- current")
            end
            local row = AceGUI:Create("InteractiveLabel")
            row:SetFullWidth(true)
            row:SetFontObject(isCurrent and GameFontNormal or GameFontHighlight)
            row:SetText(label)
            row:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                GameTooltip:AddLine(stop.name or "?")
                GameTooltip:AddLine(string.format("%s (%.1f, %.1f)", stop.zoneName or "?", stop.x, stop.y), 1, 1, 1)
                if not stop.done then
                    GameTooltip:AddLine("Click to point the arrow here.", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            row:SetCallback("OnClick", function()
                if not stop.done then Route:SetCurrent(stop.index, nil, true) end
            end)
            -- How to get here, when it's more than riding over (steps behind you greyed out).
            if not stop.done then
                for k, e in ipairs(stop.via or {}) do
                    local passed = isCurrent and k < (Route.viaIndex or 1)
                    AddLabel(scroll, "      " .. C(passed and COLOR.done or COLOR.inbags, e.text), GameFontHighlightSmall)
                end
            end
            scroll:AddChild(row)
            AddWritLines(scroll, stop.writs)
        end
    end

    AddStateList(scroll, "No location yet", route.unroutable,
        "These turn-ins aren't in the addon's data yet. Accepted writs show their spot on your world map.")
    AddStateList(scroll, "Not friendly to your faction", route.excluded,
        "These turn-in NPCs won't deal with your faction.")
end

---------------------------------------------------------------------------
-- Tab: Buy Writs
---------------------------------------------------------------------------

local BUY_PAGE_SIZE = 20

local function Ago(seconds)
    seconds = math.max(0, seconds)
    if seconds >= 2 * 86400 then return string.format("%d days ago", math.floor(seconds / 86400)) end
    if seconds < 60 then return "just now" end
    return ns.FormatDuration(seconds) .. " ago"
end

-- One line on where prices come from (and how fresh they are), or why there are none.
local function PriceSourceText()
    local P = ns.Prices
    local key = P.ActiveSource()
    if key == "AUCTIONATOR" then
        local t = P.LastFullScan()
        return C(COLOR.dim, "Prices from Auctionator. " ..
            (t and ("Last full Auction House scan: " .. Ago(time() - t) .. ".") or "No full Auction House scan yet."))
    elseif key == "TSM" then
        local s = CH.db.profile.tsmPrice
        if not s or s:match("^%s*$") then s = P.DEFAULT_TSM_PRICE end
        return C(COLOR.dim, "Prices from TradeSkillMaster (" .. s .. ").")
    end
    local pref = CH.db.profile.priceSource
    if pref and pref ~= "AUTO" then
        return C(COLOR.inbags, P.SOURCE_NAMES[pref] .. " isn't installed, so there are no prices.")
    end
    return C(COLOR.inbags, "No price addon found: install Auctionator or TradeSkillMaster for prices.")
end

-- Filter keys for a writ's turn-in: zone name, and NPC (name + zone, since names can repeat).
local function BuyKeys(writID)
    local s = CH.Tracker:GetState(writID)
    local t = s and s.turnIn
    local zone = (s and s.zoneName and s.zoneName ~= "") and s.zoneName or "Unknown"
    local name = t and t.name or "Unknown NPC"
    return { zone = zone, npc = name .. ";" .. zone, npcLabel = string.format("%s (%s)", name, zone) }
end

-- Where you already have a writ: { log = bool, bags = n, bank = n, alts = { holders } }.
local function OwnedWrit(writID)
    local s = CH.Tracker:GetState(writID)
    return {
        log = s.inLog,
        bags = s.writsInBags or 0,
        bank = math.max(0, (s.writsTotal or 0) - (s.writsInBags or 0), CH.Alts:InBank(writID, "writs")),
        alts = CH.Alts:Holders(writID, "writs"),
    }
end

-- The "Have" column: where you already have the writ, e.g. "Bank x2, Thrallbank", or "".
-- Character names are written out in full (in their class colour).
local function OwnedText(o)
    local parts = {}
    if o.log then table.insert(parts, "Quest log") end
    if o.bags > 0 then table.insert(parts, "Bags" .. (o.bags > 1 and (" x" .. o.bags) or "")) end
    if o.bank > 0 then table.insert(parts, "Bank" .. (o.bank > 1 and (" x" .. o.bank) or "")) end
    for _, h in ipairs(o.alts) do
        table.insert(parts, CH.Alts.ColoredName(h, true) .. (h.count > 1 and (" x" .. h.count) or ""))
    end
    return table.concat(parts, ", ")
end

local function ShowBuyTooltip(widget, e)
    local w = ns.Writs[e.writID]
    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
    CH.Tooltips.suppress = true
    GameTooltip:SetItemByID(e.writID)
    CH.Tooltips.suppress = false
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Writ", ns.FormatMoneyIcons(e.writPrice), 1, 0.82, 0, 1, 1, 1)
    local k = BuyKeys(e.writID)
    GameTooltip:AddDoubleLine("Deliver to", k.npcLabel, 1, 0.82, 0, 1, 1, 1)
    local itemLabel = ItemName(w.item, w.name) .. " x" .. w.count
    GameTooltip:AddDoubleLine(itemLabel, e.itemCost and ns.FormatMoneyIcons(e.itemCost) or "no price",
        1, 0.82, 0, 1, 1, 1)
    if e.cost then
        GameTooltip:AddDoubleLine("Total", ns.FormatMoneyIcons(e.cost), 1, 0.82, 0, 1, 1, 1)
        if e.cashback > 0 then
            GameTooltip:AddDoubleLine("Coin pouch back", "-" .. ns.FormatMoneyIcons(e.cashback), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("After the pouch", e.net > 0 and ns.FormatMoneyIcons(e.net) or
                ("profit " .. ns.FormatMoneyIcons(-e.net)), 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Rep per gold", string.format("%s (%d rep)", ns.FormatRepPerGold(e.repPerGold), e.rep),
            1, 0.82, 0, 1, 1, 1)
    end
    if e.age and e.age > ns.Prices.STALE_DAYS then
        GameTooltip:AddLine(string.format("Oldest price is %d days old.", e.age), 1, 0.63, 0.13)
    end
    local o = OwnedWrit(e.writID)
    if o.log or o.bags > 0 or o.bank > 0 or #o.alts > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You already have this writ", 1, 0.63, 0.13)
        if o.log then GameTooltip:AddLine("In your quest log", 1, 1, 1) end
        if o.bags > 0 then GameTooltip:AddDoubleLine("Bags", "x" .. o.bags, 1, 1, 1, 1, 1, 1) end
        if o.bank > 0 then GameTooltip:AddDoubleLine("Bank", "x" .. o.bank, 1, 1, 1, 1, 1, 1) end
        for _, h in ipairs(o.alts) do
            GameTooltip:AddDoubleLine(CH.Alts.ColoredName(h, true), "x" .. h.count, 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link the writ (e.g. into the Auction House search).", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Buy Writs table columns. Rep per gold starts with the best, Have with the writs you have.
local BUY_COLUMNS = {
    { key = "name", title = "Name", width = 0.31 },
    { key = "level", title = "Level", width = 0.14 },
    { key = "price", title = "Price", width = 0.20 },
    { key = "rep", title = "Rep/|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", width = 0.11,
      sortName = "rep per gold", descFirst = true },
    { key = "have", title = "Have", width = 0.23, descFirst = true },
}

-- The text of each cell in a writ's row.
local function BuyCells(e, done)
    local w = ns.Writs[e.writID]
    -- The writ is named after the item it asks for; show the count when it's more than one.
    local name = ItemName(w.item, w.name)
    if w.count > 1 then name = name .. " " .. C(COLOR.ready, "x" .. w.count) end
    if done then name = name .. "  " .. C(COLOR.done, "done today") end
    local price, repPerGold
    if e.cost then
        price = ns.FormatMoneyIcons(e.cost)
        repPerGold = C(COLOR.ready, ns.FormatRepPerGold(e.repPerGold))
    else
        price = ns.FormatMoneyIcons(e.writPrice) .. " + ?"
        repPerGold = C(COLOR.inbags, "no price")
    end
    return { name, C(COLOR.dim, ns.TIER_NAMES[w.tier]), price, repPerGold, OwnedText(OwnedWrit(e.writID)) }
end

-- The line above the Buy Writs table on reaching your next standing, as an InteractiveLabel:
-- click it to show only the writs it picks (planSet), or all of them again.
local function AddPlanLine(parent, plan, planSet, onToggle)
    local db = CH.db.profile
    local N = ns.Rep.Number
    local after = plan.have > 0 and string.format(" after the %s from writs you have", N(plan.have)) or ""
    local text
    if plan.need <= 0 then
        text = C(COLOR.ready, string.format("The writs you have already get you to %s (%s of the %s reputation needed).",
            plan.nextName, N(plan.have), N(plan.toGo)))
    elseif plan.writs then
        local price = ns.FormatMoneyIcons(plan.cost)
        if plan.net ~= plan.cost then
            price = price .. " (" .. (plan.net > 0 and ns.FormatMoneyIcons(plan.net) or "nothing") ..
                " after the coin pouches)"
        end
        text = string.format("%s is %s reputation away%s. Cheapest way there: %s for %s.", plan.nextName,
            C(COLOR.ready, N(plan.need)), after,
            C(COLOR.ready, string.format("%d writ%s", #plan.writs, #plan.writs == 1 and "" or "s")), price)
        text = text .. C(COLOR.dim, planSet and "  Click to show every writ again." or "  Click to show only these.")
    else
        text = string.format("%s is %s reputation away%s: more than all %d writs for sale give today.",
            plan.nextName, C(COLOR.ready, N(plan.need)), after, plan.forSale)
    end
    local l = AceGUI:Create("InteractiveLabel")
    l:SetFullWidth(true)
    l:SetFontObject(GameFontHighlight)
    l:SetText(text)
    if plan.writs and plan.need > 0 then
        l:SetHighlight(HIGHLIGHT)
        l:SetCallback("OnClick", onToggle)
        l:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Cheapest way to " .. plan.nextName, 1, 1, 1)
            for _, e in ipairs(plan.writs) do
                local w = ns.Writs[e.writID]
                GameTooltip:AddDoubleLine(ItemName(w.item, w.name) .. "  " .. C(COLOR.dim, ns.TIER_NAMES[w.tier]),
                    ns.FormatMoneyIcons(e.cost), 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:AddDoubleLine("Total", ns.FormatMoneyIcons(plan.cost), 1, 0.82, 0, 1, 1, 1)
            if plan.net ~= plan.cost then
                GameTooltip:AddDoubleLine("Coin pouches back", "-" .. ns.FormatMoneyIcons(plan.cost - plan.net),
                    1, 0.82, 0, 1, 1, 1)
            end
            GameTooltip:AddDoubleLine("Reputation", N(plan.rep), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Writs you have or have done today aren't counted again: each one can be " ..
                "turned in once a day. Prices are the writ plus the items it asks for" ..
                (ns.Prices.CashbackOn() and ", and the cheapest way counts the coin pouch you get back. " or ". ") ..
                RepBonusNote(),
                0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        l:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    parent:AddChild(l)
end

function UI:BuildBuy(container)
    local db = CH.db.profile
    container:SetLayout("Flow")

    if not ns.Prices.IsAvailable() then
        local scroll = CreateScroll(container, "buy")
        AddLabel(scroll, "This tab needs Auction House prices from Auctionator or TradeSkillMaster.\n\n" ..
            "Install one of them and scan the Auction House to see which writs are cheapest to buy. " ..
            "You can choose the price source in the Settings tab.", GameFontHighlight)
        AddLabel(scroll, "\n" .. PriceSourceText(), GameFontHighlightSmall)
        return
    end

    -- Show another page, scrolled back to the top.
    local function GoToPage(n)
        self.buyPage = n
        self.scrollStatus.buy = nil
        self:Redraw()
    end
    local function Refilter() GoToPage(1) end

    -- Controls in three fixed rows, each sharing the window's width, so they keep their
    -- place at any window size:
    --   zone, NPC / the two checkboxes / page buttons
    local function Row()
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        container:AddChild(row)
        return row
    end
    local HALF = 0.49 -- a little under half, so rounding never wraps the second widget
    local rowPlace, rowHide, rowPage = Row(), Row(), Row()

    -- Sort: the column chosen by clicking its title, and a direction.
    local sortKey, sortDesc, sortBy = TableSort(db, "buy", BUY_COLUMNS, "price", Refilter)



    local function HideBox(label, key, tip)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetRelativeWidth(HALF)
        cb:SetValue(db[key])
        cb:SetCallback("OnValueChanged", function(_, _, v) db[key] = v; Refilter() end)
        cb:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        rowHide:AddChild(cb)
    end
    HideBox("Hide done today", "buyHideDone", "Hide writs you've already turned in since the daily reset.")
    HideBox("Hide writs I have", "buyHideOwned", "Hide writs that are in your quest log or bags. Writs in your bank or on your other characters stay in the list, marked with where they are.")

    -- Zone and turn-in NPC of every writ; the NPC list only shows NPCs in the chosen zone.
    local zoneList, zoneOrder, npcList, npcOrder = { ALL = "All zones" }, {}, { ALL = "All NPCs" }, {}
    local keyOf = {}
    for writID in pairs(ns.Writs) do
        local k = BuyKeys(writID)
        keyOf[writID] = k
        if not zoneList[k.zone] then zoneList[k.zone] = k.zone; table.insert(zoneOrder, k.zone) end
        if (db.buyZone == "ALL" or db.buyZone == k.zone) and not npcList[k.npc] then
            npcList[k.npc] = k.npcLabel
            table.insert(npcOrder, k.npc)
        end
    end
    -- Saved choices that no longer exist (or don't fit the zone) fall back to "All".
    if not zoneList[db.buyZone] then db.buyZone = "ALL" end
    if not npcList[db.buyNpc] then db.buyNpc = "ALL" end
    table.sort(zoneOrder, SortName)
    table.sort(npcOrder, function(a, b) return SortName(npcList[a], npcList[b]) end)
    table.insert(zoneOrder, 1, "ALL")
    table.insert(npcOrder, 1, "ALL")

    local zone = AceGUI:Create("Dropdown")
    zone:SetLabel("Zone")
    zone:SetRelativeWidth(HALF)
    zone:SetList(zoneList, zoneOrder)
    zone:SetValue(db.buyZone)
    zone:SetCallback("OnValueChanged", function(_, _, v) db.buyZone = v; db.buyNpc = "ALL"; Refilter() end)
    rowPlace:AddChild(zone)

    local npc = AceGUI:Create("Dropdown")
    npc:SetLabel("Turn-in NPC")
    npc:SetRelativeWidth(HALF)
    npc:SetList(npcList, npcOrder)
    npc:SetValue(db.buyNpc)
    npc:SetCallback("OnValueChanged", function(_, _, v) db.buyNpc = v; Refilter() end)
    rowPlace:AddChild(npc)

    -- Values for the columns Prices.GetBuyList doesn't know how to sort.
    local function SortValue(e)
        local w = ns.Writs[e.writID]
        if db.buySort == "name" then return (ItemName(w.item, w.name) or ""):lower() end
        if db.buySort == "level" then return ns.TIER_NAMES[w.tier] end
        if db.buySort == "have" then return OwnedText(OwnedWrit(e.writID)) ~= "" and 1 or 0 end
    end

    -- The cheapest writs to the next standing; "show only these" overrides the other filters.
    local plan = ns.Rep.NextStandingPlan()
    local planSet
    if db.buyPlanOnly and plan and plan.writs and #plan.writs > 0 and plan.need > 0 then
        planSet = {}
        for _, e in ipairs(plan.writs) do planSet[e.writID] = true end
    end

    local list = ns.Prices.GetBuyList(db.buySort, function(writID)
        if planSet then return planSet[writID] or false end
        local k = keyOf[writID]
        if db.buyZone ~= "ALL" and k.zone ~= db.buyZone then return false end
        if db.buyNpc ~= "ALL" and k.npc ~= db.buyNpc then return false end
        local s = CH.Tracker:GetState(writID)
        if db.buyHideOwned and (s.inLog or (s.writsInBags or 0) > 0) then return false end
        return not (db.buyHideDone and s.status == STATUS.DONE)
    end, sortDesc, SortValue)

    local pages = math.max(1, math.ceil(#list / BUY_PAGE_SIZE))
    local page = math.min(math.max(self.buyPage or 1, 1), pages)
    self.buyPage = page

    local prev = AddButton(rowPage, "< Prev", 80, function() GoToPage(page - 1) end)
    prev:SetRelativeWidth(0.2)
    prev:SetDisabled(page <= 1)
    local info = AceGUI:Create("Label")
    info:SetRelativeWidth(0.58)
    info:SetJustifyH("CENTER")
    info:SetFontObject(GameFontHighlight)
    info:SetText(string.format("Page %d of %d  (%d writ%s)", page, pages, #list, #list == 1 and "" or "s"))
    rowPage:AddChild(info)
    local nextB = AddButton(rowPage, "Next >", 80, function() GoToPage(page + 1) end)
    nextB:SetRelativeWidth(0.2)
    nextB:SetDisabled(page >= pages)

    -- The list sits in a bordered box.
    local box = AceGUI:Create("InlineGroup")
    box:SetFullWidth(true)
    box:SetFullHeight(true)
    box:SetLayout("Fill")
    container:AddChild(box)
    local scroll = CreateScroll(box, "buy")
    if #list == 0 then
        AddLabel(scroll, "No writs with an Auction House price.\n\n" ..
            "Writs only show up here once your price addon has seen them for sale.", GameFontHighlight)
        AddLabel(scroll, "\n" .. PriceSourceText(), GameFontHighlightSmall)
        return
    end

    if plan then
        AddPlanLine(scroll, plan, planSet, function()
            db.buyPlanOnly = not planSet
            Refilter()
        end)
    end
    AddLabel(scroll, PriceSourceText() .. C(COLOR.dim, "  Price = the writ plus the items it asks for."),
        GameFontHighlightSmall)
    local rows = {}
    local first = (page - 1) * BUY_PAGE_SIZE + 1
    for i = first, math.min(first + BUY_PAGE_SIZE - 1, #list) do
        local e = list[i]
        local done = not db.buyHideDone and CH.Tracker:GetState(e.writID).status == STATUS.DONE
        table.insert(rows, {
            cells = BuyCells(e, done),
            onEnter = function(frame) ShowBuyTooltip({ frame = frame }, e) end,
            onClick = function()
                if IsModifiedClick("CHATLINK") then
                    local _, link = C_Item.GetItemInfo(e.writID)
                    if link then InsertLink(link) end
                end
            end,
        })
    end
    AddTable(scroll, "buy", BUY_COLUMNS, rows, sortKey, sortDesc, sortBy)
end

---------------------------------------------------------------------------
-- Tab: Settings
---------------------------------------------------------------------------

local function AddCheckBox(parent, label, description, value, onChange)
    local cb = AceGUI:Create("CheckBox")
    cb:SetFullWidth(true)
    cb:SetLabel(label)
    if description then cb:SetDescription(description) end
    cb:SetValue(value)
    cb:SetCallback("OnValueChanged", function(_, _, v) onChange(v) end)
    parent:AddChild(cb)
    return cb
end

function UI:BuildSettings(container)
    local db = CH.db.profile
    container:SetLayout("Fill")
    local scroll = CreateScroll(container, "settings")

    AddHeading(scroll, "Tooltips")
    local writPrice
    AddCheckBox(scroll, "Show writ info in item tooltips",
        "Today's status, the item needed and where to deliver it on writs, and which writs want it on crafted items.",
        db.tooltips, function(v)
            db.tooltips = v
            if writPrice then writPrice:SetDisabled(not v) end
        end)
    AddCheckBox(scroll, "Mark recipes used by writs",
        "A small icon on recipes at the trainer and in your profession window that craft an item a writ asks " ..
        "for. Hover it to see which writs.",
        db.markRecipes ~= false, function(v) db.markRecipes = v; CH.RecipeMarks:Refresh() end)

    AddHeading(scroll, "Price estimates")
    local P = ns.Prices
    local source = AceGUI:Create("Dropdown")
    source:SetLabel("Price source")
    source:SetWidth(220)
    local function Label(key)
        return P.SOURCE_NAMES[key] .. (P.IsInstalled(key) and "" or " (not installed)")
    end
    source:SetList({ AUTO = "Automatic (whichever is installed)", AUCTIONATOR = Label("AUCTIONATOR"), TSM = Label("TSM") },
        { "AUTO", "AUCTIONATOR", "TSM" })
    source:SetValue(db.priceSource or "AUTO")
    source:SetCallback("OnValueChanged", function(_, _, v) db.priceSource = v; self:Redraw() end)
    scroll:AddChild(source)

    local tsm = AceGUI:Create("EditBox")
    tsm:SetLabel("TSM price (custom price string)")
    tsm:SetWidth(320)
    tsm:SetText(db.tsmPrice or "")
    tsm:SetDisabled(not P.IsInstalled("TSM"))
    tsm:SetCallback("OnEnterPressed", function(widget, _, text)
        text = strtrim(text or "")
        local valid, err = P.CheckTSMPrice(text ~= "" and text or P.DEFAULT_TSM_PRICE)
        if not valid then
            CH:Print("TSM can't use that price: " .. tostring(err or "invalid custom price"))
            widget:SetText(db.tsmPrice or "")
            return
        end
        db.tsmPrice = text
        self:Redraw()
    end)
    scroll:AddChild(tsm)
    AddLabel(scroll, C(COLOR.dim, "Empty uses " .. P.DEFAULT_TSM_PRICE .. ". Press Enter to save."), GameFontHighlightSmall)
    AddLabel(scroll, PriceSourceText(), GameFontHighlightSmall)

    writPrice = AddCheckBox(scroll, "Include the writ's own price",
        "Add the Auction House price of the writ itself to the estimated price and rep per gold, " ..
        "for when you buy writs instead of looting them.",
        db.includeWritPrice, function(v) db.includeWritPrice = v end)
    writPrice:SetDisabled(not db.tooltips)

    AddCheckBox(scroll, "Count the coin pouch as money back",
        "Turning in a writ gives a Coin Pouch. Take its average gold off the cost for rep per gold " ..
        "and the cheapest way to your next standing.",
        db.cashback ~= false, function(v) db.cashback = v; self:Redraw() end)
    local pouchParts = {}
    for _, tier in ipairs(ns.TIERS) do
        local st = P.PouchStats(tier)
        table.insert(pouchParts, ns.TIER_NAMES[tier] .. " " .. ns.FormatMoneyIcons(st.average))
    end
    local opened = 0
    for _, tier in ipairs(ns.TIERS) do opened = opened + P.PouchStats(tier).opened end
    AddLabel(scroll, C(COLOR.dim, "Average pouch: " .. table.concat(pouchParts, ", ") .. ". From Wowhead" ..
        (opened > 0 and string.format(" and the %d pouch%s you've opened", opened, opened == 1 and "" or "es") or
        ", until you open some") .. ". /writs pouches for details."), GameFontHighlightSmall)

    AddHeading(scroll, "Reputation")
    local dip = AceGUI:Create("Dropdown")
    dip:SetLabel("Diplomat rank (this character)")
    dip:SetWidth(220)
    local dipList, dipOrder = {}, {}
    for r = 0, ns.DIPLOMAT_RANKS do
        dipList[r] = r == 0 and "None" or string.format("Rank %d (+%d%%)", r, math.floor(r * ns.DIPLOMAT_STEP * 100 + 0.5))
        table.insert(dipOrder, r)
    end
    dip:SetList(dipList, dipOrder)
    dip:SetValue(ns.DiplomatRank())
    dip:SetCallback("OnValueChanged", function(_, _, v) CH.db.char.diplomat = v; self:Redraw() end)
    scroll:AddChild(dip)
    AddLabel(scroll, C(COLOR.dim, "Diplomat is a Legacy perk (Resourcefulness): +2% reputation per rank. " ..
        "Set the rank you've chosen on this character, and reputation and rep per gold include it."),
        GameFontHighlightSmall)

    AddHeading(scroll, "Route planning")
    AddCheckBox(scroll, "Use your Hearthstone",
        "When it's off cooldown and saves time, the route uses your Hearthstone once.",
        db.useHearth, function(v) db.useHearth = v end)
    local spot = CH.Hearth:GetSpot()
    AddLabel(scroll, spot and C(COLOR.dim, "Hearthstone: " .. spot.name .. " (location learned).")
        or C(COLOR.inbags, "Hearthstone location not learned yet: use your Hearthstone once, or set it at an innkeeper."),
        GameFontHighlightSmall)
    -- Mage teleports: only shown to characters that know one.
    local teleports = CH.Teleports:GetKnown()
    if #teleports > 0 then
        AddCheckBox(scroll, "Use mage teleports",
            "The route teleports to a city whenever that's quicker. Each teleport uses a Rune of Teleportation.",
            db.useTeleports, function(v) db.useTeleports = v end)
        local names = {}
        for _, t in ipairs(teleports) do table.insert(names, t.name) end
        local runes = CH.Teleports:Runes()
        local runeText = runes == math.huge and ""
            or string.format(" (%d Rune%s of Teleportation)", runes, runes == 1 and "" or "s")
        AddLabel(scroll, runes > 0 and C(COLOR.dim, "Teleports: " .. table.concat(names, ", ") .. runeText .. ".")
            or C(COLOR.inbags, "No Rune of Teleportation in your bags: routes don't use your teleports."),
            GameFontHighlightSmall)
    end
    local fp = CH.FlightPaths:Count()
    AddLabel(scroll, fp > 0 and C(COLOR.dim, string.format("Flight paths known: %d.", fp))
        or C(COLOR.inbags, "No flight paths learned yet: open a flight master's map once on each continent."),
        GameFontHighlightSmall)

    AddHeading(scroll, "Route tracker")
    AddCheckBox(scroll, "Show the route tracker",
        "A small window with the next 5 steps of your route, shown while a route is active.",
        db.tracker.shown, function(v) CH.RouteTracker:SetShown(v) end)
    AddCheckBox(scroll, "Lock its position",
        "Stop the route tracker from being dragged around.",
        db.tracker.locked, function(v) CH.RouteTracker:SetLocked(v) end)

    AddHeading(scroll, "Minimap")
    AddCheckBox(scroll, "Show the minimap button",
        "Left-click opens this window, right-click plans a route. Also available in the addon compartment.",
        not db.minimap.hide, function(v) CH.Minimap:SetShown(v) end)

    AddHeading(scroll, "Characters")
    AddLabel(scroll, C(COLOR.dim, "Writs and writ items in your bank and on these characters are shown in tooltips, " ..
        "the Shopping tab and Buy Writs. Log in on a character once to add it, and open its bank once to include " ..
        "the bank. Only characters on your realm and faction count, since they can mail you what they hold."),
        GameFontHighlightSmall)
    for _, c in ipairs(CH.Alts:List()) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        local label = AceGUI:Create("Label")
        label:SetRelativeWidth(c.me and 0.98 or 0.78)
        label:SetFontObject(GameFontHighlight)
        local seen = c.me and C(COLOR.ready, "this character")
            or (c.updated and GetServerTime and ("updated " .. Ago(GetServerTime() - c.updated)) or "")
        label:SetText(string.format("%s - %s (%s)   %s   %s", CH.Alts.ColoredName(c, true), c.realm or "?",
            c.faction or "?", C(COLOR.dim, string.format("%d writ%s", c.writs, c.writs == 1 and "" or "s")),
            C(COLOR.dim, seen)))
        row:AddChild(label)
        if not c.me then
            local forget = AceGUI:Create("Button")
            forget:SetText("Forget")
            forget:SetRelativeWidth(0.2)
            forget:SetCallback("OnClick", function()
                CH.Alts:Forget(c.key)
                UI:Redraw()
            end)
            row:AddChild(forget)
        end
        scroll:AddChild(row)
    end

    AddHeading(scroll, "Credits")
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("CraftmansHelper", "Version")) or "?"
    local lines = {
        "Craftman's Helper " .. version .. " by Emsworth, released under the GPL-3.0.",
        " ",
        C(COLOR.ready, "Glyalith") .. " - boat, zeppelin, skycutter and tram connections and measured flight times, " ..
            "collected for EllesmereUI Forever Essentials and used with permission.",
        C(COLOR.ready, "Questie / QuestieDB") .. " - turn-in NPCs, flight masters and zeppelin and ship masters (GPL-3.0).",
        C(COLOR.ready, "Wowhead") .. " - the list of Craftsman's Writs.",
        C(COLOR.ready, "Ace3, LibDataBroker and LibDBIcon") .. " - the libraries this addon is built on.",
        C(COLOR.ready, "You") .. " - for every turn-in location shared with /writs export.",
        " ",
        C(COLOR.dim, "Source, issues and suggestions: github.com/emsw0rth/craftmanshelper"),
    }
    for _, line in ipairs(lines) do AddLabel(scroll, line, GameFontHighlightSmall) end
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

-- Puts the tab's scroll position back after a rebuild (see CreateScroll).
function UI:RestoreScroll()
    local p = self.pendingScroll
    self.pendingScroll = nil
    if not (p and p.offset and p.offset ~= 0) then return end
    local status = p.widget.status
    if not status then return end
    status.offset, status.scrollvalue = p.offset, p.value
    p.widget:FixScroll()
end

function UI:Redraw()
    if not (self.frame and self.tabs) then return end
    self.tabs:SelectTab(self.currentTab or "mine")
end

-- Forgets the window's saved position and size, and centres it (when it's lost off-screen).
function UI:ResetPosition()
    CH.db.profile.window = CH.db.profile.window or {}
    local status = CH.db.profile.window
    status.top, status.left, status.width, status.height = nil, nil, 560, 520
    if self.frame then
        self.frame:ApplyStatus() -- without a saved position, AceGUI centres the frame
    else
        self:Show(self.currentTab or "mine")
    end
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
    tabs:SetTabs({
        { text = "My Writs", value = "mine" },
        { text = "Route", value = "route" },
        { text = "Shopping", value = "shopping" },
        { text = "Buy Writs", value = "buy" },
        { text = "All Writs", value = "all" },
        { text = "Settings", value = "settings" },
    })
    tabs:SetCallback("OnGroupSelected", function(container, _, group)
        self.currentTab = group
        self.pendingScroll = nil
        container:ReleaseChildren()
        if group == "all" then
            self:BuildAll(container)
        elseif group == "route" then
            self:BuildRoute(container)
        elseif group == "shopping" then
            self:BuildShopping(container)
        elseif group == "buy" then
            self:BuildBuy(container)
        elseif group == "settings" then
            self:BuildSettings(container)
        else
            self:BuildMine(container)
        end
        self:RestoreScroll()
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

---------------------------------------------------------------------------
-- Tab: Shopping
---------------------------------------------------------------------------

function UI:BuildShopping(container)
    container:SetLayout("Flow")
    local scroll = CreateScroll(container, "shopping")

    -- crafted item -> { need = total, writs = { states } } for writs you hold but can't deliver yet
    local byItem, items = {}, {}
    for _, s in pairs(CH.Tracker:GetAllStates()) do
        local held = s.status == STATUS.ACTIVE or s.status == STATUS.INBAGS
        if held and s.have < s.need then
            local entry = byItem[s.writ.item]
            if not entry then
                entry = { item = s.writ.item, name = s.writ.name, need = 0, have = s.have, writs = {} }
                byItem[s.writ.item] = entry
                table.insert(items, entry)
            end
            entry.need = entry.need + s.need
            table.insert(entry.writs, s)
        end
    end

    if #items == 0 then
        AddLabel(scroll, "Nothing to buy or craft: every writ you hold has its item.\n\n" ..
            "This list shows the crafted items still missing for writs in your quest log or bags.", GameFontHighlight)
        return
    end

    table.sort(items, function(a, b) return SortName(ItemName(a.item, a.name), ItemName(b.item, b.name)) end)
    AddHeading(scroll, string.format("%d item%s missing", #items, #items == 1 and "" or "s"))

    for _, e in ipairs(items) do
        local missing = math.max(0, e.need - e.have)
        local row = AceGUI:Create("InteractiveLabel")
        row:SetFullWidth(true)
        row:SetFontObject(GameFontHighlight)
        row:SetImage(ItemIcon(e.item))
        row:SetImageSize(18, 18)
        -- Copies in the bank or on alts that could cover what's missing.
        local spare = {}
        local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
        local bank = math.max(CH.Alts:InBank(e.item, "items"), (GetCount(e.item, true) or 0) - (GetCount(e.item) or 0))
        if bank > 0 then table.insert(spare, bank .. " in bank") end
        local alts = CH.Alts.Summary(CH.Alts:Holders(e.item, "items"))
        if alts ~= "" then table.insert(spare, "on " .. alts) end
        row:SetText(string.format("  %s   %s   %s%s", ItemName(e.item, e.name),
            C(COLOR.active, string.format("need %d more", missing)),
            C(COLOR.dim, string.format("(have %d of %d)", e.have, e.need)),
            #spare > 0 and ("   " .. C(COLOR.ready, table.concat(spare, ", "))) or ""))
        row:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
            CH.Tooltips.suppress = true
            GameTooltip:SetItemByID(e.item)
            CH.Tooltips.suppress = false
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click to link (e.g. into the Auction House search).", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        row:SetCallback("OnClick", function()
            if IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(e.item)
                if link then InsertLink(link) end
            end
        end)
        scroll:AddChild(row)
        for _, s in ipairs(e.writs) do
            local where = s.turnIn and s.turnIn.name and (s.turnIn.name .. ", " .. (s.zoneName or "?")) or (s.zoneName or "?")
            AddLabel(scroll, string.format("      %s writ x%d -> %s%s", ns.TIER_NAMES[s.writ.tier], s.need, where,
                s.status == STATUS.INBAGS and "  " .. C(COLOR.inbags, "(not started)") or ""), GameFontHighlightSmall)
        end
    end
end

---------------------------------------------------------------------------
-- Export window
---------------------------------------------------------------------------

function UI:ShowExport()
    local text, n, pouches = CH:BuildExport()
    if n + pouches == 0 then
        CH:Print("Nothing to share yet: no new turn-in locations or coin pouches recorded. Deliver or accept " ..
            "Expert/Artisan writs, or open the coin pouches they give, to record some.")
        return
    end
    if self.exportFrame then AceGUI:Release(self.exportFrame) end

    local f = AceGUI:Create("Frame")
    f:SetTitle("Craftman's Helper: share your data")
    f:SetLayout("List")
    f:SetWidth(520)
    f:SetHeight(360)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.exportFrame = nil
    end)
    local status = string.format("%d location%s recorded", n, n == 1 and "" or "s")
    if pouches > 0 then
        status = status .. string.format(", coin pouches of %d level%s", pouches, pouches == 1 and "" or "s")
    end
    f:SetStatusText(status)

    local intro = AceGUI:Create("Label")
    intro:SetFullWidth(true)
    intro:SetFontObject(GameFontHighlight)
    intro:SetText("Press Ctrl+C to copy, then paste it into a new issue at\n" ..
        C(COLOR.ready, "github.com/emsw0rth/craftmanshelper/issues") ..
        "\nso everyone gets this data in the next release. Thank you!")
    f:AddChild(intro)

    local box = AceGUI:Create("MultiLineEditBox")
    box:SetFullWidth(true)
    box:SetNumLines(12)
    box:SetLabel("")
    box:DisableButton(true)
    box:SetText(text)
    -- Keep the text intact if someone types into the box.
    box:SetCallback("OnTextChanged", function(widget) widget:SetText(text); widget:HighlightText() end)
    f:AddChild(box)
    box:SetFocus()
    box:HighlightText()

    self.exportFrame = f
end

function UI:OnEnable()
    self.scrollStatus = {}
    self.currentTab = "mine"
    self:RegisterMessage(ns.MSG_UPDATED, "Redraw")
    self:RegisterMessage(ns.MSG_NAMES, "Redraw")
    self:RegisterMessage(ns.MSG_ROUTE, "Redraw")
end
