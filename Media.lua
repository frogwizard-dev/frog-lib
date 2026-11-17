-- FrogLib Media: the bar textures and fonts the settings offer, and setting a font safely, with the
-- letters the client's language needs. An addon's own fonts are listed as "Bundled"; then Frog, the
-- game's own, EllesmereUI's and anything shared through LibSharedMedia, built fresh each time.

local Media = FrogLib:Module("Media", 5) -- 2: Usable; 3: the "SHADOW" outline; 4: ForClient; 5: SetNameFont,
-- one retry timer per font string
if not Media then return end

local GROUPS = { "Bundled", "Frog", "Blizzard", "EllesmereUI", "Shared media" }
local BUILTIN = {
    statusbar = {
        { name = "Flat", path = "Interface\\Buttons\\WHITE8X8" },
        { name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
        { name = "Blizzard Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    },
    font = {
        { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
        { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
        { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
        { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
    },
}

-- Shared registrations (kept across newer copies of this part).
Media.registered = Media.registered or { statusbar = {}, font = {} }

-- Listed by every addon under "Frog" (FrogUI's bars). kind: "statusbar" or "font".
function Media.Register(kind, name, path)
    local list = Media.registered[kind]
    if not list then return end
    for _, entry in ipairs(list) do
        if entry.path == path then return end
    end
    list[#list + 1] = { name = name, path = path }
end

Media.Instance = Media.Instance or {}
local Instance = Media.Instance
Media.InstanceMeta = Media.InstanceMeta or { __index = Instance }

-- ns.Media = FrogLib.Media.New({ fonts = { { "Michroma (wide)", path } }, fallbackFont = path }):
-- the addon's own fonts, and one for a font file that won't load (default: the game's own).
function Media.New(opts)
    return setmetatable({ opts = opts or {} }, Media.InstanceMeta)
end

-- { { title = group, items = { { name =, path = } } } } for kind "statusbar" or "font".
function Instance:List(kind)
    local buckets, seen = {}, {}
    for _, group in ipairs(GROUPS) do buckets[group] = {} end
    local function Add(group, name, path)
        if type(path) ~= "string" or seen[path:lower()] then return end
        seen[path:lower()] = true
        table.insert(buckets[group], { name = name, path = path })
    end

    if kind == "font" then
        for _, font in ipairs(self.opts.fonts or {}) do Add("Bundled", font[1], font[2]) end
    end
    for _, entry in ipairs(Media.registered[kind] or {}) do Add("Frog", entry.name, entry.path) end
    for _, entry in ipairs(BUILTIN[kind] or {}) do Add("Blizzard", entry.name, entry.path) end

    -- EllesmereUI doesn't register its bar textures with LibSharedMedia, so read its catalogue.
    local Ellesmere = _G.EllesmereUI
    if kind == "statusbar" and Ellesmere and Ellesmere.BAR_TEXTURE_ORDER and Ellesmere.BAR_TEXTURE_FILES
        and Ellesmere.MEDIA_PATH then
        for _, key in ipairs(Ellesmere.BAR_TEXTURE_ORDER) do
            local file = Ellesmere.BAR_TEXTURE_FILES[key]
            if file then
                Add("EllesmereUI", (Ellesmere.BAR_TEXTURE_NAMES and Ellesmere.BAR_TEXTURE_NAMES[key]) or key,
                    Ellesmere.MEDIA_PATH .. "textures\\" .. file)
            end
        end
    end

    -- EllesmereUI's fonts, plus anything other addons share, come through LibSharedMedia.
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local names = {}
        for name in pairs(LSM:HashTable(kind)) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local path = LSM:Fetch(kind, name, true)
            local group = (type(path) == "string" and path:find("EllesmereUI", 1, true)) and "EllesmereUI" or "Shared media"
            Add(group, name, path)
        end
    end

    local groups = {}
    for _, group in ipairs(GROUPS) do
        if #buckets[group] > 0 then
            if group ~= "Bundled" then
                table.sort(buckets[group], function(first, second) return first.name < second.name end)
            end
            groups[#groups + 1] = { title = group, items = buckets[group] }
        end
    end
    return groups
end

-- Redraws a font string's text in its current font. One whose words don't change can keep drawing
-- the old font (the target's target name rarely changes).
local function RedrawNow(fontString)
    local text = fontString:GetText()
    fontString:SetText("")
    fontString:SetText(text)
end
local function Redraw(fontString) pcall(RedrawNow, fontString) end

-- A font from an addon that isn't loaded (EllesmereUI's, after it's turned off or removed): asking
-- for it raises an error rather than failing quietly, so it isn't asked for at all.
local function FromMissingAddOn(path)
    local addon = path:match("^[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]([^\\/]+)")
    return addon ~= nil and not FrogLib.Loaded(addon)
end

-- False for a file inside an addon that isn't loaded (FrogUI's textures without FrogUI).
function Media.Usable(path)
    return type(path) == "string" and not FromMissingAddOn(path)
end

-- What known fonts draw past the Latin alphabet, by file name (measured from the files). A font drawn
-- with a letter it lacks shows nothing there, so a Russian name in Michroma is blank.
local KNOWN = {
    ["frizqt__.ttf"] = { twin = "Fonts\\FRIZQT___CYR.TTF" }, -- the game's faces each have a Cyrillic twin
    ["morpheus.ttf"] = { twin = "Fonts\\MORPHEUS_CYR.TTF" },
    ["skurri.ttf"] = { twin = "Fonts\\SKURRI_CYR.TTF" },
    ["frizqt___cyr.ttf"] = { cyrillic = true },
    ["morpheus_cyr.ttf"] = { cyrillic = true },
    ["skurri_cyr.ttf"] = { cyrillic = true },
    ["arialn.ttf"] = { cyrillic = true },
    ["michroma.ttf"] = {},
    ["sourcesans3.ttf"] = { cyrillic = true },
    ["xiv.ttf"] = { cyrillic = true }, -- M PLUS 1p: some Chinese, too little to rely on
    ["expressway.ttf"] = { cyrillic = true }, -- EllesmereUI's
    ["expressway bold.ttf"] = { cyrillic = true },
}
local SCRIPT = ({ ruRU = "cyrillic", koKR = "korean", zhCN = "chinese", zhTW = "chinese" })[GetLocale()]

-- Whether the font has this client's letters (one not listed, a player's own pick, is trusted).
local function Draws(path)
    local known = KNOWN[(path:match("[^\\/]+$") or path):lower()]
    return not known or known[SCRIPT] == true, known
end

-- The font to draw with on this client: path, or one with its language's letters (the game face's
-- Cyrillic twin, else fallback if it has them, else the game's own font for that language).
function Media.ForClient(path, fallback)
    if not SCRIPT or type(path) ~= "string" then return path end
    local draws, known = Draws(path)
    if draws then return path end
    if known.twin and SCRIPT == "cyrillic" then return known.twin end
    if type(fallback) == "string" and Draws(fallback) then return fallback end
    return STANDARD_TEXT_FONT
end

-- [fontString] = { wanted = what was last asked for, shadow = our drop shadow is on, retry = the running retry's
-- token }: kept here, not on the font
-- string (some are Blizzard's, the cast bar's spell name and the meter's rows).
Media.fontState = Media.fontState or setmetatable({}, { __mode = "k" })
local function FontState(fontString)
    local font = Media.fontState[fontString]
    if not font then
        font = {}
        Media.fontState[fontString] = font
    end
    return font
end

-- What SetFont was last asked for on the font string ("path|size|outline"), or nil.
function Media.Wanted(fontString)
    local font = Media.fontState[fontString]
    return font and font.wanted or nil
end

-- Taken off again when another outline is chosen (an addon's own shadow, set without it, is left alone). Returns the
-- outline to hand the game.
local function Shadow(fontString, outline)
    if outline == "SHADOW" then
        -- At least one whole screen pixel down and right, so text drawn small (nameplates) still
        -- shows it rather than a smudge.
        local ok, pixel = pcall(FrogLib.Pixel, fontString)
        local offset = (ok and pixel and pixel > 1) and pixel or 1
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(offset, -offset)
        FontState(fontString).shadow = true
        return ""
    end
    local font = Media.fontState[fontString]
    if font and font.shadow then
        font.shadow = nil
        fontString:SetShadowOffset(0, 0)
    end
    return outline or ""
end

-- Font families for other people's names: the chosen face for Latin letters, the game's own for the scripts a face
-- may lack (a plain SetFont drops the game's fallbacks, so a Russian or Chinese name in a Latin-only face draws
-- blank, even on an English client). Font objects are never freed: one per face, size and outline.
local ALPHABETS = {
    { "russian", "Fonts\\FRIZQT___CYR.TTF", 0 }, { "korean", "Fonts\\2002.TTF", 0 },
    { "simplifiedchinese", "Fonts\\ARKai_T.ttf", 3 }, { "traditionalchinese", "Fonts\\blei00d.TTF", 3 },
}
Media.families = Media.families or {}
Media.familyCount = Media.familyCount or 0
-- The client's own script takes the size asked for (on a Chinese client every name is drawn in it, so the lift a
-- Chinese face gets beside Latin letters would make them all too big).
local OWN_ALPHABET = ({ ruRU = "russian", koKR = "korean", zhCN = "simplifiedchinese",
    zhTW = "traditionalchinese" })[GetLocale()]

local function Family(path, size, flags)
    if not CreateFontFamily then return nil end
    size = math.floor(size * 4 + 0.5) / 4
    local key = path .. "|" .. size .. "|" .. flags
    local family = Media.families[key]
    if family == nil then
        local known = KNOWN[(path:match("[^\\/]+$") or path):lower()]
        local members = { { alphabet = "roman", file = path, height = size, flags = flags } }
        for _, alphabet in ipairs(ALPHABETS) do
            -- A face with Cyrillic of its own (or its own Cyrillic twin) draws Russian names too.
            local file = alphabet[2]
            if alphabet[1] == "russian" then
                if not known or known.cyrillic then file = path elseif known.twin then file = known.twin end
            end
            local lift = alphabet[1] == OWN_ALPHABET and 0 or alphabet[3]
            members[#members + 1] = { alphabet = alphabet[1], file = file, height = size + lift, flags = flags }
        end
        Media.familyCount = Media.familyCount + 1
        local ok, made = pcall(CreateFontFamily, "FrogLibNameFont" .. Media.familyCount, members)
        family = ok and made or false
        Media.families[key] = family
    end
    return family or nil
end

-- A font string that shows other people's names: as SetFont, through a font family so every script draws. A font
-- object resets the string's colour, justification and shadow, so they're put back (the shadow as Shadow() or the
-- addon left it). Falls back to SetFont when the face is a missing addon's or families can't be made.
function Instance:SetNameFont(fontString, path, size, outline)
    if not fontString then return end
    if type(path) ~= "string" or FromMissingAddOn(path) then return self:SetFont(fontString, path, size, outline) end
    local flags = Shadow(fontString, outline)
    local family = Family(path, size, flags)
    if not family then return self:SetFont(fontString, path, size, outline) end
    local font = FontState(fontString)
    font.wanted, font.retry = path .. "|" .. size .. "|" .. (outline or ""), nil
    local r, g, b, a = fontString:GetTextColor()
    local justifyH, justifyV = fontString:GetJustifyH(), fontString:GetJustifyV()
    local sr, sg, sb, sa = fontString:GetShadowColor()
    local sx, sy = fontString:GetShadowOffset()
    fontString:SetFontObject(family)
    if not FrogLib.issecret(r) then fontString:SetTextColor(r, g, b, a) end
    fontString:SetJustifyH(justifyH)
    fontString:SetJustifyV(justifyV)
    if sr then fontString:SetShadowColor(sr, sg, sb, sa) end
    if sx then fontString:SetShadowOffset(sx, sy) end
    Redraw(fontString)
end

-- outline: the game's ("", "OUTLINE", "THICKOUTLINE"...) or "SHADOW", a drop shadow instead. A font
-- file WoW hasn't finished loading can be refused at first, so it's retried; the fallback shows till then.
function Instance:SetFont(fontString, path, size, outline)
    if not fontString then return end
    local wanted = path .. "|" .. size .. "|" .. (outline or "") -- what was asked for (StatSheet reads it)
    local fallback = self.opts.fallbackFont
    path = Media.ForClient(path, fallback)
    fallback = Media.ForClient(fallback)
    outline = Shadow(fontString, outline)
    local font = FontState(fontString)
    font.wanted, font.retry = wanted, nil
    local usable = not FromMissingAddOn(path)
    local ok, set = false, false
    if usable then ok, set = pcall(fontString.SetFont, fontString, path, size, outline) end
    if not (ok and set) then
        if not (fallback and fontString:SetFont(fallback, size, outline)) then
            fontString:SetFont(STANDARD_TEXT_FONT, size, outline)
        end
        if usable then
            font.retry = {}
            Media.Retry(fontString, font.retry, path, size, outline)
        end
    end
    Redraw(fontString)
end

-- A refused font file asked for again after 0.2, 1 and 3 seconds: one chain per font string (token: the latest
-- SetFont's; any later SetFont or SetNameFont ends it), stopping once it takes.
local RETRY_AFTER = { 0.2, 0.8, 2 }
function Media.Retry(fontString, token, path, size, outline, step)
    step = step or 1
    local delay = RETRY_AFTER[step]
    if not delay then return end
    C_Timer.After(delay, function()
        -- By now the text may be forbidden (aura text in restricted content), or set to another font.
        local font = Media.fontState[fontString]
        if not (font and font.retry == token) or (fontString.IsForbidden and fontString:IsForbidden()) then return end
        local retried, took = pcall(fontString.SetFont, fontString, path, size, outline)
        if retried and took then
            font.retry = nil
            Redraw(fontString)
        else
            Media.Retry(fontString, token, path, size, outline, step + 1)
        end
    end)
end
