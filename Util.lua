-- FrogLib Util: small things every addon needs.

local Util = FrogLib:Module("Util", 3) -- 2: Knows; 3: Say, Warn, and printing waits for the end of combat
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

-- A line in chat. In combat it waits for combat to end, the lines in the order they came: a line printed in combat
-- taints the chat history (EllesmereUI found it on Forever).
local held, waiter -- the lines waiting, and the frame that waits for the end of combat
function Util.Say(text)
    if not InCombatLockdown() then
        print(text)
        return
    end
    held = held or {}
    held[#held + 1] = text
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            local lines = held or {}
            held = nil
            for _, line in ipairs(lines) do print(line) end
        end)
    end
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- A refusal the player should see now ("not in combat"): in combat, in the game's red error text over the screen
-- (as EllesmereUI does: no chat), otherwise in chat.
function Util.Warn(text)
    if InCombatLockdown() and UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, 1, 0.3, 0.3, 1)
    else
        FrogLib.Util.Say(text)
    end
end

-- print(...) under the addon's coloured name, through Say: ns.Print = FrogLib.Util.Printer("FrogTarget", "ffd100").
-- Say is looked up on each call, so a newer FrogLib copy loaded by another addon reaches printers made before it.
function Util.Printer(title, hex)
    local prefix = "|cff" .. hex .. title .. "|r:"
    return function(...)
        local parts = { prefix }
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        FrogLib.Util.Say(table.concat(parts, " "))
    end
end
