-- FrogLib Curve: step curves the game reads a unit's health or power through, so a value it keeps
-- secret can still decide something on screen (an opacity, say): the answer comes back secret too,
-- and goes straight into a widget (SetAlpha takes secrets), never looked at here.

local Curve = FrogLib:Module("Curve", 2) -- 2: Below kept by its numbers
if not Curve then return end

local issecret = FrogLib.issecret
local EDGE = 0.0001 -- how close to a line its last point below sits

-- Kept across newer copies of this part: a curve made by an older one serves as well.
Curve.cache = Curve.cache or {} -- [key] = curve, or false when the client couldn't make one
-- Below's, the same way: [line][under][over], so no string key is built (it's asked per bar per
-- frame while a fade runs).
Curve.below = Curve.below or {}
local below = Curve.below

local function Make(points)
    local curve = C_CurveUtil.CreateCurve()
    if not curve then return false end
    if Enum and Enum.LuaCurveType and curve.SetType then
        pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    end
    for _, point in ipairs(points) do curve:AddPoint(point[1], point[2]) end
    return curve
end

-- A new curve through the points, or false when the client can't make one.
local function New(points)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return false end
    local ok, made = pcall(Make, points)
    return ok and made or false
end

-- A step curve through points ({ { x, y }, ... }, x the fraction 0 to 1), made once per key and
-- kept; nil when the client has no curves.
function Curve.Step(key, points)
    local cached = Curve.cache[key]
    if cached == nil then
        cached = New(points)
        Curve.cache[key] = cached
    end
    return cached or nil
end

local function BelowPoints(line, under, over)
    local points = {}
    if line > 0 then
        points[#points + 1] = { 0, under }
        if line - EDGE > 0 then points[#points + 1] = { line - EDGE, under } end
    end
    points[#points + 1] = { line, over }
    if line < 1 then points[#points + 1] = { 1, over } end
    return points
end

-- `under` below the fraction `line`, `over` from it up (an execute range: Below(0.2, 1, 0)). A pair
-- of points either side of the line keeps it sharp however the game steps through it.
function Curve.Below(line, under, over)
    if not (line == line and under == under and over == over) then -- NaN can't be a table key
        local key = string.format("below:%.4f:%.4f:%.4f", line, under, over)
        return Curve.Step(key, BelowPoints(line, under, over))
    end
    local byUnder = below[line]
    if not byUnder then
        byUnder = {}
        below[line] = byUnder
    end
    local byOver = byUnder[under]
    if not byOver then
        byOver = {}
        byUnder[under] = byOver
    end
    local curve = byOver[over]
    if curve == nil then
        curve = New(BelowPoints(line, under, over))
        byOver[over] = curve
    end
    return curve or nil
end

-- 0 when empty, 1 otherwise (an empty power bar fading out).
function Curve.Empty()
    return Curve.Below(EDGE, 0, 1)
end

-- `under` (default 1) below full, `atFull` at full (a fade that only happens at full health).
function Curve.Full(atFull, under)
    return Curve.Below(1, under or 1, atFull)
end

-- What came back, if it's a number (secret or not).
local function Result(ok, value)
    if ok and (issecret(value) or type(value) == "number") then return value end
    return nil
end

-- The curve's value at the unit's health or power fraction (may be secret), or nil when the game
-- can't say (no curve, an old client, an odd unit).
function Curve.Health(unit, curve)
    if not (curve and UnitHealthPercent) then return nil end
    return Result(pcall(UnitHealthPercent, unit, true, curve))
end

function Curve.Power(unit, curve, powerType)
    if not (curve and UnitPowerPercent) then return nil end
    return Result(pcall(UnitPowerPercent, unit, powerType, false, curve))
end
