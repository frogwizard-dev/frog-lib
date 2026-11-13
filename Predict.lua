-- FrogLib Predict: heal prediction on a health bar, as Blizzard's frames draw it (FrogFrames' unit
-- frames, and the FFXIV gauges through Gauge:EnableHeal): your incoming heals, everyone else's and
-- damage shields, each a bar of its own, one after the other from the end of the health bar's fill.
--
--   local p = FrogLib.Predict.New(healthBar, opts)   healthBar: a StatusBar
--     opts.parts  which bars, in order (default { "mine", "others", "shield" })
--     opts.colors { mine = { r, g, b, a }, ... } in place of the defaults
--     opts.ease   ease to new amounts (SetValue's smooth interpolation), as a gauge's fill does
--     opts.level  the bars' frame level above healthBar's (default: just above it)
--   p:Update(unit, instant)                  read the unit's amounts and draw them
--   p:SetValues(max, { mine = n, ... }, instant)  draw given amounts (a sample while unlocked)
--   p:SetShown(shown), p:SetColor(part, r, g, b, a), p:SetTexture(path)
--   p:Anchor()   again whenever healthBar's fill texture is replaced
--   p:End()      the last bar's fill texture, to start something else where the prediction ends
--   FrogLib.Predict.Read(unit, calc) -> max, mine, others, shield (any of them may be secret)
--
-- The amounts can be secret, so they're never added up here: each bar is as wide as the health
-- bar, set from 0 to the unit's maximum health and given its amount (status bars take secret
-- values), and starts where the one before it ends (the fill texture's right edge). The game's own
-- heal prediction calculator splits yours from others' and caps them at the health that's
-- missing; anything past the health bar's end is cut off.
-- Predictions keep their methods in this part's tables, so a newer copy's apply to them.

local Predict = FrogLib:Module("Predict", 1)
if not Predict then return end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

Predict.PARTS = { "mine", "others", "shield" }
Predict.COLORS = { mine = { 0.35, 1, 0.45, 0.65 }, others = { 0.1, 0.7, 0.3, 0.55 }, shield = { 1, 1, 1, 0.5 } }

Predict.Methods = Predict.Methods or {}
local P = Predict.Methods
Predict.Meta = Predict.Meta or {}
Predict.Meta.__index = P

-- calc: one from CreateUnitHealPredictionCalculator, where the game has it. Without one, all
-- incoming heals count as "mine" (splitting them would take sums the secret values don't allow).
function Predict.Read(unit, calc)
    local max = UnitHealthMax(unit)
    if calc and UnitGetDetailedHealPrediction then
        pcall(UnitGetDetailedHealPrediction, unit, "player", calc)
        local _, mine, others = calc:GetIncomingHeals()
        return max, mine, others, (calc:GetDamageAbsorbs())
    end
    local mine = UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
    local shield = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
    return max, mine, 0, shield
end

function Predict.New(bar, opts)
    opts = opts or {}
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints()
    clip:SetClipsChildren(true)
    if opts.level then clip:SetFrameLevel(bar:GetFrameLevel() + opts.level) end
    local p = setmetatable({ bar = bar, clip = clip, parts = opts.parts or Predict.PARTS,
        ease = opts.ease, shown = true }, Predict.Meta)
    if CreateUnitHealPredictionCalculator then p.calc = CreateUnitHealPredictionCalculator() end
    for _, key in ipairs(p.parts) do
        local s = CreateFrame("StatusBar", nil, clip)
        s:SetStatusBarTexture(WHITE)
        s:SetMinMaxValues(0, 1)
        s:SetValue(0)
        p[key] = s
        local c = (opts.colors and opts.colors[key]) or Predict.COLORS[key] or Predict.COLORS.mine
        p:SetColor(key, c[1], c[2], c[3], c[4])
    end
    local function Size()
        local w = math.max(1, bar:GetWidth())
        for _, key in ipairs(p.parts) do p[key]:SetWidth(w) end
    end
    bar:HookScript("OnSizeChanged", Size)
    Size()
    p:Anchor()
    return p
end

function P:Anchor()
    local after = self.bar:GetStatusBarTexture()
    for _, key in ipairs(self.parts) do
        local s = self[key]
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", after, "TOPRIGHT")
        s:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
        after = s:GetStatusBarTexture()
    end
end

function P:End()
    return self[self.parts[#self.parts]]:GetStatusBarTexture()
end

function P:SetColor(key, r, g, b, a)
    local s = self[key]
    if not s then return end
    s.color = { r, g, b, a or 1 }
    s:SetStatusBarColor(r, g, b, a or 1)
end

-- Each bar's fill texture can be a new one afterwards, so they're anchored again.
function P:SetTexture(path)
    for _, key in ipairs(self.parts) do
        local s = self[key]
        s:SetStatusBarTexture(path)
        if s.color then s:SetStatusBarColor(unpack(s.color)) end
    end
    self:Anchor()
end

function P:SetValues(max, values, instant)
    for _, key in ipairs(self.parts) do
        local s = self[key]
        s:SetMinMaxValues(0, max or 1)
        local v = values[key] or 0
        if self.ease then
            s:SetValue(v, instant and IMMEDIATE or SMOOTH)
        else
            s:SetValue(v)
        end
    end
end

function P:Update(unit, instant)
    local max, mine, others, shield = Predict.Read(unit, self.calc)
    self:SetValues(max, { mine = mine, others = others, shield = shield }, instant)
end

function P:SetShown(shown)
    self.shown = shown and true or false
    self.clip:SetShown(self.shown)
end
