-- FrogLib Grid: a layout grid over the screen while something is unlocked, and snapping to the
-- screen's horizontal centre: let go of a frame with its centre within SNAP of the middle and
-- it's centred exactly. The centre line lights up while a drag is near enough to snap.
--   FrogLib.Grid:SetShown(on, owner)                -- with the unlock; shown while any owner
--                                                      (an addon's name) wants it
--   FrogLib.Grid:Track(frame) / FrogLib.Grid:Track() -- from OnDragStart / OnDragStop
--   local p, rp, x, y = FrogLib.Grid:Snap(frame)     -- after StopMovingOrSizing: its point to save
-- One grid for every addon: its state lives in this part's table.

local Grid = FrogLib:Module("Grid", 1)
if not Grid then return end

local SPACING = 32 -- between lines, in interface units
local SNAP = 16    -- how near the middle snaps
local LINE = { 1, 1, 1, 0.08 }
local CENTRE = { 1, 0.82, 0, 0.45 }
local CENTRE_HOT = { 1, 0.82, 0, 1 }

Grid.owners = Grid.owners or {}

local function Pixel() return FrogLib.Pixel(UIParent) end

-- How far `frame`'s centre is from the screen's, across, in UIParent's units.
local function OffCentre(frame)
    local x = frame:GetCenter()
    if not x then return math.huge end
    return x * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() - UIParent:GetWidth() / 2
end

local function Build()
    local grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid.lines = {}
    grid:Hide()
    grid:SetScript("OnUpdate", function()
        local tracked = Grid.tracked
        local near = tracked and math.abs(OffCentre(tracked)) <= SNAP
        local c = near and CENTRE_HOT or CENTRE
        grid.centre:SetColorTexture(c[1], c[2], c[3], c[4])
        grid.centre:SetWidth(Pixel() * (near and 3 or 2))
    end)
    Grid.frame = grid
end

-- Lines out from the middle, so the centre ones land exactly on the centre.
local function Layout()
    local grid = Grid.frame
    local w, h, px = UIParent:GetWidth(), UIParent:GetHeight(), Pixel()
    local n = 0
    local function Add(vertical, offset, colour, thickness)
        n = n + 1
        local t = grid.lines[n]
        if not t then
            t = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[n] = t
        end
        t:ClearAllPoints()
        if vertical then
            t:SetPoint("TOP", grid, "TOP", offset, 0)
            t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
            t:SetWidth(px * thickness)
        else
            t:SetPoint("LEFT", grid, "LEFT", 0, offset)
            t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
            t:SetHeight(px * thickness)
        end
        t:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        t:Show()
        return t
    end
    for x = SPACING, w / 2, SPACING do
        Add(true, x, LINE, 1)
        Add(true, -x, LINE, 1)
    end
    for y = SPACING, h / 2, SPACING do
        Add(false, y, LINE, 1)
        Add(false, -y, LINE, 1)
    end
    Add(false, 0, CENTRE, 1)
    grid.centre = Add(true, 0, CENTRE, 2)
    for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

function Grid:SetShown(on, owner)
    Grid.owners[owner or "?"] = on and true or nil
    local want = next(Grid.owners) ~= nil
    if not Grid.frame then
        if not want then return end
        Build()
    end
    if want then Layout() end
    Grid.frame:SetShown(want)
end

function Grid:Track(frame)
    Grid.tracked = frame
end

function Grid:Snap(frame)
    if math.abs(OffCentre(frame)) <= SNAP then
        local top = frame:GetTop()
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "BOTTOM", 0, top)
        return "TOP", "BOTTOM", 0, top
    end
    local p, _, rp, x, y = frame:GetPoint()
    return p, rp, x, y
end
