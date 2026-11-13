-- FrogLib Options: an entry for an addon in the game's Options > AddOns list, under one shared
-- "Frog Wizard" section: its name, version and description, a button that opens its own settings
-- window, and its slash commands. The section is the global FrogwizardOptions, as before FrogLib,
-- so addons with the old per-addon Options.lua still join it.

local Options = FrogLib:Module("Options", 2) -- 2: gamepad-safe
if not Options then return end

local SECTION = "Frog Wizard"

local function Meta(addon, field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local value = get and get(addon, field)
    return value and value ~= "" and value or nil
end

local function Text(parent, font, text, width)
    local line = parent:CreateFontString(nil, "ARTWORK", font)
    line:SetJustifyH("LEFT")
    if width then line:SetWidth(width) end
    line:SetText(text)
    return line
end

local function Gamepad()
    local ok, on = pcall(function() return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() end)
    return ok and on and true or false
end

-- Closes the game's options window so the addon's own isn't hidden behind it. Not in gamepad mode:
-- the gamepad navigation runs its own code on closing, and from ours it'd be left tainted.
local function CloseOptions()
    if Gamepad() then return end
    if not (SettingsPanel and SettingsPanel:IsShown()) then return end
    if SettingsPanel.Close then
        pcall(SettingsPanel.Close, SettingsPanel, true)
    else
        pcall(HideUIPanel, SettingsPanel)
    end
end
Options.CloseOptions = CloseOptions

local function Build(addon, opts)
    local title = Meta(addon, "Title") or addon
    local panel = CreateFrame("Frame")
    panel.name = title

    local heading = Text(panel, "GameFontNormalHuge", title)
    heading:SetPoint("TOPLEFT", 16, -16)
    local version = Meta(addon, "Version")
    local versionLine = Text(panel, "GameFontDisableSmall", version and ("Version " .. version) or "")
    versionLine:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    local notes = Text(panel, "GameFontHighlight", Meta(addon, "Notes") or "", 560)
    notes:SetPoint("TOPLEFT", versionLine, "BOTTOMLEFT", 0, -14)

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetText(opts.button or ("Open " .. title .. " settings"))
    button:SetWidth(math.max(200, button:GetFontString():GetStringWidth() + 40))
    button:SetHeight(26)
    button:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -18)
    -- Only while its page is the one shown: a gamepad cursor can be left on the page before's.
    button:SetScript("OnClick", function()
        if not panel:IsVisible() then return end
        CloseOptions()
        opts.open()
    end)

    local last = button
    if opts.commands and #opts.commands > 0 then
        local label = Text(panel, "GameFontNormal", "Slash commands")
        label:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -24)
        last = label
        for _, command in ipairs(opts.commands) do
            local line = Text(panel, "GameFontHighlight", "|cffffd100" .. command[1] .. "|r   " .. command[2], 560)
            line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -6)
            last = line
        end
    end
    local hint = Text(panel, "GameFontDisableSmall",
        "Also in the AddOn compartment, the button beside your minimap.", 560)
    hint:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -20)
    return panel, title
end

-- One row of the section's page: the addon's name and a button to its settings. Made when the addon
-- registers (at login): the gamepad navigation rescans the window for each frame made inside it.
local function Row(section)
    local row = CreateFrame("Frame", nil, section.panel)
    row:SetSize(560, 28)
    row.label = Text(row, "GameFontNormal", "")
    row.label:SetPoint("LEFT", 0, 0)
    row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button:SetSize(140, 22)
    row.button:SetPoint("LEFT", 230, 0)
    row.button:SetText("Open settings")
    row:Hide()
    return row
end

-- The rows in name order, laid out each time the page opens (addons join as they load). A row is
-- only made here for an addon an older FrogLib registered (it makes none of its own).
local function Layout(section)
    table.sort(section.entries, function(first, second) return first.title < second.title end)
    local last = section.intro
    for i, entry in ipairs(section.entries) do
        local row = section.rows[i] or Row(section)
        section.rows[i] = row
        row.label:SetText(entry.title)
        row.button:SetScript("OnClick", function()
            if not row:IsVisible() then return end
            CloseOptions()
            entry.open()
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -16 or -2)
        row:Show()
        last = row
    end
end

-- The section: whichever addon gets here first makes it, a page listing them all, each with a
-- button to its own settings; each addon's page goes under it. One an older FrogLib made is taken over.
local function Section()
    local section = _G.FrogwizardOptions
    if not section then
        local panel = CreateFrame("Frame")
        panel.name = SECTION
        local heading = Text(panel, "GameFontNormalHuge", SECTION)
        heading:SetPoint("TOPLEFT", 16, -16)
        section = { panel = panel, entries = {}, rows = {} }
        section.intro = Text(panel, "GameFontHighlight",
            "Frog Wizard's addons. Each has its own page under this one, or open its settings here.", 560)
        section.intro:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -14)
        section.category = Settings.RegisterCanvasLayoutCategory(panel, SECTION)
        Settings.RegisterAddOnCategory(section.category)
        _G.FrogwizardOptions = section
    end
    if not section.intro then
        -- An older section: its intro is the page's text under the heading; rows go from the top.
        section.intro = CreateFrame("Frame", nil, section.panel)
        section.intro:SetSize(1, 1)
        section.intro:SetPoint("TOPLEFT", 16, -62)
    end
    if section.layout ~= 2 then
        section.layout = 2
        section.panel:SetScript("OnShow", function() Layout(section) end)
    end
    return section
end

function Options.Register(addon, ns, opts)
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel, title = Build(addon, opts)
    local category
    if Settings.RegisterCanvasLayoutSubcategory then
        local section = Section()
        category = Settings.RegisterCanvasLayoutSubcategory(section.category, panel, title)
        table.insert(section.entries, { title = title, open = opts.open })
        -- Its row now, so none is made while the page is open.
        while #section.rows < #section.entries do section.rows[#section.rows + 1] = Row(section) end
    else
        category = Settings.RegisterCanvasLayoutCategory(panel, title)
        Settings.RegisterAddOnCategory(category)
    end
    if ns then ns.optionsCategory = category end
end

-- opts.open(): opens the addon's settings; opts.button: that button's label; opts.commands:
-- { { "/xiv", "open the settings" } }. Sets ns.optionsCategory once registered, at login.
function Options.Add(addon, ns, opts)
    if IsLoggedIn and IsLoggedIn() then
        pcall(Options.Register, addon, ns, opts)
    else
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_LOGIN")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            pcall(Options.Register, addon, ns, opts)
        end)
    end
end
