-- FrogLib: the code Frog Wizard's addons share. It has a repository of its own (frog-lib), and
-- each addon carries a copy in Libs\FrogLib: added by the packager when the addon is built (its
-- .pkgmeta "externals"), and locally by _tools\sync_froglib.py. Never edit an addon's copy.
-- It also loads on its own, as the FrogLib addon.
-- With several addons loaded, the newest copy of each part wins: a part only loads if no copy
-- with the same or a higher minor version has, so a newer one must stay compatible with the old.
--
--   FrogLib:Module(name, minor) -> the part's table to fill in, or nil if one as new is loaded
--   FrogLib.Pixel(frame)        -> one screen pixel in frame's units
--   FrogLib.NoSnap(region)      -> keep a texture exactly where it's put (no pixel snapping)
--   FrogLib.PixelSnap(region)   -> lay a region out on whole screen pixels, its texture unsnapped
--                                  (crisp 1px borders sized in pixels)
--   FrogLib.issecret(v), FrogLib.Safe(v) -> v, or nil when the game hides it from addons
--   FrogLib.Loaded(addon)       -> whether an addon is loaded
-- The parts: Options (the "Frog Wizard" section of Options > AddOns), Media (texture and font
-- lists), Borders (pixel, classic stone and Forever frames), Threat (your lead on a unit), Hider
-- (hiding Blizzard's frames, shared between the addons that hide the same one), Curve (step
-- curves the game reads a secret health or power through), Idle (fade when idle), Swing (swing
-- timers), Cast (reading casts, and when a cast bar shows), FSR (the five-second rule), Text (text
-- templates), Color (class, reaction and power colours), Unit (names, levels, percentages and the
-- template words for a unit), Icons (raid marks and the icons by a name) and Secure (click-to-target
-- buttons with the unit menu on right-click).

local MINOR = 2 -- 2: PixelSnap (1 shipped in the first releases of the addons)

local lib = _G.FrogLib
if lib and (lib.minor or 0) >= MINOR then return end
lib = lib or {}
_G.FrogLib = lib
lib.minor = MINOR
lib.modules = lib.modules or {}

function lib:Module(name, minor)
    local m = self.modules[name]
    if m and (m.minor or 0) >= minor then return nil end
    m = m or {}
    m.minor = minor
    self.modules[name] = m
    self[name] = m
    return m
end

-- Midnight hides some combat values from addons ("secret values"): they can be handed to the
-- game's widgets, but not compared or used in arithmetic.
lib.issecret = issecretvalue or function() return false end

function lib.Safe(v)
    if lib.issecret(v) then return nil end
    return v
end

function lib.Pixel(frame)
    return 768 / select(2, GetPhysicalScreenSize()) / frame:GetEffectiveScale()
end

function lib.NoSnap(region)
    if region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        region:SetTexelSnappingBias(0)
    end
end

function lib.PixelSnap(region)
    if region and region.SetRoundLayoutToNearestPixel then region:SetRoundLayoutToNearestPixel(true) end
    lib.NoSnap(region)
end

function lib.Loaded(addon)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded ~= nil and isLoaded(addon) and true or false
end
