-- FrogLib Predict: heal prediction on a health bar, as Blizzard's frames draw it (FrogFrames' unit
-- frames, and the FFXIV gauges through Gauge:EnableHeal): your incoming heals, everyone else's and
-- damage shields, each a bar of its own, one after the other from the end of the health bar's fill.
-- Predictions keep their methods in this part's tables, so a newer copy's apply to them.

local Predict = FrogLib:Module("Predict", 2) -- 2: nothing made or written again on an update
if not Predict then return end

local issecret = FrogLib.issecret
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

Predict.PARTS = { "mine", "others", "shield" }
Predict.COLORS = { mine = { 0.35, 1, 0.45, 0.65 }, others = { 0.1, 0.7, 0.3, 0.55 }, shield = { 1, 1, 1, 0.5 } }

Predict.Methods = Predict.Methods or {}
local Prediction = Predict.Methods
Predict.Meta = Predict.Meta or {}
Predict.Meta.__index = Prediction

-- max, mine, others, shield (any may be secret). calculator: one from
-- CreateUnitHealPredictionCalculator; without one, all incoming heals count as "mine".
function Predict.Read(unit, calculator)
    local max = UnitHealthMax(unit)
    if calculator and UnitGetDetailedHealPrediction then
        pcall(UnitGetDetailedHealPrediction, unit, "player", calculator)
        local _, mine, others = calculator:GetIncomingHeals()
        return max, mine, others, (calculator:GetDamageAbsorbs())
    end
    local mine = UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
    local shield = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
    return max, mine, 0, shield
end

-- The amounts can be secret, so they're never added up: each bar is as wide as the health bar, set
-- from 0 to the unit's maximum health, and starts where the one before it ends (cut off past the end).
function Predict.New(bar, opts)
    -- opts.parts: which bars, in order (default PARTS); opts.colors: { mine = { r, g, b, a }, ... };
    -- opts.ease: ease to new amounts, as a gauge's fill does; opts.level: frame levels above the bar.
    opts = opts or {}
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints()
    clip:SetClipsChildren(true)
    if opts.level then clip:SetFrameLevel(bar:GetFrameLevel() + opts.level) end
    local prediction = setmetatable({ bar = bar, clip = clip, parts = opts.parts or Predict.PARTS,
        ease = opts.ease, shown = true }, Predict.Meta)
    if CreateUnitHealPredictionCalculator then prediction.calculator = CreateUnitHealPredictionCalculator() end
    for _, key in ipairs(prediction.parts) do
        local part = CreateFrame("StatusBar", nil, clip)
        part:SetStatusBarTexture(WHITE)
        part:SetMinMaxValues(0, 1)
        part:SetValue(0)
        prediction[key] = part
        local color = (opts.colors and opts.colors[key]) or Predict.COLORS[key] or Predict.COLORS.mine
        prediction:SetColor(key, color[1], color[2], color[3], color[4])
    end
    local function Size()
        local width = math.max(1, bar:GetWidth())
        for _, key in ipairs(prediction.parts) do prediction[key]:SetWidth(width) end
    end
    bar:HookScript("OnSizeChanged", Size)
    Size()
    prediction:Anchor()
    return prediction
end

-- Again whenever the health bar's fill texture is replaced.
function Prediction:Anchor()
    local after = self.bar:GetStatusBarTexture()
    for _, key in ipairs(self.parts) do
        local part = self[key]
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", after, "TOPRIGHT")
        part:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
        after = part:GetStatusBarTexture()
    end
end

-- The last bar's fill texture, to start something else where the prediction ends.
function Prediction:End()
    return self[self.parts[#self.parts]]:GetStatusBarTexture()
end

function Prediction:SetColor(key, r, g, b, a)
    local part = self[key]
    if not part then return end
    part.color = { r, g, b, a or 1 }
    part:SetStatusBarColor(r, g, b, a or 1)
end

-- Each bar's fill texture can be a new one afterwards, so they're anchored again.
function Prediction:SetTexture(path)
    for _, key in ipairs(self.parts) do
        local part = self[key]
        part:SetStatusBarTexture(path)
        if part.color then part:SetStatusBarColor(unpack(part.color)) end
    end
    self:Anchor()
end

-- Given amounts ({ mine = amount, ... }; a sample while unlocked). The maximum goes on only when
-- it's new (or secret, so it can't be told).
function Prediction:SetValues(max, values, instant)
    max = max or 1
    local secret = issecret(max)
    for _, key in ipairs(self.parts) do
        local part = self[key]
        if secret or part.lastMax ~= max then
            part:SetMinMaxValues(0, max)
            part.lastMax = not secret and max or nil
        end
        local value = values[key] or 0
        if self.ease then
            part:SetValue(value, instant and IMMEDIATE or SMOOTH)
        else
            part:SetValue(value)
        end
    end
end

-- One table for every update: SetValues reads the amounts at once and keeps none.
local amounts = {}

-- The unit's amounts, read and drawn.
function Prediction:Update(unit, instant)
    local max
    max, amounts.mine, amounts.others, amounts.shield = Predict.Read(unit, self.calculator)
    self:SetValues(max, amounts, instant)
    amounts.mine, amounts.others, amounts.shield = nil, nil, nil
end

function Prediction:SetShown(shown)
    shown = shown and true or false
    if self.shown == shown then return end
    self.shown = shown
    self.clip:SetShown(shown)
end
