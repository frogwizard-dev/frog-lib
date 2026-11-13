-- FrogLib Mover: dragging a frame to move it, with its place saved by the addon, not the game's
-- layout cache (SetUserPlaced(false) after each drag, so the two never fight over it).

local Mover = FrogLib:Module("Mover", 1)
if not Mover then return end

-- Left-drag moves the frame (or opts.target, such as a holder), which must be movable and take the
-- mouse; after the drag, opts.save({ point, "UIParent", relativePoint, x, y }).
function Mover.Make(frame, opts)
    opts = opts or {}
    local target = opts.target or frame
    frame:RegisterForDrag("LeftButton")
    -- opts.grid: the drag shows on FrogLib's layout grid, and lands exactly centred near the middle.
    frame:SetScript("OnDragStart", function()
        target:StartMoving()
        if opts.grid and FrogLib.Grid then FrogLib.Grid:Track(target) end
    end)
    frame:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        target:SetUserPlaced(false)
        local point, relativePoint, x, y
        if opts.grid and FrogLib.Grid then
            FrogLib.Grid:Track(nil)
            point, relativePoint, x, y = FrogLib.Grid:Snap(target)
        else
            local _
            point, _, relativePoint, x, y = target:GetPoint()
        end
        if opts.save then opts.save({ point, "UIParent", relativePoint, x, y }) end
    end)
    -- opts.tint: frame.unlockTint, a blue wash that far past the frame (on BACKGROUND sublevel
    -- opts.tintLevel), for the addon to show while unlocked.
    if opts.tint then
        local tint = frame:CreateTexture(nil, "BACKGROUND", nil, opts.tintLevel)
        tint:SetPoint("TOPLEFT", -opts.tint, opts.tint)
        tint:SetPoint("BOTTOMRIGHT", opts.tint, -opts.tint)
        tint:SetColorTexture(0.3, 0.6, 1, 0.2)
        frame.unlockTint = tint
    end
end
