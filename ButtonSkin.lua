-- FrogLib ButtonSkin: FrogUI's button looks, for any button or icon frame with an `icon` texture
-- (action buttons, FrogTotems' timers). look.style: "rounded" (the cooldown manager's rounded mask
-- and thin frame), "square", or "classic" (below). The icon sits in a border (look.border pixels,
-- look.borderColor): the dark backing showing round it. `look` is the addon's settings table, read
-- live for the border; the style is set when a button is first dressed (a /reload changes it).

local ButtonSkin = FrogLib:Module("ButtonSkin", 1)
if not ButtonSkin then return end

local MASK = "UI-HUD-CoolDownManager-Mask"
local OVERLAY = "UI-HUD-CoolDownManager-IconOverlay"
local SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local COOLDOWNS = { "cooldown", "chargeCooldown", "lossOfControlCooldown" }

-- Inside the border (the Classic look has its slot art for one instead).
local function Fit(region, button)
    region:ClearAllPoints()
    local look = button.frogLook
    local inset = look.style == "classic" and 0 or (look.border or 0)
    region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
end

-- The rounded mask, once per region: the icon's (inside the border) for the icon and its
-- highlights, or `mask` (the backing's, the whole button).
local function Mask(region, button, mask)
    mask = mask or button.frogMask
    if not (mask and region and region.AddMaskTexture) or region.frogMasked then return end
    region.frogMasked = true
    pcall(region.AddMaskTexture, region, mask)
end

-- The overlay frame is sized from the button (Edit Mode's icon size changes it); it reaches a
-- little past the icon, 9 and 8 of a 50px icon.
local function FitOverlay(button)
    local overlay = button.frogOverlay
    if not overlay then return end
    local width, height = button:GetSize()
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", -width * 9 / 50, height * 8 / 50)
    overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", width * 9 / 50, -height * 8 / 50)
end

------------------------------------------------------------------------------
-- The Classic look: the 1.x slot ring (UI-Quickslot2, half strength) over the icon, the open socket faint behind,
-- and the old pressed, highlight and checked art, as Classic Era draws them. Sized from the button.
------------------------------------------------------------------------------

local QUICKSLOT, QUICKSLOT_EMPTY = "Interface\\Buttons\\UI-Quickslot2", "Interface\\Buttons\\UI-Quickslot"
local RING_CROP = { 0.1875, 0.796875 }

-- The icon's size: the whole button, or button.frogSlot when the addon gives one (FrogUI's wells behind its bars:
-- 36/42 of the step to the next button, as Classic's 36px icons sat 42 apart).
local function Slot(button)
    return button.frogSlot or button:GetWidth()
end

local function SlotArt(region, button, file, size, alpha, crop, layer, sub)
    if not region then return end
    local width = Slot(button)
    region:SetTexture(file)
    local low, high = crop and crop[1] or 0, crop and crop[2] or 1
    region:SetTexCoord(low, high, low, high)
    region:ClearAllPoints()
    region:SetPoint("CENTER", button, "CENTER", 0, 0)
    region:SetSize(width * size, width * size)
    region:SetVertexColor(1, 1, 1)
    region:SetAlpha(alpha)
    region:SetDrawLayer(layer, sub)
end

function ButtonSkin.ClassicRestyle(button)
    for _, key in ipairs({ "SlotArt", "SlotBackground" }) do
        if button[key] then button[key]:SetAlpha(0) end
    end
    local icon, width = button.icon, Slot(button)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetSize(width, width)
    local ring = button.frogRing or (button.GetNormalTexture and button:GetNormalTexture())
    SlotArt(ring, button, QUICKSLOT, 40 / 36, 0.5, RING_CROP, "OVERLAY", 0)
    SlotArt(button.frogBack, button, QUICKSLOT_EMPTY, 66 / 36, 0.4, nil, "BACKGROUND", -1)
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        pushed:SetTexCoord(0, 1, 0, 1)
    end
    -- Everything else over the icon, at its size.
    for _, get in ipairs({ "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
        local region = button[get] and button[get](button)
        if region then
            region:ClearAllPoints()
            region:SetAllPoints(icon)
        end
    end
    for _, key in ipairs(COOLDOWNS) do
        if button[key] then
            button[key]:ClearAllPoints()
            button[key]:SetAllPoints(icon)
        end
    end
end

local function ClassicSkin(button)
    local icon = button.icon
    if button.IconMask then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    button.frogBack = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    -- A plain frame has no normal texture to carry the ring.
    if not (button.GetNormalTexture and button:GetNormalTexture()) then
        button.frogRing = button:CreateTexture(nil, "OVERLAY")
    end
    if button.SetHighlightTexture then
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        checked:SetBlendMode("ADD")
        checked:SetTexCoord(0, 1, 0, 1)
    end
    ButtonSkin.ClassicRestyle(button)
    if button.UpdateButtonArt then hooksecurefunc(button, "UpdateButtonArt", ButtonSkin.ClassicRestyle) end
    -- Edit Mode's icon size: the slot art follows.
    button:HookScript("OnSizeChanged", ButtonSkin.ClassicRestyle)
end

-- The parts Blizzard puts back whenever it redraws a button (UpdateButtonArt): its frame art
-- and its pushed texture.
local function Restyle(button)
    for _, key in ipairs({ "SlotArt", "SlotBackground" }) do
        if button[key] then button[key]:SetAlpha(0) end
    end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetColorTexture(1, 1, 1, 0.25)
        Fit(pushed, button)
        Mask(pushed, button)
    end
end

-- Dresses `button` in `look` (once; later calls do nothing).
function ButtonSkin.Skin(button, look)
    if button.frogSkinned or not button.icon then return end
    button.frogSkinned = true
    button.frogLook = look
    if look.style == "classic" then
        button.frogClassic = true
        ClassicSkin(button)
        return
    end
    local rounded = look.style == "rounded"

    local icon = button.icon
    if button.IconMask then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the icon's own baked-in border
    Fit(icon, button)

    if rounded then
        local mask = button:CreateMaskTexture()
        mask:SetAtlas(MASK)
        mask:SetAllPoints(icon)
        button.frogMask = mask
        Mask(icon, button)
        local outer = button:CreateMaskTexture()
        outer:SetAtlas(MASK)
        outer:SetAllPoints(button)
        button.frogOuterMask = outer
        local overlay = button:CreateTexture(nil, "OVERLAY", nil, -1)
        overlay:SetAtlas(OVERLAY)
        button.frogOverlay = overlay
        FitOverlay(button)
        button:HookScript("OnSizeChanged", FitOverlay)
    end

    -- Behind the icon, the whole button: the border round it, and the look of an empty slot.
    local back = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetAllPoints(button)
    button.frogBack = back
    Mask(back, button, button.frogOuterMask)

    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetColorTexture(1, 1, 1, 0.15)
        Fit(highlight, button)
        Mask(highlight, button)
    end
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetColorTexture(1, 0.82, 0.3, 0.3)
        Fit(checked, button)
        Mask(checked, button)
    end
    for _, key in ipairs(COOLDOWNS) do
        local cd = button[key]
        if cd then
            Fit(cd, button)
            -- The cooldown manager's rounded sweep, so the swipe follows the corners.
            if rounded and cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, SWIPE) end
        end
    end

    Restyle(button)
    if button.UpdateButtonArt then hooksecurefunc(button, "UpdateButtonArt", Restyle) end
    ButtonSkin.Refit(button)
end

-- The border's thickness and colour, on a dressed button (live, from its look).
function ButtonSkin.Refit(button)
    if not button.frogSkinned or button.frogClassic then return end
    local color = button.frogLook.borderColor
    button.frogBack:SetColorTexture(color.r, color.g, color.b, color.a or 0.9)
    Fit(button.icon, button)
    for _, get in ipairs({ "GetHighlightTexture", "GetCheckedTexture", "GetPushedTexture" }) do
        local region = button[get] and button[get](button)
        if region then Fit(region, button) end
    end
    for _, key in ipairs(COOLDOWNS) do
        if button[key] then Fit(button[key], button) end
    end
end
