-- FrogLib Sheet: the character window's width when more than one addon widens it (FrogUI's model
-- pane for the text beside the slots, StatSheet's stats pane). Each says how much it adds to which
-- pane, and the window is Forever's width plus all of it, whichever addon sets it. Forever's
-- CharacterFrame:UpdateSize: 631 wide (398 model pane, 233 stats pane), 398 with the stats collapsed.

local Sheet = FrogLib:Module("Sheet", 1)
if not Sheet then return end

Sheet.extras = Sheet.extras or { left = {}, right = {} }

-- side: "left" (the model pane) or "right" (the stats pane); pixels: how much wider it makes it.
function Sheet.SetExtra(owner, side, pixels)
    Sheet.extras[side][owner] = pixels or 0
end

local function Sum(side)
    local total = 0
    for _, pixels in pairs(Sheet.extras[side]) do total = total + pixels end
    return total
end

-- The window's width now: the right pane's extra only while that pane is open.
function Sheet.Width()
    local window = _G.CharacterFrame
    local collapsed = window and window.IsRightPaneCollapsed and window:IsRightPaneCollapsed()
    if collapsed then return (CHARACTER_FRAME_COLLAPSED_WIDTH or 398) + Sum("left") end
    return (CHARACTER_FRAME_WIDTH or 631) + Sum("left") + Sum("right")
end
