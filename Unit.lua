-- FrogLib Unit: what the unit frames and bars print about a unit, and their text templates' words
-- (FrogLib.Text) for it. Anything here may come back secret: it's only handed on (to a widget, or
-- SetFormattedText through the templates), never tested.

local Unit = FrogLib:Module("Unit", 3) -- 2: IsPlayer; secret checks first; 3: the pet's happiness and care
if not Unit then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Text, Color = FrogLib.Text, FrogLib.Color

Unit.SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t"
local NOT_SPECIFIED = 10 -- creature type id
local NONE, COLORED = {}, { color = true }

-- The name as the game's own frames show it (on Forever with the surname: GetUnitName's second
-- argument; UnitName gives only the first name), or nil.
function Unit.Name(unit)
    if GetUnitName then
        local ok, name = pcall(GetUnitName, unit, true)
        if ok and (issecret(name) or name ~= nil) then return name end
    end
    return (UnitName(unit))
end

-- The level as text ("60"), "??" when it's too high to show. opts.color: in the colour for how hard
-- it is for you, a skull for too high, as the game's target frame (your own level stays plain).
function Unit.Level(unit, opts)
    local level = UnitLevel(unit)
    if issecret(level) then return level end
    local colored = opts and opts.color
    if colored and UnitIsUnit and Safe(UnitIsUnit(unit, "player")) then colored = false end
    if type(level) ~= "number" or level <= 0 then return colored and Unit.SKULL or "??" end
    if colored and GetCreatureDifficultyColor then
        local color = GetCreatureDifficultyColor(level)
        if color then return Color.Wrap(tostring(level), color.r, color.g, color.b) end
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

-- 0 to 100.
function Unit.HealthPercent(unit)
    if UnitHealthPercent and Scale() then
        local ok, percent = pcall(UnitHealthPercent, unit, true, Scale())
        if ok and (issecret(percent) or percent ~= nil) then return percent end
    end
    return Ratio(UnitHealth(unit), UnitHealthMax(unit))
end

-- 0 to 100 (kind: which power, by number; the unit's own by default). "Unmodified" is false, as
-- UnitPower's own default: the power as it's shown (rage out of 100), like the value and max words.
function Unit.PowerPercent(unit, kind)
    if UnitPowerPercent and Scale() then
        local ok, percent = pcall(UnitPowerPercent, unit, kind, false, Scale())
        if ok and (issecret(percent) or percent ~= nil) then return percent end
    end
    return Ratio(UnitPower(unit, kind), UnitPowerMax(unit, kind))
end

-- Whether unit is you: true, false, or nil when the game hides it (and your GUIDs too).
function Unit.IsPlayer(unit)
    local same = UnitIsUnit(unit, "player")
    if not issecret(same) then return same and true or false end
    local unitGUID, playerGUID = UnitGUID(unit), UnitGUID("player")
    if issecret(unitGUID) or issecret(playerGUID) or unitGUID == nil then return nil end
    return unitGUID == playerGUID
end

-- Forever has them in C_PetInfo (the old game had globals); either, whichever this client has.
local function PetCall(name, ...)
    local Call = (C_PetInfo and C_PetInfo[name]) or _G[name]
    if not Call then return nil end
    local ok, first, second, third = pcall(Call, ...)
    if not ok then return nil end
    return first, second, third
end

-- The game's face for each happiness.
Unit.HAPPINESS_ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }

-- Only for a hunter's pet: a warlock's has no happiness (and the game says "happy" for it).
local function HunterPet()
    if not HasPetUI then return UnitExists("pet") end
    local has, isHunterPet = HasPetUI()
    return has and isHunterPet and true or false
end

-- happiness (1 unhappy, 2 content, 3 happy), damage percentage, loyalty rate; nil without a hunter's pet.
function Unit.PetHappiness()
    if not HunterPet() then return nil end
    local happiness, damage, loyalty = PetCall("GetPetHappiness")
    happiness = Safe(happiness)
    if not Unit.HAPPINESS_ATLAS[happiness] then return nil end
    return happiness, Safe(damage), Safe(loyalty)
end

-- Its loyalty's name.
function Unit.PetLoyalty()
    if not HunterPet() then return nil end
    local name = Safe((PetCall("GetPetLoyalty")))
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Total training points, and used.
function Unit.PetTraining()
    if not HunterPet() then return nil end
    local total, used = PetCall("GetPetTrainingPoints")
    total, used = Safe(total), Safe(used)
    if type(total) ~= "number" or total <= 0 then return nil end
    return total, used or 0
end

-- A list of the foods it eats.
function Unit.PetFood()
    if not HunterPet() then return nil end
    local first, second, third = PetCall("GetPetFoodTypes")
    local list = type(first) == "table" and first or { first, second, third } -- C_PetInfo's is a table
    local foods = {}
    for _, food in ipairs(list) do
        if type(food) == "string" and food ~= "" then foods[#foods + 1] = food end
    end
    return #foods > 0 and foods or nil
end

-- "Mana", "Rage", "Energy"... as the game prints it: the global string named by the power's token,
-- or the token tidied up ("" when it can't tell).
function Unit.PowerTypeName(unit, kind)
    local token
    if not issecret(kind) and kind ~= nil then
        for name, value in pairs(Enum and Enum.PowerType or NONE) do
            if value == kind then token = name:gsub("(%l)(%u)", "%1_%2"):upper() end
        end
    end
    if not token then
        local _, unitToken = UnitPowerType(unit)
        if issecret(unitToken) or type(unitToken) ~= "string" then return "" end
        token = unitToken
    end
    local text = _G[token]
    if type(text) == "string" then return text end
    return (token:sub(1, 1) .. token:sub(2):lower():gsub("_", " "))
end

-- A player's class ("Paladin", in its colour if `colored`), anything else's creature type ("Beast");
-- "" for "Not specified" or when it can't be told. A secret one is shown as it is (uncoloured).
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
-- Template words: percent is the unit's health
------------------------------------------------------------------------------

Unit.WORDS = {
    name = "text", level = "text", class = "text", powertype = "text",
    value = "number", max = "number", percent = "percent",
    power = "number", powermax = "number", powerpercent = "percent",
}
local POWER_WORDS = { power = true, powermax = true, powerpercent = true, powertype = true }
local AS_POWER = { value = "power", max = "powermax", percent = "powerpercent" }

-- Each word's value for a unit: looked up only when a template uses it, so a missing function only
-- blanks its word.
local GET = {
    name = function(unit) return Unit.Name(unit) end,
    level = function(unit, opts) return Unit.Level(unit, opts.levelColor and COLORED or nil) end,
    class = function(unit, opts) return Unit.ClassText(unit, opts.classColor) end,
    value = function(unit) return UnitHealth(unit) end,
    max = function(unit) return UnitHealthMax(unit) end,
    percent = function(unit) return Unit.HealthPercent(unit) end,
    power = function(unit, opts) return UnitPower(unit, opts.kind) end,
    powermax = function(unit, opts) return UnitPowerMax(unit, opts.kind) end,
    powerpercent = function(unit, opts) return Unit.PowerPercent(unit, opts.kind) end,
    powertype = function(unit, opts) return Unit.PowerTypeName(unit, opts.kind) end,
}

-- Whether a template shows any of the power words.
function Unit.UsesPower(template)
    if type(template) ~= "string" then return false end
    local uses = Text.Compile(template, Unit.WORDS).uses
    for word in pairs(POWER_WORDS) do
        if uses[word] then return true end
    end
    return false
end

local values = {}

-- A sample's value for a word: its class coloured from fake.classFile ("PALADIN").
local function Fake(fake, word, source, opts)
    local value = fake[source]
    if value == nil then value = fake[word] end
    if type(value) == "table" then return nil end
    if source == "class" and type(value) == "string" and opts.classColor then
        value = Color.ClassText(value, fake.classFile)
    end
    return value
end

-- The template filled in for the unit (an empty one hides the font string), and whether it went in.
-- opts.power: value, max and percent are the unit's power (a power bar's text); opts.kind: which power.
function Unit.SetText(fontString, template, unit, opts)
    opts = opts or NONE
    if type(template) ~= "string" or not template:find("%S") then
        fontString:Hide()
        return false
    end
    local compiled = Text.Compile(template, Unit.WORDS)
    for word in pairs(compiled.uses) do
        local source = (opts.power and AS_POWER[word]) or word
        local value
        -- opts.fake: the words' values for a sample (no unit); with opts.power, its power words if it has them.
        if opts.fake then
            value = Fake(opts.fake, word, source, opts)
        elseif unit and GET[source] then
            local ok, got = pcall(GET[source], unit, opts)
            if ok then value = got end
        end
        values[word] = value
    end
    local ok = Text.Set(fontString, template, values, Unit.WORDS)
    for word in pairs(values) do values[word] = nil end
    return ok
end
