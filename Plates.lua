-- FrogLib Plates: the machinery for restyling enemy nameplates (FrogPlates, XIVPlates). An addon
-- registers a skin (its look); the engine takes plates over and tells it when to build, lay out and
-- fill each in. Blizzard's plate works on underneath, see-through (clicks hit-test its health bar),
-- its cast bar and auras showing through round the skin's bar, as its code copes with secret values.

local Plates = FrogLib:Module("Plates", 1)
if not Plates then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

-- Kept on the module, so a newer copy of FrogLib carries on with the same plates.
local state = Plates.state or { own = {}, frames = {}, byUnit = {}, hooked = {}, casts = {} }
Plates.state = state

-- Blizzard's cast bar parts a skin may hide.
Plates.CAST_EXTRAS = { "Border", "CastTargetNameText", "CastTargetIndicator" }

------------------------------------------------------------------------------
-- Blizzard's parts
------------------------------------------------------------------------------

-- Blizzard's health bar inside the plate: the skin's goes over it, since that's where clicks land.
function Plates.BlizzardBar(unitFrame)
    return unitFrame and ((unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar) or unitFrame.healthBar)
end

function Plates.BlizzardCast(unitFrame)
    return unitFrame and unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar
end

-- plate.slot: the plate's full width at the health bar's height. Blizzard's bar stops short on the
-- right (the level badge), so the slot runs to the cast bar area's top right, raised by the gap.
function Plates.PlaceSlot(plate)
    local unitFrame = plate.uf
    local healthBars, castBars = unitFrame and unitFrame.HealthBarsContainer, unitFrame and unitFrame.CastBarsContainer
    local slot = plate.slot
    slot:ClearAllPoints()
    if healthBars and castBars then
        local gap = NamePlateSetupOptions and NamePlateSetupOptions.castBarToHealthBarSpacing or 0
        slot:SetPoint("TOPLEFT", healthBars, "TOPLEFT")
        slot:SetPoint("BOTTOMRIGHT", castBars, "TOPRIGHT", 0, gap)
    else
        slot:SetAllPoints(Plates.BlizzardBar(unitFrame) or plate.base)
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

-- r, g, b, or nil when its threat doesn't colour it. colors: { safe, warn, danger }. 3: it's on you,
-- safely; 2: on you, but someone's close; 1: someone else is about to take it; 0: on someone else.
function Plates.ThreatColour(unit, colors, role)
    local situation = Safe(UnitThreatSituation("player", unit))
    if not situation then return nil end
    local color
    if Plates.Tanking(role) then
        color = (situation == 3 and colors.safe) or (situation == 2 and colors.warn) or colors.danger
    elseif situation >= 2 then
        color = colors.danger
    elseif situation == 1 then
        color = colors.warn
    end
    if color then return color.r, color.g, color.b end
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

local function Knows(spellID)
    for _, check in ipairs({ C_SpellBook and C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnown }) do
        if check then
            local ok, known = pcall(check, spellID)
            if ok and Safe(known) == true then return true end
        end
    end
    return false
end

function Plates.ExecuteCheck()
    local _, class = UnitClass("player")
    local execute = EXECUTES[class]
    local usable = false
    if execute then
        for _, spellID in ipairs(execute.spells) do
            if Knows(spellID) then
                usable = true
                break
            end
        end
        if usable and execute.forms then
            local form = GetShapeshiftFormID and GetShapeshiftFormID()
            if form then
                usable = execute.forms[form] or false
            else
                local index = GetShapeshiftForm and GetShapeshiftForm()
                usable = (index and execute.stances[index]) or false
            end
        end
    end
    state.executeBelow = usable and execute.below or false
end

-- The health fraction your execute works under, or false.
function Plates.ExecuteBelow()
    return state.executeBelow or false
end

-- 1 under the line, 0 above it: from the game's curve where it has one (health may be secret,
-- and SetAlpha takes the answer as it is), otherwise worked out here while health isn't secret.
function Plates.ExecuteAlpha(unit, below)
    if UnitHealthPercent and FrogLib.Curve then
        local alpha = FrogLib.Curve.Health(unit, FrogLib.Curve.Below(below, 1, 0))
        if issecret(alpha) or alpha ~= nil then return alpha end
        return 0
    end
    local health, healthMax = Safe(UnitHealth(unit)), Safe(UnitHealthMax(unit))
    return (health and healthMax and healthMax > 0 and health / healthMax < below) and 1 or 0
end

------------------------------------------------------------------------------
-- Quests: does a quest of yours still need this enemy? The unit's tooltip lists your objectives
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
        local asked, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        return asked and Safe(related) == true
    end
    return false
end

------------------------------------------------------------------------------
-- Cast bars
------------------------------------------------------------------------------

-- Ours for a cast bar: .time, a font string the engine keeps writing the time left into while it's
-- shown; .last and .seen, the "can't interrupt" shield's state.
function Plates.CastParts(cast)
    local parts = state.casts[cast]
    if not parts then
        parts = {}
        state.casts[cast] = parts
    end
    return parts
end

-- A texture over a status bar's fill exactly (shrinking and growing with it). The fill's own
-- draw layer can be secret on enemy cast bars, so it isn't read.
function Plates.OverFill(region, bar)
    local fill = bar:GetStatusBarTexture()
    if not fill then return end
    region:ClearAllPoints()
    region:SetAllPoints(fill)
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
    for _, ReadDuration in ipairs({ UnitCastingDuration, UnitChannelDuration }) do
        local ok, duration = pcall(ReadDuration, unit)
        if ok and (issecret(duration) or duration ~= nil) then return duration end
    end
end

local function WriteCastTime(fontString, unit)
    local duration = unit and CastTimer(unit)
    if duration then
        fontString:SetFormattedText("%.1f", duration:GetRemainingDuration())
    else
        fontString:SetText("")
    end
end

-- skin.castShield(unitFrame, cast, shown, ours): the shield showed or hid (shown may be secret).
local function Shield(unitFrame, cast, shown)
    local parts = Plates.CastParts(cast)
    if not issecret(shown) then shown = shown and true or false end
    parts.last, parts.seen = shown, true
    local skin = state.skin
    if skin and skin.castShield then skin.castShield(unitFrame, cast, shown, state.own[unitFrame] and true or false) end
end

-- Once per cast bar (they come with the pooled unit frames). Optional skin.castFill(cast) and
-- skin.castInterrupted(cast): its fill texture changed, or the cast was interrupted.
local function HookCast(unitFrame)
    local cast = Plates.BlizzardCast(unitFrame)
    if not cast then return end
    local parts = Plates.CastParts(cast)
    if parts.hooked then return end
    parts.hooked = true
    parts.time = cast:CreateFontString(nil, "OVERLAY", nil, 7)
    parts.time:SetShadowOffset(1, -1)
    parts.time:SetShadowColor(0, 0, 0, 1)
    parts.time:Hide()
    local since = 0
    cast:HookScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.1 or not parts.time:IsShown() then return end
        since = 0
        if not pcall(WriteCastTime, parts.time, cast.unit) then parts.time:SetText("") end
    end)
    if cast.BorderShield and type(cast.BorderShield.SetShown) == "function" then
        hooksecurefunc(cast.BorderShield, "SetShown", function(_, shown) Shield(unitFrame, cast, shown) end)
    end
    if type(cast.UpdateBarFillTexture) == "function" then
        hooksecurefunc(cast, "UpdateBarFillTexture", function()
            if state.skin and state.skin.castFill then state.skin.castFill(cast) end
        end)
    end
    if type(cast.PlayInterruptAnims) == "function" then
        hooksecurefunc(cast, "PlayInterruptAnims", function()
            if state.skin and state.skin.castInterrupted then state.skin.castInterrupted(cast) end
        end)
    end
end

------------------------------------------------------------------------------
-- Auras: Blizzard's row (your debuffs; buffs you can steal; crowd control), moved round the bar
------------------------------------------------------------------------------

-- opts: { auras (shown), allDebuffs, auraScale }. Game settings: Blizzard's debuff list unless "show
-- all personal auras", and only if enemy auras include debuffs; set out of combat (not in it).
function Plates.AuraSettings(opts)
    if not opts.auras or InCombatLockdown() then return end
    if opts.auraScale and C_CVar.GetCVar("nameplateAuraScale") then
        SetCVar("nameplateAuraScale", string.format("%.2f", opts.auraScale))
    end
    if C_CVar.GetCVar("nameplateShowAllPersonalAuras") then
        SetCVar("nameplateShowAllPersonalAuras", opts.allDebuffs and "1" or "0")
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

-- The aura row `up` above the bar: your debuffs from its left end (or centred), stealable buffs over
-- its right end, crowd control `side` past it. Blizzard pins them back in UpdateAnchors (see Hook).
function Plates.PlaceAuras(unitFrame, bar, shown, up, centred, side)
    local auras = unitFrame and unitFrame.AurasFrame
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
    if now - (state.lastSeenAt or 0) < 1 then return end
    state.lastSeenAt = now
    state.lastSeen = FrogLib.Threat.Snapshot(unit)
end

-- Shows the font string (true) or hides it (false: no threat to show). colors: { safe, danger }.
function Plates.ThreatText(fontString, unit, colors)
    local situation = Safe(UnitThreatSituation("player", unit))
    if situation == nil then return false end
    NoteThreat(unit)
    local gap = FrogLib.Threat.Gap(unit)
    if gap then
        FrogLib.Threat.SetGapText(fontString, gap, colors.safe, colors.danger)
    elseif situation >= 1 then
        local word = STATUS[situation][1]
        local color = STATUS[situation][2] == "safe" and colors.safe or colors.danger
        fontString:SetTextColor(color.r, color.g, color.b)
        fontString:SetText(word)
    else
        local _, _, percent = UnitDetailedThreatSituation("player", unit)
        fontString:SetTextColor(1, 1, 1)
        pcall(fontString.SetFormattedText, fontString, "%d%%", percent)
    end
    return true
end

-- Live while you're fighting your target, otherwise the last fight's snapshot.
function Plates.ThreatReport(say)
    local live = UnitExists("target") and Safe(UnitAffectingCombat("player"))
    local lines = live and FrogLib.Threat.Snapshot("target") or state.lastSeen
    if not lines then
        say("nothing seen yet: fight something with it targeted, then try again.")
        return
    end
    say(live and "threat now:" or string.format("threat as last seen in combat (%ds ago):",
        math.floor(GetTime() - (state.lastSeenAt or 0))))
    for _, line in ipairs(lines) do print(line) end
end

------------------------------------------------------------------------------
-- Taking plates over, and giving them back
------------------------------------------------------------------------------

-- Blizzard pools the unit frames (base.UnitFrame) for any plate, friendly too, so one made
-- see-through gets its opacity back when it's next used for something friendly.
local function SeeThrough(unitFrame, on)
    state.busy = true
    unitFrame:SetAlpha(on and 0 or 1)
    state.busy = false
    if unitFrame.selectionHighlight then unitFrame.selectionHighlight:SetAlpha(on and 0 or 0.25) end
    if on then return end
    local cast = Plates.BlizzardCast(unitFrame)
    if cast then
        cast:SetIgnoreParentAlpha(false)
        if cast.BorderShield then cast.BorderShield:SetAlpha(1) end
        for _, key in ipairs(Plates.CAST_EXTRAS) do
            if cast[key] then cast[key]:SetAlpha(1) end
        end
        local parts = state.casts[cast]
        if parts and parts.time then parts.time:Hide() end
        -- Optional skin.release(unitFrame, cast): the skin's cast parts off.
        if state.skin and state.skin.release then state.skin.release(unitFrame, cast) end
    end
    if unitFrame.AurasFrame then unitFrame.AurasFrame:SetIgnoreParentAlpha(false) end
end

-- Once per unit frame: kept see-through while it's ours, and laid out again after Blizzard
-- re-lays it out (a new unit, or a nameplate setting changed).
local function Hook(unitFrame)
    if state.hooked[unitFrame] then return end
    state.hooked[unitFrame] = true
    hooksecurefunc(unitFrame, "SetAlpha", function(self, alpha)
        if state.busy or not state.own[self] then return end
        if issecret(alpha) or alpha ~= 0 then
            state.busy = true
            self:SetAlpha(0)
            state.busy = false
        end
    end)
    local function Relayout(self)
        local plate = state.own[self] and state.frames[self:GetParent()]
        if plate and plate.uf == self and state.skin then state.skin.layout(plate) end
    end
    for _, method in ipairs({ "ApplyFrameOptions", "UpdateAnchors" }) do
        if type(unitFrame[method]) == "function" then hooksecurefunc(unitFrame, method, Relayout) end
    end
    HookCast(unitFrame)
end

local function Release(unitFrame)
    if unitFrame and state.own[unitFrame] then
        state.own[unitFrame] = nil
        SeeThrough(unitFrame, false)
    end
end

-- skin.create(plate): the look built on plate, a frame over the plate's base (plate.base, plate.slot).
local function Create(base)
    local plate = CreateFrame("Frame", nil, base)
    plate:SetAllPoints(base)
    plate.base = base
    plate.slot = CreateFrame("Frame", nil, plate)
    state.skin.create(plate)
    -- Plates move and scale smoothly, landing between screen pixels, which drops 1px edges and
    -- blurs text: everything snapped to whole pixels, as Blizzard's own plates do.
    if PixelUtil and PixelUtil.SetRoundLayoutToNearestPixelRecursively then
        PixelUtil.SetRoundLayoutToNearestPixelRecursively(plate, true)
    end
    state.frames[base] = plate
    return plate
end

-- skin.enabled(): restyle enemy plates now; skin.layout(plate) places it (also after Blizzard lays
-- it out again, and on settings); skin.update(plate, "all") fills it in; skin.target(): see Each.
local function Add(unit)
    local skin = state.skin
    if not skin then return end
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base or base:IsForbidden() then return end
    local unitFrame = base.UnitFrame
    local enemy = skin.enabled() and Safe(UnitCanAttack("player", unit)) and Safe(UnitIsUnit(unit, "player")) == false
    if not enemy then
        Release(unitFrame)
        if state.frames[base] then state.frames[base]:Hide() end
        return
    end
    if unitFrame then
        state.own[unitFrame] = true
        Hook(unitFrame)
        SeeThrough(unitFrame, true)
    end
    local plate = state.frames[base] or Create(base)
    plate.unit, plate.uf = unit, unitFrame
    state.byUnit[unit] = plate
    skin.layout(plate)
    skin.update(plate, "all")
    plate:Show()
    plate:SetShown(Safe(UnitIsDead(unit)) ~= true)
    skin.target()
end

local function Remove(unit)
    local plate = state.byUnit[unit]
    if not plate then return end
    state.byUnit[unit] = nil
    plate.unit = nil
    plate:Hide()
end

-- Each plate in turn (skin.target(), called when your target changes, goes through them this way).
function Plates.Each(Visit)
    for _, plate in pairs(state.byUnit) do Visit(plate) end
end

function Plates.Frame(unit)
    return state.byUnit[unit]
end

function Plates.IsTarget(plate)
    return C_NamePlate.GetNamePlateForUnit("target") == plate.base
end

-- Every plate again (after a settings change, or turning it on or off).
function Plates.Refresh()
    if not state.skin then return end
    Plates.ExecuteCheck()
    for unit in pairs(state.byUnit) do Remove(unit) end
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

-- skin.update(plate, what): what is "all", "health", "name", "class" (classification), "threat" (its
-- colour and text: on changes and every 0.3 seconds), "mark", "quest" or "execute" (stance or spells).
local function UpdateAll(what)
    local skin = state.skin
    for _, plate in pairs(state.byUnit) do skin.update(plate, what) end
end

-- Quest progress comes in bursts of events: looked at again once they settle.
local function QuestsChanged()
    if state.questPending then return end
    state.questPending = true
    C_Timer.After(0.3, function()
        state.questPending = nil
        if state.skin then UpdateAll("quest") end
    end)
end

local function OnEvent(_, event, unit)
    local skin = state.skin
    if not skin then return end
    if event == "PLAYER_TARGET_CHANGED" then
        skin.target()
    elseif event == "RAID_TARGET_UPDATE" then
        UpdateAll("mark")
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_REGEN_ENABLED" or event == "SPELLS_CHANGED" then
        -- A new stance or spell can change your execute, and if you're tanking.
        Plates.ExecuteCheck()
        UpdateAll("execute")
    elseif event:match("^QUEST_") or event == "UNIT_QUEST_LOG_CHANGED" then
        QuestsChanged()
    else
        local plate = unit and state.byUnit[unit]
        if not plate then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            skin.update(plate, "health")
            plate:SetShown(Safe(UnitIsDead(unit)) ~= true)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
            skin.update(plate, "name")
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            skin.update(plate, "class")
        else
            skin.update(plate, "threat")
        end
    end
end

-- Registers the skin that drives the plates (skin.owner: its addon's name): true, or false and the
-- addon already driving them, as only one can at a time.
function Plates.Register(skin)
    if state.skin and state.skin.owner ~= skin.owner then return false, state.skin.owner end
    state.skin = skin
    if not state.started then
        state.started = true
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit) Add(unit) end)
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit) Remove(unit) end)
        local events = CreateFrame("Frame")
        for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
        pcall(events.RegisterUnitEvent, events, "UNIT_QUEST_LOG_CHANGED", "player")
        events:SetScript("OnEvent", OnEvent)
        -- The threat gap drifts with every hit, without its own event for each plate. Optional
        -- skin.tick(plate): every frame, per plate.
        local sinceThreat = 0
        events:SetScript("OnUpdate", function(_, elapsed)
            local current = state.skin
            if not current then return end
            if current.tick then
                for _, plate in pairs(state.byUnit) do current.tick(plate) end
            end
            sinceThreat = sinceThreat + elapsed
            if sinceThreat < 0.3 then return end
            sinceThreat = 0
            UpdateAll("threat")
        end)
    end
    Plates.Refresh()
    return true
end
