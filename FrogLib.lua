-- FrogLib: the code Frog Wizard's addons share. Each addon carries a copy in Libs\FrogLib (the
-- packager adds frog-lib's latest release; _tools\sync_froglib.py does it locally; never edit a
-- copy), and it also loads on its own as the FrogLib addon. With several loaded, the newest copy
-- of each part wins, so a newer part must stay compatible with the old.

local MINOR = 2 -- 2: PixelSnap (1 shipped in the first releases of the addons)

local lib = _G.FrogLib
if lib and (lib.minor or 0) >= MINOR then return end
lib = lib or {}
_G.FrogLib = lib
lib.minor = MINOR
lib.modules = lib.modules or {}

-- A part's table to fill in, or nil when a copy of it as new (the same or a higher minor) has loaded.
function lib:Module(name, minor)
    local part = self.modules[name]
    if part and (part.minor or 0) >= minor then return nil end
    part = part or {}
    part.minor = minor
    self.modules[name] = part
    self[name] = part
    return part
end

-- Midnight hides some combat values from addons ("secret values"): they can be handed to the
-- game's widgets, but not compared or used in arithmetic.
lib.issecret = issecretvalue or function() return false end

-- The value, or nil when the game hides it.
function lib.Safe(value)
    if lib.issecret(value) then return nil end
    return value
end

-- One screen pixel in the frame's units.
function lib.Pixel(frame)
    return 768 / select(2, GetPhysicalScreenSize()) / frame:GetEffectiveScale()
end

-- Keeps a texture exactly where it's put (no pixel snapping).
function lib.NoSnap(region)
    if region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        region:SetTexelSnappingBias(0)
    end
end

-- Lays a region out on whole screen pixels, its texture unsnapped: crisp 1px borders sized in pixels.
function lib.PixelSnap(region)
    if region and region.SetRoundLayoutToNearestPixel then region:SetRoundLayoutToNearestPixel(true) end
    lib.NoSnap(region)
end

function lib.Loaded(addon)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded ~= nil and isLoaded(addon) and true or false
end
