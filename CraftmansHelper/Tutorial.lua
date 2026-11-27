-- Guided tours: everything on screen is dimmed except the part being explained, with a card that
-- says what it is and Back / Next / Close tutorial buttons.
--
-- A tour is { key, steps = { { title, text, show = fn() (optional: get the screen ready), target =
-- fn() -> frame, or a list of frames (their combined area), or nil for no spotlight } },
-- alive = fn() -> false ends the tour (its window was closed) }.
-- Tours run once: CH.db.global.tutorials[key] = true once one has started.
local _, ns = ...
local CH = ns.CH

local Tutorial = CH:NewModule("Tutorial", "AceEvent-3.0", "AceTimer-3.0")
CH.Tutorial = Tutorial

local DIM = 0.7        -- how dark everything else gets
local PAD = 6          -- space around the spotlit part
local CARD_WIDTH = 320
local GAP = 14         -- between the spotlight and the card

local overlay, shades, border, card
local tour, step

local function Seen()
    local g = CH.db.global
    g.tutorials = g.tutorials or {}
    return g.tutorials
end

function Tutorial:HasSeen(key) return Seen()[key] == true end
function Tutorial:IsRunning() return tour ~= nil end

-- Makes every tour show again (Settings: "Reset tutorials").
function Tutorial:Reset()
    wipe(Seen())
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function Button(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetText(text)
    b:SetSize(math.max(80, b:GetFontString():GetStringWidth() + 28), 22)
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateFrames()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetAllPoints(UIParent)
    overlay:Hide()

    -- Four dark panels around the spotlight; they catch clicks, the spotlight lets them through.
    shades = {}
    for i = 1, 4 do
        local f = CreateFrame("Frame", nil, overlay)
        f:SetFrameLevel(overlay:GetFrameLevel())
        f:EnableMouse(true)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetColorTexture(0, 0, 0, DIM)
        shades[i] = f
    end

    border = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    border:SetBackdropBorderColor(1, 0.82, 0, 1)

    card = CreateFrame("Frame", "CraftmansHelperTutorialCard", overlay, "BackdropTemplate")
    card:SetFrameLevel(overlay:GetFrameLevel() + 10)
    card:SetWidth(CARD_WIDTH)
    card:EnableMouse(true)
    card:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    card.count = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.count:SetPoint("TOPRIGHT", -16, -16)
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", 16, -16)
    card.title:SetPoint("RIGHT", card.count, "LEFT", -8, 0)
    card.title:SetJustifyH("LEFT")
    card.text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -8)
    card.text:SetWidth(CARD_WIDTH - 32)
    card.text:SetJustifyH("LEFT")
    card.text:SetSpacing(2)
    card.close = Button(card, "Close tutorial", function() Tutorial:Stop() end)
    card.close:SetPoint("BOTTOMLEFT", 14, 14)
    card.nextB = Button(card, "Next", function() Tutorial:Go(step + 1) end)
    card.nextB:SetPoint("BOTTOMRIGHT", -14, 14)
    card.back = Button(card, "Back", function() Tutorial:Go(step - 1) end)
    card.back:SetPoint("RIGHT", card.nextB, "LEFT", -6, 0)

    -- Escape closes the tutorial.
    card:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            Tutorial:Stop()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    overlay:SetScript("OnUpdate", function() Tutorial:Layout() end)
end

---------------------------------------------------------------------------
-- Placing the spotlight and the card
---------------------------------------------------------------------------

-- The screen area (in UIParent's coordinates) covered by a frame or a list of frames, or nil.
local function Area(target)
    if type(target) ~= "table" then return nil end
    local list = target.GetObjectType and { target } or target
    local scale = UIParent:GetEffectiveScale()
    local l, r, t, b
    for _, f in ipairs(list) do
        if f and f.IsVisible and f:IsVisible() and f:GetLeft() then
            local s = f:GetEffectiveScale() / scale
            local fl, fr, ft, fb = f:GetLeft() * s, f:GetRight() * s, f:GetTop() * s, f:GetBottom() * s
            l, r = l and math.min(l, fl) or fl, r and math.max(r, fr) or fr
            t, b = t and math.max(t, ft) or ft, b and math.min(b, fb) or fb
        end
    end
    if not l then return nil end
    return l - PAD, r + PAD, t + PAD, b - PAD
end

local function Place(f, l, r, t, b)
    f:ClearAllPoints()
    if r <= l or t <= b then f:Hide(); return end
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    f:SetSize(r - l, t - b)
    f:Show()
end

function Tutorial:Layout()
    if not tour then return end
    if tour.alive and not tour.alive() then
        self:Stop()
        return
    end
    local s = tour.steps[step]
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local l, r, t, b = Area(s.target and s.target())
    if not l then
        -- No spotlight: dim everything, card in the middle.
        Place(shades[1], 0, W, H, 0)
        for i = 2, 4 do shades[i]:Hide() end
        border:Hide()
        card:ClearAllPoints()
        card:SetPoint("CENTER", UIParent, "CENTER")
        return
    end
    l, r, t, b = math.max(0, l), math.min(W, r), math.min(H, t), math.max(0, b)
    Place(shades[1], 0, W, H, t)       -- above
    Place(shades[2], 0, W, b, 0)       -- below
    Place(shades[3], 0, l, t, b)       -- left
    Place(shades[4], r, W, t, b)       -- right
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l - 4, t + 4)
    border:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", r + 4, b - 4)
    border:Show()

    -- The card: to the right of the spotlight, else the left, else below or above it, else inside.
    local cw, ch = card:GetWidth(), card:GetHeight()
    local x, y
    local top = math.min(H - 10, math.max(t, ch + 10))
    if r + GAP + cw <= W then
        x, y = r + GAP, top
    elseif l - GAP - cw >= 0 then
        x, y = l - GAP - cw, top
    elseif b - GAP - ch >= 0 then
        x, y = math.min(W - cw - 10, math.max(10, l)), b - GAP
    elseif t + GAP + ch <= H then
        x, y = math.min(W - cw - 10, math.max(10, l)), t + GAP + ch
    else
        x, y = math.max(10, r - cw - 10), math.max(ch + 10, b + ch + 10)
    end
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

---------------------------------------------------------------------------
-- Running a tour
---------------------------------------------------------------------------

function Tutorial:Go(n)
    if not tour then return end
    if n > #tour.steps then
        self:Stop()
        return
    end
    step = math.max(1, n)
    local s = tour.steps[step]
    if s.show then s.show() end
    card.title:SetText(s.title)
    card.text:SetText(s.text)
    card.count:SetText(string.format("%d / %d", step, #tour.steps))
    card.back:SetEnabled(step > 1)
    card.nextB:SetText(step == #tour.steps and "Finish" or "Next")
    card:SetHeight(16 + card.title:GetStringHeight() + 8 + card.text:GetStringHeight() + 16 + 22 + 16)
    self:Layout()
end

-- Starts a tour (and marks it seen). Returns false when another one is running.
function Tutorial:Start(t)
    if tour then return false end
    if not overlay then CreateFrames() end
    Seen()[t.key] = true
    tour = t
    overlay:Show()
    card:EnableKeyboard(true)
    self:Go(1)
    return true
end

-- Starts a tour unless it has been seen.
function Tutorial:Offer(t)
    if self:HasSeen(t.key) then return false end
    return self:Start(t)
end

function Tutorial:Stop()
    if not tour then return end
    local t = tour
    tour, step = nil, nil
    overlay:Hide()
    card:EnableKeyboard(false)
    if t.onStop then t.onStop() end
end

-- Tours stop when combat starts (the dim layer would be in the way).
function Tutorial:PLAYER_REGEN_DISABLED()
    self:Stop()
end

function Tutorial:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
end
