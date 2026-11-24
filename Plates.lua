-- FrogLib Plates: the machinery for restyling enemy nameplates (FrogPlates, XIVPlates), and your
-- group's or every other friendly one's (as a name alone) if a skin asks. An addon registers a skin (its look); the engine takes plates over and tells
-- it when to build, lay out and fill each in. Blizzard's plate works on underneath, see-through (clicks
-- hit-test its health bar), its cast bar and auras showing through round the skin's bar, as its code
-- copes with secret values.

local Plates = FrogLib:Module("Plates", 6) -- 2: crisp cast bar spell names; each plate hears only its own
-- events; your group's plates (skin.party); Blizzard's auras put back when a plate is handed back; 3: see CHANGELOG
-- (enemy or not decided again, your quests only, no threat colours alone, less work per plate); 4: the threat
-- report's lines wait for the end of combat; 5: friendly name plates (skin.names, plate.nameOnly); 6: their health
-- too if the skin asks (skin.nameBars)
if not Plates then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe

-- Kept on the module, so a newer copy of FrogLib carries on with the same plates.
local state = Plates.state or { own = {}, frames = {}, byUnit = {}, hooked = {}, casts = {} }
Plates.state = state
state.moved = state.moved or {}
state.left = state.left or {} -- Regroup's: the units whose party plates it just handed back

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
-- Righteous Fury; Forever has two more of its own (EllesmereUI reads all three).
local RIGHTEOUS_FURY = { 25780, 407627, 407628 }

-- Your form and auras can't change during one pass over the plates (UpdateAll): looked at once.
local inPass, passTanking

-- A paladin's Righteous Fury. A secret aura reads as missing (no error), so while the game would keep it secret the
-- last plain answer stands, rather than the plates turning to a damage dealer's colours mid-fight.
local function Fury()
    local _, class = UnitClass("player")
    if issecret(class) or class ~= "PALADIN" then return false end
    local Lookup = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not Lookup then return false end
    local Hidden = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    for _, id in ipairs(RIGHTEOUS_FURY) do
        if Hidden then
            local asked, hidden = pcall(Hidden, id)
            if asked and (issecret(hidden) or hidden == true) then return state.fury or false end
        end
        local ok, aura = pcall(Lookup, id)
        if ok and aura then
            state.fury = true
            return true
        end
    end
    state.fury = false
    return false
end

-- (Forever reports one specialization per class whatever you play, so its role says nothing here.)
local function AutoTanking()
    local form = GetShapeshiftFormID and GetShapeshiftFormID()
    if form and TANK_FORMS[form] then return true end
    return Fury()
end

function Plates.Tanking(role)
    if role and role ~= "auto" then return role == "tank" end
    if not inPass then return AutoTanking() end
    if passTanking == nil then passTanking = AutoTanking() end
    return passTanking
end

-- r, g, b, or nil when its threat doesn't colour it. colors: { safe, warn, danger }. 3: it's on you,
-- safely; 2: on you, but someone's close; 1: someone else is about to take it; 0: on someone else.
-- A damage dealer alone (no group, no pet) has everything on them anyway: no colour then.
function Plates.ThreatColour(unit, colors, role)
    local situation = Safe(UnitThreatSituation("player", unit))
    if not situation then return nil end
    local color
    if Plates.Tanking(role) then
        color = (situation == 3 and colors.safe) or (situation == 2 and colors.warn) or colors.danger
    elseif not (IsInGroup() or Safe(UnitExists("pet"))) then
        return nil
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

function Plates.ExecuteCheck()
    local _, class = UnitClass("player")
    local execute = EXECUTES[class]
    local usable = false
    if execute then
        for _, spellID in ipairs(execute.spells) do
            if FrogLib.Util.Knows(spellID) then
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

local LINES = Enum.TooltipDataLineType or {}
local QUEST_LINE, QUEST_TITLE, QUEST_PLAYER = LINES.QuestObjective, LINES.QuestTitle, LINES.QuestPlayer

-- In a group the tooltip lists your groupmates' objectives too, each player's under their name (a QuestPlayer
-- line); only yours count: those under a quest you're on, before any other player's name.
local function QuestLines(unit)
    if not (QUEST_LINE and C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
    local data = Safe(C_TooltipInfo.GetUnit(unit))
    local lines = type(data) == "table" and Safe(data.lines)
    if type(lines) ~= "table" then return end
    local total, open, mine = 0, 0, true
    for _, line in ipairs(lines) do
        local kind = type(line) == "table" and Safe(line.type)
        if kind == QUEST_TITLE then
            local id = Safe(line.id)
            mine = true
            if type(id) == "number" and C_QuestLog and C_QuestLog.IsOnQuest then mine = C_QuestLog.IsOnQuest(id) and true or false end
        elseif kind == QUEST_PLAYER then
            mine = false
        elseif kind == QUEST_LINE and mine then
            total = total + 1
            if Safe(line.completed) ~= true then open = open + 1 end
        end
    end
    return total, open
end

-- The answer, and whether it's sure: the tooltip read (a "no" before the game has the tooltip isn't kept).
local function Quest(unit)
    if Safe(UnitIsPlayer(unit)) ~= false then return false, true end
    local ok, total, open = pcall(QuestLines, unit)
    if ok and total and total > 0 then return open > 0, true end
    local sure = ok and total ~= nil
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local asked, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if asked and Safe(related) == true then return true, true end
    end
    return false, sure
end

-- The tooltip is read once per plate (state.quests, cleared as quests change and as the plate goes), not again on
-- every look.
state.quests = state.quests or {}
function Plates.OnQuest(unit)
    local known = state.quests[unit]
    if known == nil then
        local sure
        known, sure = Quest(unit)
        if sure then state.quests[unit] = known end
    end
    return known
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
    local ok, duration = pcall(UnitCastingDuration, unit)
    if ok and (issecret(duration) or duration ~= nil) then return duration end
    ok, duration = pcall(UnitChannelDuration, unit)
    if ok and (issecret(duration) or duration ~= nil) then return duration end
end

local function WriteCastTime(fontString, unit)
    local duration = unit and CastTimer(unit)
    if duration then
        fontString:SetFormattedText("%.1f", duration:GetRemainingDuration())
    else
        fontString:SetText("")
    end
end

-- skin.castShield(unitFrame, cast, shown, ours): the shield showed or hid (shown may be secret). ours:
-- an enemy plate of the skin's (a plate of your group's keeps Blizzard's cast bar out of sight).
local function Shield(unitFrame, cast, shown)
    local parts = Plates.CastParts(cast)
    if not issecret(shown) then shown = shown and true or false end
    parts.last, parts.seen = shown, true
    local skin = state.skin
    if skin and skin.castShield then skin.castShield(unitFrame, cast, shown, state.own[unitFrame] == true) end
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
    -- The time written ten times a second by a looping animation on the cast bar (it only runs while the bar shows),
    -- not a script every frame on every casting plate.
    local ticker = cast:CreateAnimationGroup()
    ticker:SetLooping("REPEAT")
    ticker:CreateAnimation():SetDuration(0.1)
    ticker:SetScript("OnLoop", function()
        if not parts.time:IsShown() then return end
        if not pcall(WriteCastTime, parts.time, cast.unit) then parts.time:SetText("") end
    end)
    cast:HookScript("OnShow", function() ticker:Play() end)
    cast:HookScript("OnHide", function() ticker:Stop() end)
    if cast:IsShown() then ticker:Play() end
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
-- Each written only when it differs: every write makes Blizzard rescale and refresh the auras on every plate.
local function SetIfChanged(name, value)
    local now = C_CVar.GetCVar(name)
    if now ~= nil and now ~= value then SetCVar(name, value) end
end

local function SetBitIfOff(name, bit)
    if not (bit and C_CVar.GetCVar(name)) then return end
    if C_CVar.GetCVarBitfield then
        local ok, on = pcall(C_CVar.GetCVarBitfield, name, bit)
        if ok and on then return end
    end
    pcall(C_CVar.SetCVarBitfield, name, bit, true)
end

function Plates.AuraSettings(opts)
    if not opts.auras or InCombatLockdown() then return end
    if opts.auraScale then
        local now = tonumber(C_CVar.GetCVar("nameplateAuraScale") or "")
        if now and math.abs(now - opts.auraScale) > 0.001 then
            SetCVar("nameplateAuraScale", string.format("%.2f", opts.auraScale))
        end
    end
    SetIfChanged("nameplateShowAllPersonalAuras", opts.allDebuffs and "1" or "0")
    if C_CVar.SetCVarBitfield then
        SetBitIfOff("nameplateEnemyNpcAuraDisplay",
            Enum.NamePlateEnemyNpcAuraDisplay and Enum.NamePlateEnemyNpcAuraDisplay.Debuffs)
        SetBitIfOff("nameplateEnemyPlayerAuraDisplay",
            Enum.NamePlateEnemyPlayerAuraDisplay and Enum.NamePlateEnemyPlayerAuraDisplay.Debuffs)
    end
end

local CONTROL_LISTS = { "CrowdControlListFrame", "LossOfControlFrame" }

-- Blizzard anchors the aura frame, its buffs and the debuffs' left end once, in its XML
-- (Blizzard_NamePlates.xml), and again in UpdateAnchors only the debuffs' height and crowd control, so
-- what PlaceAuras moved stays moved. Put back as Blizzard has them when the plate is Blizzard's again
-- (state.moved: the unit frames whose auras are the skin's), worked out now rather than kept, so a
-- pooled frame costs nothing.
local function PutBackAuras(unitFrame, auras)
    local healthBars = unitFrame.HealthBarsContainer
    if not (state.moved[unitFrame] and healthBars) then return end
    state.moved[unitFrame] = nil
    auras:ClearAllPoints()
    auras:SetAllPoints(unitFrame)
    local debuffs = auras.DebuffListFrame
    if debuffs then
        local constants, options = NamePlateConstants, NamePlateSetupOptions
        local cvar = constants and constants.DEBUFF_PADDING_CVAR
        local styles = constants and constants.NAME_ANCHOR_STYLES
        local inside = styles and options and options.unitNameAnchorStyle == styles.InsideHealthBar
        local over = inside and healthBars.healthBar or unitFrame.name
        debuffs:ClearAllPoints()
        debuffs:SetPoint("LEFT", healthBars, "LEFT")
        if over then debuffs:SetPoint("BOTTOM", over, "TOP", 0, cvar and tonumber(C_CVar.GetCVar(cvar)) or 0) end
    end
    if auras.BuffListFrame and unitFrame.ClassificationFrame then
        auras.BuffListFrame:ClearAllPoints()
        auras.BuffListFrame:SetPoint("RIGHT", unitFrame.ClassificationFrame, "LEFT", -5, 0)
    end
    -- Past the level badge while it shows (UpdateControlAnchors; its extra gap is for a badge anchored
    -- at RIGHT, and Forever's is at TOPRIGHT).
    local level = unitFrame.PlayerLevelDiffFrame
    local after = (level and level:IsShown()) and level or healthBars
    for _, key in ipairs(CONTROL_LISTS) do
        if auras[key] then
            auras[key]:ClearAllPoints()
            auras[key]:SetPoint("LEFT", after, "RIGHT", 5, 0)
        end
    end
end

-- The aura row `up` above the bar: your debuffs from its left end (or centred), stealable buffs over
-- its right end, crowd control `side` past it. Blizzard pins some back in UpdateAnchors (see Hook).
function Plates.PlaceAuras(unitFrame, bar, shown, up, centred, side)
    local auras = unitFrame and unitFrame.AurasFrame
    if not auras then return end
    auras:SetIgnoreParentAlpha(shown)
    if not shown then return end
    state.moved[unitFrame] = true
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
    for _, key in ipairs(CONTROL_LISTS) do
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
        local _, _, percent = UnitDetailedThreatSituation("player", FrogLib.Threat.Readable(unit))
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
    for _, line in ipairs(lines) do FrogLib.Util.Say(line) end -- in combat, after it (see Util.Say)
end

------------------------------------------------------------------------------
-- Taking plates over, and giving them back
------------------------------------------------------------------------------

-- Blizzard pools the unit frames (base.UnitFrame) for any plate, friendly too, so one made
-- see-through gets its opacity back when it's next used for something friendly, its auras back in
-- their places. A plate of your group's (friend) shows nothing of Blizzard's through it: its cast bar
-- and auras are left where Blizzard puts them, out of sight, so it can be handed back while it's up
-- with nothing out of place.
local function SeeThrough(unitFrame, on, friend, named)
    state.busy = true
    unitFrame:SetAlpha(on and 0 or 1)
    state.busy = false
    if unitFrame.selectionHighlight then unitFrame.selectionHighlight:SetAlpha(on and 0 or 0.25) end
    -- A name plate keeps the game's soft-target icon (the gamepad's interact cursor over an NPC) showing.
    local soft = unitFrame.SoftTargetFrame
    if soft then soft:SetIgnoreParentAlpha((on and named) and true or false) end
    local cast = Plates.BlizzardCast(unitFrame)
    local text = cast and cast.Text
    -- Blizzard's spell name scales smoothly with the plate, drawn at in-between pixel sizes, which
    -- smears it; while the plate is ours it snaps to whole sizes like the skin's own text.
    if text and text.SetSmoothScaling then text:SetSmoothScaling(not on) end
    -- Its font as Blizzard had it, before a skin restyles it (Blizzard sets back only the text's height), to put back.
    local parts = cast and Plates.CastParts(cast)
    if text and on and not parts.font then
        parts.font = { text:GetFont() }
        parts.justify = text:GetJustifyH()
    end
    if on and not friend then return end
    if cast then
        if text and parts.font and parts.font[1] then
            pcall(text.SetFont, text, parts.font[1], parts.font[2], parts.font[3] or "")
            text:SetJustifyH(parts.justify or "CENTER")
        end
        cast:SetIgnoreParentAlpha(false)
        if cast.BorderShield then cast.BorderShield:SetAlpha(1) end
        for _, key in ipairs(Plates.CAST_EXTRAS) do
            if cast[key] then cast[key]:SetAlpha(1) end
        end
        if parts.time then parts.time:Hide() end
        -- Optional skin.release(unitFrame, cast): the skin's cast parts off.
        if state.skin and state.skin.release then state.skin.release(unitFrame, cast) end
    end
    local auras = unitFrame.AurasFrame
    if auras then
        auras:SetIgnoreParentAlpha(false)
        PutBackAuras(unitFrame, auras)
    end
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
        -- Not while it's put away (no unit): Add lays it out when it's next used.
        local plate = state.own[self] and state.frames[self:GetParent()]
        if plate and plate.unit and plate.uf == self and state.skin then state.skin.layout(plate) end
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

-- A plate's own events, and what each updates on it.
local UNIT_EVENTS = { UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_NAME_UPDATE = "name",
    UNIT_LEVEL = "name", UNIT_CLASSIFICATION_CHANGED = "class", UNIT_FACTION = "threat", UNIT_FLAGS = "threat",
    UNIT_THREAT_SITUATION_UPDATE = "threat", UNIT_THREAT_LIST_UPDATE = "threat" }

-- In your party or raid (one question, whichever you're in: see WatchGroup), and not you: true, false,
-- or nil while the game keeps the answer secret. Pets aren't members: theirs get no party plate.
local function Member(unit)
    local member
    if state.raid then
        member = UnitInRaid(unit)
    else
        member = UnitInParty(unit)
    end
    if issecret(member) then return nil end
    if not member then return false end
    local me = UnitIsUnit(unit, "player")
    if issecret(me) then return nil end
    return not me
end

local Add, Remove

-- A unit a name plate is for: one the game calls friendly (as Blizzard picks its friendly look), not
-- you, a game object (a mailbox) or a plate that's only a widget (a capture bar), which stay Blizzard's.
local UnitIsGameObject, UnitNameplateShowsWidgetsOnly = UnitIsGameObject, UnitNameplateShowsWidgetsOnly
local function Nameable(unit)
    return Safe(UnitIsFriend("player", unit)) == true and Safe(UnitCanAttack("player", unit)) == false
        and Safe(UnitIsUnit(unit, "player")) == false
        and not (UnitIsGameObject and Safe(UnitIsGameObject(unit)))
        and not (UnitNameplateShowsWidgetsOnly and Safe(UnitNameplateShowsWidgetsOnly(unit)))
end

-- A dead enemy's plate hides; one of your group's stays, so you can see who needs a res. Whether it can be attacked
-- is decided again as it changes while the plate is up (a party member's duel, a PvP flag, or a unit the game hadn't
-- finished with the frame its plate came): taken over or handed back. A plate not taken is watched for the same.
local function OnUnitEvent(frame, event, unit)
    local skin, plate = state.skin, state.byUnit[unit]
    if not skin then return end
    if not plate then
        -- Looked at again only once it's one to take (a city's townsfolk send these all the time).
        if frame.kind == "watch" and ((skin.enabled() and Safe(UnitCanAttack("player", unit)) == true)
            or (state.party and Member(unit)) or (state.names and Nameable(unit))) then
            Add(unit)
        end
        return
    end
    if event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
        local again
        if plate.nameOnly then
            -- A name plate only once it can be attacked or joins your group: townsfolk send these all the time.
            again = Safe(UnitCanAttack("player", unit)) == true or (state.party and Member(unit))
        else
            local party = event == "UNIT_FACTION" and (plate.friend or (state.party and Member(unit)))
            again = party or (not plate.friend and Safe(UnitCanAttack("player", unit)) == false)
        end
        if again then
            Remove(unit)
            Add(unit)
            return
        end
    end
    local what = UNIT_EVENTS[event]
    skin.update(plate, what)
    if what == "health" and not plate.friend then plate:SetShown(Safe(UnitIsDead(unit)) ~= true) end
end

-- A friend's token hears only these: its health, name and level are all its plate shows, and its
-- faction says when it stops being a friend.
local FRIEND_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION" }
-- A plate not taken hears only what could make it one to take; a name plate the same (its name, and
-- whether it stops being a name plate).
local WATCH_EVENTS = { "UNIT_FLAGS", "UNIT_FACTION", "UNIT_NAME_UPDATE" }
-- A name plate with a health bar (state.nameBars): a friend's and its flags.
local NAME_BAR_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS" }

-- Its unit's events on a frame for its token, so the game sends this plate's alone, not every unit's.
-- Tokens come back, so the frame stays; a friend's or a watched one stops listening when its plate goes
-- (Remove), so a stranger's plate on that token later costs nothing. kind: "foe", "friend", "name", "namebar" or
-- "watch".
local function Listen(unit, kind)
    local frame = state.tokenFrames[unit]
    if frame and frame.kind == kind then return end
    if frame then
        frame:UnregisterAllEvents()
    else
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnUnitEvent)
        state.tokenFrames[unit] = frame
    end
    if kind == "friend" then
        for _, event in ipairs(FRIEND_EVENTS) do pcall(frame.RegisterUnitEvent, frame, event, unit) end
    elseif kind == "watch" or kind == "name" then
        for _, event in ipairs(WATCH_EVENTS) do pcall(frame.RegisterUnitEvent, frame, event, unit) end
    elseif kind == "namebar" then
        for _, event in ipairs(NAME_BAR_EVENTS) do pcall(frame.RegisterUnitEvent, frame, event, unit) end
    else
        for event in pairs(UNIT_EVENTS) do pcall(frame.RegisterUnitEvent, frame, event, unit) end
    end
    frame.kind = kind
end

local function AnyEnemy()
    for _, plate in pairs(state.byUnit) do
        if not plate.friend then return true end
    end
    return false
end

-- The driver (Register) runs while enemy plates are up and you're fighting: the threat gap drifts with every hit,
-- with no event per plate. Out of a fight nothing runs every frame. A skin with a tick (an older one) keeps it on
-- while enemy plates are up.
local function Drive()
    local driver, skin = state.driver, state.skin
    if not driver then return end
    driver:SetShown(((skin and skin.tick ~= nil) or state.fighting) and AnyEnemy() or false)
end

-- Every plate's target look (skin.target()), noting which plate was your target's (state.targetBase): when that one
-- goes (out of view, your target kept) the rest are looked at again, so none stay dimmed for a plate that's gone.
local function TargetAll()
    state.targetBase = C_NamePlate.GetNamePlateForUnit("target")
    state.skin.target()
end

local function TargetAllQueued()
    state.targetQueued = nil
    if state.skin then TargetAll() end
end

-- skin.enabled(): restyle enemy plates now; skin.layout(plate) places it (also after Blizzard lays
-- it out again, and on settings); skin.update(plate, "all") fills it in; skin.target(): see Each.
-- A plate of your group's (see WatchGroup, a switch of its own) has plate.friend set; the skin leaves
-- Blizzard's cast bar and auras be on it. A member you can attack (a duel) gets an enemy's plate, or
-- Blizzard's. Every other friendly plate, NPC or player, is a name plate (plate.friend and plate.nameOnly)
-- while the skin wants them (state.names, see Refresh); it hears its health too while the skin draws a bar on
-- them (state.nameBars), and only its name otherwise. refreshing: Refresh styles the plates for your
-- target once, after adding them all.
function Add(unit, refreshing)
    local skin = state.skin
    if not skin then return end
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base or base:IsForbidden() then return end
    local unitFrame = base.UnitFrame
    local enemy = skin.enabled() and Safe(UnitCanAttack("player", unit)) and Safe(UnitIsUnit(unit, "player")) == false
    local friend = not enemy and state.party and Member(unit) and Safe(UnitCanAttack("player", unit)) ~= true
    local named = not (enemy or friend) and state.names and Nameable(unit)
    friend = friend or named
    if not (enemy or friend) then
        Release(unitFrame)
        if state.frames[base] then state.frames[base]:Hide() end
        -- Watched, in case it can be attacked in a moment (see OnUnitEvent).
        if state.driver and (skin.enabled() or state.names) and Safe(UnitIsUnit(unit, "player")) == false then
            Listen(unit, "watch")
        end
        return
    end
    if unitFrame then
        state.own[unitFrame] = friend and "friend" or true
        Hook(unitFrame)
        SeeThrough(unitFrame, true, friend, named)
    end
    local plate = state.frames[base] or Create(base)
    -- The frame may still be filed under the unit it showed before (its removal not come yet): that one's off it.
    if plate.unit and plate.unit ~= unit and state.byUnit[plate.unit] == plate then state.byUnit[plate.unit] = nil end
    plate.unit, plate.uf, plate.friend, plate.nameOnly = unit, unitFrame, friend or nil, named or nil
    state.byUnit[unit] = plate
    if state.driver then
        Listen(unit, (named and (state.nameBars and "namebar" or "name")) or (friend and "friend") or "foe")
        Drive()
    end
    skin.layout(plate)
    skin.update(plate, "all")
    plate:Show()
    plate:SetShown(friend or Safe(UnitIsDead(unit)) ~= true)
    -- Only this plate's target look (optional skin.targetPlate(plate)); your target hasn't changed. Your target's
    -- own plate coming into view (picked from afar, or out of sight) re-looks them all: the others dim only now.
    if not refreshing then
        if skin.targetPlate and base ~= C_NamePlate.GetNamePlateForUnit("target") then
            skin.targetPlate(plate)
        else
            TargetAll()
        end
    end
end

function Remove(unit)
    state.quests[unit] = nil
    local plate = state.byUnit[unit]
    local frame = state.tokenFrames and state.tokenFrames[unit]
    if not plate then
        if frame and frame.kind == "watch" then
            frame:UnregisterAllEvents()
            frame.kind = nil
        end
        return
    end
    state.byUnit[unit] = nil
    if frame and (frame.kind == "friend" or frame.kind == "name" or frame.kind == "namebar") then
        frame:UnregisterAllEvents()
        frame.kind = nil
    end
    if plate.unit ~= unit then return end -- its frame shows another unit by now
    plate.unit = nil
    plate:Hide()
    if state.targetBase and plate.base == state.targetBase and not state.targetQueued then
        state.targetQueued = true
        C_Timer.After(0, TargetAllQueued)
    end
    Drive()
end

------------------------------------------------------------------------------
-- Your group's plates: optional skin.party(), true while the skin wants them (party and raid
-- members; never you, their pets, or a plate the game keeps to itself, as it does friendly ones
-- in dungeons and raids). Someone joining or leaving has their plate taken over or handed back.
------------------------------------------------------------------------------

-- On your own, the watch hears a group forming, you joining one, or the roster (at login it can
-- come after the skin registers, with nothing else); in a group, who's in it (GROUP_ROSTER_UPDATE
-- comes as you leave too). Nothing at all while the skin doesn't want them.
local GROUP_EVENTS = { solo = { "GROUP_FORMED", "GROUP_JOINED", "GROUP_ROSTER_UPDATE" },
    group = { "GROUP_ROSTER_UPDATE", "GROUP_LEFT" } }

local WatchGroup

-- Plates taken over or handed back as your group now is, without a reload. A plate stays while the
-- game won't say who's in (Member nil); a plate the game keeps to itself is never looked at, as
-- addons get none back for it.
local function Regroup()
    local skin = state.skin
    if not skin then return end
    WatchGroup()
    local party, left = state.party, state.left
    wipe(left)
    for unit, plate in pairs(state.byUnit) do
        if plate.friend and not plate.nameOnly and not (party and Member(unit) ~= false) then
            Release(plate.uf)
            Remove(unit)
            left[unit] = true
        end
    end
    local named = state.names and next(left) ~= nil
    if not (party or named) then return end
    -- Members get their plates (from a name plate too); those who left get name plates, if wanted.
    local added = false
    for i = 1, 40 do
        local unit = "nameplate" .. i
        local plate = state.byUnit[unit]
        if (not plate or plate.nameOnly) and ((named and left[unit]) or (party and Member(unit)))
            and C_NamePlate.GetNamePlateForUnit(unit) then
            if plate then Remove(unit) end
            Add(unit, true)
            added = added or state.byUnit[unit] ~= nil
        end
    end
    if added then TargetAll() end
end

-- state.party: your group's plates are wanted now (the skin wants them, with or without enemy plates,
-- and you're in a group); state.raid: it's a raid.
function WatchGroup()
    local skin = state.skin
    local mode = skin and skin.party and skin.party() and (IsInGroup() and "group" or "solo") or nil
    state.party = mode == "group"
    state.raid = state.party and IsInRaid() or false
    local was = state.groupMode
    if mode == was then return end
    state.groupMode = mode
    local watch = state.groupWatch
    if was then watch:UnregisterAllEvents() end
    if not mode then return end
    if not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", Regroup)
        state.groupWatch = watch
    end
    for _, event in ipairs(GROUP_EVENTS[mode]) do pcall(watch.RegisterEvent, watch, event) end
end

-- Each plate in turn (skin.target(), called when your target changes, goes through them this way;
-- plate.friend on your group's).
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
    WatchGroup()
    -- Optional skin.names(): true while the skin wants every other friendly plate as a name alone.
    state.names = state.skin.names and state.skin.names() and true or false
    -- Optional skin.nameBars(): true while it draws their health too, so they hear it.
    state.nameBars = state.names and state.skin.nameBars and state.skin.nameBars() and true or false
    for unit in pairs(state.byUnit) do Remove(unit) end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then Add(unit, true) end
    end
    if next(state.byUnit) then TargetAll() end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

-- The events for every plate, and what each updates. The player's UNIT_QUEST_LOG_CHANGED is a quest one too.
local EVENTS = { PLAYER_TARGET_CHANGED = "target", RAID_TARGET_UPDATE = "mark",
    UPDATE_SHAPESHIFT_FORM = "execute", PLAYER_REGEN_ENABLED = "execute", SPELLS_CHANGED = "execute",
    QUEST_LOG_UPDATE = "quest", QUEST_ACCEPTED = "quest", QUEST_REMOVED = "quest", QUEST_TURNED_IN = "quest",
    QUEST_WATCH_UPDATE = "quest" }

-- skin.update(plate, what): what is "all", "health", "name", "class" (classification), "threat" (its
-- colour and text: on changes and every 0.3 seconds), "mark", "quest" or "execute" (stance or spells).
-- A plate of your group's gets only these: threat, quests and execute are about enemies.
local FRIEND_UPDATES = { all = true, health = true, name = true, mark = true }

local function UpdateAll(what)
    local skin = state.skin
    local friends = FRIEND_UPDATES[what]
    inPass, passTanking = true, nil
    for _, plate in pairs(state.byUnit) do
        if friends or not plate.friend then skin.update(plate, what) end
    end
    inPass = false
end

-- Quest progress comes in bursts of events: looked at again once they settle.
local function QuestsChanged()
    if state.questPending then return end
    state.questPending = true
    C_Timer.After(0.3, function()
        state.questPending = nil
        wipe(state.quests)
        if state.skin then UpdateAll("quest") end
    end)
end

local function OnEvent(_, event)
    local skin = state.skin
    if not skin then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        state.fighting = event == "PLAYER_REGEN_DISABLED"
        Drive()
        if state.fighting then return end
    end
    local what = EVENTS[event]
    if what == "target" then
        TargetAll()
    elseif what == "mark" then
        UpdateAll("mark")
    elseif what == "execute" then
        -- A new stance or spell can change your execute, and if you're tanking: the plates are painted again only
        -- when one did (spells change often while levelling), and after every fight.
        local before, wasTanking = state.executeBelow, state.tanking
        Plates.ExecuteCheck()
        state.tanking = AutoTanking()
        if event == "PLAYER_REGEN_ENABLED" or state.executeBelow ~= before or state.tanking ~= wasTanking then
            UpdateAll("execute")
        end
    else
        QuestsChanged()
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
        local driver = CreateFrame("Frame")
        for event in pairs(EVENTS) do pcall(driver.RegisterEvent, driver, event) end
        pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_DISABLED")
        pcall(driver.RegisterUnitEvent, driver, "UNIT_QUEST_LOG_CHANGED", "player")
        driver:SetScript("OnEvent", OnEvent)
        state.fighting = InCombatLockdown() or Safe(UnitAffectingCombat("player")) == true
        -- The threat gap drifts with every hit, without its own event for each plate. Optional
        -- skin.tick(plate): every frame, per enemy plate. Shown only while it's wanted (Drive).
        local sinceThreat = 0
        driver:SetScript("OnUpdate", function(_, elapsed)
            local current = state.skin
            if not current then return end
            if current.tick then
                for _, plate in pairs(state.byUnit) do
                    if not plate.friend then current.tick(plate) end
                end
            end
            sinceThreat = sinceThreat + elapsed
            if sinceThreat < 0.3 then return end
            sinceThreat = 0
            UpdateAll("threat")
        end)
        driver:Hide()
        state.driver, state.tokenFrames = driver, {}
    end
    Plates.Refresh()
    return true
end
