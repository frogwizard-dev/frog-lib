-- FrogLib Unit: what the unit frames and bars print about a unit, and their text templates' words
-- (FrogLib.Text) for it. Anything here may come back secret: it's only handed on (to a widget,
-- or SetFormattedText through the templates), never tested.
--   FrogLib.Unit.Name(unit)      -> the name as the game's own frames show it (on Forever with the
--       surname, GetUnitName's second argument; UnitName gives only the first name), or nil
--   FrogLib.Unit.Level(unit, opts) -> the level as text ("60"), "??" when it's too high to show;
--       opts.color: in the colour for how hard it is for you (grey, green, yellow, orange, red)
--       and a skull for "too high", as the game's target frame; your own level stays plain.
--   FrogLib.Unit.HealthPercent(unit), FrogLib.Unit.PowerPercent(unit, kind) -> 0 to 100
--       (kind: which power, by number; the unit's own by default)
--   FrogLib.Unit.PowerTypeName(unit, kind) -> "Mana", "Rage", "Energy"... ("" when it can't tell)
--   FrogLib.Unit.ClassText(unit, colored) -> a player's class ("Paladin", in its colour if
--       `colored`), anything else's creature type ("Beast"); "" for "Not specified" or when it
--       can't be told whether it's a player
--   FrogLib.Unit.WORDS: the template words for a unit: name, level, class, value, max, percent
--       (its health), power, powermax, powerpercent, powertype
--   FrogLib.Unit.UsesPower(template) -> whether a template shows any of the power words
--   FrogLib.Unit.SetText(fs, template, unit, opts) -> whether the text went in: the template
--       filled in for the unit (FrogLib.Text.Set: empty hides fs). opts (all optional):
--       power: value, max and percent are the unit's power rather than its health (a power
--       bar's text); kind: which power (by number); levelColor: the level as Level's opts.color;
--       classColor: the class word in the class's colour; fake: the words' values for a sample
--       (no unit), its class word coloured from fake.classFile ("PALADIN"); with `power`, a
--       sample's value, max and percent are taken from its power words if it has them.

local Unit = FrogLib:Module("Unit", 2) -- 2: IsPlayer; secret checks first
if not Unit then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Text, Color = FrogLib.Text, FrogLib.Color

Unit.SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t"
local NOT_SPECIFIED = 10 -- creature type id
local NONE, COLORED = {}, { color = true }

function Unit.Name(unit)
    if GetUnitName then
        local ok, name = pcall(GetUnitName, unit, true)
        if ok and (issecret(name) or name ~= nil) then return name end
    end
    return (UnitName(unit))
end

function Unit.Level(unit, opts)
    local level = UnitLevel(unit)
    if issecret(level) then return level end
    local colored = opts and opts.color
    if colored and UnitIsUnit and Safe(UnitIsUnit(unit, "player")) then colored = false end
    if type(level) ~= "number" or level <= 0 then return colored and Unit.SKULL or "??" end
    if colored and GetCreatureDifficultyColor then
        local c = GetCreatureDifficultyColor(level)
        if c then return Color.Wrap(tostring(level), c.r, c.g, c.b) end
    end
    return tostring(level)
end

-- Ours from the two numbers, when the game can't work it out (an older client).
local function Ratio(value, max)
    if issecret(value) or issecret(max) or type(value) ~= "number" or type(max) ~= "number" or max <= 0 then
        return 0
    end
    return value / max * 100
end

local function Scale()
    return CurveConstants and CurveConstants.ScaleTo100
end

function Unit.HealthPercent(unit)
    if UnitHealthPercent and Scale() then
        local ok, p = pcall(UnitHealthPercent, unit, true, Scale())
        if ok and (issecret(p) or p ~= nil) then return p end
    end
    return Ratio(UnitHealth(unit), UnitHealthMax(unit))
end

-- The third argument ("unmodified") is false, as UnitPower's own default: the power as it's
-- shown (rage out of 100), the same as the value and max words.
function Unit.PowerPercent(unit, kind)
    if UnitPowerPercent and Scale() then
        local ok, p = pcall(UnitPowerPercent, unit, kind, false, Scale())
        if ok and (issecret(p) or p ~= nil) then return p end
    end
    return Ratio(UnitPower(unit, kind), UnitPowerMax(unit, kind))
end

-- The power's name as the game prints it: the global string named by its token, or the token
-- tidied up.
-- Whether unit is you: true, false, or nil when the game hides it (and your GUIDs too).
function Unit.IsPlayer(unit)
    local same = UnitIsUnit(unit, "player")
    if not issecret(same) then return same and true or false end
    local a, b = UnitGUID(unit), UnitGUID("player")
    if issecret(a) or issecret(b) or a == nil then return nil end
    return a == b
end

function Unit.PowerTypeName(unit, kind)
    local token
    if not issecret(kind) and kind ~= nil then
        for name, value in pairs(Enum and Enum.PowerType or NONE) do
            if value == kind then token = name:gsub("(%l)(%u)", "%1_%2"):upper() end
        end
    end
    if not token then
        local _, t = UnitPowerType(unit)
        if issecret(t) or type(t) ~= "string" then return "" end
        token = t
    end
    local text = _G[token]
    if type(text) == "string" then return text end
    return (token:sub(1, 1) .. token:sub(2):lower():gsub("_", " "))
end

-- A secret class or type is shown as it is (it can't be coloured).
function Unit.ClassText(unit, colored)
    local player = UnitIsPlayer(unit)
    if issecret(player) then return "" end
    if player then
        local name, file = UnitClass(unit)
        if issecret(name) then return name end
        if type(name) ~= "string" then return "" end
        if colored then return Color.ClassText(name, file) end
        return name
    end
    local kind, id = UnitCreatureType(unit)
    if issecret(kind) then return kind end
    if type(kind) ~= "string" then return "" end
    if not issecret(id) and id == NOT_SPECIFIED then return "" end
    return kind
end

------------------------------------------------------------------------------
-- Template words
------------------------------------------------------------------------------

Unit.WORDS = {
    name = "text", level = "text", class = "text", powertype = "text",
    value = "number", max = "number", percent = "percent",
    power = "number", powermax = "number", powerpercent = "percent",
}
local POWER_WORDS = { power = true, powermax = true, powerpercent = true, powertype = true }
local AS_POWER = { value = "power", max = "powermax", percent = "powerpercent" }

-- Each word's value for a unit: looked up only when a template uses it, so a missing function
-- only blanks its word.
local GET = {
    name = function(unit) return Unit.Name(unit) end,
    level = function(unit, o) return Unit.Level(unit, o.levelColor and COLORED or nil) end,
    class = function(unit, o) return Unit.ClassText(unit, o.classColor) end,
    value = function(unit) return UnitHealth(unit) end,
    max = function(unit) return UnitHealthMax(unit) end,
    percent = function(unit) return Unit.HealthPercent(unit) end,
    power = function(unit, o) return UnitPower(unit, o.kind) end,
    powermax = function(unit, o) return UnitPowerMax(unit, o.kind) end,
    powerpercent = function(unit, o) return Unit.PowerPercent(unit, o.kind) end,
    powertype = function(unit, o) return Unit.PowerTypeName(unit, o.kind) end,
}

function Unit.UsesPower(template)
    if type(template) ~= "string" then return false end
    local uses = Text.Compile(template, Unit.WORDS).uses
    for w in pairs(POWER_WORDS) do
        if uses[w] then return true end
    end
    return false
end

local vals = {}

local function Fake(fake, word, src, opts)
    local v = fake[src]
    if v == nil then v = fake[word] end
    if type(v) == "table" then return nil end
    if src == "class" and type(v) == "string" and opts.classColor then v = Color.ClassText(v, fake.classFile) end
    return v
end

function Unit.SetText(fs, template, unit, opts)
    opts = opts or NONE
    if type(template) ~= "string" or not template:find("%S") then
        fs:Hide()
        return false
    end
    local c = Text.Compile(template, Unit.WORDS)
    for w in pairs(c.uses) do
        local src = (opts.power and AS_POWER[w]) or w
        local v
        if opts.fake then
            v = Fake(opts.fake, w, src, opts)
        elseif unit and GET[src] then
            local ok, got = pcall(GET[src], unit, opts)
            if ok then v = got end
        end
        vals[w] = v
    end
    local ok = Text.Set(fs, template, vals, Unit.WORDS)
    for w in pairs(vals) do vals[w] = nil end
    return ok
end
