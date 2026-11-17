-- FrogLib Cast: reading a unit's cast or channel, and when a cast bar shows, for the addons that
-- draw one (FrogTarget, XIVTarget, FrogFrames, XIVPlayer), each in its own look. Cast data can be
-- secret (the spell's name and icon, its times, whether it can be interrupted), so nothing here
-- tests it: a secret name still counts, the bar fills on the game's own timer, values go into widgets.

local Cast = FrogLib:Module("Cast", 5) -- 2: NewLine; 3: a blank time isn't written every frame; 4: a running one
-- twenty times a second; 5: interrupted channels held, holds end with the unit, secret "can't interrupt" greys
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

-- The time left on the bar's timer into the font string ("1.4"). Cast.EVERY: how often a running time is written
-- (its tenths change ten times a second).
Cast.EVERY = 0.05
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

-- Whether the cast was broken off: interrupted, failed, or a channel stopped by someone (its stop event names who,
-- as Blizzard's own bar reads it; unreadable, it counts as finished).
local function Broken(event, interruptedBy)
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then return true end
    return event == "UNIT_SPELLCAST_CHANNEL_STOP" and not issecret(interruptedBy) and interruptedBy ~= nil
end

-- unit nil when there's nobody to show; unlocked, a sample shows unless there's a real cast. What's
-- showing is in self.casting, self.holdUntil and self.sample (no time is written while held or a sample).
-- interruptedBy: UNIT_SPELLCAST_CHANNEL_STOP's fourth argument.
function Driver:Update(unit, event, unlocked, interruptedBy)
    self.sample = nil
    -- Anything but a cast event (a new target, a refresh) ends a hold: the red bar was another unit's cast.
    if self.holdUntil and not (type(event) == "string" and event:find("^UNIT_SPELLCAST_")) then
        self.holdUntil = nil
    end
    if not unit then
        if unlocked then self:Sample() else self:Hide() end
        return
    end
    local info = Cast.Read(unit)
    if info and Has(info.duration) then
        self.casting, self.holdUntil = true, nil
        self.view.show(info)
    elseif Broken(event, interruptedBy) and self.casting then
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
    -- Grey over the fill when whether it can be interrupted is secret: shown by the game from the secret yes/no
    -- (on a frame: EllesmereUI found SetAlphaFromBoolean on a texture drew nothing).
    local locker
    local function Lock(locked)
        if not issecret(locked) then
            if locker then locker:SetAlpha(0) end
            return locked == true
        end
        if not locker then
            locker = CreateFrame("Frame", nil, line.bar)
            locker:SetFrameLevel(line.bar:GetFrameLevel() + 1)
            locker.tint = locker:CreateTexture(nil, "ARTWORK")
            locker.tint:SetAllPoints()
            locker.tint:SetColorTexture(LOCKED[1], LOCKED[2], LOCKED[3])
            -- The line style's spark sits on the fill's end: lifted above the grey, which would cover half of it.
            local spark = line.gauge and line.gauge.spark
            if spark then
                local over = CreateFrame("Frame", nil, line.bar)
                over:SetAllPoints(line.bar)
                over:SetFrameLevel(line.bar:GetFrameLevel() + 2)
                spark:SetParent(over)
            end
        end
        locker:SetAllPoints(line.bar:GetStatusBarTexture()) -- the fill's texture is replaced with the bar texture
        if not pcall(locker.SetAlphaFromBoolean, locker, locked, 1, 0) then locker:SetAlpha(0) end
        return false
    end
    local function Unlock() if locker then locker:SetAlpha(0) end end
    local blank = false -- the time is already empty: not written again every frame
    local wait = 0      -- seconds till the running time is written again
    local function Blank()
        if blank then return end
        blank = true
        line.time:SetText("")
    end
    local driver = Cast.NewDriver({
        show = function(info)
            blank, wait = false, 0
            Cast.Fill(line.bar, info)
            line.label:SetText(info.text)
            if line.icon then Cast.SetIcon(line.icon, info.texture) end -- the icon can be secret too
            Paint(Lock(info.notInterruptible) and LOCKED or COLOR)
            holder:Show()
        end,
        hold = function(event)
            Unlock()
            line.bar:SetMinMaxValues(0, 1)
            line.bar:SetValue(1)
            Paint(BROKEN)
            line.label:SetText(event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
            Blank()
        end,
        sample = function()
            blank = false
            Unlock()
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
    -- The time left can be secret, so it only goes straight into SetFormattedText; its tenths change ten times a
    -- second, so it's written twenty times a second rather than every frame.
    line.bar:SetScript("OnUpdate", function(bar, elapsed)
        if driver.sample then
            if sample.loop then
                local left = sample.loop - GetTime() % sample.loop
                bar:SetValue(1 - left / sample.loop)
                if line.showTime() then
                    blank = false
                    line.time:SetFormattedText("%.1f", left)
                else
                    Blank()
                end
            end
            return
        end
        if not line.showTime() or driver.holdUntil then
            Blank()
            return
        end
        wait = wait - elapsed
        if not blank and wait > 0 then return end
        blank, wait = false, Cast.EVERY
        Cast.ShowTime(bar, line.time)
    end)
    return driver
end
