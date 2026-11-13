-- Minimap button (LibDataBroker launcher + LibDBIcon). Also shows up in
-- broker displays and the addon compartment.
local _, ns = ...
local CH = ns.CH

local Minimap = CH:NewModule("Minimap")
CH.Minimap = Minimap

local ICON = "Interface\\Icons\\INV_Misc_Note_01"

local function ShowTooltip(tooltip)
    local c = CH.Tracker:GetCounts()
    tooltip:AddLine("Craftman's Helper")
    tooltip:AddDoubleLine("Ready to deliver", tostring(c.ready), 1, 0.82, 0, 0.13, 1, 0.13)
    tooltip:AddDoubleLine("In progress", tostring(c.active), 1, 0.82, 0, 1, 1, 1)
    if c.inbags > 0 then
        tooltip:AddDoubleLine("Not started (in bags)", tostring(c.inbags), 1, 0.82, 0, 1, 0.63, 0.13)
    end
    tooltip:AddDoubleLine("Done today", tostring(c.done), 1, 0.82, 0, 0.5, 0.5, 0.5)
    tooltip:AddDoubleLine("Daily reset in", ns.FormatDuration(CH.Tracker:SecondsUntilReset()), 1, 0.82, 0, 1, 1, 1)

    local stop = CH.Route:GetCurrent()
    if stop then
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("Next stop", string.format("%s (%s)", stop.name or "?", stop.zoneName or "?"),
            1, 0.82, 0, 1, 1, 1)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("Left-click: open / close", 0.6, 0.6, 0.6)
    tooltip:AddLine("Right-click: plan a route", 0.6, 0.6, 0.6)
end

function Minimap:OnEnable()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB then return end

    self.broker = LDB:NewDataObject("CraftmansHelper", {
        type = "launcher",
        label = "Craftman's Helper",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                CH.Route:Plan()
                CH.UI:Show("route")
            else
                CH.UI:Toggle()
            end
        end,
        OnTooltipShow = ShowTooltip,
    })

    if DBIcon and self.broker then
        DBIcon:Register("CraftmansHelper", self.broker, CH.db.profile.minimap)
        if DBIcon.AddButtonToCompartment then
            pcall(DBIcon.AddButtonToCompartment, DBIcon, "CraftmansHelper")
        end
        self.icon = DBIcon
    end
end

function Minimap:SetShown(show)
    if not self.icon then return end
    local cfg = CH.db.profile.minimap
    cfg.hide = not show
    if cfg.hide then self.icon:Hide("CraftmansHelper") else self.icon:Show("CraftmansHelper") end
end

function Minimap:Toggle()
    if not self.icon then return end
    self:SetShown(CH.db.profile.minimap.hide)
    CH:Print(CH.db.profile.minimap.hide and "Minimap button hidden (/writs minimap to show it again)."
        or "Minimap button shown.")
end
