-- FrogLib UI: the settings controls every Frog Wizard addon's settings window is built from.
-- local UI = FrogLib.UI.Kit(opts); each control returns the frame to place. A kit looks its controls
-- up here each time, so a newer copy of FrogLib's apply to it, and an addon can add its own fields.
-- A control's setting is get and set functions, or a settings table and a key in it.

local UI = FrogLib:Module("UI", 5) -- 2: "Drop shadow" among the outlines; 3: UI.Column, sidebar windows;
-- 4: a search box on tabbed windows; 5: controls bound to a settings table and key
if not UI then return end

UI.Controls = UI.Controls or {}
local Controls = UI.Controls

local function Refresh(kit)
    if kit.opts.refresh then kit.opts.refresh() end
end

local function Column(kit) return kit.opts.column or 150 end

-- get and set functions as they are, or a settings table and a key in it.
local function Bind(get, set)
    if type(get) ~= "table" then return get, set end
    local settings, key = get, set
    return function() return settings[key] end, function(value) settings[key] = value end
end

UI.KitMeta = UI.KitMeta or {}
-- kit.Name(...) -> UI.Controls.Name(kit, ...), looked up at the call: an addon may keep
-- `local Checkbox = UI.Checkbox` from before a newer copy of FrogLib loaded.
UI.KitMeta.__index = function(kit, name)
    if type(UI.Controls[name]) == "function" then
        return function(...) return UI.Controls[name](kit, ...) end
    end
end

-- opts.refresh(): after every change a control makes (usually ns.Refresh); opts.column: where controls
-- start, right of their labels (150); opts.dropWidth (210), text boxes 10 narrower; opts.helpWidth (400).
function UI.Kit(opts)
    local kit = setmetatable({ opts = opts or {} }, UI.KitMeta)
    kit.OUTLINES = Controls.Options(kit, "", "None", "SHADOW", "Drop shadow", "OUTLINE", "Outline",
        "THICKOUTLINE", "Thick outline")
    return kit
end

------------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------------

function Controls.Label(_, parent, text, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    label:SetText(text)
    return label
end

function Controls.Button(_, parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    button:SetText(text)
    return button
end

function Controls.Checkbox(kit, parent, text, get, set)
    get, set = Bind(get, set)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    Controls.Label(kit, checkbox, text, "GameFontHighlight"):SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox:SetChecked(get())
    checkbox:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    checkbox:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Refresh(kit)
    end)
    return checkbox
end

-- - value +; shift-click: ten steps. format: how the value shows ("%.2f").
function Controls.Stepper(kit, parent, text, min, max, step, get, set, format)
    get, set = Bind(get, set)
    local column = Column(kit)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(column + 150, 24)
    Controls.Label(kit, control, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local minus = Controls.Button(kit, control, "-", 24)
    minus:SetPoint("LEFT", column, 0)
    local valueText = Controls.Label(kit, control, "", "GameFontHighlight")
    valueText:SetWidth(44)
    valueText:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = Controls.Button(kit, control, "+", 24)
    plus:SetPoint("LEFT", valueText, "RIGHT", 4, 0)
    local function Show() valueText:SetText(format and string.format(format, get()) or get()) end
    local function Change(delta)
        if IsShiftKeyDown() then delta = delta * 10 end
        local value = math.max(min, math.min(max, get() + delta))
        set(math.floor(value / step + 0.5) * step)
        Show()
        Refresh(kit)
    end
    minus:SetScript("OnClick", function() Change(-step) end)
    plus:SetScript("OnClick", function() Change(step) end)
    control:SetScript("OnShow", Show)
    Show()
    return control
end

-- A slider with - and +. Top(), if given, works out the top of the range each time it's shown (it
-- can depend on the screen size or another setting).
function Controls.Slider(kit, parent, text, min, max, step, get, set, Top)
    get, set = Bind(get, set)
    local column = Column(kit)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(column + 230, 24)
    Controls.Label(kit, control, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local slider = CreateFrame("Slider", nil, control, "UISliderTemplate")
    slider:SetPoint("LEFT", column, 0)
    slider:SetSize(116, 16)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local minus = Controls.Button(kit, control, "-", 24)
    minus:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    local valueText = Controls.Label(kit, control, "", "GameFontHighlight")
    valueText:SetWidth(44)
    valueText:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = Controls.Button(kit, control, "+", 24)
    plus:SetPoint("LEFT", valueText, "RIGHT", 2, 0)

    local updating = false
    local function Highest() return math.max(min, Top and Top() or max) end
    local function Show()
        updating = true
        local highest = Highest()
        slider:SetMinMaxValues(min, highest)
        slider:SetValue(math.min(get(), highest))
        valueText:SetText(get())
        updating = false
    end
    local function Change(value)
        value = math.max(min, math.min(Highest(), value))
        value = math.floor(value / step + 0.5) * step
        if value == get() then return end
        set(value)
        Show()
        Refresh(kit)
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if not updating then Change(value) end
    end)
    local function Nudge(direction)
        Change(get() + direction * step * (IsShiftKeyDown() and 10 or 1))
    end
    minus:SetScript("OnClick", function() Nudge(-1) end)
    plus:SetScript("OnClick", function() Nudge(1) end)
    control:SetScript("OnShow", Show)
    Show()
    return control
end

-- groups() -> { { title =, items = { { name =, path = } } } }; .dd is the dropdown.
function Controls.Dropdown(kit, parent, text, groups, get, set)
    get, set = Bind(get, set)
    local column, width = Column(kit), kit.opts.dropWidth or 210
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(column + width + 20, 26)
    Controls.Label(kit, control, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local dropdown = CreateFrame("DropdownButton", nil, control, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    dropdown:SetPoint("LEFT", column, 0)
    dropdown:SetupMenu(function(_, root)
        local all, count = groups(), 0
        for _, group in ipairs(all) do count = count + #group.items end
        if count > 20 then root:SetScrollMode(20 * 20) end
        for _, group in ipairs(all) do
            if group.title then root:CreateTitle(group.title) end
            for _, item in ipairs(group.items) do
                root:CreateRadio(item.name, function() return get() == item.path end, function()
                    set(item.path)
                    Refresh(kit)
                end)
            end
        end
    end)
    -- Its text afresh when its page shows, in case another control changed the setting.
    control:SetScript("OnShow", function()
        if dropdown.GenerateMenu then pcall(dropdown.GenerateMenu, dropdown) end
    end)
    control.dd = dropdown
    return control
end

-- Groups for a plain list: UI.Options("path", "Name", "path", "Name", ...).
function Controls.Options(_, ...)
    local items = {}
    for i = 1, select("#", ...), 2 do
        local path, name = select(i, ...)
        items[#items + 1] = { path = path, name = name }
    end
    local groups = { { items = items } }
    return function() return groups end
end

-- get() -> { r, g, b }; set(r, g, b). Bound to a settings table and key, the colour is changed in place.
function Controls.ColorSwatch(kit, parent, text, get, set)
    if type(get) == "table" then
        local settings, key = get, set
        get = function() return settings[key] end
        set = function(r, g, b)
            local color = settings[key]
            color.r, color.g, color.b = r, g, b
        end
    end
    local column = Column(kit)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(column + 150, 24)
    Controls.Label(kit, control, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local swatch = CreateFrame("Button", nil, control, "BackdropTemplate")
    swatch:SetSize(40, 18)
    swatch:SetPoint("LEFT", column, 0)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(1, 1, 1, 0.6)
    local function Show()
        local color = get()
        swatch:SetBackdropColor(color.r, color.g, color.b, 1)
    end
    local function Apply(r, g, b)
        set(r, g, b)
        Show()
        Refresh(kit)
    end
    swatch:SetScript("OnClick", function()
        local color = get()
        local startR, startG, startB = color.r, color.g, color.b
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startR, g = startG, b = startB,
            swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() Apply(startR, startG, startB) end,
        })
    end)
    control:SetScript("OnShow", Show)
    Show()
    return control
end

-- Applies as you type; .eb is the edit box.
function Controls.TextBox(kit, parent, text, get, set)
    get, set = Bind(get, set)
    local column, width = Column(kit), kit.opts.dropWidth or 210
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(column + width + 20, 26)
    Controls.Label(kit, control, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local editBox = CreateFrame("EditBox", nil, control, "InputBoxTemplate")
    editBox:SetSize(width - 10, 20)
    editBox:SetPoint("LEFT", column + 6, 0)
    editBox:SetAutoFocus(false)
    editBox:SetText(get())
    editBox:SetScript("OnShow", function(self) self:SetText(get()) end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        set(self:GetText())
        Refresh(kit)
    end)
    editBox:SetScript("OnEnterPressed", editBox.ClearFocus)
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    control.eb = editBox
    return control
end

-- Small grey text.
function Controls.Help(kit, parent, text, width)
    local help = Controls.Label(kit, parent, text, "GameFontDisableSmall")
    help:SetWidth(width or kit.opts.helpWidth or 400)
    help:SetJustifyH("LEFT")
    return help
end

-- A small stepper for a pair on one row: a short label ("x", "y", "inset"), - value +.
function Controls.Mini(kit, parent, label, min, max, get, set)
    get, set = Bind(get, set)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(130, 24)
    local labelText = Controls.Label(kit, control, label, "GameFontDisableSmall")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetWidth(34)
    labelText:SetJustifyH("RIGHT")
    local minus = Controls.Button(kit, control, "-", 20, 20)
    minus:SetPoint("LEFT", 38, 0)
    local valueText = Controls.Label(kit, control, "", "GameFontHighlightSmall")
    valueText:SetWidth(36)
    valueText:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = Controls.Button(kit, control, "+", 20, 20)
    plus:SetPoint("LEFT", valueText, "RIGHT", 2, 0)
    local function Show() valueText:SetText(get()) end
    local function Change(delta)
        if IsShiftKeyDown() then delta = delta * 10 end -- shift-click: ten steps at once
        set(math.max(min, math.min(max, get() + delta)))
        Show()
        Refresh(kit)
    end
    minus:SetScript("OnClick", function() Change(-1) end)
    plus:SetScript("OnClick", function() Change(1) end)
    control:SetScript("OnShow", Show)
    Show()
    return control
end

-- One row: a label and two small steppers side by side. first, second: { label, min, max, get, set }.
function Controls.Pair(kit, parent, text, first, second)
    local column = Column(kit)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(column + 250, 24)
    Controls.Label(kit, control, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    Controls.Mini(kit, control, first[1], first[2], first[3], first[4], first[5]):SetPoint("LEFT", column - 60, 0)
    if second then
        Controls.Mini(kit, control, second[1], second[2], second[3], second[4], second[5]):SetPoint("LEFT", column + 80, 0)
    end
    return control
end

-- settings[key .. "X"] and settings[key .. "Y"] as a Pair: right and up are +.
function Controls.XY(kit, parent, text, settings, key, range)
    range = range or 40
    return Controls.Pair(kit, parent, text,
        { "x", -range, range, settings, key .. "X" }, { "y", -range, range, settings, key .. "Y" })
end

------------------------------------------------------------------------------
-- Spell lists (Personal Resource Tweaks' and XIVPlayer's aura whitelists and blacklists)
------------------------------------------------------------------------------

local LIST_ROW_HEIGHT = 26

-- A mouse-wheel scroll list of icon + text rows; callers add their own buttons per row.
function Controls.ScrollList(_, parent, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetSize(width, height)
    local back = scroll:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.3)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * LIST_ROW_HEIGHT)))
    end)
    scroll.child, scroll.rows, scroll.w = child, {}, width
    return scroll
end

-- The list's rows for `items`: setup(row, item, i) fills each (row.icon, row.text).
function Controls.FillList(kit, scroll, items, setup)
    for i, item in ipairs(items) do
        local row = scroll.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, scroll.child)
            row:SetSize(scroll.w - 8, LIST_ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 4, -(i - 1) * LIST_ROW_HEIGHT - 2)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.text = Controls.Label(kit, row, "", "GameFontHighlight")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetWidth(scroll.w - 150)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            scroll.rows[i] = row
        end
        setup(row, item, i)
        row:Show()
    end
    for i = #items + 1, #scroll.rows do scroll.rows[i]:Hide() end
    scroll.child:SetHeight(math.max(1, #items * LIST_ROW_HEIGHT + 4))
    local max = math.max(0, scroll.child:GetHeight() - scroll:GetHeight())
    if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
end

-- A spell's name and icon.
function Controls.SpellInfo(_, spellID)
    return C_Spell.GetSpellName(spellID), C_Spell.GetSpellTexture(spellID)
end

-- A window beside `owner` listing the auras on you now ("buffs" or "debuffs"), each with an Add
-- button: onAdd(spellID). Ones the game hides are left out. say(text): messages to chat.
-- Returns the window (one per owner).
function Controls.AuraPicker(kit, owner, kind, onAdd, say)
    if InCombatLockdown() then
        say("Leave combat to browse your current auras.")
        return owner.frogPicker
    end
    local picker = owner.frogPicker
    if not picker then
        picker = CreateFrame("Frame", nil, owner, "BasicFrameTemplateWithInset")
        picker:SetSize(320, 420)
        picker:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
        picker.title = Controls.Label(kit, picker, "")
        picker.title:SetPoint("TOP", 0, -5)
        picker.list = Controls.ScrollList(kit, picker, 296, 370)
        picker.list:SetPoint("TOPLEFT", 12, -32)
        owner.frogPicker = picker
    end
    picker.title:SetText("Your current " .. kind)
    local issecret = FrogLib.issecret
    local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
    local items = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if not ok or issecret(aura) or not aura then break end
        if not (issecret(aura.spellId) or issecret(aura.name) or issecret(aura.icon)) then
            items[#items + 1] = aura
        end
    end
    Controls.FillList(kit, picker.list, items, function(row, aura)
        row.icon:SetTexture(aura.icon)
        row.text:SetText((aura.name or "?") .. " |cff888888(" .. aura.spellId .. ")|r")
        if not row.add then
            row.add = Controls.Button(kit, row, "Add", 44, 20)
            row.add:SetPoint("RIGHT", -2, 0)
        end
        row.add:SetScript("OnClick", function() onAdd(aura.spellId) end)
    end)
    if #items == 0 then say("You have no " .. kind .. " right now.") end
    picker:Show()
    return picker
end

-- Text templates (FrogLib.Text).
function Controls.Compile(_, template, strings)
    return FrogLib.Text.Compile(template, strings)
end

function Controls.SetTemplateText(_, fontString, template, values, strings)
    FrogLib.Text.Set(fontString, template, values, strings)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

-- place(widget, height, x): controls down a frame; given the frame (page), it grows to fit them.
function Controls.Placer(_, page)
    local y = 0
    return function(widget, height, x)
        widget:SetPoint("TOPLEFT", x or 0, -y)
        y = y + height
        if page then page:SetHeight(y + 4) end
    end
end

-- place(widget, height, dx), head(text): a column at x of headed groups (a gold heading with a faint
-- rule under it, a gap above each but the first).
function Controls.Column(_, page, x, width)
    local y = 0
    width = width or 450
    local function Place(widget, height, dx)
        widget:SetPoint("TOPLEFT", x + (dx or 0), -y)
        y = y + height
        -- A scrolling page grows to fit its longest column.
        if page.GetHeight and (page:GetHeight() or 0) < y + 4 then page:SetHeight(y + 4) end
    end
    local function Head(text)
        if y > 0 then y = y + 14 end
        local heading = CreateFrame("Frame", nil, page)
        heading:SetSize(width, 22)
        local label = heading:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT")
        label:SetText(text)
        local rule = heading:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 0.82, 0, 0.25)
        rule:SetPoint("TOPLEFT", 0, -16)
        rule:SetSize(width, 1)
        Place(heading, 26)
    end
    return Place, Head
end

local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

-- Headers that open and close: Add(key, title, defaultOpen) -> place, body; and Relayout(). Which
-- are open is kept in `open` (saved settings).
function Controls.Sections(kit, page, open, width)
    local list = {}
    local function IsOpen(section)
        if section.peek then return true end -- opened by a search, not saved
        local saved = open[section.key]
        if saved == nil then return section.default end
        return saved
    end
    local function Relayout()
        local y = 0
        for _, section in ipairs(list) do
            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT", 0, -y)
            y = y + 26
            local isOpen = IsOpen(section)
            section.icon:SetTexture(isOpen and MINUS or PLUS)
            section.body:SetShown(isOpen)
            if isOpen then
                section.body:ClearAllPoints()
                section.body:SetPoint("TOPLEFT", 0, -y)
                y = y + section.body:GetHeight() + 8
            end
        end
        page:SetHeight(y + 10)
    end
    -- A tabbed window's search finds these, and opens the sections with what it found.
    page.frogSections = page.frogSections or {}
    table.insert(page.frogSections, { list = list, relayout = Relayout })
    -- Adds a section; returns its placer. defaultOpen: open until the user closes it.
    local function Add(key, title, defaultOpen)
        local section = { key = key, default = defaultOpen and true or false }
        local header = CreateFrame("Button", nil, page)
        header:SetSize(width, 24)
        local back = header:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(1, 1, 1, 0.06)
        local highlight = header:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.82, 0, 0.08)
        section.icon = header:CreateTexture(nil, "ARTWORK")
        section.icon:SetSize(16, 16)
        section.icon:SetPoint("LEFT", 4, 0)
        Controls.Label(kit, header, title):SetPoint("LEFT", section.icon, "RIGHT", 6, 0)
        header:SetScript("OnClick", function()
            if section.peek then
                section.peek = nil -- opened by a search: back to how it was
            else
                open[section.key] = not IsOpen(section)
            end
            Relayout()
        end)
        section.header = header
        section.body = CreateFrame("Frame", nil, page)
        section.body:SetSize(width, 1)
        section.body.frogSection = section
        list[#list + 1] = section
        return Controls.Placer(kit, section.body), section.body
    end
    return Add, Relayout
end

------------------------------------------------------------------------------
-- Search: every label, current choice and help line on a page, marked where they have the words
------------------------------------------------------------------------------

local SIDE_WIDTH, ENTRY_HEIGHT, HEADING_HEIGHT = 170, 20, 24

-- Every font string on a page, its own and its controls'.
local function Words(frame, found)
    for _, region in ipairs({ frame:GetRegions() }) do
        if type(region) == "table" and region.GetObjectType and region:GetObjectType() == "FontString" then
            found[#found + 1] = region
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" then Words(child, found) end
    end
    return found
end

local function Plain(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower())
end

local function Mark(fontString, on)
    if not fontString.frogMark then
        if not on then return end
        local parent = fontString:GetParent()
        if not (parent and parent.CreateTexture) then return end
        local mark = parent:CreateTexture(nil, "BACKGROUND")
        mark:SetColorTexture(1, 0.82, 0, 0.22)
        mark:SetPoint("TOPLEFT", fontString, "TOPLEFT", -3, 2)
        mark:SetPoint("BOTTOMRIGHT", fontString, "BOTTOMRIGHT", 3, -2)
        fontString.frogMark = mark
    end
    fontString.frogMark:SetShown(on)
end

-- Whether a font string is on show on its page: it and every frame up to the page shown, a
-- closed section's body (which a search opens) counting as shown.
local function OnPage(fontString, content)
    if not fontString:IsShown() then return false end
    local parent = fontString:GetParent()
    while parent and parent ~= content do
        if not parent:IsShown() and not parent.frogSection then return false end
        parent = parent:GetParent()
    end
    return parent == content
end

-- Every set of sections (UI.Sections) on a page.
local function SectionSets(frame, found)
    if frame.frogSections then
        for _, set in ipairs(frame.frogSections) do found[#found + 1] = set end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" then SectionSets(child, found) end
    end
    return found
end

-- Marks the words on a page that have `query` (nil: none), opens the sections they're in for as
-- long as the search lasts, and says whether there were any. The words are read afresh each
-- time, as pages can change.
local function FindOnPage(content, query)
    local sets = SectionSets(content, {})
    for _, set in ipairs(sets) do
        for _, section in ipairs(set.list) do section.peek = nil end
    end
    local any = false
    for _, fontString in ipairs(Words(content, {})) do
        local hit = query ~= nil and OnPage(fontString, content) and Plain(fontString:GetText()):find(query, 1, true) ~= nil
        Mark(fontString, hit)
        if hit then
            any = true
            local parent = fontString:GetParent()
            while parent and parent ~= content do
                if parent.frogSection then parent.frogSection.peek = true end
                parent = parent:GetParent()
            end
        end
    end
    for _, set in ipairs(sets) do set.relayout() end
    return any
end

-- Scrolls a scrolling page to its first marked word (words: the page's, when already known), and
-- says whether it found one.
local function ScrollToMark(page, content, words)
    if not (page and page.SetVerticalScroll) then return false end
    local top, first = content:GetTop(), nil
    for _, fontString in ipairs(words or Words(content, {})) do
        if fontString.frogMark and fontString.frogMark:IsShown() and fontString:GetTop() and top then
            local offset = top - fontString:GetTop()
            if not first or offset < first then first = offset end
        end
    end
    if first then page:SetVerticalScroll(math.max(0, first - 40)) end
    return first ~= nil
end

-- A search box: the game's own (with its grey "Search" and clear button) where it has one.
local function SearchBox(parent, width)
    local ok, search = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
    if not ok or not search then search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate") end
    search:SetSize(width, 20)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    local hint = rawget(search, "Instructions") -- SearchBoxTemplate's grey "Search"
    if type(hint) == "table" and hint.SetText then hint:SetText(SEARCH or "Search") end
    return search
end

-- A settings window with a sidebar instead of tabs: a search box, then the pages in a list under
-- their headings, each page scrolling. A search keeps only the pages with its words and marks them.
local function SidebarWindow(kit, window, width, pages, wopts)
    local side = CreateFrame("Frame", nil, window)
    side:SetPoint("TOPLEFT", 12, -30)
    side:SetPoint("BOTTOMLEFT", 12, 12)
    side:SetWidth(SIDE_WIDTH)
    local back = side:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.25)

    local search = SearchBox(side, SIDE_WIDTH - 16)
    search:SetPoint("TOPLEFT", 10, -6)

    local list = CreateFrame("Frame", nil, side)
    list:SetPoint("TOPLEFT", 0, -34)
    list:SetPoint("BOTTOMRIGHT")

    local frames, contents, entries, byKey = {}, {}, {}, {}
    local current, query
    -- To the first word the search marked, or the top.
    local function ScrollPage(key)
        local page = frames[key]
        if not (query and ScrollToMark(page, contents[key], byKey[key].words)) then page:SetVerticalScroll(0) end
    end
    local function Select(key)
        current = key
        for otherKey, page in pairs(frames) do page:SetShown(otherKey == key) end
        for _, entry in ipairs(entries) do
            if entry.selected then entry.selected:SetShown(entry.key == key) end
        end
        ScrollPage(key)
        if wopts.onSelect then wopts.onSelect(key) end
    end

    for _, page in ipairs(pages) do
        local entry = {}
        if page.heading then
            entry.heading = true
            entry.row = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            entry.row:SetText(page.heading:upper())
        else
            local key = page[1]
            entry.key, entry.label = key, page[2]
            local button = CreateFrame("Button", nil, list)
            button:SetSize(SIDE_WIDTH, ENTRY_HEIGHT)
            local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", 16, 0)
            label:SetText(page[2])
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.08)
            entry.selected = button:CreateTexture(nil, "BACKGROUND")
            entry.selected:SetAllPoints()
            entry.selected:SetColorTexture(1, 0.82, 0, 0.2)
            entry.selected:Hide()
            button:SetScript("OnClick", function() Select(key) end)
            entry.row = button
            local scroller = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
            scroller:SetPoint("TOPLEFT", SIDE_WIDTH + 28, -34)
            scroller:SetPoint("BOTTOMRIGHT", -34, 12)
            local content = CreateFrame("Frame", nil, scroller)
            content:SetSize(width - SIDE_WIDTH - 72, 10)
            scroller:SetScrollChild(content)
            scroller:Hide()
            frames[key], contents[key] = scroller, content
            byKey[key] = entry
        end
        entries[#entries + 1] = entry
    end

    -- The list, with only the pages the search finds (and their headings).
    local function Relayout()
        local y, pendingHeading = 0, nil
        for _, entry in ipairs(entries) do
            if entry.heading then
                entry.row:Hide()
                pendingHeading = entry
            elseif entry.shown ~= false then
                if pendingHeading then
                    pendingHeading.row:ClearAllPoints()
                    pendingHeading.row:SetPoint("TOPLEFT", 10, -(y + 6))
                    pendingHeading.row:Show()
                    y = y + HEADING_HEIGHT
                    pendingHeading = nil
                end
                entry.row:ClearAllPoints()
                entry.row:SetPoint("TOPLEFT", 0, -y)
                entry.row:Show()
                y = y + ENTRY_HEIGHT
            else
                entry.row:Hide()
            end
        end
    end

    local function Search()
        local text = strtrim and strtrim(search:GetText() or "") or (search:GetText() or "")
        query = text ~= "" and text:lower() or nil
        local firstShown
        for _, entry in ipairs(entries) do
            if not entry.heading then
                local found = false
                for _, fontString in ipairs(entry.words) do
                    local hit = query and Plain(fontString:GetText()):find(query, 1, true) and true or false
                    Mark(fontString, hit)
                    found = found or hit
                end
                entry.shown = not query or found or entry.label:lower():find(query, 1, true) ~= nil
                if entry.shown and not firstShown then firstShown = entry.key end
            end
        end
        Relayout()
        if current and byKey[current].shown then
            Select(current)
        elseif firstShown then
            Select(firstShown)
        end
    end
    search:HookScript("OnTextChanged", Search)

    for _, page in ipairs(pages) do
        if not page.heading and page[3] then page[3](contents[page[1]]) end
    end
    for key, entry in pairs(byKey) do entry.words = Words(contents[key], {}) end
    Relayout()
    for _, page in ipairs(pages) do
        if not page.heading then
            Select(page[1])
            break
        end
    end
    window.Select = Select
    window.search = search
    return window, contents
end

-- A movable settings window with a row of tabs: frame, contents. pages = { { key, label, build(content) } };
-- wopts: tabWidth (100), tabGap (4), fitTabs, scroll, onSelect(key), search (false: none), sidebar.
function Controls.Window(kit, globalName, title, width, height, pages, wopts)
    wopts = wopts or {}
    local window = CreateFrame("Frame", globalName, UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(width, height)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    Controls.Label(kit, window, title):SetPoint("TOP", 0, -5)
    if globalName then tinsert(UISpecialFrames, globalName) end
    -- wopts.sidebar: a searchable list down the left instead of tabs; { heading = "Bars" } among the
    -- pages heads the ones after it.
    if wopts.sidebar then return SidebarWindow(kit, window, width, pages, wopts) end

    local frames, contents, tabs = {}, {}, {}
    local searching = wopts.search ~= false
    local down = searching and 26 or 0 -- the search box's row, under the tabs
    if searching then window:SetHeight(height + down) end
    local current, query, found = nil, nil, {}
    local function Select(key)
        current = key
        for otherKey, page in pairs(frames) do page:SetShown(otherKey == key) end
        for otherKey, tab in pairs(tabs) do
            if otherKey == key then tab:LockHighlight() else tab:UnlockHighlight() end
        end
        if query then ScrollToMark(frames[key], contents[key]) end
        if wopts.onSelect then wopts.onSelect(key) end
    end
    -- wopts.fitTabs: the width shared out between the tabs.
    local tabWidth, step = wopts.tabWidth or 100, (wopts.tabWidth or 100) + (wopts.tabGap or 4)
    if wopts.fitTabs then
        step = math.floor((width - 28) / #pages)
        tabWidth = step - 2
    end
    for i, page in ipairs(pages) do
        local key = page[1]
        local tab = Controls.Button(kit, window, page[2], tabWidth)
        tab:SetPoint("TOPLEFT", 14 + (i - 1) * step, -30)
        tab:SetScript("OnClick", function() Select(key) end)
        local label = tab:GetFontString()
        if label and wopts.fitTabs then label:SetWordWrap(false) end
        tabs[key] = tab
        local frame, content
        -- wopts.scroll: each page scrolls, built on its content.
        if wopts.scroll then
            frame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
            frame:SetPoint("TOPLEFT", 16, -64 - down)
            frame:SetPoint("BOTTOMRIGHT", -34, 12)
            content = CreateFrame("Frame", nil, frame)
            content:SetSize(width - 60, 10)
            frame:SetScrollChild(content)
        else
            frame = CreateFrame("Frame", nil, window)
            frame:SetPoint("TOPLEFT", 16, -62 - down)
            frame:SetPoint("BOTTOMRIGHT", -16, 12)
            content = frame
        end
        frames[key], contents[key] = frame, content
    end
    for _, page in ipairs(pages) do
        if page[3] then page[3](contents[page[1]]) end
    end

    -- The search: marks the words on every page that have it (opening the sections they're in),
    -- dims the tabs with none, and moves to a page with some when this one has none.
    if searching then
        local search = SearchBox(window, 160)
        search:SetPoint("TOPRIGHT", -18, -61)
        local function Search()
            local text = strtrim and strtrim(search:GetText() or "") or (search:GetText() or "")
            query = text ~= "" and text:lower() or nil
            local first
            for _, page in ipairs(pages) do
                local key = page[1]
                local hit = FindOnPage(contents[key], query)
                found[key] = hit or (query ~= nil and page[2]:lower():find(query, 1, true) ~= nil)
                tabs[key]:SetAlpha((not query or found[key]) and 1 or 0.4)
                if found[key] and not first then first = key end
            end
            if query and not found[current] and first then
                Select(first)
            else
                Select(current)
            end
        end
        search:HookScript("OnTextChanged", Search)
        window.search = search
    end

    Select(pages[1][1])
    window.Select = Select
    return window, contents
end
