-- Adds writ information to item tooltips:
--   on a Craftsman's Writ: today's status, the item it needs, where it goes
--   on a crafted item that a writ asks for: which writs, and their status
local _, ns = ...
local CH = ns.CH
local STATUS = ns.STATUS

local Tooltips = CH:NewModule("Tooltips")
CH.Tooltips = Tooltips

local HEADER_R, HEADER_G, HEADER_B = 0.83, 0.63, 0.09
local MAX_CRAFT_LINES = 4

-- crafted item ID -> { writ IDs }
local writsByItem = {}
for writID, w in pairs(ns.Writs) do
    writsByItem[w.item] = writsByItem[w.item] or {}
    table.insert(writsByItem[w.item], writID)
end

local STATUS_TEXT = {
    [STATUS.READY] = { "Ready to deliver", 0.13, 1, 0.13 },
    [STATUS.ACTIVE] = { "In your quest log", 1, 0.31, 0.31 },
    [STATUS.INBAGS] = { "Not started", 1, 0.63, 0.13 },
    [STATUS.AVAILABLE] = { "Available today", 1, 1, 1 },
    [STATUS.DONE] = { "Done today", 0.5, 0.5, 0.5 },
}

local function ItemName(id, fallback)
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or fallback
end

local function Where(s)
    local t = s.turnIn
    if not t then return "unknown yet" end
    local where = s.zoneName or "?"
    if t.x then where = string.format("%s (%.1f, %.1f)", where, t.x, t.y) end
    return (t.name and (t.name .. ", ") or "") .. where
end

local function AddWritInfo(tooltip, writID)
    local s = CH.Tracker:GetState(writID)
    local st = STATUS_TEXT[s.status]
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Craftman's Helper", ns.TIER_NAMES[s.writ.tier], HEADER_R, HEADER_G, HEADER_B, 0.6, 0.6, 0.6)
    tooltip:AddDoubleLine("Today", st[1], 1, 0.82, 0, st[2], st[3], st[4])
    local haveColor = s.have >= s.need and { 0.13, 1, 0.13 } or { 1, 0.31, 0.31 }
    tooltip:AddDoubleLine("Needs", string.format("%s  %d/%d", ItemName(s.writ.item, s.writ.name), math.min(s.have, s.need), s.need),
        1, 0.82, 0, haveColor[1], haveColor[2], haveColor[3])
    tooltip:AddDoubleLine("Deliver to", Where(s), 1, 0.82, 0, 1, 1, 1)

    -- AH estimate (Auctionator); left out when there's no price.
    local est = ns.Prices.GetWritEstimate(writID, CH.db.profile.includeWritPrice)
    if est then
        local price = ns.FormatMoneyIcons(est.cost)
        if est.writIncluded then
            price = price .. " (incl. writ)"
        elseif est.writMissing then
            price = price .. " (writ price unknown)"
        end
        if est.age and est.age > ns.Prices.STALE_DAYS then
            price = string.format("%s (%d days old)", price, est.age)
        end
        tooltip:AddDoubleLine("Estimated price", price, 1, 0.82, 0, 1, 1, 1)
        if est.repPerGold then
            tooltip:AddDoubleLine("Rep per gold", string.format("%.1f (%d rep)", est.repPerGold, est.rep),
                1, 0.82, 0, 1, 1, 1)
        end
    end
end

local function AddCraftInfo(tooltip, writIDs)
    tooltip:AddLine(" ")
    tooltip:AddLine("Craftman's Helper: wanted by a writ", HEADER_R, HEADER_G, HEADER_B)
    -- Writs you're working on first.
    local list = {}
    for _, id in ipairs(writIDs) do table.insert(list, CH.Tracker:GetState(id)) end
    local order = { ready = 1, active = 2, inbags = 3, available = 4, done = 5 }
    table.sort(list, function(a, b) return order[a.status] < order[b.status] end)
    for i, s in ipairs(list) do
        if i > MAX_CRAFT_LINES then break end
        local st = STATUS_TEXT[s.status]
        local label = string.format("%s writ (x%d)", ns.TIER_NAMES[s.writ.tier], s.need)
        tooltip:AddDoubleLine(label, st[1], 1, 1, 1, st[2], st[3], st[4])
        if s.status ~= STATUS.DONE and s.turnIn then
            tooltip:AddLine("    " .. Where(s), 0.6, 0.6, 0.6)
        end
    end
end

local function OnItemTooltip(tooltip, data)
    if Tooltips.suppress or not CH.db.profile.tooltips then return end
    local id = data and data.id
    if not id or (issecretvalue and issecretvalue(id)) then return end
    if ns.Writs[id] then
        AddWritInfo(tooltip, id)
    elseif writsByItem[id] then
        AddCraftInfo(tooltip, writsByItem[id])
    end
end

function Tooltips:OnEnable()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    end
end
