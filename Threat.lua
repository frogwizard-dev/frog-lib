-- FrogLib Threat: your lead on a unit, for threat text (FrogPlates, EnmityList).
--   FrogLib.Threat.Gap(unit)      -> your threat minus the highest of anyone else in your group
--                                    (pets too): ahead when positive. nil when the game hides
--                                    your threat, or you're alone with no one else on it.
--   FrogLib.Threat.Short(n)       -> a threat number kept short: "840", "12.5k", "1.2m"
--   FrogLib.Threat.FormatGap(gap) -> "+1.2k" ahead, "-340" behind; and whether you're ahead
--   FrogLib.Threat.SetGapText(fs, gap, ahead, behind): the gap into fs, in the colour `ahead` or
--       `behind` ({ r, g, b } tables)
--   FrogLib.Threat.Snapshot(unit) -> lines of text: what the game lets addons see of the threat
--                                    on the unit (for a /... threat report).

local Threat = FrogLib:Module("Threat", 2) -- 2: Short, FormatGap, SetGapText
if not Threat then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

local function ForEachOther(fn)
    fn("pet")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            fn("raid" .. i)
            fn("raidpet" .. i)
        end
    else
        for i = 1, 4 do
            fn("party" .. i)
            fn("partypet" .. i)
        end
    end
end

function Threat.Gap(unit)
    local _, _, _, _, mine = UnitDetailedThreatSituation("player", unit)
    if mine == nil or issecret(mine) then return nil end
    local best
    ForEachOther(function(who)
        if not UnitExists(who) or Safe(UnitIsUnit(who, "player")) ~= false then return end
        local _, _, _, _, v = UnitDetailedThreatSituation(who, unit)
        if v ~= nil and not issecret(v) and v > 0 and (not best or v > best) then best = v end
    end)
    -- In a group with nobody else on it yet, your lead is all of your threat.
    if not best then return IsInGroup() and mine or nil end
    return mine - best
end

function Threat.Short(n)
    local a = math.abs(n)
    if a >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if a >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

function Threat.FormatGap(gap)
    local ahead = gap >= 0
    return (ahead and "+" or "") .. Threat.Short(gap), ahead
end

function Threat.SetGapText(fs, gap, ahead, behind)
    local text, isAhead = Threat.FormatGap(gap)
    local c = isAhead and ahead or behind
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetText(text)
end

local function Describe(v)
    if v == nil then return "none" end
    if issecret(v) then return "hidden by the game" end
    return tostring(v)
end

local function Name(unit)
    if GetUnitName then
        local ok, name = pcall(GetUnitName, unit, true)
        -- Secret first: a hidden name mustn't be tested, or used in the report's text.
        if ok and not issecret(name) and name then return name end
    end
    return Safe(UnitName(unit)) or "?"
end

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
            local _, _, p, _, v = UnitDetailedThreatSituation(who, unit)
            lines[#lines + 1] = string.format("   %s (%s): threat %s (%s%%)", who, Name(who), Describe(v), Describe(p))
        end
    end
    return lines
end
