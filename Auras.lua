-- FrogLib Auras: the pieces every addon's aura rows are made of (FrogTarget, XIVTarget,
-- FrogFrames, XIVPlayer, Personal Resource Tweaks). Each row is one of 12.1's AuraContainers:
-- the engine picks and draws the auras, so it keeps working where addons can't read aura data.
-- What's been learnt: position a container before setting it up (moving it means building it
-- again), never anchor anything to it, size the buttons yourself (the engine makes them 0x0),
-- and set a button's fonts before handing its regions over (the engine writes text at once).
--
--   FrogLib.Auras.NewContainer(parent) -> c, or nil when the client has none. 1x1, unplaced.
--   FrogLib.Auras.Flow(c, point, across, down): its anchor corner ("TOPLEFT"...), and which way
--       it grows: across "RIGHT" / "LEFT", down "DOWN" / "UP".
--   FrogLib.Auras.SetLineSize(c, width): how long a line gets before it wraps.
--   FrogLib.Auras.Release(c): unbound from its unit and hidden, to be built again.
--   FrogLib.Auras.Call(c, newName, oldName, ...): a setter under its new or old name (renamed
--       mid-12.1: SetAuraLayout* -> SetFlowLayout*).
--   FrogLib.Auras.Formatter(seconds) -> the timer text: "12", "3m", "1h" ("12s" with seconds).
--   FrogLib.Auras.Shape(icon, border, button, cooldown, rounded): the icon inside its border,
--       1px square, or 2px with the action bars' rounded corners (cooldown sweep following).
--   FrogLib.Auras.InitButton(button, o) -> d: an engine-made button dressed: d.border (o.border
--       = { r, g, b }), d.icon, d.cooldown, d.stack (bottom right), d.duration (under the icon,
--       or centred on it with o.timerOnIcon). o.rounded, o.shadow (text shadows), o.seconds (the
--       timer's format), o.style(d) (sizes and fonts: run before the regions are handed over).
--       Clicks off, so the icons never eat clicks meant for the world; tooltips stay.

local Auras = FrogLib:Module("Auras", 1)
if not Auras then return end

local MASK = "UI-HUD-CoolDownManager-Mask"
local SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

function Auras.Call(c, newName, oldName, ...)
    local f = c[newName] or c[oldName]
    if f then pcall(f, c, ...) end
end

function Auras.NewContainer(parent)
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    c:SetSize(1, 1)
    return c
end

function Auras.Flow(c, point, across, down)
    local flow = AnchorUtil.FlowDirection
    Auras.Call(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", point)
    Auras.Call(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection",
        across == "LEFT" and flow.Left or flow.Right, down == "UP" and flow.Up or flow.Down)
end

function Auras.SetLineSize(c, width)
    Auras.Call(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", width)
end

function Auras.Release(c)
    if not c then return end
    pcall(c.SetUnit, c, "none")
    c:Hide()
end

Auras.formatters = Auras.formatters or {}

function Auras.Formatter(seconds)
    local key = seconds and "s" or "plain"
    local cached = Auras.formatters[key]
    if cached ~= nil then return cached or nil end
    Auras.formatters[key] = false
    local R = Enum and Enum.NumericRuleFormatRounding
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and R then
        local f = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(f.SetBreakpoints, f, {
            { threshold = 0, format = seconds and "%ds" or "%d", step = 1, rounding = R.Up },
            { threshold = 60, format = "%dm", step = 1, rounding = R.Up, components = { { div = 60 } } },
            { threshold = 61, format = "%dm", step = 1, rounding = R.Down, components = { { div = 60 } } },
            { threshold = 3600, format = "%dh", step = 1, rounding = R.Down, components = { { div = 3600 } } },
        }) then
            Auras.formatters[key] = f
        end
    end
    return Auras.formatters[key] or nil
end

function Auras.Shape(icon, border, button, cooldown, rounded)
    local inset = rounded and 2 or 1
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    if not rounded then return end
    local inner = button:CreateMaskTexture()
    inner:SetAtlas(MASK)
    inner:SetAllPoints(icon)
    pcall(icon.AddMaskTexture, icon, inner)
    local outer = button:CreateMaskTexture()
    outer:SetAtlas(MASK)
    outer:SetAllPoints(button)
    pcall(border.AddMaskTexture, border, outer)
    if cooldown and cooldown.SetSwipeTexture then pcall(cooldown.SetSwipeTexture, cooldown, SWIPE) end
end

local BLACK = { 0, 0, 0 }

function Auras.InitButton(button, o)
    local d = { button = button }
    local c = o.border or BLACK
    d.border = button:CreateTexture(nil, "BACKGROUND")
    d.border:SetAllPoints()
    d.border:SetColorTexture(c[1], c[2], c[3], 1)
    d.icon = button:CreateTexture(nil, "ARTWORK")
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    Auras.Shape(d.icon, d.border, button, d.cooldown, o.rounded)
    d.cooldown:SetAllPoints(d.icon)
    d.cooldown:SetDrawEdge(false)
    d.cooldown:SetReverse(true)
    d.cooldown:SetHideCountdownNumbers(true)
    -- The texts on a frame above the cooldown sweep.
    local carrier = CreateFrame("Frame", nil, button)
    carrier:SetAllPoints()
    carrier:SetFrameLevel(d.cooldown:GetFrameLevel() + 1)
    carrier:EnableMouse(false)
    d.stack = carrier:CreateFontString(nil, "OVERLAY")
    d.stack:SetPoint("BOTTOMRIGHT", -1, 1)
    d.duration = carrier:CreateFontString(nil, "OVERLAY")
    if o.timerOnIcon then
        d.duration:SetPoint("CENTER")
    else
        d.duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
    end
    if o.shadow then
        for _, fs in ipairs({ d.stack, d.duration }) do
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 1)
        end
    end
    if o.style then o.style(d) end

    pcall(button.SetMouseClickEnabled, button, false)
    button:SetIcon(d.icon)
    button:SetDurationCooldown(d.cooldown)
    button:SetApplicationCount(d.stack, {})
    if not pcall(button.SetDurationText, button, d.duration, { textFormatter = Auras.Formatter(o.seconds) }) then
        pcall(button.SetDurationText, button, d.duration, {})
    end
    return d
end
