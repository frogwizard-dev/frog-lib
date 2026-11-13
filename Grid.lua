-- FrogLib Grid: a layout grid over the screen while something is unlocked, and snapping to the
-- screen's horizontal centre: let go of a frame with its centre within SNAP of the middle and it's
-- centred exactly (the centre line lights up while it's near enough). One grid for every addon:
-- its state lives in this part's table.

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
        local colour = near and CENTRE_HOT or CENTRE
        grid.centre:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        grid.centre:SetWidth(Pixel() * (near and 3 or 2))
    end)
    Grid.frame = grid
end

-- Lines out from the middle, so the centre ones land exactly on the centre.
local function Layout()
    local grid = Grid.frame
    local width, height, pixel = UIParent:GetWidth(), UIParent:GetHeight(), Pixel()
    local count = 0
    local function Add(vertical, offset, colour, thickness)
        count = count + 1
        local line = grid.lines[count]
        if not line then
            line = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[count] = line
        end
        line:ClearAllPoints()
        if vertical then
            line:SetPoint("TOP", grid, "TOP", offset, 0)
            line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
            line:SetWidth(pixel * thickness)
        else
            line:SetPoint("LEFT", grid, "LEFT", 0, offset)
            line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
            line:SetHeight(pixel * thickness)
        end
        line:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        line:Show()
        return line
    end
    for x = SPACING, width / 2, SPACING do
        Add(true, x, LINE, 1)
        Add(true, -x, LINE, 1)
    end
    for y = SPACING, height / 2, SPACING do
        Add(false, y, LINE, 1)
        Add(false, -y, LINE, 1)
    end
    Add(false, 0, CENTRE, 1)
    grid.centre = Add(true, 0, CENTRE, 2)
    for i = count + 1, #grid.lines do grid.lines[i]:Hide() end
end

-- With the unlock: shown while any owner (an addon's name) wants it.
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

-- From OnDragStart (the frame) and OnDragStop (nil).
function Grid:Track(frame)
    Grid.tracked = frame
end

-- After StopMovingOrSizing: the frame's point to save (point, relativePoint, x, y).
function Grid:Snap(frame)
    if math.abs(OffCentre(frame)) <= SNAP then
        local top = frame:GetTop()
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "BOTTOM", 0, top)
        return "TOP", "BOTTOM", 0, top
    end
    local point, _, relativePoint, x, y = frame:GetPoint()
    return point, relativePoint, x, y
end
