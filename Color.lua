-- FrogLib Color: the colours Frog Wizard's addons paint units in. Colours are { r =, g =, b = }
-- tables; the functions return r, g, b. Anything the game keeps secret (a class, a reaction,
-- whether a mob is tapped) is never tested: that rule doesn't apply, and the next one does.

local Color = FrogLib:Module("Color", 2) -- 2: secret checks first
if not Color then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

-- FFXIV's enemy colours: pink-red while fighting, pale gold before, light blue for friends (you,
-- players, friendly NPCs).
Color.XIV = {
    engaged = { r = 0.95, g = 0.42, b = 0.50 },
    passive = { r = 0.96, g = 0.86, b = 0.56 },
    friend = { r = 0.50, g = 0.78, b = 1.00 },
}
local MANA = { r = 0, g = 0, b = 1 }

local function Lookup(class)
    local custom = _G.CUSTOM_CLASS_COLORS
    local color = custom and custom[class]
    if color then return color end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, got = pcall(C_ClassColor.GetClassColor, class)
        if ok and got then return got end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

-- A class's colour (its token, "PALADIN"), from a class colour addon (CUSTOM_CLASS_COLORS) first,
-- then the game's; nil for a secret or unknown class.
function Color.Class(class)
    if issecret(class) or type(class) ~= "string" then return nil end
    local color = Lookup(class)
    if not color then return nil end
    return color.r, color.g, color.b
end

local function Byte(value)
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
end

-- "|cffrrggbb" .. text .. "|r" (text must not be secret).
function Color.Wrap(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", Byte(r), Byte(g), Byte(b), text)
end

-- Text in the class's colour (text must not be secret; unchanged without a colour).
function Color.ClassText(text, class)
    local r, g, b = Color.Class(class)
    if not r then return text end
    return Color.Wrap(text, r, g, b)
end

-- r, g, b moved `amount` (0 to 1) of the way to white (text tinted after its bar; 0.55 in the XIV addons).
function Color.Lighten(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function RGB(color)
    if color then return color.r, color.g, color.b end
    return nil
end

-- The first rule (each a colour) that applies: tapped (by someone else), offline (players), class
-- (true: a player's), then hostile, neutral or friendly by reaction; fallback when none can be told.
function Color.Unit(unit, rules)
    if rules.tapped and Safe(UnitIsTapDenied(unit)) then return RGB(rules.tapped) end
    if rules.offline and Safe(UnitIsConnected(unit)) == false then
        return RGB(rules.offline)
    end
    if rules.class and Safe(UnitIsPlayer(unit)) then
        local _, class = UnitClass(unit)
        local r, g, b = Color.Class(class)
        if r then return r, g, b end
    end
    local reaction = Safe(UnitReaction(unit, "player"))
    if type(reaction) == "number" then
        if reaction <= 3 then return RGB(rules.hostile or rules.fallback) end
        if reaction == 4 then return RGB(rules.neutral or rules.fallback) end
        return RGB(rules.friendly or rules.fallback)
    end
    return RGB(rules.fallback)
end

-- A unit by Color.XIV's rules.
function Color.XIVUnit(unit)
    local color
    if Safe(UnitIsFriend("player", unit)) then
        color = Color.XIV.friend
    elseif Safe(UnitAffectingCombat(unit)) then
        color = Color.XIV.engaged
    else
        color = Color.XIV.passive
    end
    return color.r, color.g, color.b
end

-- The game's colour for a power's token, or nil.
function Color.PowerToken(token)
    local colors = _G.PowerBarColor
    local color = colors and not issecret(token) and token ~= nil and colors[token]
    if color then return color.r, color.g, color.b end
    return nil
end

-- The game's colour for a power (kind: its token, "MANA", or its number); without kind, the unit's
-- own power; mana when it can't tell.
function Color.Power(unit, kind)
    local colors, color = _G.PowerBarColor or {}, nil
    if issecret(kind) then
        color = nil -- hidden: the default below
    elseif kind ~= nil then
        color = colors[kind]
    elseif unit then
        local powerType, token = UnitPowerType(unit)
        powerType, token = Safe(powerType), Safe(token)
        color = (token and colors[token]) or (powerType and colors[powerType])
    end
    color = color or colors.MANA or MANA
    return color.r, color.g, color.b
end
