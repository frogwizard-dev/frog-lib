-- FrogLib Swing: the swing timers' workings, for the addons that draw them (FrogUI's flat bars,
-- XIVPlayer's gauges). PLAYER_SWING, as Blizzard_SwingTimer uses it, gives the time until a hand's
-- next swing. Values the game may keep secret (the swing's type and duration, attack speeds, range)
-- are never compared: a secret type is skipped, a secret duration falls back on the weapon's speed.

local Swing = FrogLib:Module("Swing", 3) -- 2: Listen; ADDON_LOADED only till Blizzard_SwingTimer loads;
-- 3: a secret attack speed keeps the last answer; the range check is turned on
if not Swing then return end

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local SwingType = (Enum and Enum.PlayerSwingType) or { MainHand = 0, OffHand = 1, Ranged = 2 }
local BLIZZARD = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

Swing.HANDS = {
    { key = "main", type = SwingType.MainHand, label = "Main hand" },
    { key = "off", type = SwingType.OffHand, label = "Off hand" },
    { key = "ranged", type = SwingType.Ranged, label = "Ranged" },
}

-- [hand key] = whether it had a weapon when last readable, or a swing of it proved one.
Swing.known = Swing.known or {}

-- Whether there's a weapon for the hand (the main hand: always). Attack speeds turn secret in a fight (a haste proc
-- reads them again): the last plain answer stands, so an empty hand's bar doesn't come up mid-fight.
function Swing.HasWeapon(hand)
    if hand.key == "main" then return true end
    local _, off, ranged = UnitAttackSpeed("player")
    local speed
    if hand.key == "off" then speed = off else speed = ranged end
    if issecret(speed) then return Swing.known[hand.key] == true end
    local has = speed ~= nil and speed > 0
    Swing.known[hand.key] = has
    return has
end

-- The equipped weapon's swing time (haste included), or nil.
function Swing.Speed(hand)
    local main, off, ranged = UnitAttackSpeed("player")
    local speed = main
    if hand.key == "off" then speed = off elseif hand.key == "ranged" then speed = ranged end
    speed = Safe(speed)
    if type(speed) == "number" and speed > 0 then return speed end
    return nil
end

-- Shown, for the setting: "combat", "target" (an enemy targeted), "either" or "always". inCombat:
-- from the combat events, when known.
function Swing.Wanted(show, inCombat)
    if show == "always" then return true end
    local combat = inCombat
    if combat == nil then combat = Safe(UnitAffectingCombat("player")) and true or false end
    if show == "combat" then return combat end
    local exists = UnitExists("target")
    local enemy = (issecret(exists) or exists) and Safe(UnitCanAttack("player", "target")) == true
        and Safe(UnitIsDead("target")) ~= true or false
    if show == "target" then return enemy end
    if show == "either" then return combat or enemy end
    return combat
end

-- True only when the game says your target is out of reach.
function Swing.OutOfRange(hand)
    if not (C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange) then return false end
    local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, hand.type)
    -- nil: no check could be made (no target, say), which isn't out of range.
    return ok and not issecret(inRange) and inRange == false
end

------------------------------------------------------------------------------
-- Blizzard's bars. Hooked once, whichever addon gets there first; the hook calls through this
-- part's table, so the newest copy answers.
------------------------------------------------------------------------------

Swing.blizzardOwners = Swing.blizzardOwners or {} -- [owner] = true while it wants them faded
Swing.blizzardHooked = Swing.blizzardHooked or {} -- [frame] = true once its SetAlpha is hooked
Swing.blizzardFaded = Swing.blizzardFaded or {}   -- [frame] = true while faded by us

local function SetAlpha(frame, alpha)
    Swing.writing = true
    pcall(frame.SetAlpha, frame, alpha)
    Swing.writing = false
end

-- Edit Mode's layout and the managed-frame fades set it back: ours goes on after.
function Swing.OnBlizzardAlpha(frame)
    if Swing.writing or not Swing.blizzardFaded[frame] then return end
    SetAlpha(frame, 0)
end

-- Blizzard's swing bars faded out (opacity only: they keep their place in Edit Mode) while any owner
-- wants them gone. owner nil: put it on again (Blizzard_SwingTimer has loaded, a loading screen).
function Swing.FadeBlizzard(owner, hide)
    if owner ~= nil then Swing.blizzardOwners[owner] = hide and true or nil end
    local faded = next(Swing.blizzardOwners) ~= nil
    for _, name in ipairs(BLIZZARD) do
        local frame = _G[name]
        if frame then
            if not Swing.blizzardHooked[frame] then
                Swing.blizzardHooked[frame] = true
                hooksecurefunc(frame, "SetAlpha", function(hooked) Swing.OnBlizzardAlpha(hooked) end)
            end
            if faded then
                SetAlpha(frame, 0)
            elseif Swing.blizzardFaded[frame] then
                SetAlpha(frame, 1) -- Edit Mode's own opacity comes back with its next layout
            end
            Swing.blizzardFaded[frame] = faded or nil
        end
    end
end

------------------------------------------------------------------------------
-- Trackers
------------------------------------------------------------------------------

Swing.TrackerMethods = Swing.TrackerMethods or {}
local Tracker = Swing.TrackerMethods
Swing.TrackerMeta = Swing.TrackerMeta or { __index = Tracker }

local EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "WEAPON_SLOT_CHANGED", "PLAYER_ENTERING_WORLD" }

local function Call(Callback, ...)
    if Callback then Callback(...) end
end

-- PLAYER_SWING_RANGE_UPDATE only comes for swing types with the range check on. Blizzard's own bars turn it off
-- when they don't need it (hidden, faded), so it's turned on again with each target and fight; never off, as
-- Blizzard's bars may be the ones in use.
local function RangeCheck()
    if not (C_SwingTimer and C_SwingTimer.EnableRangeCheck) then return end
    for _, hand in ipairs(Swing.HANDS) do pcall(C_SwingTimer.EnableRangeCheck, hand.type, true) end
end

-- Listens to the game and keeps each hand's timer. opts.accept() -> whether swings count now (not
-- while samples show); called back: onStart(hand), onShown(), onRange(), onLayout(event), onBlizzard().
function Swing.NewTracker(opts)
    local tracker = setmetatable({ opts = opts or {}, swings = {} }, Swing.TrackerMeta)
    tracker.frame = CreateFrame("Frame")
    tracker.frame:SetScript("OnEvent", function(_, event, ...) tracker:OnEvent(event, ...) end)
    tracker:Listen(true)
    return tracker
end

-- Listening to the game, or (off, the timers not used) only to the swings, so turned back on mid-fight
-- the running one shows. Combat is read afresh when it comes back on, its events having been missed.
function Tracker:Listen(on)
    on = on and true or false
    if on == self.listening then return end
    self.listening = on
    local events = self.frame
    if not on then
        events:UnregisterAllEvents()
        pcall(events.RegisterEvent, events, "PLAYER_SWING")
        pcall(events.RegisterEvent, events, "WEAPON_SLOT_CHANGED")
        return
    end
    self.inCombat = nil
    for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
    for _, event in ipairs(self.opts.events or {}) do pcall(events.RegisterEvent, events, event) end
    -- Every addon loading is only watched for Blizzard's swing bars, till they're there.
    if not FrogLib.Loaded("Blizzard_SwingTimer") then events:RegisterEvent("ADDON_LOADED") end
    pcall(events.RegisterUnitEvent, events, "UNIT_ATTACK_SPEED", "player")
    pcall(events.RegisterUnitEvent, events, "UNIT_FLAGS", "target")
    RangeCheck()
end

function Tracker:Hand(swingType)
    if issecret(swingType) then return nil end
    for _, hand in ipairs(Swing.HANDS) do
        if hand.type == swingType then return hand end
    end
    return nil
end

-- The swing's time, or the weapon's speed when the game keeps it secret.
function Tracker:Start(hand, duration)
    if issecret(duration) or type(duration) ~= "number" then duration = Swing.Speed(hand) end
    if not duration or duration <= 0 then return false end
    -- One record per hand, reused (a tracker an older copy made has none yet).
    self.records = self.records or {}
    local record = self.records[hand.key] or {}
    self.records[hand.key] = record
    record.duration, record.ends = duration, GetTime() + duration
    self.swings[hand.key] = record
    return true
end

function Tracker:Clear(hand)
    self.swings[hand.key] = nil
end

function Tracker:Running(hand)
    return self.swings[hand.key] ~= nil
end

-- The fraction done and seconds left while running; nil, true the moment it runs out (once); nil
-- otherwise.
function Tracker:Progress(hand, now)
    local swing = self.swings[hand.key]
    if not swing then return nil end
    local left = swing.ends - (now or GetTime())
    if left <= 0 then
        self.swings[hand.key] = nil
        return nil, true
    end
    return (swing.duration - left) / swing.duration, left
end

function Tracker:OnEvent(event, ...)
    local opts = self.opts
    if event == "PLAYER_SWING" then
        -- Handled even while hidden, so the first swing of a fight is caught.
        local duration, swingType = ...
        local hand = self:Hand(swingType)
        if hand then Swing.known[hand.key] = true end -- it swung: there's a weapon there
        if hand and (not opts.accept or opts.accept()) and self:Start(hand, duration) then Call(opts.onStart, hand) end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        Call(opts.onRange)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- From the event (self.inCombat, nil until the first): UnitAffectingCombat can lag behind it.
        self.inCombat = event == "PLAYER_REGEN_DISABLED"
        if self.inCombat then RangeCheck() end
        Call(opts.onShown)
        Call(opts.onRange)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_FLAGS" then
        if event == "PLAYER_TARGET_CHANGED" then RangeCheck() end
        Call(opts.onShown)
        Call(opts.onRange)
    elseif event == "ADDON_LOADED" then
        if ... == "Blizzard_SwingTimer" then
            self.frame:UnregisterEvent("ADDON_LOADED")
            Call(opts.onBlizzard)
        end
    elseif event == "WEAPON_SLOT_CHANGED" then
        -- A new weapon mid-swing: the running timers restart at its speed (as Blizzard's do).
        for _, hand in ipairs(Swing.HANDS) do
            if self.swings[hand.key] then self:Start(hand, Swing.Speed(hand)) end
        end
        Call(opts.onLayout, event)
    else
        if event == "PLAYER_ENTERING_WORLD" then
            self.inCombat = nil
            Call(opts.onBlizzard)
        end
        Call(opts.onLayout, event) -- weapons, attack speed, loading screens, opts.events
    end
end
