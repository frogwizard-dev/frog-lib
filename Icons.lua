-- FrogLib Icons: the small icons unit frames and bars show by a name. Which raid mark a unit has
-- can be secret in combat, so it's never looked at: it goes into the icon's file name inside a
-- font string's text ("|T...RaidTargetingIcon_%d:size|t"), which SetFormattedText fills in
-- engine-side; a secret "no mark" fails to format, and shows nothing.

local Icons = FrogLib:Module("Icons", 2) -- 2: a failed mark clears the text
if not Icons then return end

local Safe = FrogLib.Safe

local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local PVP_COORDS = { 0.08, 0.58, 0.045, 0.545 } -- the old PvP badges sit in the corner of a larger file
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local FULL = { 0, 1, 0, 1 }

-- The format string for a mark `size` pixels square.
function Icons.RaidMarkup(size)
    return "|T" .. RAID_ICON .. "%d:" .. size .. ":" .. size .. "|t"
end

-- Whether a mark went into the font string (index may be secret; nil or false: no mark). It
-- doesn't show or hide it.
function Icons.SetRaidMark(fontString, index, size)
    if not FrogLib.issecret(index) and not index then return false end
    local ok = pcall(fontString.SetFormattedText, fontString, Icons.RaidMarkup(size), index)
    if not ok then fontString:SetText("") end -- not the last mark
    return ok
end

-- The same, for the unit's own mark.
function Icons.RaidMark(fontString, unit, size)
    return Icons.SetRaidMark(fontString, GetRaidTargetIndex(unit), size)
end

local function HasAtlas(atlas)
    return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- The modern atlas where the client has it, otherwise the classic file (cut to coords).
function Icons.Set(texture, atlas, file, coords)
    if HasAtlas(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetTexture(file)
        local cut = coords or FULL
        texture:SetTexCoord(cut[1], cut[2], cut[3], cut[4])
    end
end

-- Whether a class's round icon went on (class: its token): the game's class atlas, as its
-- portraits use, or the old sheet of class circles.
function Icons.SetClass(texture, class)
    if type(class) ~= "string" or FrogLib.issecret(class) then return false end
    local atlas = GetClassAtlas and GetClassAtlas(class) or ("classicon-" .. class:lower())
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not (HasAtlas(atlas) or coords) then return false end
    Icons.Set(texture, atlas, CLASS_CIRCLES, coords)
    return true
end

local function Leader(texture)
    Icons.Set(texture, "UI-HUD-UnitFrame-Player-Group-LeaderIcon", "Interface\\GroupFrame\\UI-Group-LeaderIcon")
end

-- SHOW[key](region, unit, size) -> whether the icon applies to the unit (and is set): raid (a font
-- string), leader (or assistant), role, pvp, quest (a quest boss), class.
local SHOW = {}
Icons.SHOW = SHOW

function SHOW.raid(fontString, unit, size)
    return Icons.RaidMark(fontString, unit, size)
end

function SHOW.leader(texture, unit)
    if Safe(UnitIsGroupLeader(unit)) then
        Leader(texture)
        return true
    elseif Safe(UnitIsGroupAssistant(unit)) then
        Icons.Set(texture, "UI-HUD-UnitFrame-Player-Group-AssistantIcon", "Interface\\GroupFrame\\UI-Group-AssistantIcon")
        return true
    end
    return false
end

function SHOW.role(texture, unit)
    local role = UnitGroupRolesAssigned and Safe(UnitGroupRolesAssigned(unit))
    if not role or not ROLE_ATLAS[role] then return false end
    Icons.Set(texture, ROLE_ATLAS[role], "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
        GetTexCoordsForRoleSmallCircle and { GetTexCoordsForRoleSmallCircle(role) })
    return true
end

-- Players only (faction guards are flagged too).
function SHOW.pvp(texture, unit)
    if not Safe(UnitIsPlayer(unit)) then return false end
    if Safe(UnitIsPVPFreeForAll(unit)) then
        Icons.Set(texture, "UI-HUD-UnitFrame-Player-PVP-FFAIcon", "Interface\\TargetingFrame\\UI-PVP-FFA", PVP_COORDS)
        return true
    end
    if Safe(UnitIsPVP(unit)) then
        local faction = Safe(UnitFactionGroup(unit))
        if faction == "Horde" or faction == "Alliance" then
            Icons.Set(texture, "UI-HUD-UnitFrame-Player-PVP-" .. faction .. "Icon",
                "Interface\\TargetingFrame\\UI-PVP-" .. faction, PVP_COORDS)
            return true
        end
    end
    return false
end

function SHOW.quest(texture, unit)
    if not Safe(UnitIsQuestBoss(unit)) then return false end
    Icons.Set(texture, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest", "Interface\\TargetingFrame\\PortraitQuestBadge")
    return true
end

-- An NPC's class says little; nothing when the class is secret.
function SHOW.class(texture, unit)
    if not Safe(UnitIsPlayer(unit)) then return false end
    local _, class = UnitClass(unit)
    return Icons.SetClass(texture, Safe(class))
end

-- PREVIEW[key](region, size) -> true, with a sample set (raid, leader, class).
Icons.PREVIEW = {
    raid = function(fontString, size) return Icons.SetRaidMark(fontString, 1, size) end,
    leader = function(texture)
        Leader(texture)
        return true
    end,
    class = function(texture) return Icons.SetClass(texture, "PALADIN") end,
}
