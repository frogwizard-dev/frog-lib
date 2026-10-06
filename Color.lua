-- FrogLib Color: the colours Frog Wizard's addons paint units in. Colours are { r =, g =, b = }
-- tables; the functions return r, g, b. Anything the game keeps secret (a class, a reaction,
-- whether a mob is tapped) is never tested: that rule just doesn't apply, and the next one does.
--   FrogLib.Color.Class(class) -> r, g, b, or nil: a class's colour (its token, "PALADIN"), from
--       a class colour addon (CUSTOM_CLASS_COLORS) first, then the game's. nil for a secret or
--       unknown class.
--   FrogLib.Color.ClassText(text, class) -> text in the class's colour (text must not be secret;
--       unchanged without a colour)
--   FrogLib.Color.Wrap(text, r, g, b) -> "|cffrrggbb" .. text .. "|r" (text must not be secret)
--   FrogLib.Color.Lighten(r, g, b, amount) -> r, g, b moved `amount` (0 to 1) of the way to white
--       (text tinted after its bar; 0.55 in the XIV addons)
--   FrogLib.Color.Unit(unit, rules) -> r, g, b, or nil: the first of these that applies:
--       rules.tapped (a colour): a mob someone else has tapped; rules.offline (a colour): a
--       unit that's offline (players); rules.class (true): a player in their class colour; then by how
--       the unit feels about you: rules.hostile (reaction 1 to 3), rules.neutral (4),
--       rules.friendly (5 and up); rules.fallback when that can't be told (or nil).
--   FrogLib.Color.XIV.engaged / passive / friend: FFXIV's enemy colours (fighting, not yet,
--       a friend); FrogLib.Color.XIVUnit(unit) -> r, g, b for a unit by those rules
--   FrogLib.Color.Power(unit, kind) -> r, g, b: the game's colour for a power (kind: its token,
--       "MANA", or its number); without kind, the unit's own power; mana when it can't tell.
--   FrogLib.Color.PowerToken(token) -> r, g, b, or nil: the game's colour for a power's token

local Color = FrogLib:Module("Color", 1)
if not Color then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

-- Pink-red while fighting, pale gold before, light blue for friends (you, players, friendly NPCs).
Color.XIV = {
    engaged = { r = 0.95, g = 0.42, b = 0.50 },
    passive = { r = 0.96, g = 0.86, b = 0.56 },
    friend = { r = 0.50, g = 0.78, b = 1.00 },
}
local MANA = { r = 0, g = 0, b = 1 }

local function Lookup(class)
    local custom = _G.CUSTOM_CLASS_COLORS
    local c = custom and custom[class]
    if c then return c end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, got = pcall(C_ClassColor.GetClassColor, class)
        if ok and got then return got end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

function Color.Class(class)
    if issecret(class) or type(class) ~= "string" then return nil end
    local c = Lookup(class)
    if not c then return nil end
    return c.r, c.g, c.b
end

local function Byte(v)
    return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
end

function Color.Wrap(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", Byte(r), Byte(g), Byte(b), text)
end

function Color.ClassText(text, class)
    local r, g, b = Color.Class(class)
    if not r then return text end
    return Color.Wrap(text, r, g, b)
end

function Color.Lighten(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function RGB(c)
    if c then return c.r, c.g, c.b end
    return nil
end

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

function Color.XIVUnit(unit)
    local c
    if Safe(UnitIsFriend("player", unit)) then
        c = Color.XIV.friend
    elseif Safe(UnitAffectingCombat(unit)) then
        c = Color.XIV.engaged
    else
        c = Color.XIV.passive
    end
    return c.r, c.g, c.b
end

function Color.PowerToken(token)
    local colors = _G.PowerBarColor
    local c = colors and not issecret(token) and token ~= nil and colors[token]
    if c then return c.r, c.g, c.b end
    return nil
end

function Color.Power(unit, kind)
    local colors, c = _G.PowerBarColor or {}, nil
    if kind ~= nil then
        if not issecret(kind) then c = colors[kind] end
    elseif unit then
        local k, token = UnitPowerType(unit)
        k, token = Safe(k), Safe(token)
        c = (token and colors[token]) or (k and colors[k])
    end
    c = c or colors.MANA or MANA
    return c.r, c.g, c.b
end
