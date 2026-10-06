-- FrogLib Text: text templates, the words people type into a text box ("value / max  percent")
-- turned into a format string the game fills in. Values may be secret, so they're only ever
-- formatted engine-side by SetFormattedText, never looked at here.
--   FrogLib.Text.WORDS            the built-in words: value, max (whole numbers), percent ("76%";
--                                 percent.1 for "76.4%", up to three places)
--   FrogLib.Text.Compile(template, words) -> { pattern, args, uses }
--       words: the caller's own words, over the built-in ones: a list of names formatted as text
--       ({ "name", "level" }), or a table of name = kind, kind "text", "number" or "percent".
--       pattern: the format string ("|" doubled, as a single one starts a text escape; a "||"
--       typed into an edit box counts as one); args: the words in order (each time it's used);
--       uses[word]: whether the template uses a word. Made once per template and set of words.
--   FrogLib.Text.Set(fs, template, vals, words) -> whether the text went in
--       The template with vals[word] filled in, any number of words. An empty template hides fs
--       (shown otherwise). A missing value is blank (text words) or 0 (numbers); one the format
--       can't take (or a secret "nothing") leaves the old text.

local Text = FrogLib:Module("Text", 1)
if not Text then return end

local issecret = FrogLib.issecret
local unpack = unpack or table.unpack

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
    for k, v in pairs(words) do
        if type(k) == "number" then
            parts[#parts + 1] = tostring(v):lower() .. "=text"
        else
            parts[#parts + 1] = tostring(k):lower() .. "=" .. tostring(v)
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
        for _, w in ipairs(words) do
            if type(w) == "string" and w:lower() == word then return "text" end
        end
    end
    return Text.WORDS[word]
end

function Text.Compile(template, words)
    local key = Key(words)
    local byTemplate = Text.cache[key]
    if not byTemplate then
        byTemplate = {}
        Text.cache[key] = byTemplate
    end
    local c = byTemplate[template]
    if c then return c end
    local args, blank, uses = {}, {}, {}
    local pattern = template:gsub("%%", "%%%%")
    pattern = pattern:gsub("||", "|") -- edit boxes store a typed "|" already doubled
    pattern = pattern:gsub("|", "||")
    pattern = pattern:gsub("(%a+)(%.?%d*)", function(word, suffix)
        local w = word:lower()
        local kind = Kind(w, words)
        if not kind then return nil end
        args[#args + 1] = w
        blank[#args] = BLANK[kind] or ""
        uses[w] = true
        if kind == "percent" then
            local places = tonumber(suffix:match("^%.(%d)"))
            if places then return "%." .. math.min(places, 3) .. "f%%" end
            return "%d%%" .. suffix
        end
        return (FORMAT[kind] or "%s") .. suffix
    end)
    c = { pattern = pattern, args = args, blank = blank, uses = uses }
    byTemplate[template] = c
    return c
end

local out = {}

function Text.Set(fs, template, vals, words)
    if type(template) ~= "string" or not template:find("%S") then
        fs:Hide()
        return false
    end
    fs:Show()
    local c = Text.Compile(template, words)
    local n = #c.args
    vals = vals or NONE
    for i = 1, n do
        local v = vals[c.args[i]]
        if not issecret(v) and v == nil then v = c.blank[i] end
        out[i] = v
    end
    local ok = pcall(fs.SetFormattedText, fs, c.pattern, unpack(out, 1, n))
    for i = 1, n do out[i] = nil end
    return ok
end
