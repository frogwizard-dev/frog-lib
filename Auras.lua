-- FrogLib Auras: the pieces every addon's aura rows are made of. Each row is one of 12.1's
-- AuraContainers, the engine picking and drawing the auras where addons can't read them. Learnt:
-- place a container before setting it up (moving it means building it again), anchor nothing to it,
-- size the buttons (the engine makes them 0x0), and set fonts before handing regions over.

local Auras = FrogLib:Module("Auras", 2) -- 2: debuff borders in their dispel type's colour
if not Auras then return end

local MASK = "UI-HUD-CoolDownManager-Mask"
local SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

-- A container's setter under its new or old name (renamed mid-12.1: SetAuraLayout* -> SetFlowLayout*).
function Auras.Call(container, newName, oldName, ...)
    local setter = container[newName] or container[oldName]
    if setter then pcall(setter, container, ...) end
end

-- 1x1 and unplaced, or nil when the client has none.
function Auras.NewContainer(parent)
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container then return nil end
    container:SetSize(1, 1)
    return container
end

-- Its anchor corner ("TOPLEFT"...), and which way it grows: across "RIGHT" or "LEFT", down "DOWN" or "UP".
function Auras.Flow(container, point, across, down)
    local flow = AnchorUtil.FlowDirection
    Auras.Call(container, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", point)
    Auras.Call(container, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection",
        across == "LEFT" and flow.Left or flow.Right, down == "UP" and flow.Up or flow.Down)
end

-- How long a line gets before it wraps.
function Auras.SetLineSize(container, width)
    Auras.Call(container, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", width)
end

-- Unbound from its unit and hidden, to be built again.
function Auras.Release(container)
    if not container then return end
    pcall(container.SetUnit, container, "none")
    container:Hide()
end

Auras.formatters = Auras.formatters or {}

-- The timer text: "12", "3m", "1h" ("12s" with seconds).
function Auras.Formatter(seconds)
    local key = seconds and "s" or "plain"
    local cached = Auras.formatters[key]
    if cached ~= nil then return cached or nil end
    Auras.formatters[key] = false
    local Rounding = Enum and Enum.NumericRuleFormatRounding
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Rounding then
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(formatter.SetBreakpoints, formatter, {
            { threshold = 0, format = seconds and "%ds" or "%d", step = 1, rounding = Rounding.Up },
            { threshold = 60, format = "%dm", step = 1, rounding = Rounding.Up, components = { { div = 60 } } },
            { threshold = 61, format = "%dm", step = 1, rounding = Rounding.Down, components = { { div = 60 } } },
            { threshold = 3600, format = "%dh", step = 1, rounding = Rounding.Down, components = { { div = 3600 } } },
        }) then
            Auras.formatters[key] = formatter
        end
    end
    return Auras.formatters[key] or nil
end

-- The icon inside its border: 1px square, or 2px with the action bars' rounded corners (the
-- cooldown sweep following). Returns the border's rounded mask, for anything drawn in its place.
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
    return outer
end

local BLACK = { 0, 0, 0 }

-- An engine-made button dressed: { border, icon, cooldown, stack (bottom right), duration, dispel }.
-- Clicks off, so the icons never eat clicks meant for the world; tooltips stay.
function Auras.InitButton(button, opts)
    local parts = { button = button }
    local color = opts.border or BLACK -- { r, g, b }
    parts.border = button:CreateTexture(nil, "BACKGROUND")
    parts.border:SetAllPoints()
    parts.border:SetColorTexture(color[1], color[2], color[3], 1)
    parts.icon = button:CreateTexture(nil, "ARTWORK")
    parts.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    parts.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    local mask = Auras.Shape(parts.icon, parts.border, button, parts.cooldown, opts.rounded)
    -- Over the border, a harmful aura's dispel type in the game's colours, worked out by the engine so
    -- it shows where addons can't read the type (opts.dispel = false: never).
    local style = Enum.CustomAuraButtonDispelTypeTextureStyle
    if opts.dispel ~= false and button.AddDispelTypeTexture and style and style.PreserveAsset then
        local dispel = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        dispel:SetAllPoints()
        dispel:SetTexture("Interface\\Buttons\\WHITE8X8")
        if mask then pcall(dispel.AddMaskTexture, dispel, mask) end
        if pcall(button.AddDispelTypeTexture, button, dispel, { style = style.PreserveAsset,
            showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = false }) then
            parts.dispel = dispel
        else
            dispel:Hide()
        end
    end
    parts.cooldown:SetAllPoints(parts.icon)
    parts.cooldown:SetDrawEdge(false)
    parts.cooldown:SetReverse(true)
    parts.cooldown:SetHideCountdownNumbers(true)
    -- The texts on a frame above the cooldown sweep.
    local carrier = CreateFrame("Frame", nil, button)
    carrier:SetAllPoints()
    carrier:SetFrameLevel(parts.cooldown:GetFrameLevel() + 1)
    carrier:EnableMouse(false)
    parts.stack = carrier:CreateFontString(nil, "OVERLAY")
    parts.stack:SetPoint("BOTTOMRIGHT", -1, 1)
    parts.duration = carrier:CreateFontString(nil, "OVERLAY")
    if opts.timerOnIcon then
        parts.duration:SetPoint("CENTER")
    else
        parts.duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
    end
    if opts.shadow then
        for _, text in ipairs({ parts.stack, parts.duration }) do
            text:SetShadowOffset(1, -1)
            text:SetShadowColor(0, 0, 0, 1)
        end
    end
    -- Sizes and fonts, before the regions are handed over (the engine writes text at once).
    if opts.style then opts.style(parts) end

    pcall(button.SetMouseClickEnabled, button, false)
    button:SetIcon(parts.icon)
    button:SetDurationCooldown(parts.cooldown)
    button:SetApplicationCount(parts.stack, {})
    -- opts.seconds: the timer's format.
    if not pcall(button.SetDurationText, button, parts.duration, { textFormatter = Auras.Formatter(opts.seconds) }) then
        pcall(button.SetDurationText, button, parts.duration, {})
    end
    return parts
end
