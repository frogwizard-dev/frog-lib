-- FrogLib Secure: click buttons for unit frames and bars: left-click targets, right-click opens the
-- unit's menu. On 12.x a unit button's own "togglemenu" silently does nothing, and its "target" only works on a
-- plain click (a click with shift, ctrl or alt has no click binding, so the game drops it), so those "/click" a
-- hidden SecureActionButton child that does both (as EllesmereUI's frames do).
-- Secure frames are only made, set up, placed and shown out of combat: callers wait for it to end.

local Secure = FrogLib:Module("Secure", 4) -- 3: Watch; 4: modified left-clicks target too
if not Secure then return end

-- The hidden menu button: a child of `owner` (a secure unit button), opening the menu for its unit.
function Secure.MenuButton(owner, name)
    local menu = CreateFrame("Button", name, owner, "SecureActionButtonTemplate")
    -- Over the whole unit button, taking no mouse. With the gamepad UI on, a menu opens beside its
    -- owner, and one with no place on screen failed (FrameUtil.GetScreenQuadrant).
    menu:SetAllPoints(owner)
    menu:EnableMouse(false)
    menu:RegisterForClicks("AnyUp")
    for i = 1, 5 do menu:SetAttribute("type" .. i, "togglemenu") end
    menu:SetAttribute("*type-target", "target") -- "/click <name> target", with the click's modifier still held
    menu:SetAttribute("useparent-unit", true)
    menu:SetAttribute("useOnKeyDown", false) -- act on the up-click whatever the key-down setting
    return menu
end

-- Left-click targets (a plain one itself, one with a modifier through the menu button named menuName), right-click
-- "/click"s the menu button; no name turns both off.
function Secure.SetClicks(button, menuName)
    if menuName then
        button:SetAttribute("type1", "target")
        button:SetAttribute("*type1", "macro")
        button:SetAttribute("*macrotext1", "/click " .. menuName .. " target")
        button:SetAttribute("*type2", "macro")
        button:SetAttribute("*macrotext2", "/click " .. menuName)
    else
        button:SetAttribute("type1", nil)
        button:SetAttribute("*type1", nil)
        button:SetAttribute("*type2", nil)
    end
end

local function TooltipOff(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- A hidden SecureUnitButton for the unit, clicks set, and its menu button (opts.menu: another's name,
-- for two buttons over one bar). opts.tooltip: the unit's tooltip while the mouse is over it.
function Secure.UnitButton(name, unit, opts)
    opts = opts or {}
    local button = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    button:SetAttribute("unit", unit)
    button:RegisterForClicks("AnyUp")
    local menuName, menu = opts.menu, nil
    if not menuName then
        menuName = name .. "Menu"
        menu = Secure.MenuButton(button, menuName)
    end
    Secure.SetClicks(button, menuName)
    if opts.tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", TooltipOff)
    end
    button:Hide()
    return button, menu
end

-- Active, the game shows the button while its unit exists (the unit watch); otherwise it stays hidden.
function Secure.Watch(button, active)
    if active then
        RegisterUnitWatch(button)
    else
        UnregisterUnitWatch(button)
        button:Hide()
    end
end
