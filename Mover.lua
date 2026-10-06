-- FrogLib Mover: dragging a frame to move it, with its place saved by the addon (not the game's
-- layout cache: SetUserPlaced(false) after each drag, so the two never fight over it).
--
--   FrogLib.Mover.Make(frame, o)
--       Left-drag moves frame (o.target: another frame moves instead, e.g. a holder). After the
--       drag, o.save(point) with point = { point, "UIParent", relativePoint, x, y }.
--       o.grid: track the drag on FrogLib's layout grid and centre it exactly when let go near
--       the middle of the screen. o.tint: also make frame.unlockTint, a blue wash reaching
--       o.tint units past the frame (shown while unlocked: the addon shows and hides it), on
--       BACKGROUND sublevel o.tintLevel.
--       The frame must be movable (SetMovable) and take the mouse while it's to be dragged.

local Mover = FrogLib:Module("Mover", 1)
if not Mover then return end

function Mover.Make(frame, o)
    o = o or {}
    local target = o.target or frame
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        target:StartMoving()
        if o.grid and FrogLib.Grid then FrogLib.Grid:Track(target) end
    end)
    frame:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        target:SetUserPlaced(false)
        local p, rp, x, y
        if o.grid and FrogLib.Grid then
            FrogLib.Grid:Track(nil)
            p, rp, x, y = FrogLib.Grid:Snap(target)
        else
            local _
            p, _, rp, x, y = target:GetPoint()
        end
        if o.save then o.save({ p, "UIParent", rp, x, y }) end
    end)
    if o.tint then
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, o.tintLevel)
        t:SetPoint("TOPLEFT", -o.tint, o.tint)
        t:SetPoint("BOTTOMRIGHT", o.tint, -o.tint)
        t:SetColorTexture(0.3, 0.6, 1, 0.2)
        frame.unlockTint = t
    end
end
