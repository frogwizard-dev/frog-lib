-- FrogLib Hider: hides Blizzard's frames (unit frames, cast bars, bars, the minimap...), so that
-- several of Frog Wizard's addons can hide the same frame without undoing each other.
--   FrogLib.Hider.Set(owner, frame, hidden, opts)
--       owner: who's asking, the addon's name. frame: a frame or its global name (nothing happens
--       if the game has no such frame). A frame stays hidden while any owner wants it hidden, and
--       comes back once none do.
--       opts.keep: children with a life of their own that stay on screen while the frame is
--       hidden, as global names, keys on the frame, or the frames themselves; e.g. the player
--       frame with { keep = { "PetFrame", "TotemFrame" } }, or the cast bar while Edit Mode has
--       it locked under the player frame ("PlayerCastingBarFrame"). They move out to UIParent,
--       keeping their place and size, and go back when it's shown. Each call replaces that
--       owner's list (so it can change from call to call), and the frame keeps out every child
--       any of its owners lists. A child that's hidden itself (Set on it too) just stays hidden.
--   FrogLib.Hider.IsHidden(frame) -> whether any owner is hiding it
--   FrogLib.Hider.Parent()        -> the hidden frame they go under (FrogwizardHiddenParent)
--   FrogLib.Hider.Refresh()       -> hide them all again now (it does so itself; see below)
-- Two layers, so a frame stays hidden in every situation:
--   * Opacity: at once, and kept at 0 whatever Blizzard sets it to (its fades, the managed-frame
--     layout's alpha, Edit Mode). Opacity can be set in combat, so a frame hidden mid-fight, or
--     one Blizzard moves back under its old parent mid-fight (the cast bar's layout does), stays
--     invisible until the parent layer takes it.
--   * Parent: out of combat and Edit Mode, the frame moves under a hidden frame. Its events keep
--     running, so anything it drives still updates, and it can't be seen or clicked. Unit frames
--     are protected, so nothing is re-parented in combat or in Edit Mode (where it runs
--     Blizzard's layout code under our taint): that waits for the fight's end or Edit Mode's.
-- Everything is checked again after combat, loading screens, Edit Mode and its layout changes
-- (switching between gamepad and keyboard swaps layouts), and whenever Blizzard moves a hidden
-- frame or a kept child (the cast bar locking under the player frame) somewhere else.
-- Frames come back before others hide, so a child going back to its parent (the pet frame to the
-- player frame) is there to be kept out when the parent hides.
-- The hidden frame is shared with the Hider.lua the addons used to carry each (still in older
-- releases): with one each, two addons hiding the same frame would keep taking it from each other.
-- Its state lives in this part's table and its hooks call through it, so a newer copy takes over
-- the frames an older one hid.

local Hider = FrogLib:Module("Hider", 1)
if not Hider then return end

-- [frame] = { frame, owners = { [owner] = keep list }, kept = { [child] = its own scale },
--             home, homeScale (where it goes back to), faded }
Hider.frames = Hider.frames or {}
Hider.keptBy = Hider.keptBy or {}   -- [child] = the state of the hidden frame it was kept out of
Hider.watched = Hider.watched or {} -- [child] = true once we watch where Blizzard puts it
local frames, keptBy, watched = Hider.frames, Hider.keptBy, Hider.watched
local NONE = {}

function Hider.Parent()
    local h = Hider.hiddenParent
    if not h then
        h = _G.FrogwizardHiddenParent or CreateFrame("Frame", "FrogwizardHiddenParent")
        h:Hide()
        Hider.hiddenParent = h
    end
    return h
end

local function Blocked()
    return InCombatLockdown() or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

local function Resolve(frame)
    if type(frame) == "string" then frame = _G[frame] end
    if type(frame) == "table" and frame.GetParent then return frame end
    return nil
end

local function On(s)
    return s ~= nil and next(s.owners) ~= nil
end

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
    local s = frames[frame]
    if On(s) then
        SetAlpha(frame, 0)
        s.faded = true
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
    hooksecurefunc(child, "SetParent", function(c, parent) Hider.OnChildSetParent(c, parent) end)
end

------------------------------------------------------------------------------
-- The two layers
------------------------------------------------------------------------------

local function Fade(s)
    if On(s) then
        SetAlpha(s.frame, 0)
        s.faded = true
    elseif s.faded then
        SetAlpha(s.frame, 1)
        s.faded = nil
    end
end

-- The children to keep out while it's hidden: every owner's list, less those hidden themselves.
local function KeepSet(s)
    local set = {}
    for _, keep in pairs(s.owners) do
        for _, k in ipairs(keep) do
            local child = Resolve(k)
            if not child and type(k) == "string" then child = Resolve(s.frame[k]) end
            if child and child ~= s.frame then
                Watch(child)
                if not On(frames[child]) then set[child] = true end
            end
        end
    end
    return set
end

local function Take(s, hidden)
    local frame = s.frame
    local parent = frame:GetParent()
    if parent == hidden then return end
    s.home, s.homeScale = parent, nil
    local from = keptBy[frame]
    if from then
        -- Kept out of another hidden frame: it goes back there, at its own scale.
        s.homeScale = from.kept[frame]
        if parent == UIParent then s.home = from.frame end
        from.kept[frame] = nil
        keptBy[frame] = nil
    end
    frame:SetParent(hidden)
end

local function Release(s, hidden)
    local frame = s.frame
    if s.home and frame:GetParent() == hidden then
        frame:SetParent(s.home)
        if s.homeScale then frame:SetScale(s.homeScale) end
    end
    s.home, s.homeScale = nil, nil
end

-- Children kept out that should go back in (no longer kept, or the frame's shown), and the size
-- of those staying out (Edit Mode's frame size can change meanwhile).
local function Settle(s, keep)
    local frame = s.frame
    for child, scale in pairs(s.kept) do
        local parent = child:GetParent()
        if parent == UIParent and keep and keep[child] then
            local want = scale * frame:GetScale()
            if child:GetScale() ~= want then child:SetScale(want) end
        else
            s.kept[child] = nil
            keptBy[child] = nil
            if parent == UIParent then child:SetParent(frame) end
            child:SetScale(scale)
        end
    end
end

local function KeepOut(s, keep)
    local frame = s.frame
    for child in pairs(keep) do
        if child:GetParent() == frame then
            -- Its size came partly from the frame's scale (Edit Mode's frame size).
            local scale = s.kept[child] or child:GetScale()
            s.kept[child] = scale
            keptBy[child] = s
            child:SetParent(UIParent)
            child:SetScale(scale * frame:GetScale())
        end
    end
end

local function Apply(s, hidden)
    if On(s) then
        local keep = KeepSet(s)
        Take(s, hidden)
        Settle(s, keep)
        KeepOut(s, keep)
    else
        Settle(s, nil)
        Release(s, hidden)
    end
end

function Hider.Flush()
    for _, s in pairs(frames) do Fade(s) end
    if Blocked() then
        Hider.pending = true
        return
    end
    Hider.pending = nil
    local hidden = Hider.Parent()
    for _, s in pairs(frames) do
        if not On(s) then Apply(s, hidden) end
    end
    for _, s in pairs(frames) do
        if On(s) then Apply(s, hidden) end
    end
end

function Hider.Refresh()
    if next(frames) then Hider.Flush() end
end

function Hider.Set(owner, frame, hidden, opts)
    assert(owner ~= nil, "FrogLib.Hider.Set: who's asking (the addon's name) comes first")
    frame = Resolve(frame)
    if not frame then return end
    local s = frames[frame]
    if not s then
        if not hidden then return end
        s = { frame = frame, owners = {}, kept = {} }
        frames[frame] = s
        hooksecurefunc(frame, "SetParent", function(f, parent) Hider.OnSetParent(f, parent) end)
        hooksecurefunc(frame, "SetAlpha", function(f) Hider.OnSetAlpha(f) end)
    end
    if hidden then
        local keep = NONE
        if opts and opts.keep then
            keep = {}
            for i, k in ipairs(opts.keep) do keep[i] = k end
        end
        s.owners[owner] = keep
    else
        s.owners[owner] = nil
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
        -- A loading screen, Edit Mode closing or a new Edit Mode layout can lay Blizzard's
        -- frames out again.
        Hider.FlushSoon()
    end
end

Hider.events = Hider.events or CreateFrame("Frame")
Hider.events:RegisterEvent("PLAYER_REGEN_ENABLED")
Hider.events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(Hider.events.RegisterEvent, Hider.events, "EDIT_MODE_LAYOUTS_UPDATED")
Hider.events:SetScript("OnEvent", function(_, event) Hider.OnEvent(event) end)
if EventRegistry and not Hider.editModeHooked then
    Hider.editModeHooked = true
    EventRegistry:RegisterCallback("EditMode.Exit", function() Hider.OnEvent("EditMode.Exit") end)
end
