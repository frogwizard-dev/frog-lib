-- FrogLib Icons: the small icons unit frames and bars show by a name.
-- Raid marks: which mark a unit has can be secret in combat, so it's never looked at. It goes into
-- the icon's file name inside a FontString's text ("|T...RaidTargetingIcon_%d:size|t"), which
-- SetFormattedText fills in engine-side; a secret "no mark" fails to format, and shows nothing.
--   FrogLib.Icons.RaidMarkup(size) -> the format string for a mark `size` pixels square
--   FrogLib.Icons.SetRaidMark(fs, index, size) -> whether a mark went into fs (index may be
--       secret; nil or false: no mark). It doesn't show or hide fs.
--   FrogLib.Icons.RaidMark(fs, unit, size) -> the same, for the unit's own mark
--   FrogLib.Icons.Set(tex, atlas, file, coords): the modern atlas where the client has it,
--       otherwise the classic file (cut to coords)
--   FrogLib.Icons.SetClass(tex, class) -> whether a class's round icon went on (class: its token)
--   FrogLib.Icons.SHOW[key](region, unit, size) -> whether the icon applies to the unit (and is
--       set): raid (a FontString), leader (or assistant), role, pvp (players only: faction guards
--       are flagged too), quest (a quest boss), class (players only)
--   FrogLib.Icons.PREVIEW[key](region, size) -> true, with a sample set (raid, leader, class)

local Icons = FrogLib:Module("Icons", 1)
if not Icons then return end

local Safe = FrogLib.Safe

local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local PVP_COORDS = { 0.08, 0.58, 0.045, 0.545 } -- the old PvP badges sit in the corner of a larger file
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local FULL = { 0, 1, 0, 1 }

function Icons.RaidMarkup(size)
    return "|T" .. RAID_ICON .. "%d:" .. size .. ":" .. size .. "|t"
end

function Icons.SetRaidMark(fs, index, size)
    if not FrogLib.issecret(index) and not index then return false end
    return (pcall(fs.SetFormattedText, fs, Icons.RaidMarkup(size), index))
end

function Icons.RaidMark(fs, unit, size)
    return Icons.SetRaidMark(fs, GetRaidTargetIndex(unit), size)
end

local function HasAtlas(atlas)
    return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

function Icons.Set(tex, atlas, file, coords)
    if HasAtlas(atlas) then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture(file)
        local c = coords or FULL
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    end
end

-- The game's class atlas (as its portraits use), or the old sheet of class circles.
function Icons.SetClass(tex, class)
    if type(class) ~= "string" or FrogLib.issecret(class) then return false end
    local atlas = GetClassAtlas and GetClassAtlas(class) or ("classicon-" .. class:lower())
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not (HasAtlas(atlas) or coords) then return false end
    Icons.Set(tex, atlas, CLASS_CIRCLES, coords)
    return true
end

local function Leader(tex)
    Icons.Set(tex, "UI-HUD-UnitFrame-Player-Group-LeaderIcon", "Interface\\GroupFrame\\UI-Group-LeaderIcon")
end

local SHOW = {}
Icons.SHOW = SHOW

function SHOW.raid(fs, unit, size)
    return Icons.RaidMark(fs, unit, size)
end

function SHOW.leader(tex, unit)
    if Safe(UnitIsGroupLeader(unit)) then
        Leader(tex)
        return true
    elseif Safe(UnitIsGroupAssistant(unit)) then
        Icons.Set(tex, "UI-HUD-UnitFrame-Player-Group-AssistantIcon", "Interface\\GroupFrame\\UI-Group-AssistantIcon")
        return true
    end
    return false
end

function SHOW.role(tex, unit)
    local role = UnitGroupRolesAssigned and Safe(UnitGroupRolesAssigned(unit))
    if not role or not ROLE_ATLAS[role] then return false end
    Icons.Set(tex, ROLE_ATLAS[role], "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
        GetTexCoordsForRoleSmallCircle and { GetTexCoordsForRoleSmallCircle(role) })
    return true
end

function SHOW.pvp(tex, unit)
    if not Safe(UnitIsPlayer(unit)) then return false end
    if Safe(UnitIsPVPFreeForAll(unit)) then
        Icons.Set(tex, "UI-HUD-UnitFrame-Player-PVP-FFAIcon", "Interface\\TargetingFrame\\UI-PVP-FFA", PVP_COORDS)
        return true
    end
    if Safe(UnitIsPVP(unit)) then
        local faction = Safe(UnitFactionGroup(unit))
        if faction == "Horde" or faction == "Alliance" then
            Icons.Set(tex, "UI-HUD-UnitFrame-Player-PVP-" .. faction .. "Icon",
                "Interface\\TargetingFrame\\UI-PVP-" .. faction, PVP_COORDS)
            return true
        end
    end
    return false
end

function SHOW.quest(tex, unit)
    if not Safe(UnitIsQuestBoss(unit)) then return false end
    Icons.Set(tex, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest", "Interface\\TargetingFrame\\PortraitQuestBadge")
    return true
end

-- An NPC's class says little; nothing when the class is secret.
function SHOW.class(tex, unit)
    if not Safe(UnitIsPlayer(unit)) then return false end
    local _, class = UnitClass(unit)
    return Icons.SetClass(tex, Safe(class))
end

Icons.PREVIEW = {
    raid = function(fs, size) return Icons.SetRaidMark(fs, 1, size) end,
    leader = function(tex)
        Leader(tex)
        return true
    end,
    class = function(tex) return Icons.SetClass(tex, "PALADIN") end,
}
