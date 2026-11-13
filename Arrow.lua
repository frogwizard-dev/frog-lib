-- FrogLib Arrow: a waypoint arrow (Media\Arrow.tga) that turns to point at a place, green when it's
-- ahead, through yellow to red when it's behind you, with a line of text under it (how far) and a
-- smaller one (what's there). Drag it to move it. FrogRoute's. Positions and facing the game keeps
-- secret (instances) hide the arrow.

local Arrow = FrogLib:Module("Arrow", 1)
if not Arrow then return end

local ADDON = ...
local HOME = ADDON == "FrogLib" and "Interface\\AddOns\\FrogLib\\"
    or ("Interface\\AddOns\\" .. ADDON .. "\\Libs\\FrogLib\\")
local TEXTURE = HOME .. "Media\\Arrow"

local issecret = FrogLib.issecret

-- 0: straight ahead (green) .. pi: behind (red), through yellow.
local function Color(angle)
    local fraction = math.abs(angle) / math.pi
    if fraction < 0.5 then return fraction * 2, 1, 0.2 end
    return 1, 1 - (fraction - 0.5) * 2, 0.2
end

-- The player's position (north, west, instance), or nil where the game won't say.
local function Player()
    local north, west, _, instance = UnitPosition("player")
    if not north or issecret(north) then return end
    return north, west, instance
end

local function Facing()
    local facing = GetPlayerFacing()
    if facing and not issecret(facing) then return facing end
end

-- The angle to turn the arrow by (radians, counter-clockwise) for a place `north` and `west` of
-- you, facing `facing`.
local function Angle(north, west, facing)
    local angle = math.atan2(west, north) - facing
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local Methods = {}

local function Yards(distance) return string.format("%d yd", distance) end

-- A place, in UnitPosition's order (north, west, and its instance); nil hides the arrow.
function Methods:SetTarget(north, west, instance, label)
    self.north, self.west, self.instance = north, west, instance
    if self.labelText ~= label then
        self.labelText = label
        self.label:SetText(label or "")
    end
    self.box:SetAlpha(north and 1 or 0)
    if not north then
        self.texture:Hide()
        self.distance:SetText("")
    end
end

-- Format(yards) -> the line under the arrow (default "123 yd").
function Methods:SetText(Format) self.Format = Format end

-- Shown instead of the arrow when the place is on another map.
function Methods:Elsewhere(text) self.elsewhere = text end

function Methods:Place()
    local frame = self.frame
    frame:ClearAllPoints()
    local point = self.opts.point and self.opts.point()
    if point then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", point[1], point[2])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end
end

local function OnUpdate(frame, elapsed)
    local arrow = frame.arrow
    arrow.elapsed = (arrow.elapsed or 0) + elapsed
    if arrow.elapsed < 0.03 then return end
    arrow.elapsed = 0
    if not arrow.north then return end
    local north, west, instance = Player()
    local facing = Facing()
    if north and facing and instance == arrow.instance then
        local ahead, across = arrow.north - north, arrow.west - west
        local angle = Angle(ahead, across, facing)
        arrow.texture:Show()
        arrow.texture:SetRotation(angle)
        arrow.texture:SetVertexColor(Color(angle))
        arrow.distance:SetText((arrow.Format or Yards)(math.sqrt(ahead * ahead + across * across)))
    else
        arrow.texture:Hide()
        arrow.distance:SetText(arrow.elsewhere or "")
    end
end

-- opts.point() -> { x, y }: its saved centre in UIParent pixels, or nil (above the centre);
-- opts.save({ x, y }) where it was dragged to; opts.locked() -> true while it can't be dragged.
function Arrow.New(name, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(56, 56)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    local arrow = setmetatable({ frame = frame, opts = opts }, { __index = Methods })
    frame.arrow = arrow
    frame:SetScript("OnDragStart", function()
        if not (opts.locked and opts.locked()) then frame:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local x, y = frame:GetCenter()
        if opts.save then opts.save({ x * scale, y * scale }) end
        frame:SetUserPlaced(false)
        arrow:Place()
    end)
    arrow.texture = frame:CreateTexture(nil, "ARTWORK")
    arrow.texture:SetTexture(TEXTURE)
    arrow.texture:SetAllPoints()
    arrow.texture:Hide()
    -- The words under it.
    arrow.box = CreateFrame("Frame", nil, frame)
    arrow.box:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    arrow.box:SetSize(220, 30)
    arrow.distance = arrow.box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrow.distance:SetPoint("TOP")
    arrow.label = arrow.box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow.label:SetPoint("TOP", arrow.distance, "BOTTOM", 0, -2)
    arrow.label:SetWidth(220)
    arrow.label:SetWordWrap(false)
    arrow.label:SetTextColor(0.75, 0.75, 0.78)
    arrow.box:SetAlpha(0)
    frame:SetScript("OnUpdate", OnUpdate)
    arrow:Place()
    return arrow
end
