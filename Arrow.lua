-- FrogLib Arrow: a waypoint arrow (Media\Arrow.tga) that turns to point at a place, green when
-- it's ahead, through yellow to red when it's behind you, with a line of text under it (how far)
-- and a smaller one (what's there). Drag it to move it. FrogRoute's.
--   local arrow = FrogLib.Arrow.New(name, opts)
--       opts.point() -> { x, y } (its saved centre, UIParent pixels) or nil (default: above centre)
--       opts.save({ x, y })        where it was dragged to
--       opts.locked() -> true      while it can't be dragged
--   arrow:SetTarget(x, y, instance, label)   a place (UnitPosition's order: north, west, and its
--                                            instance); nil hides the arrow
--   arrow:SetText(fn)              fn(yards) -> the line under the arrow (default "123 yd")
--   arrow:Elsewhere(text)          shown instead of the arrow when the place is on another map
--   arrow.frame                    the frame (show, hide, scale it)
-- Positions and facing the game keeps secret (instances) just hide the arrow.

local Arrow = FrogLib:Module("Arrow", 1)
if not Arrow then return end

local ADDON = ...
local HOME = ADDON == "FrogLib" and "Interface\\AddOns\\FrogLib\\"
    or ("Interface\\AddOns\\" .. ADDON .. "\\Libs\\FrogLib\\")
Arrow.TEXTURE = HOME .. "Media\\Arrow"

local issecret = FrogLib.issecret

-- 0: straight ahead (green) .. pi: behind (red), through yellow.
function Arrow.Color(angle)
    local t = math.abs(angle) / math.pi
    if t < 0.5 then return t * 2, 1, 0.2 end
    return 1, 1 - (t - 0.5) * 2, 0.2
end

-- The player's position (north, west, instance) and facing, or nil where the game won't say.
function Arrow.Player()
    local north, west, _, inst = UnitPosition("player")
    if not north or issecret(north) then return end
    return north, west, inst
end

function Arrow.Facing()
    local f = GetPlayerFacing()
    if f and not issecret(f) then return f end
end

-- The angle to turn the arrow by (radians, counter-clockwise) for a place dn north and dw west
-- of you, facing `facing`.
function Arrow.Angle(dn, dw, facing)
    local angle = math.atan2(dw, dn) - facing
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local Methods = {}

local function Yards(d) return string.format("%d yd", d) end

function Methods:SetTarget(x, y, inst, label)
    self.x, self.y, self.inst = x, y, inst
    if self.labelText ~= label then
        self.labelText = label
        self.label:SetText(label or "")
    end
    self.box:SetAlpha(x and 1 or 0)
    if not x then
        self.tex:Hide()
        self.dist:SetText("")
    end
end

function Methods:SetText(fn) self.textFn = fn end
function Methods:Elsewhere(text) self.elsewhere = text end

function Methods:Place()
    local f = self.frame
    f:ClearAllPoints()
    local p = self.opts.point and self.opts.point()
    if p then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end
end

local function OnUpdate(self, dt)
    local a = self.arrow
    a.elapsed = (a.elapsed or 0) + dt
    if a.elapsed < 0.03 then return end
    a.elapsed = 0
    if not a.x then return end
    local px, py, pinst = Arrow.Player()
    local facing = Arrow.Facing()
    if px and facing and pinst == a.inst then
        local dn, dw = a.x - px, a.y - py
        local angle = Arrow.Angle(dn, dw, facing)
        a.tex:Show()
        a.tex:SetRotation(angle)
        a.tex:SetVertexColor(Arrow.Color(angle))
        a.dist:SetText((a.textFn or Yards)(math.sqrt(dn * dn + dw * dw)))
    else
        a.tex:Hide()
        a.dist:SetText(a.elsewhere or "")
    end
end

function Arrow.New(name, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(56, 56)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    local a = setmetatable({ frame = f, opts = opts }, { __index = Methods })
    f.arrow = a
    f:SetScript("OnDragStart", function()
        if not (opts.locked and opts.locked()) then f:StartMoving() end
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local x, y = f:GetCenter()
        if opts.save then opts.save({ x * s, y * s }) end
        f:SetUserPlaced(false)
        a:Place()
    end)
    a.tex = f:CreateTexture(nil, "ARTWORK")
    a.tex:SetTexture(Arrow.TEXTURE)
    a.tex:SetAllPoints()
    a.tex:Hide()
    -- The words under it.
    a.box = CreateFrame("Frame", nil, f)
    a.box:SetPoint("TOP", f, "BOTTOM", 0, -2)
    a.box:SetSize(220, 30)
    a.dist = a.box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    a.dist:SetPoint("TOP")
    a.label = a.box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a.label:SetPoint("TOP", a.dist, "BOTTOM", 0, -2)
    a.label:SetWidth(220)
    a.label:SetWordWrap(false)
    a.label:SetTextColor(0.75, 0.75, 0.78)
    a.box:SetAlpha(0)
    f:SetScript("OnUpdate", OnUpdate)
    a:Place()
    return a
end
