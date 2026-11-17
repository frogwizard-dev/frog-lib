-- FrogLib Threat: your lead on a unit, for threat text (FrogPlates, EnmityList).

local Threat = FrogLib:Module("Threat", 4) -- 2: Short, FormatGap, SetGapText; 3: secret checks first;
-- 4: your group looked up once a frame, not for every plate
if not Threat then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

-- The group's unit tokens in the order they're looked at: your pet, then each member and their
-- pet. The raid list is made the first time you're in a raid, rather than joined up on every look.
local RAID
local PARTY = { "pet", "party1", "partypet1", "party2", "partypet2", "party3", "partypet3", "party4", "partypet4" }

-- Everyone else in your group who's there, pets too. The same for every plate, so worked out at
-- most once a frame (GetTime stays the same through one), and again if someone joins or leaves.
local others, otherCount, othersAt, groupSize = {}, 0

local function Others()
    local now, size = GetTime(), GetNumGroupMembers()
    if now == othersAt and size == groupSize then return otherCount end
    othersAt, groupSize = now, size
    local tokens, last = PARTY, 9
    if IsInRaid() then
        if not RAID then
            RAID = { "pet" }
            for i = 1, 40 do RAID[2 * i], RAID[2 * i + 1] = "raid" .. i, "raidpet" .. i end
        end
        tokens, last = RAID, 2 * size + 1
    end
    local count = 0
    for i = 1, last do
        local who = tokens[i]
        if UnitExists(who) and Safe(UnitIsUnit(who, "player")) == false then
            count = count + 1
            others[count] = who
        end
    end
    otherCount = count
    return count
end

-- Your threat minus the highest of anyone else in your group, pets too: ahead when positive. nil
-- when the game hides your threat, or you're alone with no one else on it.
function Threat.Gap(unit)
    local _, _, _, _, mine = UnitDetailedThreatSituation("player", unit)
    if issecret(mine) or mine == nil then return nil end
    local best
    for i = 1, Others() do
        local _, _, _, _, theirs = UnitDetailedThreatSituation(others[i], unit)
        if not issecret(theirs) and theirs ~= nil and theirs > 0 and (not best or theirs > best) then best = theirs end
    end
    -- In a group with nobody else on it yet, your lead is all of your threat.
    if not best then return IsInGroup() and mine or nil end
    return mine - best
end

-- A threat number kept short: "840", "12.5k", "1.2m".
function Threat.Short(amount)
    local size = math.abs(amount)
    if size >= 1000000 then return string.format("%.1fm", amount / 1000000) end
    if size >= 1000 then return string.format("%.1fk", amount / 1000) end
    return tostring(math.floor(amount + 0.5))
end

-- "+1.2k" ahead, "-340" behind, and true when you're ahead.
function Threat.FormatGap(gap)
    local ahead = gap >= 0
    return (ahead and "+" or "") .. Threat.Short(gap), ahead
end

-- The gap into a font string, in the colour `ahead` or `behind` ({ r, g, b } tables).
function Threat.SetGapText(fontString, gap, ahead, behind)
    local text, isAhead = Threat.FormatGap(gap)
    local color = isAhead and ahead or behind
    fontString:SetTextColor(color.r, color.g, color.b)
    fontString:SetText(text)
end

local function Describe(value)
    if value == nil then return "none" end
    if issecret(value) then return "hidden by the game" end
    return tostring(value)
end

local function Name(unit)
    if GetUnitName then
        local ok, name = pcall(GetUnitName, unit, true)
        -- Secret first: a hidden name mustn't be tested, or used in the report's text.
        if ok and not issecret(name) and name then return name end
    end
    return Safe(UnitName(unit)) or "?"
end

-- Lines of text: what the game lets addons see of the threat on the unit, for a threat report.
function Threat.Snapshot(unit)
    local _, status, percent, _, mine = UnitDetailedThreatSituation("player", unit)
    local lines = {
        string.format("on %s: your threat %s (%s%%, status %s, situation %s); in a group: %s; lead shown: %s",
            Name(unit), Describe(mine), Describe(percent), Describe(status),
            Describe(UnitThreatSituation("player", unit)), tostring(IsInGroup()), Describe(Threat.Gap(unit))),
    }
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, IsInRaid() and GetNumGroupMembers() or 4 do
        local who = prefix .. i
        if UnitExists(who) then
            local _, _, theirPercent, _, theirs = UnitDetailedThreatSituation(who, unit)
            lines[#lines + 1] = string.format("   %s (%s): threat %s (%s%%)", who, Name(who), Describe(theirs),
                Describe(theirPercent))
        end
    end
    return lines
end
