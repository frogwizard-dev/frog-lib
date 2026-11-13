-- FrogLib Gauge: FFXIV gauges (XIVPlayer, XIVTarget, XIVExp, EnmityList) in two styles: "line", a
-- hair-thin bright line with a soft glow and a spark at the fill's end (the modern target bar), and
-- "framed", a capsule in a gold rim with a dark track and a glossy fill (the classic HP/MP/TP bar).
-- Both have round ends. Gauges keep their methods in this part's tables, so a newer copy's apply.

local Gauge = FrogLib:Module("Gauge", 2) -- 2: incoming heals
if not Gauge then return end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a soft-edged white circle
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

local GOLD_TOP = { 0.92, 0.80, 0.50 }
local GOLD_BOTTOM = { 0.66, 0.51, 0.27 }
local RIM = 2 -- gold rim thickness in the framed style

Gauge.Methods = Gauge.Methods or {}
local Methods = Gauge.Methods
Gauge.Meta = Gauge.Meta or {}
Gauge.Meta.__index = Methods
-- The shield methods alone, for another addon's own bars (FrogTarget's): they need .bar, a
-- StatusBar, and AnchorAbsorb() again whenever its fill texture is replaced.
Gauge.Absorb = Gauge.Absorb or {}
local Absorb = Gauge.Absorb

local function Texture(bar, layer, sublevel, file)
    local texture = bar:CreateTexture(nil, layer, nil, sublevel)
    if not texture:SetTexture(file or WHITE) then texture:SetTexture(WHITE) end
    return texture
end

-- A round end: an ordinary texture cut to a circle by a mask, so it can carry the same bar
-- texture or gradient as the straight part it finishes.
local function Cap(bar, layer, sublevel)
    local cap = Texture(bar, layer, sublevel)
    local mask = bar:CreateMaskTexture()
    mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    cap:AddMaskTexture(mask)
    cap.mask = mask
    return cap
end

-- A round end on `point` of `region`, only its outer half drawn: an overlap with the straight part
-- would show as a darker circle once the gauge is faded, as each piece is blended on its own.
local function PlaceCap(cap, region, point, side, diameter)
    cap:ClearAllPoints()
    cap:SetSize(diameter / 2, diameter)
    cap:SetPoint(side == "left" and "RIGHT" or "LEFT", region, point)
    cap.mask:ClearAllPoints()
    cap.mask:SetSize(diameter, diameter)
    cap.mask:SetPoint("CENTER", region, point)
end

local function Glow(bar, fill, side)
    local glow = Texture(bar, "ARTWORK", 1)
    glow:SetBlendMode("ADD")
    if side == "TOP" then
        glow:SetPoint("BOTTOMLEFT", fill, "TOPLEFT")
        glow:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT")
    else
        glow:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
        glow:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT")
    end
    return glow
end

-- gauge.bar is the StatusBar to place.
function Gauge.New(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local gauge = setmetatable({ bar = bar, style = "line", h = 3 }, Gauge.Meta)

    -- Framed style: gold rim capsule (hidden in the line style).
    gauge.rim = Texture(bar, "BACKGROUND", -8)
    gauge.rimL = Cap(bar, "BACKGROUND", -8)
    gauge.rimR = Cap(bar, "BACKGROUND", -8)

    -- Track for the missing part.
    gauge.track = Texture(bar, "BACKGROUND", -4)
    gauge.trackCap = Cap(bar, "BACKGROUND", -4)
    gauge.trackCapL = Cap(bar, "BACKGROUND", -4)

    -- Round ends of the fill itself, drawn with the bar texture (see SetTexture); all ends are
    -- placed in Layout and Anchor, once the height is known.
    gauge.startCap = Cap(bar, "ARTWORK", 0)
    gauge.endCap = Cap(bar, "ARTWORK", 0)

    -- Line style: glow above and below, spark at the fill's end.
    local fill = bar:GetStatusBarTexture()
    gauge.glowTop = Glow(bar, fill, "TOP")
    gauge.glowBottom = Glow(bar, fill, "BOTTOM")
    gauge.spark = Texture(bar, "OVERLAY", 0, SPARK)
    gauge.spark:SetBlendMode("ADD")

    -- Framed style: glossy highlight along the top of the fill, carried round both ends by
    -- sharing each end's circular mask.
    local clear, shine = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.4)
    gauge.sheen = Texture(bar, "ARTWORK", 3)
    gauge.sheen:SetGradient("VERTICAL", clear, shine)
    gauge.sheenL = Texture(bar, "ARTWORK", 3)
    gauge.sheenL:SetGradient("VERTICAL", clear, shine)
    gauge.sheenL:SetPoint("TOPLEFT", gauge.startCap, "TOPLEFT")
    gauge.sheenL:SetPoint("TOPRIGHT", gauge.startCap, "TOPRIGHT")
    gauge.sheenL:AddMaskTexture(gauge.startCap.mask)
    gauge.sheenR = Texture(bar, "ARTWORK", 3)
    gauge.sheenR:SetGradient("VERTICAL", clear, shine)
    gauge.sheenR:AddMaskTexture(gauge.endCap.mask)

    gauge:Anchor()
    gauge:Layout()
    return gauge
end

-- Everything that follows the fill's edge; the fill texture is replaced when the bar
-- texture changes, so this re-runs then.
function Methods:Anchor()
    local fill = self.bar:GetStatusBarTexture()
    for _, glow in ipairs({ self.glowTop, self.glowBottom }) do glow:ClearAllPoints() end
    self.glowTop:SetPoint("BOTTOMLEFT", fill, "TOPLEFT")
    self.glowTop:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT")
    self.glowBottom:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
    self.glowBottom:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT")
    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", fill, "RIGHT")
    PlaceCap(self.endCap, fill, "RIGHT", "right", self.h)
    self.sheenR:ClearAllPoints()
    self.sheenR:SetPoint("TOPLEFT", self.endCap, "TOPLEFT")
    self.sheenR:SetPoint("TOPRIGHT", self.endCap, "TOPRIGHT")
    self.sheen:ClearAllPoints()
    self.sheen:SetPoint("TOPLEFT", fill, "TOPLEFT")
    self.sheen:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    if self.heal then self.heal:Anchor() end
    if self.absorb then self:AnchorAbsorb() end
end

function Methods:Layout()
    local height, framed = self.h, self.style == "framed"
    self.bar:SetHeight(height)

    -- Dark border around the fill: 1px in the line style, 2px inside the gold rim.
    local pad = framed and 2 or 1
    self.track:ClearAllPoints()
    self.track:SetPoint("TOPLEFT", 0, pad)
    self.track:SetPoint("BOTTOMRIGHT", 0, -pad)
    if framed then
        self.track:SetVertexColor(0.07, 0.05, 0.03, 0.95)
    else
        self.track:SetVertexColor(0, 0, 0, 0.45)
    end
    self.trackCap:SetVertexColor(self.track:GetVertexColor())
    self.trackCapL:SetVertexColor(self.track:GetVertexColor())
    PlaceCap(self.trackCap, self.bar, "RIGHT", "right", height + pad * 2)
    PlaceCap(self.trackCapL, self.bar, "LEFT", "left", height + pad * 2)
    self.trackCapL:SetShown(framed)

    local outer = pad + RIM
    self.rim:ClearAllPoints()
    self.rim:SetPoint("TOPLEFT", 0, outer)
    self.rim:SetPoint("BOTTOMRIGHT", 0, -outer)
    -- The rim's ends are exactly as tall as its straight part, so the same gradient lines up.
    local bottom = CreateColor(GOLD_BOTTOM[1], GOLD_BOTTOM[2], GOLD_BOTTOM[3], 1)
    local top = CreateColor(GOLD_TOP[1], GOLD_TOP[2], GOLD_TOP[3], 1)
    self.rim:SetGradient("VERTICAL", bottom, top)
    PlaceCap(self.rimL, self.bar, "LEFT", "left", height + outer * 2)
    PlaceCap(self.rimR, self.bar, "RIGHT", "right", height + outer * 2)
    for _, cap in ipairs({ self.rimL, self.rimR }) do
        cap:SetGradient("VERTICAL", bottom, top)
    end
    for _, part in ipairs({ self.rim, self.rimL, self.rimR }) do part:SetShown(framed) end

    PlaceCap(self.startCap, self.bar, "LEFT", "left", height)
    PlaceCap(self.endCap, self.bar:GetStatusBarTexture(), "RIGHT", "right", height)

    -- The glow suits a hair-thin line; capped so a thick bar in line style doesn't turn into
    -- a haze, and faded further the thicker the bar (see SetColor).
    local glow = math.min(4, math.max(2, height + 1))
    self.glowTop:SetHeight(glow)
    self.glowBottom:SetHeight(glow)
    self.glowAlpha = 0.45 * math.max(0.3, math.min(1, 3 / height))
    self.spark:SetSize(math.min(12, math.max(8, height * 2)), height + glow * 2)
    for _, part in ipairs({ self.glowTop, self.glowBottom, self.spark }) do part:SetShown(not framed) end

    local sheenHeight = math.max(1, math.floor(height * 0.45))
    for _, sheen in ipairs({ self.sheen, self.sheenL, self.sheenR }) do
        sheen:SetHeight(sheenHeight)
        sheen:SetShown(framed)
    end

    if self.color then self:SetColor(unpack(self.color)) end
end

-- "line" or "framed".
function Methods:SetStyle(style)
    self.style = style
    self:Layout()
end

function Methods:SetHeight(height)
    self.h = height
    self:Layout()
end

-- The fill's round ends use a thin slice of the same texture, so a shaded or glossy bar
-- texture carries its vertical shading into the curve.
function Methods:SetTexture(path)
    self.texture = path
    self.bar:SetStatusBarTexture(path)
    if self.heal then self.heal:SetTexture(path) end
    for _, cap in ipairs({ self.startCap, self.endCap }) do
        if not cap:SetTexture(path) then cap:SetTexture(WHITE) end
        cap:SetTexCoord(0, 0.02, 0, 1)
    end
    self:Anchor()
end

-- Line style draws the core lighter than the tint so it reads as a lit line, with the glow
-- carrying the colour; framed style uses the colour as-is under its sheen.
function Methods:SetColor(r, g, b)
    self.color = { r, g, b }
    local coreR, coreG, coreB = r, g, b
    if self.style ~= "framed" then
        coreR, coreG, coreB = r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
    end
    self.bar:SetStatusBarColor(coreR, coreG, coreB)
    self.startCap:SetVertexColor(coreR, coreG, coreB)
    self.endCap:SetVertexColor(coreR, coreG, coreB)
    local near, far = CreateColor(r, g, b, self.glowAlpha or 0.45), CreateColor(r, g, b, 0)
    self.glowTop:SetGradient("VERTICAL", near, far)
    self.glowBottom:SetGradient("VERTICAL", far, near)
    self.spark:SetVertexColor(r + (1 - r) * 0.6, g + (1 - g) * 0.6, b + (1 - b) * 0.6, 0.9)
end

-- Values may be secret; StatusBar setters accept them directly.
function Methods:SetValues(value, max, instant)
    self.bar:SetMinMaxValues(0, max)
    self.bar:SetValue(value, instant and IMMEDIATE or SMOOTH)
end

------------------------------------------------------------------------------
-- Absorb shields (optional: EnableAbsorb once, then SetAbsorb)
------------------------------------------------------------------------------

-- A shield fills the missing part from the fill's edge (or the incoming heals' end), and what doesn't
-- fit lies over the fill's right end. The amount can be secret, so it's split by clipping:
--   ahead: a bar starting at the fill's edge, clipped to the missing part -> min(shield, missing)
--   over:  a right-to-left bar across the gauge, clipped to the fill      -> max(0, shield - missing)
-- (With heals in the way, the part they push past the end only shows once they land.)
local SHIELD_STRIPES = "Interface\\RaidFrame\\Shield-Overlay" -- Blizzard's diagonal shield stripes

local function ShieldBar(parent)
    local shield = CreateFrame("StatusBar", nil, parent)
    shield:SetStatusBarTexture(WHITE)
    shield:SetMinMaxValues(0, 1)
    shield:SetValue(0)
    local stripes = shield:CreateTexture(nil, "ARTWORK", nil, 1)
    shield.hasStripes = stripes:SetTexture(SHIELD_STRIPES, "REPEAT", "REPEAT") and true or false
    stripes:SetHorizTile(true)
    stripes:SetVertTile(true)
    stripes:SetAllPoints(shield:GetStatusBarTexture())
    shield.stripes = stripes
    return shield
end

function Absorb:EnableAbsorb()
    if self.absorb then return end
    local bar = self.bar
    local shields = {}
    shields.missClip = CreateFrame("Frame", nil, bar)
    shields.missClip:SetClipsChildren(true)
    shields.ahead = ShieldBar(shields.missClip)
    shields.fillClip = CreateFrame("Frame", nil, bar)
    shields.fillClip:SetClipsChildren(true)
    shields.over = ShieldBar(shields.fillClip)
    shields.over:SetReverseFill(true)
    shields.over:SetAllPoints(bar)
    for _, clip in ipairs({ shields.missClip, shields.fillClip }) do clip:SetFrameLevel(bar:GetFrameLevel() + 2) end
    -- The ahead bar is as long as the whole gauge, so a full-size shield can reach its end.
    bar:HookScript("OnSizeChanged", function(_, width) shields.ahead:SetWidth(width) end)
    shields.ahead:SetWidth(bar:GetWidth())
    self.absorb = shields
    self:AnchorAbsorb()
    self:SetAbsorbColor(1, 1, 1)
end

-- Follows the fill's edge; re-run when the fill texture is replaced (see Anchor).
function Absorb:AnchorAbsorb()
    local shields = self.absorb
    if not shields then return end
    local bar, fill = self.bar, self.bar:GetStatusBarTexture()
    local heal = self.heal
    local edge = (heal and heal.shown) and heal:End() or fill
    shields.missClip:ClearAllPoints()
    shields.missClip:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    shields.missClip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    shields.ahead:ClearAllPoints()
    shields.ahead:SetPoint("TOPLEFT", edge, "TOPRIGHT")
    shields.ahead:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT")
    shields.fillClip:ClearAllPoints()
    shields.fillClip:SetPoint("TOPLEFT", bar, "TOPLEFT")
    shields.fillClip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
end

-- Faint fill with bright stripes; a plainer, stronger fill if the stripe texture is missing.
function Absorb:SetAbsorbColor(r, g, b)
    local shields = self.absorb
    if not shields then return end
    for _, shield in ipairs({ shields.ahead, shields.over }) do
        shield:SetStatusBarColor(r, g, b, shield.hasStripes and 0.25 or 0.55)
        shield.stripes:SetVertexColor(r, g, b, 0.85)
    end
end

function Absorb:SetAbsorb(value, max)
    local shields = self.absorb
    if not shields then return end
    for _, shield in ipairs({ shields.ahead, shields.over }) do
        shield:SetMinMaxValues(0, max)
        shield:SetValue(value)
    end
end

function Absorb:ShowAbsorb(shown)
    local shields = self.absorb
    if not shields then return end
    shields.missClip:SetShown(shown)
    shields.fillClip:SetShown(shown)
end

------------------------------------------------------------------------------
-- Incoming heals (optional: EnableHeal once, then UpdateHeal)
------------------------------------------------------------------------------

-- FrogLib.Predict's bars from the fill's edge, under any shield (which starts where they end):
-- your heals on their way, then everyone else's, in Blizzard's teal (its own frames' colour, yours
-- a touch stronger). They ease like the fill, so as a heal lands the fill grows into it.
local HEAL_COLOR = { 0.0, 0.659, 0.608 } -- Blizzard's HEAL_PREDICTION_COLOR
local HEAL_ALPHA = { mine = 0.8, others = 0.6 }

function Methods:EnableHeal()
    if self.heal then return end
    self.heal = FrogLib.Predict.New(self.bar, { parts = { "mine", "others" }, ease = true, level = 1 })
    if self.texture then self.heal:SetTexture(self.texture) end
    self:SetHealColor(unpack(HEAL_COLOR))
    if self.absorb then self:AnchorAbsorb() end
end

function Methods:UpdateHeal(unit, instant)
    if self.heal then self.heal:Update(unit, instant) end
end

function Methods:ShowHeal(shown)
    local heal = self.heal
    if not heal then return end
    shown = shown and true or false
    if heal.shown == shown then return end
    heal:SetShown(shown)
    if self.absorb then self:AnchorAbsorb() end
end

function Methods:SetHealColor(r, g, b)
    local heal = self.heal
    if not heal then return end
    for key, alpha in pairs(HEAL_ALPHA) do heal:SetColor(key, r, g, b, alpha) end
end

for name, method in pairs(Absorb) do Methods[name] = method end
