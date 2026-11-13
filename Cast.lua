-- FrogLib Cast: reading a unit's cast or channel, and when a cast bar shows, for the addons that
-- draw one (FrogTarget, XIVTarget, FrogFrames, XIVPlayer), each in its own look. Cast data can be
-- secret (the spell's name and icon, its times, whether it can be interrupted), so nothing here
-- tests it: a secret name still counts, the bar fills on the game's own timer, values go into widgets.

local Cast = FrogLib:Module("Cast", 2) -- 2: NewLine
if not Cast then return end

local issecret = FrogLib.issecret
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

Cast.HOLD = 0.8
-- The UNIT_SPELLCAST_ events a cast bar listens to.
Cast.EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function Has(value) return issecret(value) or value ~= nil end

local function Duration(ReadDuration, unit)
    if not ReadDuration then return nil end
    local ok, duration = pcall(ReadDuration, unit)
    if ok then return duration end
    return nil
end

-- nil when the unit isn't casting, or { text, texture, startMS, endMS, notInterruptible, channel,
-- duration (the game's timer, or nil), direction (for SetTimerDuration) }.
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

-- True when the cast is known not to be interruptible.
function Cast.Locked(info)
    local locked = info and info.notInterruptible
    return not issecret(locked) and locked == true
end

-- Starts the status bar on the cast's timer.
function Cast.Fill(bar, info)
    pcall(bar.SetTimerDuration, bar, info.duration, IMMEDIATE, info.direction)
end

-- Whether the icon went on (it may be secret).
function Cast.SetIcon(texture, icon)
    if not Has(icon) then return false end
    return (pcall(texture.SetTexture, texture, icon))
end

local function WriteTime(bar, fontString)
    local duration = bar:GetTimerDuration()
    if Has(duration) then fontString:SetFormattedText("%.1f", duration:GetRemainingDuration()) end
end

-- The time left on the bar's timer into the font string ("1.4").
function Cast.ShowTime(bar, fontString)
    pcall(WriteTime, bar, fontString)
end

------------------------------------------------------------------------------
-- Drivers
------------------------------------------------------------------------------

Cast.DriverMethods = Cast.DriverMethods or {}
local Driver = Cast.DriverMethods
Cast.DriverMeta = Cast.DriverMeta or { __index = Driver }

-- view.show(info), view.hold(event) (interrupted or failed: held full in red), view.sample(),
-- view.hide(), and optionally view.refresh() (a hold is over: look again; else view.hide()).
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

-- unit nil when there's nobody to show; unlocked, a sample shows unless there's a real cast. What's
-- showing is in self.casting, self.holdUntil and self.sample (no time is written while held or a sample).
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

------------------------------------------------------------------------------
-- The cast line the target and unit frames draw: gold, grey when it can't be interrupted, held full
-- in red when it's interrupted or fails, a sample while unlocked
------------------------------------------------------------------------------

local COLOR, LOCKED, BROKEN = { 1, 0.72, 0.3 }, { 0.6, 0.6, 0.6 }, { 0.85, 0.2, 0.15 }

-- Its driver. line = { bar (the StatusBar), gauge (with SetColor), label, time, icon (optional),
-- holder (shown and hidden; the bar by default), showTime(), refresh() (a hold is over), sample }.
function Cast.NewLine(line)
    local holder = line.holder or line.bar
    local sample = line.sample -- { label, value, time, icon }, or loop = seconds: it fills over and over
    local function Paint(color) line.gauge:SetColor(color[1], color[2], color[3]) end
    local driver = Cast.NewDriver({
        show = function(info)
            Cast.Fill(line.bar, info)
            line.label:SetText(info.text)
            if line.icon then Cast.SetIcon(line.icon, info.texture) end -- the icon can be secret too
            Paint(Cast.Locked(info) and LOCKED or COLOR)
            holder:Show()
        end,
        hold = function(event)
            line.bar:SetMinMaxValues(0, 1)
            line.bar:SetValue(1)
            Paint(BROKEN)
            line.label:SetText(event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
        end,
        sample = function()
            line.bar:SetMinMaxValues(0, 1)
            if not sample.loop then line.bar:SetValue(sample.value) end
            Paint(COLOR)
            line.label:SetText(sample.label)
            if line.icon and sample.icon then line.icon:SetTexture(sample.icon) end
            if not sample.loop then line.time:SetText(line.showTime() and sample.time or "") end
            holder:Show()
        end,
        hide = function() holder:Hide() end,
        refresh = line.refresh,
    })
    -- The time left can be secret, so it only goes straight into SetFormattedText.
    line.bar:SetScript("OnUpdate", function(bar)
        if driver.sample then
            if sample.loop then
                local left = sample.loop - GetTime() % sample.loop
                bar:SetValue(1 - left / sample.loop)
                if line.showTime() then line.time:SetFormattedText("%.1f", left) else line.time:SetText("") end
            end
            return
        end
        if not line.showTime() or driver.holdUntil then
            line.time:SetText("")
            return
        end
        Cast.ShowTime(bar, line.time)
    end)
    return driver
end
