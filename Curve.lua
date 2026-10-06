-- FrogLib Curve: step curves the game reads a unit's health or power through, so a value it keeps
-- secret can still decide something on screen (an opacity, say): the answer comes back secret too,
-- and goes straight into a widget (SetAlpha takes secrets), never looked at here.
--   FrogLib.Curve.Step(key, points) -> a step curve through points ({ { x, y }, ... }, x the
--       fraction 0 to 1), made once per key and kept; nil when the client has no curves.
--   FrogLib.Curve.Below(line, under, over) -> `under` below the fraction `line`, `over` from it up
--       (an execute range: Below(0.2, 1, 0)); a pair of points either side of the line keeps it
--       sharp however the game steps through it.
--   FrogLib.Curve.Empty()           -> 0 when empty, 1 otherwise (an empty power bar fading out)
--   FrogLib.Curve.Full(atFull, below) -> `below` (default 1) under full, `atFull` at full (a fade
--       that only happens at full health)
--   FrogLib.Curve.Health(unit, curve), FrogLib.Curve.Power(unit, curve, powerType)
--       -> the curve's value at the unit's health or power fraction (may be secret), or nil when
--       the game can't say (no curve, an old client, an odd unit).

local Curve = FrogLib:Module("Curve", 1)
if not Curve then return end

local issecret = FrogLib.issecret
local EDGE = 0.0001 -- how close to a line its last point below sits

-- Kept across newer copies of this part: a curve made by an older one serves as well.
Curve.cache = Curve.cache or {} -- [key] = curve, or false when the client couldn't make one

local function Make(points)
    local curve = C_CurveUtil.CreateCurve()
    if not curve then return false end
    if Enum and Enum.LuaCurveType and curve.SetType then
        pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    end
    for _, p in ipairs(points) do curve:AddPoint(p[1], p[2]) end
    return curve
end

function Curve.Step(key, points)
    local cached = Curve.cache[key]
    if cached ~= nil then return cached or nil end
    local curve = false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        local ok, made = pcall(Make, points)
        if ok and made then curve = made end
    end
    Curve.cache[key] = curve
    return curve or nil
end

function Curve.Below(line, under, over)
    local key = string.format("below:%.4f:%.4f:%.4f", line, under, over)
    local cached = Curve.cache[key]
    if cached ~= nil then return cached or nil end
    local points = {}
    if line > 0 then
        points[#points + 1] = { 0, under }
        if line - EDGE > 0 then points[#points + 1] = { line - EDGE, under } end
    end
    points[#points + 1] = { line, over }
    if line < 1 then points[#points + 1] = { 1, over } end
    return Curve.Step(key, points)
end

function Curve.Empty()
    return Curve.Below(EDGE, 0, 1)
end

function Curve.Full(atFull, below)
    return Curve.Below(1, below or 1, atFull)
end

-- What came back, if it's a number (secret or not).
local function Result(ok, value)
    if ok and (issecret(value) or type(value) == "number") then return value end
    return nil
end

function Curve.Health(unit, curve)
    if not (curve and UnitHealthPercent) then return nil end
    return Result(pcall(UnitHealthPercent, unit, true, curve))
end

function Curve.Power(unit, curve, powerType)
    if not (curve and UnitPowerPercent) then return nil end
    return Result(pcall(UnitPowerPercent, unit, powerType, false, curve))
end
