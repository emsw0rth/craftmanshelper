-- Marks recipes that craft an item a writ asks for: in the trainer's list, and in the
-- profession window's recipe list. A small daily-quest icon after the name, with the
-- writs on hover. The trainer's own recipe tooltip gets the same lines.
local _, ns = ...
local CH = ns.CH

local Marks = CH:NewModule("RecipeMarks", "AceEvent-3.0")
CH.RecipeMarks = Marks

local ICON = "Interface\\GossipFrame\\DailyQuestIcon"
local SIZE = 14

local function On()
    return CH.db.profile.markRecipes ~= false
end

-- Lower-case item name -> item ID for every writ item, for a recipe whose item the game won't link.
local byName
local function ItemByName(name)
    if not byName then
        byName = {}
        for _, w in pairs(ns.Writs) do byName[w.name:lower()] = w.item end
    end
    return name and byName[name:lower()]
end

local function ItemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The writ item a trainer service crafts, or nil.
function Marks.TrainerItem(index)
    local id = GetTrainerServiceItemLink and ItemIDFromLink(GetTrainerServiceItemLink(index))
    if id and ns.WritsByItem[id] then return id end
    if id then return nil end
    -- No link (not loaded yet, or the API is gone): recipes are named after what they make.
    local name = GetTrainerServiceInfo and GetTrainerServiceInfo(index)
    return ItemByName(name)
end

-- The writ item a profession recipe crafts, or nil.
function Marks.RecipeItem(recipeID, name)
    local TS = C_TradeSkillUI
    if recipeID and TS and TS.GetRecipeSchematic then
        local ok, schematic = pcall(TS.GetRecipeSchematic, recipeID, false)
        local id = ok and schematic and schematic.outputItemID
        if id then return ns.WritsByItem[id] and id or nil end
    end
    return ItemByName(name)
end

-- The marker on a list row: created once per row frame, reused as the list scrolls.
local function Marker(row)
    local m = row.craftmansHelperMark
    if not m then
        m = CreateFrame("Frame", nil, row)
        m:SetSize(SIZE, SIZE)
        m:SetFrameLevel(row:GetFrameLevel() + 5)
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetAllPoints()
        m.tex:SetTexture(ICON)
        m:EnableMouse(true)
        m:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            CH.Tooltips.AddCraftLines(GameTooltip, self.itemID, true)
            GameTooltip:Show()
        end)
        m:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Clicks go to the row underneath (select / train the recipe).
        if m.SetPropagateMouseClicks then
            m:SetPropagateMouseClicks(true)
        else
            m:SetScript("OnMouseUp", function(_, button)
                local click = row:GetScript("OnClick")
                if click then click(row, button) end
            end)
        end
        row.craftmansHelperMark = m
    end
    return m
end

-- Shows or hides the marker on a row. label: the row's name text, the marker goes right after it.
function Marks.Mark(row, itemID, label)
    if not row then return end
    if not (itemID and On()) then
        if row.craftmansHelperMark then row.craftmansHelperMark:Hide() end
        return
    end
    local m = Marker(row)
    m.itemID = itemID
    m:ClearAllPoints()
    if label and label.GetStringWidth then
        local width = label:GetStringWidth() or 0
        local room = label.GetWidth and label:GetWidth() or 0
        if room > 0 and width > room then width = room end
        m:SetPoint("LEFT", label, "LEFT", width + 3, 0)
    else
        m:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    m:Show()
end

---------------------------------------------------------------------------
-- Trainer
---------------------------------------------------------------------------

local function TrainerRow(row, elementData)
    local index = (type(elementData) == "table" and elementData.skillIndex) or (row.GetID and row:GetID())
    local _, serviceType = nil, nil
    if index and GetTrainerServiceInfo then _, serviceType = GetTrainerServiceInfo(index) end
    local itemID = index and serviceType ~= "header" and Marks.TrainerItem(index)
    Marks.Mark(row, itemID or nil, row.name or row.Name or row.Text)
end
Marks.TrainerRow = TrainerRow

-- Calls init(frame, elementData) for every row a list shows, now and as it scrolls.
local function OnRows(scrollBox, init)
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, frame, elementData) init(frame, elementData) end,
            Marks, true)
        return true
    end
end

function Marks:HookTrainer()
    if self.trainerHooked then return end
    local box = ClassTrainerFrame and ClassTrainerFrame.ScrollBox
    if box and OnRows(box, TrainerRow) then
        self.trainerHooked = true
    elseif type(ClassTrainerFrame_InitServiceButton) == "function" then
        hooksecurefunc("ClassTrainerFrame_InitServiceButton", TrainerRow)
        self.trainerHooked = true
    end
end

-- The trainer's tooltip for a recipe: add the writs it's for.
local function OnTrainerTooltip(tooltip, index)
    if not (On() and index) then return end
    local itemID = Marks.TrainerItem(index)
    if itemID and CH.Tooltips.AddCraftLines(tooltip, itemID) then tooltip:Show() end
end

---------------------------------------------------------------------------
-- Profession window
---------------------------------------------------------------------------

local function RecipeRow(row, node)
    local data = node and node.GetData and node:GetData()
    local info = data and data.recipeInfo
    local itemID = info and Marks.RecipeItem(info.recipeID, info.name)
    Marks.Mark(row, itemID, row.Label or row.Text or row.name)
end
Marks.RecipeRow = RecipeRow

function Marks:HookProfessions()
    if self.professionsHooked then return end
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local box = page and page.RecipeList and page.RecipeList.ScrollBox
    if box and OnRows(box, RecipeRow) then self.professionsHooked = true end
end

---------------------------------------------------------------------------

-- Redraws the lists that are open (after the setting changes).
function Marks:Refresh()
    for _, box in ipairs({ ClassTrainerFrame and ClassTrainerFrame.ScrollBox,
        ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList and
        ProfessionsFrame.CraftingPage.RecipeList.ScrollBox }) do
        if box and box.ForEachFrame then
            box:ForEachFrame(function(frame, elementData)
                if box == (ClassTrainerFrame and ClassTrainerFrame.ScrollBox) then
                    TrainerRow(frame, elementData)
                else
                    RecipeRow(frame, elementData)
                end
            end)
        end
    end
end

local function WhenLoaded(addon, fn)
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded(addon, fn)
    elseif C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) then
        fn()
    end
end

function Marks:OnEnable()
    WhenLoaded("Blizzard_TrainerUI", function() self:HookTrainer() end)
    WhenLoaded("Blizzard_Professions", function() self:HookProfessions() end)
    if GameTooltip and GameTooltip.SetTrainerService then
        hooksecurefunc(GameTooltip, "SetTrainerService", OnTrainerTooltip)
    end
end
