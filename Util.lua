-- FrogLib Util: small things every addon needs.
--   FrogLib.Util.CopyDefaults(src, dst): fills in what dst (saved settings) is missing from src
--       (the defaults), into nested tables too; what's already set is kept.
--   FrogLib.Util.Merge(src, dst): src's values over dst's, nested tables too.
--   FrogLib.Util.Copy(v) -> a deep copy of v (v itself when it isn't a table).
--   FrogLib.Util.Printer(title, hex) -> print(...) under the addon's coloured name:
--       ns.Print = FrogLib.Util.Printer("FrogTarget", "ffd100")

local Util = FrogLib:Module("Util", 1)
if not Util then return end

function Util.CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Util.CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Util.Merge(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Util.Merge(v, dst[k])
        else
            dst[k] = v
        end
    end
end

function Util.Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Util.Copy(x) end
    return out
end

function Util.Printer(title, hex)
    local prefix = "|cff" .. hex .. title .. "|r:"
    return function(...) print(prefix, ...) end
end
