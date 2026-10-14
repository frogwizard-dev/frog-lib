-- FrogLib Plates: the machinery for restyling enemy nameplates (FrogPlates, XIVPlates). An addon
-- registers a skin (what its plates look like); the engine takes the plates over and tells the
-- skin when to build, lay out and fill in each one.
--
-- Blizzard's plate keeps working underneath, made see-through (opacity 0, not hidden): clicking a
-- plate is hit-tested against its health bar, so it has to stay laid out. The skin's own frame
-- sits on the plate's base frame, over that health bar. Two of Blizzard's parts are kept, shown
-- through the see-through plate and moved round the skin's bar: its cast bar and its auras. Both
-- run on Blizzard's own code, which copes with values the game keeps secret in combat.
-- Blizzard pools the inner unit frames (base.UnitFrame) and gives them to any plate, friendly ones
-- too, so a unit frame that's been made see-through gets its opacity back when it's next used for
-- something friendly. Only one skin drives the plates at a time: a second is told no.
--
--   local ok, owner = FrogLib.Plates.Register(skin)
--     skin.owner: its addon's name; skin.enabled() -> restyle enemy plates now;
--     skin.create(f): build the look on f (a frame over the plate: f.base, f.slot, made here);
--     skin.layout(f): place it (after taking a plate over, Blizzard re-laying it out, settings);
--     skin.update(f, what): what = "all", "health", "name", "class" (classification), "threat"
--       (colour and threat text: threat changes, and every 0.3 seconds), "mark", "quest",
--       "execute" (your stance or spells changed);
--     skin.target(): your target changed (FrogLib.Plates.Each to go through the plates);
--     skin.tick(f) (optional): every frame, per plate;
--     skin.castShield(uf, cast, shown, ours): Blizzard's cast bar showed or hid its "can't
--       interrupt" shield (shown may be secret); skin.castFill(cast), skin.castInterrupted(cast)
--       (optional): its fill texture changed, or the cast was interrupted;
--     skin.release(uf, cast) (optional): a unit frame given back: the skin's cast parts off.
--   FrogLib.Plates.Refresh(), .Each(fn(f)), .Frame(unit), .IsTarget(f)
--   Helpers: BlizzardBar(uf), BlizzardCast(uf), PlaceSlot(f), Tanking(role),
--     ThreatColour(unit, colors, role) -> r, g, b (nil when its threat doesn't colour it),
--     ExecuteBelow(), ExecuteAlpha(unit, below), OnQuest(unit), CastParts(cast) (.time, a font
--     string the engine keeps writing the time left into while it's shown; .last, .seen: the
--     shield state), OverFill(region, bar), AlphaFrom(region, shown, on), AuraSettings(o),
--     PlaceAuras(uf, bar, up, centred, side), ThreatText(fs, unit, colors), ThreatReport(print),
--     CAST_EXTRAS (Blizzard's cast bar parts a skin may hide).

local Plates = FrogLib:Module("Plates", 1)
if not Plates then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

-- Kept on the module, so a newer copy of FrogLib carries on with the same plates.
local S = Plates.state or { own = {}, frames = {}, byUnit = {}, hooked = {}, casts = {} }
Plates.state = S

Plates.CAST_EXTRAS = { "Border", "CastTargetNameText", "CastTargetIndicator" }

------------------------------------------------------------------------------
-- Blizzard's parts
------------------------------------------------------------------------------

-- Blizzard's health bar inside the plate: the skin's goes over it, since that's where clicks land.
function Plates.BlizzardBar(uf)
    return uf and ((uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar) or uf.healthBar)
end

function Plates.BlizzardCast(uf)
    return uf and uf.CastBarsContainer and uf.CastBarsContainer.castBar
end

-- f.slot: the plate's width at the health bar's height. Blizzard's bar starts at the plate's left
-- but stops short on the right, for the level badge, and nameplates can't be measured; so the slot
-- runs from its top left to the top right of the cast bar area below it (the plate's full width,
-- evenly inset), raised by the gap between the two.
function Plates.PlaceSlot(f)
    local uf = f.uf
    local hc, cc = uf and uf.HealthBarsContainer, uf and uf.CastBarsContainer
    local slot = f.slot
    slot:ClearAllPoints()
    if hc and cc then
        local gap = NamePlateSetupOptions and NamePlateSetupOptions.castBarToHealthBarSpacing or 0
        slot:SetPoint("TOPLEFT", hc, "TOPLEFT")
        slot:SetPoint("BOTTOMRIGHT", cc, "TOPRIGHT", 0, gap)
    else
        slot:SetAllPoints(Plates.BlizzardBar(uf) or f.base)
    end
end

------------------------------------------------------------------------------
-- Threat colour: tanking from the setting, or (auto) a tanking stance, form or aura
------------------------------------------------------------------------------

local TANK_FORMS = { [18] = true, [5] = true, [8] = true } -- Defensive Stance, Bear, Dire Bear
local RIGHTEOUS_FURY = 25780

function Plates.Tanking(role)
    if role and role ~= "auto" then return role == "tank" end
    local form = GetShapeshiftFormID and GetShapeshiftFormID()
    if form and TANK_FORMS[form] then return true end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, RIGHTEOUS_FURY)
        if ok and aura then return true end
    end
    if GetSpecialization and GetSpecializationRole then
        local spec = GetSpecialization()
        if spec and GetSpecializationRole(spec) == "TANK" then return true end
    end
    return false
end

-- colors: { safe, warn, danger }. 3: it's on you, safely; 2: on you, but someone's close; 1:
-- someone else is about to take it; 0: it's on someone else.
function Plates.ThreatColour(unit, colors, role)
    local situation = Safe(UnitThreatSituation("player", unit))
    if not situation then return nil end
    local t
    if Plates.Tanking(role) then
        t = (situation == 3 and colors.safe) or (situation == 2 and colors.warn) or colors.danger
    elseif situation >= 2 then
        t = colors.danger
    elseif situation == 1 then
        t = colors.warn
    end
    if t then return t.r, t.g, t.b end
end

------------------------------------------------------------------------------
-- Execute range: once the enemy is low enough for your class's execute, if you know it (any rank)
-- and, for warriors, are in a stance that can use it.
------------------------------------------------------------------------------

local EXECUTES = {
    -- Execute, in Battle Stance (form 17, or the first stance) or Berserker Stance (19, the third).
    WARRIOR = { spells = { 5308, 20658, 20660, 20661, 20662 }, below = 0.2,
        forms = { [17] = true, [19] = true }, stances = { [1] = true, [3] = true } },
    -- Hammer of Wrath.
    PALADIN = { spells = { 24275, 24274, 24239 }, below = 0.2 },
}

local function Knows(id)
    for _, check in ipairs({ C_SpellBook and C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnown }) do
        if check then
            local ok, known = pcall(check, id)
            if ok and Safe(known) == true then return true end
        end
    end
    return false
end

function Plates.ExecuteCheck()
    local _, class = UnitClass("player")
    local e = EXECUTES[class]
    local usable = false
    if e then
        for _, id in ipairs(e.spells) do
            if Knows(id) then
                usable = true
                break
            end
        end
        if usable and e.forms then
            local form = GetShapeshiftFormID and GetShapeshiftFormID()
            if form then
                usable = e.forms[form] or false
            else
                local index = GetShapeshiftForm and GetShapeshiftForm()
                usable = (index and e.stances[index]) or false
            end
        end
    end
    S.executeBelow = usable and e.below or false
end

-- The health fraction your execute works under, or false.
function Plates.ExecuteBelow()
    return S.executeBelow or false
end

-- 1 under the line, 0 above it: from the game's curve where it has one (health may be secret,
-- and SetAlpha takes the answer as it is), otherwise worked out here while health isn't secret.
function Plates.ExecuteAlpha(unit, below)
    if UnitHealthPercent and FrogLib.Curve then
        local a = FrogLib.Curve.Health(unit, FrogLib.Curve.Below(below, 1, 0))
        if issecret(a) or a ~= nil then return a end
        return 0
    end
    local h, m = Safe(UnitHealth(unit)), Safe(UnitHealthMax(unit))
    return (h and m and m > 0 and h / m < below) and 1 or 0
end

------------------------------------------------------------------------------
-- Quests: whether your quests still need this enemy. The unit's tooltip lists your objectives
-- for it with whether each is done; failing that, C_QuestLog.UnitIsRelatedToActiveQuest.
------------------------------------------------------------------------------

local QUEST_LINE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

local function QuestLines(unit)
    if not (QUEST_LINE and C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
    local data = Safe(C_TooltipInfo.GetUnit(unit))
    local lines = type(data) == "table" and Safe(data.lines)
    if type(lines) ~= "table" then return end
    local total, open = 0, 0
    for _, line in ipairs(lines) do
        if type(line) == "table" and Safe(line.type) == QUEST_LINE then
            total = total + 1
            if Safe(line.completed) ~= true then open = open + 1 end
        end
    end
    return total, open
end

function Plates.OnQuest(unit)
    if Safe(UnitIsPlayer(unit)) ~= false then return false end
    local ok, total, open = pcall(QuestLines, unit)
    if ok and total and total > 0 then return open > 0 end
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok2, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        return ok2 and Safe(related) == true
    end
    return false
end

------------------------------------------------------------------------------
-- Cast bars
------------------------------------------------------------------------------

function Plates.CastParts(cast)
    local x = S.casts[cast]
    if not x then
        x = {}
        S.casts[cast] = x
    end
    return x
end

-- A texture over a status bar's fill exactly (shrinking and growing with it). The fill's own
-- draw layer can be secret on enemy cast bars, so it isn't read.
function Plates.OverFill(region, bar)
    local tex = bar:GetStatusBarTexture()
    if not tex then return end
    region:ClearAllPoints()
    region:SetAllPoints(tex)
end

-- Fully shown when `shown` (which may be secret) is true, hidden when it's false.
function Plates.AlphaFrom(region, shown, on)
    if not on then
        region:SetAlpha(0)
    elseif region.SetAlphaFromBoolean then
        region:SetAlphaFromBoolean(shown)
    elseif not issecret(shown) then
        region:SetAlpha(shown and 1 or 0)
    else
        region:SetAlpha(0)
    end
end

-- The time left on a cast or channel, from the game's own timer for it (secret in combat, so it
-- only ever goes straight into the text); nothing between casts.
local function CastTimer(unit)
    for _, fn in ipairs({ UnitCastingDuration, UnitChannelDuration }) do
        local ok, d = pcall(fn, unit)
        if ok and (issecret(d) or d ~= nil) then return d end
    end
end

local function WriteCastTime(fs, unit)
    local d = unit and CastTimer(unit)
    if d then
        fs:SetFormattedText("%.1f", d:GetRemainingDuration())
    else
        fs:SetText("")
    end
end

local function Shield(uf, cast, shown)
    local x = Plates.CastParts(cast)
    if not issecret(shown) then shown = shown and true or false end
    x.last, x.seen = shown, true
    local skin = S.skin
    if skin and skin.castShield then skin.castShield(uf, cast, shown, S.own[uf] and true or false) end
end

-- Once per cast bar (they come with the pooled unit frames).
local function HookCast(uf)
    local cast = Plates.BlizzardCast(uf)
    if not cast then return end
    local x = Plates.CastParts(cast)
    if x.hooked then return end
    x.hooked = true
    x.time = cast:CreateFontString(nil, "OVERLAY", nil, 7)
    x.time:SetShadowOffset(1, -1)
    x.time:SetShadowColor(0, 0, 0, 1)
    x.time:Hide()
    local since = 0
    cast:HookScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.1 or not x.time:IsShown() then return end
        since = 0
        if not pcall(WriteCastTime, x.time, cast.unit) then x.time:SetText("") end
    end)
    if cast.BorderShield and type(cast.BorderShield.SetShown) == "function" then
        hooksecurefunc(cast.BorderShield, "SetShown", function(_, shown) Shield(uf, cast, shown) end)
    end
    if type(cast.UpdateBarFillTexture) == "function" then
        hooksecurefunc(cast, "UpdateBarFillTexture", function()
            if S.skin and S.skin.castFill then S.skin.castFill(cast) end
        end)
    end
    if type(cast.PlayInterruptAnims) == "function" then
        hooksecurefunc(cast, "PlayInterruptAnims", function()
            if S.skin and S.skin.castInterrupted then S.skin.castInterrupted(cast) end
        end)
    end
end

------------------------------------------------------------------------------
-- Auras: Blizzard's row (your debuffs; buffs you can steal; crowd control), moved round the bar
------------------------------------------------------------------------------

-- o: { auras (shown), allDebuffs, auraScale }. Game settings: the debuffs on Blizzard's list only
-- unless "show all personal auras" is on, and only if the enemy aura setting includes debuffs;
-- set out of combat (settings can't change in it).
function Plates.AuraSettings(o)
    if not o.auras or InCombatLockdown() then return end
    if o.auraScale and C_CVar.GetCVar("nameplateAuraScale") then
        SetCVar("nameplateAuraScale", string.format("%.2f", o.auraScale))
    end
    if C_CVar.GetCVar("nameplateShowAllPersonalAuras") then
        SetCVar("nameplateShowAllPersonalAuras", o.allDebuffs and "1" or "0")
    end
    if C_CVar.SetCVarBitfield then
        if Enum.NamePlateEnemyNpcAuraDisplay and C_CVar.GetCVar("nameplateEnemyNpcAuraDisplay") then
            pcall(C_CVar.SetCVarBitfield, "nameplateEnemyNpcAuraDisplay", Enum.NamePlateEnemyNpcAuraDisplay.Debuffs, true)
        end
        if Enum.NamePlateEnemyPlayerAuraDisplay and C_CVar.GetCVar("nameplateEnemyPlayerAuraDisplay") then
            pcall(C_CVar.SetCVarBitfield, "nameplateEnemyPlayerAuraDisplay", Enum.NamePlateEnemyPlayerAuraDisplay.Debuffs, true)
        end
    end
end

-- The aura row `up` above the bar (in its own unscaled units): your debuffs from the bar's left
-- end (or centred), stealable buffs over its right end, crowd control `side` past it. Blizzard
-- pins its rows to its own health bar and name (UpdateAnchors, after which the skin lays out again).
function Plates.PlaceAuras(uf, bar, shown, up, centred, side)
    local auras = uf and uf.AurasFrame
    if not auras then return end
    auras:SetIgnoreParentAlpha(shown)
    if not shown then return end
    auras:ClearAllPoints()
    auras:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, up)
    auras:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, up)
    local debuffs = auras.DebuffListFrame
    if debuffs then
        debuffs:ClearAllPoints()
        if centred then
            debuffs:SetPoint("BOTTOM", bar, "TOP", 0, up)
        else
            debuffs:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, up)
        end
    end
    if auras.BuffListFrame then
        auras.BuffListFrame:ClearAllPoints()
        auras.BuffListFrame:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, up)
    end
    for _, key in ipairs({ "CrowdControlListFrame", "LossOfControlFrame" }) do
        if auras[key] then
            auras[key]:ClearAllPoints()
            auras[key]:SetPoint("LEFT", bar, "RIGHT", side or 5, 0)
        end
    end
end

------------------------------------------------------------------------------
-- Threat text: your lead over the next highest (FrogLib.Threat), or the game's verdict where the
-- numbers are hidden, or your share of what would pull it. /fp threat's snapshot.
------------------------------------------------------------------------------

local STATUS = { [1] = { "Pulling!", "danger" }, [2] = { "Slipping", "danger" }, [3] = { "Tanking", "safe" } }

local function NoteThreat(unit)
    if not (Safe(UnitAffectingCombat("player")) and Safe(UnitIsUnit(unit, "target"))) then return end
    local now = GetTime()
    if now - (S.lastSeenAt or 0) < 1 then return end
    S.lastSeenAt = now
    S.lastSeen = FrogLib.Threat.Snapshot(unit)
end

-- Shows fs (true) or hides it (false: no threat to show). colors: { safe, danger }.
function Plates.ThreatText(fs, unit, colors)
    local situation = Safe(UnitThreatSituation("player", unit))
    if situation == nil then return false end
    NoteThreat(unit)
    local gap = FrogLib.Threat.Gap(unit)
    if gap then
        FrogLib.Threat.SetGapText(fs, gap, colors.safe, colors.danger)
    elseif situation >= 1 then
        local word, col = STATUS[situation][1], STATUS[situation][2] == "safe" and colors.safe or colors.danger
        fs:SetTextColor(col.r, col.g, col.b)
        fs:SetText(word)
    else
        local _, _, percent = UnitDetailedThreatSituation("player", unit)
        fs:SetTextColor(1, 1, 1)
        pcall(fs.SetFormattedText, fs, "%d%%", percent)
    end
    return true
end

-- Live while you're fighting your target, otherwise the last fight's snapshot.
function Plates.ThreatReport(say)
    local live = UnitExists("target") and Safe(UnitAffectingCombat("player"))
    local lines = live and FrogLib.Threat.Snapshot("target") or S.lastSeen
    if not lines then
        say("nothing seen yet: fight something with it targeted, then try again.")
        return
    end
    say(live and "threat now:" or string.format("threat as last seen in combat (%ds ago):",
        math.floor(GetTime() - (S.lastSeenAt or 0))))
    for _, line in ipairs(lines) do print(line) end
end

------------------------------------------------------------------------------
-- Taking plates over, and giving them back
------------------------------------------------------------------------------

local function SeeThrough(uf, on)
    S.busy = true
    uf:SetAlpha(on and 0 or 1)
    S.busy = false
    if uf.selectionHighlight then uf.selectionHighlight:SetAlpha(on and 0 or 0.25) end
    if on then return end
    local cast = Plates.BlizzardCast(uf)
    if cast then
        cast:SetIgnoreParentAlpha(false)
        if cast.BorderShield then cast.BorderShield:SetAlpha(1) end
        for _, key in ipairs(Plates.CAST_EXTRAS) do
            if cast[key] then cast[key]:SetAlpha(1) end
        end
        local x = S.casts[cast]
        if x and x.time then x.time:Hide() end
        if S.skin and S.skin.release then S.skin.release(uf, cast) end
    end
    if uf.AurasFrame then uf.AurasFrame:SetIgnoreParentAlpha(false) end
end

-- Once per unit frame: kept see-through while it's ours, and laid out again after Blizzard
-- re-lays it out (a new unit, or a nameplate setting changed).
local function Hook(uf)
    if S.hooked[uf] then return end
    S.hooked[uf] = true
    hooksecurefunc(uf, "SetAlpha", function(self, alpha)
        if S.busy or not S.own[self] then return end
        if issecret(alpha) or alpha ~= 0 then
            S.busy = true
            self:SetAlpha(0)
            S.busy = false
        end
    end)
    local function Relayout(self)
        local f = S.own[self] and S.frames[self:GetParent()]
        if f and f.uf == self and S.skin then S.skin.layout(f) end
    end
    for _, method in ipairs({ "ApplyFrameOptions", "UpdateAnchors" }) do
        if type(uf[method]) == "function" then hooksecurefunc(uf, method, Relayout) end
    end
    HookCast(uf)
end

local function Release(uf)
    if uf and S.own[uf] then
        S.own[uf] = nil
        SeeThrough(uf, false)
    end
end

local function Create(base)
    local f = CreateFrame("Frame", nil, base)
    f:SetAllPoints(base)
    f.base = base
    f.slot = CreateFrame("Frame", nil, f)
    S.skin.create(f)
    -- Plates move and scale smoothly, landing between screen pixels, which drops 1px edges and
    -- blurs text: everything snapped to whole pixels, as Blizzard's own plates do.
    if PixelUtil and PixelUtil.SetRoundLayoutToNearestPixelRecursively then
        PixelUtil.SetRoundLayoutToNearestPixelRecursively(f, true)
    end
    S.frames[base] = f
    return f
end

local function Add(unit)
    local skin = S.skin
    if not skin then return end
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base or base:IsForbidden() then return end
    local uf = base.UnitFrame
    local enemy = skin.enabled() and Safe(UnitCanAttack("player", unit)) and Safe(UnitIsUnit(unit, "player")) == false
    if not enemy then
        Release(uf)
        if S.frames[base] then S.frames[base]:Hide() end
        return
    end
    if uf then
        S.own[uf] = true
        Hook(uf)
        SeeThrough(uf, true)
    end
    local f = S.frames[base] or Create(base)
    f.unit, f.uf = unit, uf
    S.byUnit[unit] = f
    skin.layout(f)
    skin.update(f, "all")
    f:Show()
    f:SetShown(Safe(UnitIsDead(unit)) ~= true)
    skin.target()
end

local function Remove(unit)
    local f = S.byUnit[unit]
    if not f then return end
    S.byUnit[unit] = nil
    f.unit = nil
    f:Hide()
end

function Plates.Each(fn)
    for _, f in pairs(S.byUnit) do fn(f) end
end

function Plates.Frame(unit)
    return S.byUnit[unit]
end

function Plates.IsTarget(f)
    return C_NamePlate.GetNamePlateForUnit("target") == f.base
end

-- Every plate again (after a settings change, or turning it on or off).
function Plates.Refresh()
    if not S.skin then return end
    Plates.ExecuteCheck()
    for unit in pairs(S.byUnit) do Remove(unit) end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then Add(unit) end
    end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
    "UNIT_FLAGS", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PLAYER_TARGET_CHANGED",
    "RAID_TARGET_UPDATE", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
    "UNIT_CLASSIFICATION_CHANGED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "QUEST_TURNED_IN", "QUEST_WATCH_UPDATE" }

local function Each(what)
    local skin = S.skin
    for _, f in pairs(S.byUnit) do skin.update(f, what) end
end

-- Quest progress comes in bursts of events: looked at again once they settle.
local function QuestsChanged()
    if S.questPending then return end
    S.questPending = true
    C_Timer.After(0.3, function()
        S.questPending = nil
        if S.skin then Each("quest") end
    end)
end

local function OnEvent(_, event, unit)
    local skin = S.skin
    if not skin then return end
    if event == "PLAYER_TARGET_CHANGED" then
        skin.target()
    elseif event == "RAID_TARGET_UPDATE" then
        Each("mark")
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_REGEN_ENABLED" or event == "SPELLS_CHANGED" then
        -- A new stance or spell can change your execute and whether you're tanking.
        Plates.ExecuteCheck()
        Each("execute")
    elseif event:match("^QUEST_") or event == "UNIT_QUEST_LOG_CHANGED" then
        QuestsChanged()
    else
        local f = unit and S.byUnit[unit]
        if not f then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            skin.update(f, "health")
            f:SetShown(Safe(UnitIsDead(unit)) ~= true)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
            skin.update(f, "name")
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            skin.update(f, "class")
        else
            skin.update(f, "threat")
        end
    end
end

-- Registers the skin that drives the plates: true, or false and the addon already driving them.
function Plates.Register(skin)
    if S.skin and S.skin.owner ~= skin.owner then return false, S.skin.owner end
    S.skin = skin
    if not S.started then
        S.started = true
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit) Add(unit) end)
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit) Remove(unit) end)
        local ev = CreateFrame("Frame")
        for _, event in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, event) end
        pcall(ev.RegisterUnitEvent, ev, "UNIT_QUEST_LOG_CHANGED", "player")
        ev:SetScript("OnEvent", OnEvent)
        -- The threat gap drifts with every hit, without its own event for each plate.
        local elapsed = 0
        ev:SetScript("OnUpdate", function(_, dt)
            local s = S.skin
            if not s then return end
            if s.tick then
                for _, f in pairs(S.byUnit) do s.tick(f) end
            end
            elapsed = elapsed + dt
            if elapsed < 0.3 then return end
            elapsed = 0
            Each("threat")
        end)
    end
    Plates.Refresh()
    return true
end
