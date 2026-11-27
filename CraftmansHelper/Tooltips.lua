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
ns.WritsByItem = writsByItem

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

-- "Bank x2, Thrallbank, Other x3": copies in this character's bank and on alts
-- (same realm and faction), or nil when there are none.
local function Elsewhere(id, kind)
    local parts = {}
    local bank = CH.Alts:InBank(id, kind)
    if kind == "writs" then
        local s = CH.Tracker:GetState(id)
        bank = math.max(bank, (s.writsTotal or 0) - (s.writsInBags or 0))
    else
        local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
        bank = math.max(bank, (GetItemCount(id, true) or 0) - (GetItemCount(id) or 0))
    end
    if bank > 0 then table.insert(parts, bank > 1 and ("Bank x" .. bank) or "Bank") end
    local alts = CH.Alts.Summary(CH.Alts:Holders(id, kind), true)
    if alts ~= "" then table.insert(parts, alts) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
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
    local elsewhere = Elsewhere(writID, "writs")
    if elsewhere then tooltip:AddDoubleLine("Also have", elsewhere, 1, 0.82, 0, 1, 1, 1) end

    -- AH estimate (Auctionator or TSM); left out when there's no price.
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
    end
    local pouch = ns.Prices.PouchStats(s.writ.tier)
    if pouch then
        local back = "~" .. ns.FormatMoneyIcons(pouch.average)
        if pouch.opened > 0 then
            back = string.format("%s (%s - %s, %d opened)", back, ns.FormatMoney(pouch.min), ns.FormatMoney(pouch.max),
                pouch.opened)
        end
        tooltip:AddDoubleLine("Coin pouch", back, 1, 0.82, 0, 1, 1, 1)
    end
    if est and est.repPerGold then
        tooltip:AddDoubleLine("Rep per gold", string.format("%s (%d rep)", ns.FormatRepPerGold(est.repPerGold), est.rep),
            1, 0.82, 0, 1, 1, 1)
    end
end

-- fresh: the tooltip is ours alone (a recipe marker), so no spacer line above the heading.
local function AddCraftInfo(tooltip, itemID, writIDs, fresh)
    if fresh then
        tooltip:SetText("Craftman's Helper: used by a writ", HEADER_R, HEADER_G, HEADER_B)
    else
        tooltip:AddLine(" ")
        tooltip:AddLine("Craftman's Helper: wanted by a writ", HEADER_R, HEADER_G, HEADER_B)
    end
    local elsewhere = Elsewhere(itemID, "items")
    if elsewhere then tooltip:AddDoubleLine("Also have", elsewhere, 1, 0.82, 0, 1, 1, 1) end
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

-- Writ lines for a crafted item on any tooltip (recipe markers, trainer tooltips).
-- Returns false when no writ asks for the item.
function Tooltips.AddCraftLines(tooltip, itemID, fresh)
    local writIDs = writsByItem[itemID]
    if not writIDs then return false end
    AddCraftInfo(tooltip, itemID, writIDs, fresh)
    return true
end

-- On a Waylaid Crate: its cheapest fill, cost and Favor.
local function AddCrateInfo(tooltip, crateID)
    local e = ns.CrateCalc.Estimate(crateID)
    tooltip:AddLine(" ")
    tooltip:AddLine("Craftman's Helper", HEADER_R, HEADER_G, HEADER_B)
    tooltip:AddDoubleLine("Merchant's Favor", tostring(e.favor), 1, 1, 1, 1, 1, 1)
    if e.best then
        tooltip:AddDoubleLine(string.format("Cheapest fill: %d %s", e.best.count, ItemName(e.best.itemID, e.best.name)),
            ns.FormatMoneyIcons(e.best.cost), 1, 1, 1, 1, 1, 1)
        if not e.crateMissing then
            tooltip:AddDoubleLine("Gold per Favor (with the crate)", ns.FormatMoneyIcons(math.max(0, e.perFavor)), 1, 1, 1, 1, 1, 1)
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
        AddCraftInfo(tooltip, id, writsByItem[id])
    elseif ns.Crates[id] then
        AddCrateInfo(tooltip, id)
    end
end

function Tooltips:OnEnable()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    end
end
