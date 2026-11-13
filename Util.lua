-- FrogLib Util: small things every addon needs.

local Util = FrogLib:Module("Util", 1)
if not Util then return end

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
