-- FrogLib Hider: hides Blizzard's frames (unit frames, cast bars, bars, the minimap...) so several of
-- Frog Wizard's addons can hide the same frame without undoing each other. The hidden frame is shared
-- with the Hider.lua older releases carry; its state lives in this part's table and its hooks call
-- through it, so a newer copy takes over the frames an older one hid.

local Hider = FrogLib:Module("Hider", 4) -- 2: opts.fadeOnly; 3: an unchanged Set does nothing;
-- 4: menu owners only fade in the gamepad UI, scales set past Edit Mode's override
if not Hider then return end

-- [frame] = { frame, owners = { [owner] = keep list }, kept = { [child] = its own scale },
--             home, homeScale (where it goes back to), faded }
Hider.frames = Hider.frames or {}
Hider.keptBy = Hider.keptBy or {}   -- [child] = the state of the hidden frame it was kept out of
Hider.watched = Hider.watched or {} -- [child] = true once we watch where Blizzard puts it
local frames, keptBy, watched = Hider.frames, Hider.keptBy, Hider.watched
local NONE = {}

-- The hidden frame they go under (FrogwizardHiddenParent).
function Hider.Parent()
    local hidden = Hider.hiddenParent
    if not hidden then
        hidden = _G.FrogwizardHiddenParent or CreateFrame("Frame", "FrogwizardHiddenParent")
        hidden:Hide()
        Hider.hiddenParent = hidden
    end
    return hidden
end

local function Blocked()
    return InCombatLockdown() or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

local function Resolve(frame)
    if type(frame) == "string" then frame = _G[frame] end
    if type(frame) == "table" and frame.GetParent then return frame end
    return nil
end

local function On(state)
    return state ~= nil and next(state.owners) ~= nil
end

-- Frames the gamepad UI opens a menu on: Y opens the target menu on TargetFrame, and a menu closes the moment its
-- owner isn't visible. In the gamepad UI they only fade, their mouse off, so the menu stays (as EllesmereUI does);
-- listed with them, their children that take clicks (the target of target's button) go mouse-off too, unless an
-- owner keeps them on screen.
local MENU_OWNERS = { TargetFrame = { "totFrame" } }

local function GamepadUI()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

local function FadeOnly(state)
    if state.fadeOnly then return true end
    local name = state.frame:GetName()
    return name ~= nil and MENU_OWNERS[name] ~= nil and GamepadUI()
end

-- Edit Mode replaces its frames' SetScale with one that re-anchors and lays out the managed frames: the original,
-- so that layout doesn't run under our taint.
local function SetScale(frame, scale)
    (frame.SetScaleBase or frame.SetScale)(frame, scale)
end

-- Whether any owner is hiding it.
function Hider.IsHidden(frame)
    frame = Resolve(frame)
    return frame ~= nil and On(frames[frame])
end

------------------------------------------------------------------------------
-- Hooks (they call through the part's table, so the newest copy answers)
------------------------------------------------------------------------------

function Hider.FlushSoon()
    if Hider.soon then return end
    Hider.soon = true
    C_Timer.After(0, function()
        Hider.soon = nil
        Hider.Flush()
    end)
end

-- `fading` stops our own SetAlpha from re-entering the hook.
local fading = false
local function SetAlpha(frame, alpha)
    fading = true
    pcall(frame.SetAlpha, frame, alpha)
    fading = false
end

-- Blizzard sets its opacity back (fades, layout, Edit Mode); ours goes on after.
function Hider.OnSetAlpha(frame)
    if fading then return end
    local state = frames[frame]
    if On(state) then
        SetAlpha(frame, 0)
        state.faded = true
    end
end

-- Edit Mode, the managed-frame layout and vehicles can put it back under its old parent.
function Hider.OnSetParent(frame, parent)
    if On(frames[frame]) and parent ~= Hider.hiddenParent then Hider.FlushSoon() end
end

-- A kept child moved by Blizzard: back under its hidden frame (the cast bar locking under the
-- player frame), or somewhere new.
function Hider.OnChildSetParent(child, parent)
    if (keptBy[child] and parent ~= UIParent) or (On(frames[parent]) and not On(frames[child])) then
        Hider.FlushSoon()
    end
end

local function Watch(child)
    if watched[child] then return end
    watched[child] = true
    hooksecurefunc(child, "SetParent", function(moved, parent) Hider.OnChildSetParent(moved, parent) end)
end

------------------------------------------------------------------------------
-- Two layers, so a frame stays hidden in every situation
------------------------------------------------------------------------------

-- Opacity: at once and in combat too, kept at 0 whatever Blizzard sets, so a frame hidden mid-fight
-- (or moved back under its old parent mid-fight) stays unseen until the parent layer takes it.
local function Fade(state)
    if On(state) then
        SetAlpha(state.frame, 0)
        state.faded = true
    elseif state.faded then
        SetAlpha(state.frame, 1)
        state.faded = nil
    end
end

-- The children to keep out while it's hidden: every owner's list, less those hidden themselves.
local function KeepSet(state)
    local set = {}
    for _, keep in pairs(state.owners) do
        for _, listed in ipairs(keep) do
            local child = Resolve(listed)
            if not child and type(listed) == "string" then child = Resolve(state.frame[listed]) end
            if child and child ~= state.frame then
                Watch(child)
                if not On(frames[child]) then set[child] = true end
            end
        end
    end
    return set
end

-- Parent: under the hidden frame, its events still running (anything it drives still updates),
-- unseen and unclickable. Never in combat or Edit Mode (Blizzard's layout code under our taint).
local function Take(state, hidden)
    local frame = state.frame
    local parent = frame:GetParent()
    if parent == hidden then return end
    state.home, state.homeScale = parent, nil
    local from = keptBy[frame]
    if from then
        -- Kept out of another hidden frame: it goes back there, at its own scale.
        state.homeScale = from.kept[frame]
        if parent == UIParent then state.home = from.frame end
        from.kept[frame] = nil
        keptBy[frame] = nil
    end
    frame:SetParent(hidden)
end

local function Release(state, hidden)
    local frame = state.frame
    if state.home and frame:GetParent() == hidden then
        frame:SetParent(state.home)
        if state.homeScale then SetScale(frame, state.homeScale) end
    end
    state.home, state.homeScale = nil, nil
end

-- A frame only faded takes no clicks while hidden (out of combat only, as Apply is), nor its listed children that
-- aren't kept out (state.childMouse: those we turned off).
local function MouseOne(frame, off, store, key)
    if off and not store[key] and frame:IsMouseEnabled() then
        frame:EnableMouse(false)
        store[key] = true
    elseif not off and store[key] then
        frame:EnableMouse(true)
        store[key] = nil
    end
end

local function Mouse(state, off)
    local frame = state.frame
    MouseOne(frame, off, state, "mouseOff")
    local name = frame:GetName()
    local children = name and MENU_OWNERS[name]
    if not children then return end
    state.childMouse = state.childMouse or {}
    for _, key in ipairs(children) do
        local child = frame[key]
        if type(child) == "table" and child.EnableMouse then
            MouseOne(child, off and child:GetParent() == frame, state.childMouse, child)
        end
    end
end

-- Children kept out that should go back in (no longer kept, or the frame's shown), and the size
-- of those staying out (Edit Mode's frame size can change meanwhile).
local function Settle(state, keep)
    local frame = state.frame
    for child, scale in pairs(state.kept) do
        local parent = child:GetParent()
        if parent == UIParent and keep and keep[child] then
            local want = scale * frame:GetScale()
            if child:GetScale() ~= want then SetScale(child, want) end
        else
            state.kept[child] = nil
            keptBy[child] = nil
            if parent == UIParent then child:SetParent(frame) end
            SetScale(child, scale)
        end
    end
end

-- Kept children move out to UIParent, keeping their place and size, and go back when it's shown.
local function KeepOut(state, keep)
    local frame = state.frame
    for child in pairs(keep) do
        if child:GetParent() == frame then
            -- Its size came partly from the frame's scale (Edit Mode's frame size).
            local scale = state.kept[child] or child:GetScale()
            state.kept[child] = scale
            keptBy[child] = state
            child:SetParent(UIParent)
            SetScale(child, scale * frame:GetScale())
        end
    end
end

-- Only faded (a menu owner in the gamepad UI), it stays under its own parent, but its kept children still move out:
-- left in, they'd fade with it (Blizzard's combo points sit on the target frame).
local function Apply(state, hidden)
    local fadeOnly = FadeOnly(state)
    if On(state) then
        local keep = KeepSet(state)
        if fadeOnly then Release(state, hidden) else Take(state, hidden) end
        Settle(state, keep)
        KeepOut(state, keep)
    else
        Settle(state, nil)
        Release(state, hidden)
    end
    Mouse(state, On(state) and fadeOnly and not state.fadeOnly)
end

-- Frames come back before others hide, so a child going back to its parent (the pet frame to the
-- player frame) is there to be kept out when the parent hides.
function Hider.Flush()
    for _, state in pairs(frames) do Fade(state) end
    if Blocked() then
        Hider.pending = true
        return
    end
    Hider.pending = nil
    local hidden = Hider.Parent()
    for _, state in pairs(frames) do
        if not On(state) then Apply(state, hidden) end
    end
    for _, state in pairs(frames) do
        if On(state) then Apply(state, hidden) end
    end
end

-- Hides them all again now (it does so itself, after combat, loading screens and Edit Mode).
function Hider.Refresh()
    if next(frames) then Hider.Flush() end
end

-- Whether an owner's kept list (as Set copied it) holds what `list` does.
local function SameKeep(had, list)
    local count = 0
    for i, listed in ipairs(list or NONE) do
        if had[i] ~= listed then return false end
        count = i
    end
    return had[count + 1] == nil
end

-- owner: the addon's name; frame: a frame or its global name (nothing if the game has none). Hidden
-- while any owner wants it. opts.fadeOnly: the opacity layer only, for a frame that asks its parent things.
-- The same request again changes nothing, so it's let be (the hooks and events keep the frames in place).
function Hider.Set(owner, frame, hidden, opts)
    assert(owner ~= nil, "FrogLib.Hider.Set: who's asking (the addon's name) comes first")
    frame = Resolve(frame)
    if not frame then return end
    local state = frames[frame]
    if not state then
        if not hidden then return end
        state = { frame = frame, owners = {}, kept = {} }
        frames[frame] = state
        hooksecurefunc(frame, "SetParent", function(hooked, parent) Hider.OnSetParent(hooked, parent) end)
        hooksecurefunc(frame, "SetAlpha", function(hooked) Hider.OnSetAlpha(hooked) end)
    end
    local had = state.owners[owner]
    if not Hider.pending then
        if hidden and had and SameKeep(had, opts and opts.keep)
            and state.fadeOnly == (opts and opts.fadeOnly or nil) then return end
        if not hidden and had == nil then return end
    end
    if hidden then
        -- opts.keep: children that stay on screen (global names, keys on the frame or frames), such as
        -- { "PetFrame", "TotemFrame" } for the player frame; each call replaces this owner's list.
        local keep = NONE
        if opts and opts.keep then
            keep = {}
            for i, listed in ipairs(opts.keep) do keep[i] = listed end
        end
        state.owners[owner] = keep
        state.fadeOnly = opts and opts.fadeOnly or nil
    else
        state.owners[owner] = nil
    end
    Hider.Flush()
end

------------------------------------------------------------------------------
-- Checking again
------------------------------------------------------------------------------

function Hider.OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if Hider.pending then Hider.Flush() end
    elseif next(frames) then
        -- A loading screen, Edit Mode closing or a new Edit Mode layout (gamepad and keyboard swap
        -- layouts) can lay Blizzard's frames out again.
        Hider.FlushSoon()
    end
end

Hider.events = Hider.events or CreateFrame("Frame")
Hider.events:RegisterEvent("PLAYER_REGEN_ENABLED")
Hider.events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(Hider.events.RegisterEvent, Hider.events, "EDIT_MODE_LAYOUTS_UPDATED")
-- Into or out of the gamepad UI (read a frame later, when the new style is in): menu owners fade or go back under.
pcall(Hider.events.RegisterEvent, Hider.events, "INPUT_DEVICE_INTERFACE_TRANSITION")
Hider.events:SetScript("OnEvent", function(_, event) Hider.OnEvent(event) end)
if EventRegistry and not Hider.editModeHooked then
    Hider.editModeHooked = true
    EventRegistry:RegisterCallback("EditMode.Exit", function() Hider.OnEvent("EditMode.Exit") end)
end
