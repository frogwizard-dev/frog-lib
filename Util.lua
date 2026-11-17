-- FrogLib Util: small things every addon needs.

local Util = FrogLib:Module("Util", 2) -- 2: Knows
if not Util then return end

local BANK = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

local checks -- made on the first call (each is a function and its arguments after the spell)

-- Whether the character has a spell: learned (talents and passives too) or in its spellbook.
function Util.Knows(spellID)
    if not checks then
        local book = C_SpellBook
        checks = {
            { IsPlayerSpell },
            { book and book.IsSpellKnown, BANK },
            { book and book.IsSpellInSpellBook, BANK, false },
            { IsSpellKnown },
        }
    end
    for i = 1, #checks do
        local check = checks[i]
        if check[1] then
            local ok, known = pcall(check[1], spellID, check[2], check[3])
            if ok and not FrogLib.issecret(known) and known == true then return true end
        end
    end
    return false
end

-- Fills in what saved settings are missing from the defaults, into nested tables too; what's
-- already set is kept.
function Util.CopyDefaults(defaults, saved)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(saved[key]) ~= "table" then saved[key] = {} end
            Util.CopyDefaults(value, saved[key])
        elseif saved[key] == nil then
            saved[key] = value
        end
    end
end

-- source's values over target's, nested tables too.
function Util.Merge(source, target)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Util.Merge(value, target[key])
        else
            target[key] = value
        end
    end
end

-- A deep copy (the value itself when it isn't a table).
function Util.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Util.Copy(item) end
    return copy
end

-- print(...) under the addon's coloured name: ns.Print = FrogLib.Util.Printer("FrogTarget", "ffd100")
function Util.Printer(title, hex)
    local prefix = "|cff" .. hex .. title .. "|r:"
    return function(...) print(prefix, ...) end
end
