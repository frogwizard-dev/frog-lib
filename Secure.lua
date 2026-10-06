-- FrogLib Secure: click buttons for unit frames and bars: left-click targets the unit, right-click
-- opens its menu. On 12.x a unit button's own "togglemenu" is gated and silently does nothing, so
-- right-click runs "/click" on a hidden SecureActionButton child whose togglemenu isn't (the same
-- route EllesmereUI's unit frames use).
-- Secure frames can only be made, set up, placed and shown out of combat: callers wait for the
-- fight to end (PLAYER_REGEN_ENABLED) before calling any of these.
--   FrogLib.Secure.MenuButton(owner, name) -> the hidden menu button: a child of `owner` (a
--       secure unit button) named `name`, opening the menu for owner's unit
--   FrogLib.Secure.SetClicks(button, menuName): left-click targets, right-click "/click"s the
--       menu button named menuName; menuName false or nil turns both clicks off
--   FrogLib.Secure.UnitButton(name, unit, opts) -> button, menu: a hidden SecureUnitButton
--       named `name` for `unit` (on UIParent), clicks set. opts (optional): menu = the name of an
--       existing menu button to use (two buttons over one bar can share one), otherwise one is
--       made (name .. "Menu"); tooltip = true: the unit's tooltip while the mouse is over it.

local Secure = FrogLib:Module("Secure", 1)
if not Secure then return end

function Secure.MenuButton(owner, name)
    local menu = CreateFrame("Button", name, owner, "SecureActionButtonTemplate")
    menu:SetSize(1, 1)
    menu:EnableMouse(false)
    menu:RegisterForClicks("AnyUp")
    for i = 1, 5 do menu:SetAttribute("type" .. i, "togglemenu") end
    menu:SetAttribute("useparent-unit", true)
    menu:SetAttribute("useOnKeyDown", false) -- act on the up-click whatever the key-down setting
    return menu
end

function Secure.SetClicks(button, menuName)
    if menuName then
        button:SetAttribute("*type1", "target")
        button:SetAttribute("*type2", "macro")
        button:SetAttribute("*macrotext2", "/click " .. menuName)
    else
        button:SetAttribute("*type1", nil)
        button:SetAttribute("*type2", nil)
    end
end

local function TooltipOff(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function Secure.UnitButton(name, unit, opts)
    opts = opts or {}
    local b = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    b:SetAttribute("unit", unit)
    b:RegisterForClicks("AnyUp")
    local menuName, menu = opts.menu, nil
    if not menuName then
        menuName = name .. "Menu"
        menu = Secure.MenuButton(b, menuName)
    end
    Secure.SetClicks(b, menuName)
    if opts.tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", TooltipOff)
    end
    b:Hide()
    return b, menu
end
