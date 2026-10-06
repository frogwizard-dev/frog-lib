-- FrogLib UI: the settings controls every Frog Wizard addon's settings window is built from.
--
--   local UI = FrogLib.UI.Kit(opts)
--       opts.refresh(): called after every change a control makes (usually ns.Refresh).
--       opts.column: where the controls start, right of their labels (150).
--       opts.dropWidth: a dropdown's width (210); text boxes are 10 narrower.
--       opts.helpWidth: help text's width when none is given (400).
--
--   Controls (each returns the frame to place):
--     UI.Label(parent, text, template)            UI.Button(parent, text, w, h)
--     UI.Checkbox(parent, text, get, set)          set(true/false)
--     UI.Stepper(parent, text, min, max, step, get, set, fmt)   - value +; shift-click: ten steps
--     UI.Slider(parent, text, min, max, step, get, set, maxFn)  a slider with - and +
--     UI.Dropdown(parent, text, groups, get, set)  groups() -> { { title =, items = { { name =, path = } } } }
--     UI.Options("path", "Name", ...)              groups for a plain list;  UI.OUTLINES: font outlines
--     UI.ColorSwatch(parent, text, get, set)       get() -> { r, g, b }; set(r, g, b)
--     UI.TextBox(parent, text, get, set)           applies as you type; .eb is the edit box
--     UI.Help(parent, text, width)                 small grey text
--     UI.Mini(parent, label, min, max, get, set)   a small stepper ("x", "y")
--     UI.Pair(parent, text, a, b)                  two Minis on a row; a, b = { label, min, max, get, set }
--     UI.XY(parent, text, o, key, range)           o[key.."X"] and o[key.."Y"] as a Pair
--   Spell lists: UI.ScrollList(parent, w, h), UI.FillList(list, items, setup(row, item, i)),
--     UI.SpellInfo(id) -> name, icon, UI.AuraPicker(owner, kind, onAdd(id), say(text)) -> window
--   Layout:
--     UI.Placer(page) -> place(widget, height, x): down the page; with `page`, it grows to fit.
--     UI.Sections(page, open, width) -> Add(key, title, defaultOpen) -> place, body; and Relayout().
--         Headers that open and close; which are open is kept in `open` (saved settings).
--     UI.Window(globalName, title, width, height, pages, wopts) -> frame, contents
--         pages = { { key, label, build(content) } }; wopts.tabWidth (100), wopts.tabGap (4),
--         wopts.fitTabs (share the width out), wopts.scroll (each page scrolls; build on its
--         content), wopts.onSelect(key).
--   Text templates (FrogLib.Text): UI.Compile(template, strings), UI.SetTemplateText(fs, template, vals, strings)
--
-- A kit looks its controls up here each time, so a newer copy of FrogLib's apply to it. An addon
-- can add its own fields to its kit.

local UI = FrogLib:Module("UI", 1)
if not UI then return end

UI.Controls = UI.Controls or {}
local C = UI.Controls

local function Refresh(k)
    if k.opts.refresh then k.opts.refresh() end
end

local function Column(k) return k.opts.column or 150 end

UI.KitMeta = UI.KitMeta or {}
-- kit.Name(...) -> UI.Controls.Name(kit, ...), looked up at the call: an addon may keep
-- `local Checkbox = UI.Checkbox` from before a newer copy of FrogLib loaded.
UI.KitMeta.__index = function(k, name)
    if type(UI.Controls[name]) == "function" then
        return function(...) return UI.Controls[name](k, ...) end
    end
end

function UI.Kit(opts)
    local k = setmetatable({ opts = opts or {} }, UI.KitMeta)
    k.OUTLINES = C.Options(k, "", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline")
    return k
end

------------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------------

function C.Label(_, parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    return fs
end

function C.Button(_, parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    return b
end

function C.Checkbox(k, parent, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    C.Label(k, cb, text, "GameFontHighlight"):SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetChecked(get())
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Refresh(k)
    end)
    return cb
end

function C.Stepper(k, parent, text, min, max, step, get, set, fmt)
    local col = Column(k)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(col + 150, 24)
    C.Label(k, f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local minus = C.Button(k, f, "-", 24)
    minus:SetPoint("LEFT", col, 0)
    local val = C.Label(k, f, "", "GameFontHighlight")
    val:SetWidth(44)
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = C.Button(k, f, "+", 24)
    plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
    local function refresh() val:SetText(fmt and string.format(fmt, get()) or get()) end
    local function change(d)
        if IsShiftKeyDown() then d = d * 10 end -- shift-click: ten steps at once
        local v = math.max(min, math.min(max, get() + d))
        set(math.floor(v / step + 0.5) * step)
        refresh()
        Refresh(k)
    end
    minus:SetScript("OnClick", function() change(-step) end)
    plus:SetScript("OnClick", function() change(step) end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

-- maxFn, if given, works out the top of the range each time the control is shown (it can depend
-- on the screen size or another setting).
function C.Slider(k, parent, text, min, max, step, get, set, maxFn)
    local col = Column(k)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(col + 230, 24)
    C.Label(k, f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local s = CreateFrame("Slider", nil, f, "UISliderTemplate")
    s:SetPoint("LEFT", col, 0)
    s:SetSize(116, 16)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local minus = C.Button(k, f, "-", 24)
    minus:SetPoint("LEFT", s, "RIGHT", 6, 0)
    local val = C.Label(k, f, "", "GameFontHighlight")
    val:SetWidth(44)
    val:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = C.Button(k, f, "+", 24)
    plus:SetPoint("LEFT", val, "RIGHT", 2, 0)

    local updating = false
    local function top() return math.max(min, maxFn and maxFn() or max) end
    local function refresh()
        updating = true
        local hi = top()
        s:SetMinMaxValues(min, hi)
        s:SetValue(math.min(get(), hi))
        val:SetText(get())
        updating = false
    end
    local function change(v)
        v = math.max(min, math.min(top(), v))
        v = math.floor(v / step + 0.5) * step
        if v == get() then return end
        set(v)
        refresh()
        Refresh(k)
    end
    s:SetScript("OnValueChanged", function(_, v)
        if not updating then change(v) end
    end)
    local function nudge(d)
        change(get() + d * step * (IsShiftKeyDown() and 10 or 1))
    end
    minus:SetScript("OnClick", function() nudge(-1) end)
    plus:SetScript("OnClick", function() nudge(1) end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

function C.Dropdown(k, parent, text, groups, get, set)
    local col, w = Column(k), k.opts.dropWidth or 210
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(col + w + 20, 26)
    C.Label(k, f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    dd:SetWidth(w)
    dd:SetPoint("LEFT", col, 0)
    dd:SetupMenu(function(_, root)
        local all, count = groups(), 0
        for _, group in ipairs(all) do count = count + #group.items end
        if count > 20 then root:SetScrollMode(20 * 20) end
        for _, group in ipairs(all) do
            if group.title then root:CreateTitle(group.title) end
            for _, item in ipairs(group.items) do
                root:CreateRadio(item.name, function() return get() == item.path end, function()
                    set(item.path)
                    Refresh(k)
                end)
            end
        end
    end)
    -- Its text afresh when its page shows, in case another control changed the setting.
    f:SetScript("OnShow", function()
        if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end
    end)
    f.dd = dd
    return f
end

function C.Options(_, ...)
    local items = {}
    for i = 1, select("#", ...), 2 do
        local path, name = select(i, ...)
        items[#items + 1] = { path = path, name = name }
    end
    local groups = { { items = items } }
    return function() return groups end
end

function C.ColorSwatch(k, parent, text, get, set)
    local col = Column(k)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(col + 150, 24)
    C.Label(k, f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(40, 18)
    sw:SetPoint("LEFT", col, 0)
    sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    sw:SetBackdropBorderColor(1, 1, 1, 0.6)
    local function refresh()
        local c = get()
        sw:SetBackdropColor(c.r, c.g, c.b, 1)
    end
    local function apply(r, g, b)
        set(r, g, b)
        refresh()
        Refresh(k)
    end
    sw:SetScript("OnClick", function()
        local c = get()
        local r0, g0, b0 = c.r, c.g, c.b
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0,
            swatchFunc = function() apply(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() apply(r0, g0, b0) end,
        })
    end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

function C.TextBox(k, parent, text, get, set)
    local col, w = Column(k), k.opts.dropWidth or 210
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(col + w + 20, 26)
    C.Label(k, f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(w - 10, 20)
    eb:SetPoint("LEFT", col + 6, 0)
    eb:SetAutoFocus(false)
    eb:SetText(get())
    eb:SetScript("OnShow", function(self) self:SetText(get()) end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        set(self:GetText())
        Refresh(k)
    end)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    f.eb = eb
    return f
end

function C.Help(k, parent, text, width)
    local fs = C.Label(k, parent, text, "GameFontDisableSmall")
    fs:SetWidth(width or k.opts.helpWidth or 400)
    fs:SetJustifyH("LEFT")
    return fs
end

-- A small stepper for a pair on one row: a short label ("x", "y", "inset"), - value +.
function C.Mini(k, parent, label, min, max, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(130, 24)
    local l = C.Label(k, f, label, "GameFontDisableSmall")
    l:SetPoint("LEFT", 0, 0)
    l:SetWidth(34)
    l:SetJustifyH("RIGHT")
    local minus = C.Button(k, f, "-", 20, 20)
    minus:SetPoint("LEFT", 38, 0)
    local val = C.Label(k, f, "", "GameFontHighlightSmall")
    val:SetWidth(36)
    val:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = C.Button(k, f, "+", 20, 20)
    plus:SetPoint("LEFT", val, "RIGHT", 2, 0)
    local function refresh() val:SetText(get()) end
    local function change(d)
        if IsShiftKeyDown() then d = d * 10 end -- shift-click: ten steps at once
        set(math.max(min, math.min(max, get() + d)))
        refresh()
        Refresh(k)
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

-- One row: a label and two small steppers side by side. a, b: { label, min, max, get, set }.
function C.Pair(k, parent, text, a, b)
    local col = Column(k)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(col + 250, 24)
    C.Label(k, f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    C.Mini(k, f, a[1], a[2], a[3], a[4], a[5]):SetPoint("LEFT", col - 60, 0)
    if b then C.Mini(k, f, b[1], b[2], b[3], b[4], b[5]):SetPoint("LEFT", col + 80, 0) end
    return f
end

-- A key's x and y offsets on one row (right and up are +).
function C.XY(k, parent, text, o, key, range)
    range = range or 40
    return C.Pair(k, parent, text,
        { "x", -range, range, function() return o[key .. "X"] end, function(v) o[key .. "X"] = v end },
        { "y", -range, range, function() return o[key .. "Y"] end, function(v) o[key .. "Y"] = v end })
end

------------------------------------------------------------------------------
-- Spell lists (Personal Resource Tweaks' and XIVPlayer's aura whitelists and blacklists)
------------------------------------------------------------------------------

local ROW_H = 26

-- A mouse-wheel scroll list of icon + text rows; callers add their own buttons per row.
function C.ScrollList(_, parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(w, h)
    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * ROW_H)))
    end)
    sf.child, sf.rows, sf.w = child, {}, w
    return sf
end

-- The list's rows for `items`: setup(row, item, i) fills each (row.icon, row.text).
function C.FillList(k, sf, items, setup)
    for i, item in ipairs(items) do
        local r = sf.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, sf.child)
            r:SetSize(sf.w - 8, ROW_H)
            r:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H - 2)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT")
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.text = C.Label(k, r, "", "GameFontHighlight")
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.text:SetWidth(sf.w - 150)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            sf.rows[i] = r
        end
        setup(r, item, i)
        r:Show()
    end
    for i = #items + 1, #sf.rows do sf.rows[i]:Hide() end
    sf.child:SetHeight(math.max(1, #items * ROW_H + 4))
    local max = math.max(0, sf.child:GetHeight() - sf:GetHeight())
    if sf:GetVerticalScroll() > max then sf:SetVerticalScroll(max) end
end

-- A spell's name and icon.
function C.SpellInfo(_, id)
    return C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
end

-- A window beside `owner` listing the auras on you now ("buffs" or "debuffs"), each with an Add
-- button: onAdd(spellID). Ones the game hides are left out. say(text): messages to chat.
-- Returns the window (one per owner).
function C.AuraPicker(k, owner, kind, onAdd, say)
    if InCombatLockdown() then
        say("Leave combat to browse your current auras.")
        return owner.frogPicker
    end
    local pk = owner.frogPicker
    if not pk then
        pk = CreateFrame("Frame", nil, owner, "BasicFrameTemplateWithInset")
        pk:SetSize(320, 420)
        pk:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
        pk.title = C.Label(k, pk, "")
        pk.title:SetPoint("TOP", 0, -5)
        pk.list = C.ScrollList(k, pk, 296, 370)
        pk.list:SetPoint("TOPLEFT", 12, -32)
        owner.frogPicker = pk
    end
    pk.title:SetText("Your current " .. kind)
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
    C.FillList(k, pk.list, items, function(r, aura)
        r.icon:SetTexture(aura.icon)
        r.text:SetText((aura.name or "?") .. " |cff888888(" .. aura.spellId .. ")|r")
        if not r.add then
            r.add = C.Button(k, r, "Add", 44, 20)
            r.add:SetPoint("RIGHT", -2, 0)
        end
        r.add:SetScript("OnClick", function() onAdd(aura.spellId) end)
    end)
    if #items == 0 then say("You have no " .. kind .. " right now.") end
    pk:Show()
    return pk
end

function C.Compile(_, template, strings)
    return FrogLib.Text.Compile(template, strings)
end

function C.SetTemplateText(_, fs, template, vals, strings)
    FrogLib.Text.Set(fs, template, vals, strings)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

-- Lays controls out down a frame; given the frame, it grows to fit them.
function C.Placer(_, page)
    local y = 0
    return function(w, h, x)
        w:SetPoint("TOPLEFT", x or 0, -y)
        y = y + h
        if page then page:SetHeight(y + 4) end
    end
end

local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

function C.Sections(k, page, open, width)
    local list = {}
    local function IsOpen(s)
        local v = open[s.key]
        if v == nil then return s.default end
        return v
    end
    local function Relayout()
        local y = 0
        for _, s in ipairs(list) do
            s.header:ClearAllPoints()
            s.header:SetPoint("TOPLEFT", 0, -y)
            y = y + 26
            local on = IsOpen(s)
            s.icon:SetTexture(on and MINUS or PLUS)
            s.body:SetShown(on)
            if on then
                s.body:ClearAllPoints()
                s.body:SetPoint("TOPLEFT", 0, -y)
                y = y + s.body:GetHeight() + 8
            end
        end
        page:SetHeight(y + 10)
    end
    -- Adds a section; returns its placer. defaultOpen: open until the user closes it.
    local function Add(key, title, defaultOpen)
        local s = { key = key, default = defaultOpen and true or false }
        local header = CreateFrame("Button", nil, page)
        header:SetSize(width, 24)
        local bg = header:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.06)
        local hl = header:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.08)
        s.icon = header:CreateTexture(nil, "ARTWORK")
        s.icon:SetSize(16, 16)
        s.icon:SetPoint("LEFT", 4, 0)
        C.Label(k, header, title):SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
        header:SetScript("OnClick", function()
            open[s.key] = not IsOpen(s)
            Relayout()
        end)
        s.header = header
        s.body = CreateFrame("Frame", nil, page)
        s.body:SetSize(width, 1)
        list[#list + 1] = s
        return C.Placer(k, s.body), s.body
    end
    return Add, Relayout
end

-- A movable settings window with a row of tabs.
function C.Window(k, globalName, title, width, height, pages, wopts)
    wopts = wopts or {}
    local f = CreateFrame("Frame", globalName, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    C.Label(k, f, title):SetPoint("TOP", 0, -5)
    if globalName then tinsert(UISpecialFrames, globalName) end

    local frames, contents, tabs = {}, {}, {}
    local function select(key)
        for key2, page in pairs(frames) do page:SetShown(key2 == key) end
        for key2, tab in pairs(tabs) do
            if key2 == key then tab:LockHighlight() else tab:UnlockHighlight() end
        end
        if wopts.onSelect then wopts.onSelect(key) end
    end
    local tabW, step = wopts.tabWidth or 100, (wopts.tabWidth or 100) + (wopts.tabGap or 4)
    if wopts.fitTabs then
        step = math.floor((width - 28) / #pages)
        tabW = step - 2
    end
    for i, def in ipairs(pages) do
        local key = def[1]
        local tab = C.Button(k, f, def[2], tabW)
        tab:SetPoint("TOPLEFT", 14 + (i - 1) * step, -30)
        tab:SetScript("OnClick", function() select(key) end)
        local fs = tab:GetFontString()
        if fs and wopts.fitTabs then fs:SetWordWrap(false) end
        tabs[key] = tab
        local page, content
        if wopts.scroll then
            page = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
            page:SetPoint("TOPLEFT", 16, -64)
            page:SetPoint("BOTTOMRIGHT", -34, 12)
            content = CreateFrame("Frame", nil, page)
            content:SetSize(width - 60, 10)
            page:SetScrollChild(content)
        else
            page = CreateFrame("Frame", nil, f)
            page:SetPoint("TOPLEFT", 16, -62)
            page:SetPoint("BOTTOMRIGHT", -16, 12)
            content = page
        end
        frames[key], contents[key] = page, content
    end
    for _, def in ipairs(pages) do
        if def[3] then def[3](contents[def[1]]) end
    end
    select(pages[1][1])
    f.Select = select
    return f, contents
end
