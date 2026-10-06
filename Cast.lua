-- FrogLib Cast: reading a unit's cast or channel, and when a cast bar shows, for the addons that
-- draw one (FrogTarget, XIVTarget, FrogFrames, XIVPlayer), each in its own look.
-- Cast data can be secret (the spell's name and icon, its times, whether it can be interrupted),
-- so nothing here tests it: a secret name still counts as a cast, the bar fills on the game's own
-- timer (SetTimerDuration) and the values only go into widgets.
--   FrogLib.Cast.EVENTS           the UNIT_SPELLCAST_ events a cast bar listens to
--   FrogLib.Cast.Read(unit) -> nil when it isn't casting, or { text, texture, startMS, endMS,
--       notInterruptible, channel (true for a channel), duration (the game's timer, or nil),
--       direction (for SetTimerDuration: elapsed for a cast, remaining for a channel) }
--   FrogLib.Cast.Locked(info)     -> true when the cast is known not to be interruptible
--   FrogLib.Cast.Fill(bar, info)  starts the status bar on the cast's timer
--   FrogLib.Cast.SetIcon(texture, icon) -> whether the icon went on (it may be secret)
--   FrogLib.Cast.ShowTime(bar, fs) the time left on the bar's timer, into fs ("1.4")
--   local d = FrogLib.Cast.NewDriver(view)
--       view.show(info), view.hold(event) (interrupted or failed: the bar held full in red),
--       view.sample() (unlocked, no real cast), view.hide(), and optionally view.refresh() (a
--       hold is over: look again; without it, view.hide()).
--       d:Update(unit, event, unlocked): unit nil when there's nobody to show. A cast that's
--       interrupted or fails is held for Cast.HOLD seconds; unlocked, a sample shows unless
--       there's a real cast.
--       d.casting, d.holdUntil, d.sample: what's showing (stop writing the time while held or a
--       sample).

local Cast = FrogLib:Module("Cast", 1)
if not Cast then return end

local issecret = FrogLib.issecret
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

Cast.HOLD = 0.8
Cast.EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function Has(v) return issecret(v) or v ~= nil end

local function Duration(fn, unit)
    if not fn then return nil end
    local ok, d = pcall(fn, unit)
    if ok then return d end
    return nil
end

function Cast.Read(unit)
    local _, text, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    local channel = false
    if not Has(text) then
        _, text, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
        if not Has(text) then return nil end
        channel = true
    end
    return {
        text = text, texture = texture, startMS = startMS, endMS = endMS,
        notInterruptible = notInterruptible, channel = channel,
        duration = Duration(channel and UnitChannelDuration or UnitCastingDuration, unit),
        direction = channel and REMAINING or ELAPSED,
    }
end

function Cast.Locked(info)
    local n = info and info.notInterruptible
    return not issecret(n) and n == true
end

function Cast.Fill(bar, info)
    pcall(bar.SetTimerDuration, bar, info.duration, IMMEDIATE, info.direction)
end

function Cast.SetIcon(texture, icon)
    if not Has(icon) then return false end
    return (pcall(texture.SetTexture, texture, icon))
end

local function WriteTime(bar, fs)
    local duration = bar:GetTimerDuration()
    if Has(duration) then fs:SetFormattedText("%.1f", duration:GetRemainingDuration()) end
end

function Cast.ShowTime(bar, fs)
    pcall(WriteTime, bar, fs)
end

------------------------------------------------------------------------------
-- Drivers
------------------------------------------------------------------------------

Cast.DriverMethods = Cast.DriverMethods or {}
local Driver = Cast.DriverMethods
Cast.DriverMeta = Cast.DriverMeta or { __index = Driver }

function Cast.NewDriver(view)
    return setmetatable({ view = view, casting = false }, Cast.DriverMeta)
end

function Driver:Sample()
    self.casting, self.holdUntil, self.sample = false, nil, true
    self.view.sample()
end

function Driver:Hide()
    self.casting, self.holdUntil = false, nil
    self.view.hide()
end

function Driver:HoldOver()
    self.holdUntil = nil
    if self.view.refresh then self.view.refresh() else self:Hide() end
end

function Driver:Update(unit, event, unlocked)
    self.sample = nil
    if not unit then
        if unlocked then self:Sample() else self:Hide() end
        return
    end
    local info = Cast.Read(unit)
    if info and Has(info.duration) then
        self.casting, self.holdUntil = true, nil
        self.view.show(info)
    elseif (event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED") and self.casting then
        -- Held briefly in red, so an interrupt is seen.
        self.casting = false
        local hold = GetTime() + Cast.HOLD
        self.holdUntil = hold
        self.view.hold(event)
        C_Timer.After(Cast.HOLD, function()
            if self.holdUntil == hold then self:HoldOver() end
        end)
    elseif unlocked then
        self:Sample()
    elseif not self.holdUntil then
        self:Hide()
    end
end
