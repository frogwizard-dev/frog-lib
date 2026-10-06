-- FrogLib Sheet: the character window's width when more than one addon widens it (FrogUI's
-- model pane for the text beside the slots, StatSheet's stats pane). Each says how much it adds
-- to which pane; the window is set to Forever's width plus all of it, whichever addon sets it.
--   FrogLib.Sheet.SetExtra(owner, side, px)   side "left" (model pane) or "right" (stats pane)
--   FrogLib.Sheet.Width() -> the window's width now (the right pane's extra only while it's open)
-- Forever: CharacterFrame:UpdateSize makes it 631 wide (398 model pane, 233 stats pane), or 398
-- with the stats pane collapsed.

local Sheet = FrogLib:Module("Sheet", 1)
if not Sheet then return end

Sheet.extras = Sheet.extras or { left = {}, right = {} }

function Sheet.SetExtra(owner, side, px)
    Sheet.extras[side][owner] = px or 0
end

local function Sum(side)
    local n = 0
    for _, px in pairs(Sheet.extras[side]) do n = n + px end
    return n
end

function Sheet.Width()
    local cf = _G.CharacterFrame
    local collapsed = cf and cf.IsRightPaneCollapsed and cf:IsRightPaneCollapsed()
    if collapsed then return (CHARACTER_FRAME_COLLAPSED_WIDTH or 398) + Sum("left") end
    return (CHARACTER_FRAME_WIDTH or 631) + Sum("left") + Sum("right")
end
