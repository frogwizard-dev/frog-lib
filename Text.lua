-- FrogLib Text: text templates, the words people type into a text box ("value / max  percent")
-- turned into a format string the game fills in. Values may be secret, so they're only ever
-- formatted engine-side by SetFormattedText, never looked at here.

local Text = FrogLib:Module("Text", 2) -- 2: Shadowed, Coins
if not Text then return end

local issecret = FrogLib.issecret
local unpack = unpack or table.unpack

-- The built-in words: value, max (whole numbers), percent ("76%"; percent.1 for "76.4%", up to
-- three places).
Text.WORDS = { value = "number", max = "number", percent = "percent" }
local FORMAT = { text = "%s", number = "%d" }
local BLANK = { text = "", number = 0, percent = 0 }

-- Kept across newer copies of this part (they compile the same way).
Text.cache = Text.cache or {}           -- [words key][template] = compiled
Text.keys = Text.keys or setmetatable({}, { __mode = "k" }) -- [words table] = its key
local NONE = {}

-- A key for a set of words, the same for equal sets (callers may pass a new table each time).
local function Key(words)
    if not words then return "" end
    local key = Text.keys[words]
    if key then return key end
    local parts = {}
    for name, kind in pairs(words) do
        if type(name) == "number" then
            parts[#parts + 1] = tostring(kind):lower() .. "=text" -- a listed name
        else
            parts[#parts + 1] = tostring(name):lower() .. "=" .. tostring(kind)
        end
    end
    table.sort(parts)
    key = table.concat(parts, ",")
    Text.keys[words] = key
    return key
end

local function Kind(word, words)
    if words then
        local kind = words[word]
        if kind then return kind end
        for _, listed in ipairs(words) do
            if type(listed) == "string" and listed:lower() == word then return "text" end
        end
    end
    return Text.WORDS[word]
end

-- { pattern, args, uses }, made once per template and set of words. words: the caller's own, over
-- the built-in ones: names shown as text ({ "name", "level" }), or name = "text", "number" or "percent".
function Text.Compile(template, words)
    local key = Key(words)
    local byTemplate = Text.cache[key]
    if not byTemplate then
        byTemplate = {}
        Text.cache[key] = byTemplate
    end
    local compiled = byTemplate[template]
    if compiled then return compiled end
    -- args: the words in order, each time it's used; uses[word]: whether the template uses it.
    local args, blank, uses = {}, {}, {}
    local pattern = template:gsub("%%", "%%%%")
    -- "|" doubled, as one alone starts an escape (edit boxes store a typed "|" already doubled).
    pattern = pattern:gsub("||", "|")
    pattern = pattern:gsub("|", "||")
    pattern = pattern:gsub("(%a+)(%.?%d*)", function(typed, suffix)
        local word = typed:lower()
        local kind = Kind(word, words)
        if not kind then return nil end
        args[#args + 1] = word
        blank[#args] = BLANK[kind] or ""
        uses[word] = true
        if kind == "percent" then
            local places = tonumber(suffix:match("^%.(%d)"))
            if places then return "%." .. math.min(places, 3) .. "f%%" end
            return "%d%%" .. suffix
        end
        return (FORMAT[kind] or "%s") .. suffix
    end)
    compiled = { pattern = pattern, args = args, blank = blank, uses = uses }
    byTemplate[template] = compiled
    return compiled
end

-- A font string with the soft black shadow the bars' text has, in a default font up front: SetText
-- errors on a font string with none, and the addon's own font only goes on at its layout.
function Text.Shadowed(parent)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
    return fontString
end

local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:1:0|t"

-- Money as the game writes it with coin icons ("4g 50s 20c"); built here on a client without that.
function Text.Coins(copper)
    copper = copper or 0
    local Format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if Format then
        local ok, text = pcall(Format, copper)
        if ok and type(text) == "string" then return text end
    end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. COIN:format("Gold") end
    if silver > 0 then parts[#parts + 1] = silver .. COIN:format("Silver") end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. COIN:format("Copper") end
    return table.concat(parts, " ")
end

local filled = {}

-- The template into the font string with values[word] filled in (blank or 0 when missing), and
-- whether it went in: a value the format can't take leaves the old text. An empty template hides it.
function Text.Set(fontString, template, values, words)
    if type(template) ~= "string" or not template:find("%S") then
        fontString:Hide()
        return false
    end
    fontString:Show()
    local compiled = Text.Compile(template, words)
    local count = #compiled.args
    values = values or NONE
    for i = 1, count do
        local value = values[compiled.args[i]]
        if not issecret(value) and value == nil then value = compiled.blank[i] end
        filled[i] = value
    end
    local ok = pcall(fontString.SetFormattedText, fontString, compiled.pattern, unpack(filled, 1, count))
    for i = 1, count do filled[i] = nil end
    return ok
end
